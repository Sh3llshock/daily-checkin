"""The gatekeeper: the off-chain data holder that enforces consent itself.

Everything on-chain is public (Lecture 7 §2.1), so the document link stored in
the registry protects nothing on its own. The link points here instead, and
the gatekeeper hands out a user's ID files only if ALL of these hold:

1. The requester presents the hash of its own `requestAccess(user)`
   transaction, and the receipt shows that it succeeded, was sent to the
   DataSharingManager, and emitted `AccessGranted(user, requester)`. No
   GRANTED log entry, no data.
2. The request is signed with the key that sent that transaction. Transaction
   hashes are public, so without this anyone watching the chain could replay
   a requester's hash; the ECDSA signature (Tutorial 1) proves the caller *is*
   the requester.
3. The requester is still whitelisted and `ConsentManager.isConsentValid(user,
   requester)` is still true now, which blocks reusing an old transaction
   after a revoke, an expiry or a de-whitelisting.
4. The transaction is recent (default: mined in the last 5 minutes).
5. The transaction hash hasn't been used before, so every release matches
   exactly one GRANTED entry in the user's on-chain log.

It then returns only the files the consent scope allows (front, back or both).
The requester re-hashes them and compares with the on-chain hashes, so it
doesn't have to trust the gatekeeper for integrity.

Run it on its own with:
    python offchain/gatekeeper.py [--port 8600] [--data-dir offchain/data]

HTTP API:
    POST /users/<user-address>/files   {"tx_hash": "0x…", "signature": "0x…"}
    200 {"user", "requester", "scope", "tx_hash", "files": {name: base64}}
    403 {"error": <reason code>, "detail": <text>}

AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01. Per the
coursebook GenAI rules it must be reviewed by the team and declared in the
report's AI statement.
"""

from __future__ import annotations

import argparse
import base64
import json
import logging
import re
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from eth_account import Account
from eth_account.messages import encode_defunct
from eth_account.signers.local import LocalAccount
from eth_keys.exceptions import BadSignature
from eth_utils.exceptions import ValidationError
from web3 import Web3
from web3.exceptions import TransactionNotFound
from web3.logs import DISCARD

from common import DEFAULT_RPC, SCOPES, connect, load_contracts
from hash_tool import BACK_FILE, FRONT_FILE, sha256_bytes

logger = logging.getLogger("gatekeeper")

DEFAULT_PORT = 8600
DEFAULT_MAX_AGE_S = 5 * 60
DEFAULT_DATA_DIR = Path(__file__).resolve().parent / "data"

FILES_FOR_SCOPE = {
    "FRONT_ONLY": (FRONT_FILE,),
    "BACK_ONLY": (BACK_FILE,),
    "BOTH": (FRONT_FILE, BACK_FILE),
}

TX_HASH_RE = re.compile(r"^0x[0-9a-fA-F]{64}$")


def user_link(base_url: str, user: str) -> str:
    """The `documentLink` a user registers on-chain: this gatekeeper's URL for them."""
    return f"{base_url.rstrip('/')}/users/{Web3.to_checksum_address(user)}"


def access_message(user: str, tx_hash: str) -> str:
    """The text a requester signs to prove it sent `tx_hash`."""
    return (
        "Digital Identity Platform: gatekeeper file request\n"
        f"user: {Web3.to_checksum_address(user)}\n"
        f"tx: {tx_hash.lower()}"
    )


class AccessRefused(Exception):
    def __init__(self, code: str, detail: str):
        super().__init__(f"{code}: {detail}")
        self.code = code
        self.detail = detail


@dataclass
class Release:
    user: str
    requester: str
    scope: str
    tx_hash: str
    files: dict[str, bytes]


