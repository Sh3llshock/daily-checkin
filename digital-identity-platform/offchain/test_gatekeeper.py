"""Gatekeeper tests (TASKS C3) against the live local chain.

Needs `npx hardhat node` + `npm run deploy:local`; every test is skipped when
no node is reachable. Run from digital-identity-platform/ with:
    python -m unittest discover -s offchain -v

Each test uses fresh generated accounts and fake data in a temporary
directory, so the tests can run repeatedly on the same chain. The expiry and
staleness tests move the local chain's clock forward.

AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01. Per the
coursebook GenAI rules it must be reviewed by the team and declared in the
report's AI statement.
"""

from __future__ import annotations

import secrets
import tempfile
import unittest
from pathlib import Path

from eth_account import Account
from eth_account.messages import encode_defunct
from eth_account.signers.local import LocalAccount
from web3 import Web3

from common import SetupError, TxSender, connect, hardhat_account, increase_time, load_contracts
from fake_data import write_user_files
from gatekeeper import (
    AccessRefused,
    Gatekeeper,
    access_message,
    request_files,
    start_server,
    user_link,
    verify_files,
)
from hash_tool import BACK_FILE, FRONT_FILE, registration_values

PORT = 8601
BOTH, FRONT_ONLY, BACK_ONLY = 2, 0, 1


def _signature(account: LocalAccount, user: str, tx_hash: str) -> str:
    return "0x" + account.sign_message(encode_defunct(text=access_message(user, tx_hash))).signature.hex().removeprefix("0x")


class GatekeeperTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        try:
            cls.w3 = connect()
            cls.c = load_contracts(cls.w3)
        except SetupError as error:
            raise unittest.SkipTest(str(error))
        cls.admin = hardhat_account(0)
        cls.sender = TxSender(cls.w3)
        cls.tmp = tempfile.TemporaryDirectory()
        cls.data_dir = Path(cls.tmp.name)
        cls.gatekeeper = Gatekeeper(cls.w3, cls.c, cls.data_dir, max_age_s=300)
        cls.server = start_server(cls.gatekeeper, port=PORT)
        cls.base_url = f"http://127.0.0.1:{PORT}"

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.tmp.cleanup()

    # --- helpers ---

    def _funded(self) -> LocalAccount:
        account = Account.create()
        self.sender.wait(self.sender.send_eth(self.admin, account.address, Web3.to_wei(1, "ether")))
        return account

    def _requester(self) -> LocalAccount:
        requester = self._funded()
        self.sender.transact(self.admin, self.c["DigitalIdentityRegistry"].functions.setRequesterStatus(requester.address, True), "whitelist")
        return requester

    def _user(self) -> LocalAccount:
        user = self._funded()
        write_user_files(user.address, self.data_dir)
        email, front, back = registration_values(self.data_dir / user.address)
        link = user_link(self.base_url, user.address)
        self.sender.transact(user, self.c["DigitalIdentityRegistry"].functions.registerUser(email, link, front, back), "register")
        return user

    def _grant(self, user: LocalAccount, requester: LocalAccount, scope: int = BOTH, days: int = 30) -> None:
        self.sender.transact(user, self.c["ConsentManager"].functions.setConsent(requester.address, scope, days), "grant")

    def _request_access(self, requester: LocalAccount, user: LocalAccount) -> str:
        return self.sender.transact(requester, self.c["DataSharingManager"].functions.requestAccess(user.address), "requestAccess").tx_hash

    def _granted_setup(self, scope: int = BOTH, days: int = 30) -> tuple[LocalAccount, LocalAccount, str]:
        user, requester = self._user(), self._requester()
        self._grant(user, requester, scope, days)
        return user, requester, self._request_access(requester, user)

    def _refused(self, code: str, user: str, tx_hash: str, signature: str) -> None:
        with self.assertRaises(AccessRefused) as caught:
            self.gatekeeper.release(user, tx_hash, signature)
        self.assertEqual(caught.exception.code, code)

    # --- the granted path ---

    def test_granted_request_returns_files_matching_on_chain_hashes(self) -> None:
        user, requester, tx_hash = self._granted_setup(BOTH)
        link = self.c["DigitalIdentityRegistry"].functions.getUserRecord(user.address).call()[1]
        files = request_files(link, requester, user.address, tx_hash)  # over HTTP, via the on-chain link
        self.assertEqual(set(files), {FRONT_FILE, BACK_FILE})
        _, _, front, back, _ = self.c["DigitalIdentityRegistry"].functions.getUserRecord(user.address).call()
        verify_files(files, front, back)  # raises on a mismatch

    def test_front_only_scope_releases_only_the_front(self) -> None:
        user, requester, tx_hash = self._granted_setup(FRONT_ONLY)
        release = self.gatekeeper.release(user.address, tx_hash, _signature(requester, user.address, tx_hash))
        self.assertEqual(release.scope, "FRONT_ONLY")
        self.assertEqual(set(release.files), {FRONT_FILE})

    def test_back_only_scope_releases_only_the_back(self) -> None:
        user, requester, tx_hash = self._granted_setup(BACK_ONLY)
        release = self.gatekeeper.release(user.address, tx_hash, _signature(requester, user.address, tx_hash))
        self.assertEqual(set(release.files), {BACK_FILE})

    def test_tampered_file_fails_the_requesters_hash_check(self) -> None:
        user, requester, tx_hash = self._granted_setup(BOTH)
        (self.data_dir / user.address / FRONT_FILE).write_text('{"tampered": true}\n')
        files = self.gatekeeper.release(user.address, tx_hash, _signature(requester, user.address, tx_hash)).files
        _, _, front, back, _ = self.c["DigitalIdentityRegistry"].functions.getUserRecord(user.address).call()
        with self.assertRaises(ValueError):
            verify_files(files, front, back)

    # --- every refusal ---

    def test_unknown_transaction_is_refused(self) -> None:
        user, requester = self._user(), self._requester()
        fake_hash = "0x" + secrets.token_hex(32)
        self._refused("no_transaction", user.address, fake_hash, _signature(requester, user.address, fake_hash))

    def test_signature_from_someone_else_is_refused(self) -> None:
        # Transaction hashes are public: an observer who copies one can't use it.
        user, _, tx_hash = self._granted_setup()
        observer = Account.create()
        self._refused("wrong_sender", user.address, tx_hash, _signature(observer, user.address, tx_hash))

    def test_transaction_for_another_user_is_refused(self) -> None:
        user, requester, tx_hash = self._granted_setup()
        other = self._user()
        self._refused("access_not_granted", other.address, tx_hash, _signature(requester, other.address, tx_hash))

    def test_denied_transaction_is_refused(self) -> None:
        user, requester = self._user(), self._requester()
        tx_hash = self._request_access(requester, user)  # no consent: DENIED, logged, no revert
        self._refused("access_not_granted", user.address, tx_hash, _signature(requester, user.address, tx_hash))

    def test_transaction_to_another_contract_is_refused(self) -> None:
        user, requester = self._user(), self._requester()
        tx_hash = self.sender.transact(user, self.c["ConsentManager"].functions.setConsent(requester.address, BOTH, 30), "grant").tx_hash
        self._refused("not_an_access_request", user.address, tx_hash, _signature(user, user.address, tx_hash))

    def test_revoked_consent_is_refused(self) -> None:
        user, requester, tx_hash = self._granted_setup()
        self.sender.transact(user, self.c["ConsentManager"].functions.revokeConsent(requester.address), "revoke")
        self._refused("consent_not_valid", user.address, tx_hash, _signature(requester, user.address, tx_hash))

    def test_expired_consent_is_refused(self) -> None:
        user, requester, tx_hash = self._granted_setup(days=1)
        increase_time(self.w3, 24 * 3600 + 1)
        self._refused("consent_not_valid", user.address, tx_hash, _signature(requester, user.address, tx_hash))

    def test_stale_transaction_is_refused(self) -> None:
        user, requester, tx_hash = self._granted_setup(days=30)
        increase_time(self.w3, 301)  # consent still valid, but the tx is older than 5 minutes
        self._refused("stale_transaction", user.address, tx_hash, _signature(requester, user.address, tx_hash))

    def test_dewhitelisted_requester_is_refused(self) -> None:
        user, requester, tx_hash = self._granted_setup()
        self.sender.transact(self.admin, self.c["DigitalIdentityRegistry"].functions.setRequesterStatus(requester.address, False), "remove")
        self._refused("requester_not_whitelisted", user.address, tx_hash, _signature(requester, user.address, tx_hash))

    def test_each_transaction_releases_files_only_once(self) -> None:
        user, requester, tx_hash = self._granted_setup()
        signature = _signature(requester, user.address, tx_hash)
        self.gatekeeper.release(user.address, tx_hash, signature)
        self._refused("already_used", user.address, tx_hash, signature)

    def test_refusal_over_http_is_a_403_with_the_reason(self) -> None:
        user, requester, tx_hash = self._granted_setup()
        self.sender.transact(user, self.c["ConsentManager"].functions.revokeConsent(requester.address), "revoke")
        with self.assertRaises(AccessRefused) as caught:
            request_files(user_link(self.base_url, user.address), requester, user.address, tx_hash)
        self.assertEqual(caught.exception.code, "consent_not_valid")


if __name__ == "__main__":
    unittest.main()