class Gatekeeper:
    def __init__(self, w3: Web3, contracts: dict, data_dir: Path = DEFAULT_DATA_DIR, max_age_s: int = DEFAULT_MAX_AGE_S):
        self.w3 = w3
        self.registry = contracts["DigitalIdentityRegistry"]
        self.consent = contracts["ConsentManager"]
        self.dsm = contracts["DataSharingManager"]
        self.data_dir = Path(data_dir)
        self.max_age_s = max_age_s
        self._used: set[str] = set()  # in memory: a restart re-allows only txs still inside the age window
        self._lock = threading.Lock()

    def _now(self) -> int:
        # The later of wall-clock time and the chain head, so a local chain
        # whose clock was moved forward (evm_increaseTime) is handled too.
        return max(int(time.time()), self.w3.eth.get_block("latest")["timestamp"])

    def release(self, user: str, tx_hash: str, signature: str) -> Release:
        """Run every check; return the permitted files or raise AccessRefused."""
        if not Web3.is_address(user):
            raise AccessRefused("bad_request", "user is not an address")
        if not isinstance(tx_hash, str) or not TX_HASH_RE.match(tx_hash):
            raise AccessRefused("bad_request", "tx_hash must be 0x + 64 hex characters")
        user = Web3.to_checksum_address(user)
        tx_hash = tx_hash.lower()

        # 1. A successful requestAccess transaction that emitted AccessGranted(user, sender).
        try:
            tx = self.w3.eth.get_transaction(tx_hash)
            receipt = self.w3.eth.get_transaction_receipt(tx_hash)
        except TransactionNotFound:
            raise AccessRefused("no_transaction", "no mined transaction with this hash")
        if receipt["status"] != 1:
            raise AccessRefused("transaction_failed", "the transaction reverted")
        if tx["to"] != self.dsm.address:
            raise AccessRefused("not_an_access_request", "the transaction was not sent to the DataSharingManager")
        requester = tx["from"]

        # 2. The caller holds the key that sent the transaction.
        try:
            signer = Account.recover_message(encode_defunct(text=access_message(user, tx_hash)), signature=signature)
        except (ValueError, TypeError, ValidationError, BadSignature):
            raise AccessRefused("bad_request", "signature is malformed")
        if signer != requester:
            raise AccessRefused("wrong_sender", "the request is not signed by the transaction's sender")

        granted = [
            event
            for event in self.dsm.events.AccessGranted().process_receipt(receipt, errors=DISCARD)
            if event["address"] == self.dsm.address
            and event["args"]["user"] == user
            and event["args"]["requester"] == requester
        ]
        if not granted:
            raise AccessRefused("access_not_granted", "the transaction has no AccessGranted event for this user")

        # 3. Still allowed right now: whitelisted, and consent valid (not revoked or expired).
        if not self.registry.functions.isApprovedRequester(requester).call():
            raise AccessRefused("requester_not_whitelisted", "the requester has been removed from the whitelist")
        if not self.consent.functions.isConsentValid(user, requester).call():
            raise AccessRefused("consent_not_valid", "the user's consent has been revoked or has expired")

        # 4. Recent.
        mined_at = self.w3.eth.get_block(receipt["blockNumber"])["timestamp"]
        age = self._now() - mined_at
        if age > self.max_age_s:
            raise AccessRefused("stale_transaction", f"the transaction is {age}s old (limit {self.max_age_s}s)")

        # 5. Only the files the scope allows.
        scope = SCOPES[self.consent.functions.getConsent(user, requester).call()[0]]
        user_dir = self.data_dir / user
        try:
            files = {name: (user_dir / name).read_bytes() for name in FILES_FOR_SCOPE[scope]}
        except FileNotFoundError:
            raise AccessRefused("files_missing", "this gatekeeper holds no files for the user")

        # 6. One release per GRANTED log entry.
        with self._lock:
            if tx_hash in self._used:
                raise AccessRefused("already_used", "this transaction has already been used to fetch files")
            self._used.add(tx_hash)

        logger.info("released %s to %s for %s (scope %s, tx %s)", ", ".join(files), requester, user, scope, tx_hash)
        return Release(user, requester, scope, tx_hash, files)


# --- HTTP server --------------------------------------------------------------

FILES_PATH_RE = re.compile(r"^/users/(0x[0-9a-fA-F]{40})/files$")
USER_PATH_RE = re.compile(r"^/users/(0x[0-9a-fA-F]{40})$")


def _handler_for(gatekeeper: Gatekeeper) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        def _cors(self) -> None:
            # Lets the front-end page call the gatekeeper. Safe for any origin:
            # access is decided by the signed transaction checks, not by who asks.
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")

        def _reply(self, status: int, body: dict) -> None:
            data = json.dumps(body).encode()
            self.send_response(status)
            self._cors()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_OPTIONS(self) -> None:  # CORS preflight
            self.send_response(204)
            self._cors()
            self.end_headers()

        def do_GET(self) -> None:  # the on-chain link itself: explain how to ask
            if USER_PATH_RE.match(self.path):
                self._reply(405, {"error": "use_post", "detail": f"POST {self.path}/files with tx_hash and signature"})
            else:
                self._reply(404, {"error": "not_found", "detail": self.path})

        def do_POST(self) -> None:
            match = FILES_PATH_RE.match(self.path)
            if not match:
                self._reply(404, {"error": "not_found", "detail": self.path})
                return
            try:
                length = int(self.headers.get("Content-Length", 0))
                body = json.loads(self.rfile.read(length) or b"{}")
                release = gatekeeper.release(match.group(1), body.get("tx_hash"), body.get("signature"))
            except AccessRefused as refused:
                logger.info("refused %s: %s", self.path, refused)
                self._reply(403, {"error": refused.code, "detail": refused.detail})
                return
            except (ValueError, AttributeError):
                self._reply(400, {"error": "bad_request", "detail": "body must be JSON"})
                return
            self._reply(
                200,
                {
                    "user": release.user,
                    "requester": release.requester,
                    "scope": release.scope,
                    "tx_hash": release.tx_hash,
                    "files": {name: base64.b64encode(data).decode() for name, data in release.files.items()},
                },
            )

        def log_message(self, fmt: str, *args: object) -> None:  # route http.server's access log through logging
            logger.debug("%s " + fmt, self.address_string(), *args)

    return Handler


def start_server(gatekeeper: Gatekeeper, host: str = "127.0.0.1", port: int = DEFAULT_PORT) -> ThreadingHTTPServer:
    """Start serving in a background thread; call `.shutdown()` to stop."""
    server = ThreadingHTTPServer((host, port), _handler_for(gatekeeper))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


# --- Requester side -----------------------------------------------------------


def request_files(link: str, requester: LocalAccount, user: str, tx_hash: str) -> dict[str, bytes]:
    """Ask the gatekeeper at the user's on-chain `link` for their files."""
    signature = requester.sign_message(encode_defunct(text=access_message(user, tx_hash))).signature
    body = json.dumps({"tx_hash": tx_hash, "signature": "0x" + signature.hex().removeprefix("0x")}).encode()
    request = urllib.request.Request(
        f"{link.rstrip('/')}/files", data=body, headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read())
    except urllib.error.HTTPError as error:
        payload = json.loads(error.read() or b"{}")
        raise AccessRefused(payload.get("error", f"http_{error.code}"), payload.get("detail", ""))
    return {name: base64.b64decode(data) for name, data in payload["files"].items()}


def verify_files(files: dict[str, bytes], front_hash: bytes, back_hash: bytes) -> None:
    """Re-hash the received files against the on-chain hashes; raise on any mismatch."""
    expected = {FRONT_FILE: bytes(front_hash), BACK_FILE: bytes(back_hash)}
    for name, data in files.items():
        if sha256_bytes(data) != expected[name]:
            raise ValueError(f"{name} does not match its on-chain hash: the file was altered or is stale")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the gatekeeper HTTP server.")
    parser.add_argument("--rpc", default=DEFAULT_RPC)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument("--max-age", type=int, default=DEFAULT_MAX_AGE_S, help="seconds a transaction stays usable")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    w3 = connect(args.rpc)
    gatekeeper = Gatekeeper(w3, load_contracts(w3), args.data_dir, args.max_age)
    server = ThreadingHTTPServer((args.host, args.port), _handler_for(gatekeeper))
    logger.info("gatekeeper serving %s on http://%s:%d", args.data_dir, args.host, args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
