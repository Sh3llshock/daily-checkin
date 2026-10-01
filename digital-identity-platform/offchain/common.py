"""Shared helpers for the off-chain components: connecting to the local
Hardhat node, loading the deployed contracts, accounts, and sending signed
transactions while timing them.

AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01. Per the
coursebook GenAI rules it must be reviewed by the team and declared in the
report's AI statement.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path

from eth_account import Account
from eth_account.signers.local import LocalAccount
from web3 import Web3
from web3.contract.contract import ContractFunction

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OFFCHAIN_DIR = PROJECT_ROOT / "offchain"
ARTIFACTS_DIR = PROJECT_ROOT / "artifacts" / "contracts"
DEPLOYED_ADDRESSES = PROJECT_ROOT / "ignition" / "deployments" / "chain-31337" / "deployed_addresses.json"

DEFAULT_RPC = "http://127.0.0.1:8545"
LOCAL_CHAIN_ID = 31337
CONTRACT_NAMES = (
    "DigitalIdentityRegistry",
    "ConsentManager",
    "DataSharingManager",
    "AccessLogger",
    "AccessToken",
)

# Matches ConsentManager.Scope and AccessLogger.Outcome / AccessLogger.Reason.
SCOPES = ("FRONT_ONLY", "BACK_ONLY", "BOTH")
OUTCOMES = ("DENIED", "GRANTED")
REASONS = ("NONE", "NO_CONSENT", "REVOKED", "EXPIRED")

# The well-known, public test mnemonic every `npx hardhat node` uses. Its keys
# hold ETH only on local development chains; never use it anywhere else.
HARDHAT_MNEMONIC = "test test test test test test test test test test test junk"

Account.enable_unaudited_hdwallet_features()


class SetupError(RuntimeError):
    """The node isn't running or the contracts aren't deployed."""


def connect(rpc_url: str = DEFAULT_RPC) -> Web3:
    w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={"timeout": 60}))
    if not w3.is_connected():
        raise SetupError(f"No node at {rpc_url}. Start one with `npx hardhat node`.")
    if w3.eth.chain_id != LOCAL_CHAIN_ID:
        raise SetupError(f"Expected the local Hardhat chain ({LOCAL_CHAIN_ID}), got chain id {w3.eth.chain_id}.")
    return w3


def load_abi(name: str) -> list:
    path = ARTIFACTS_DIR / f"{name}.sol" / f"{name}.json"
    if not path.exists():
        raise SetupError(f"Missing {path}. Run `npx hardhat compile`.")
    return json.loads(path.read_text())["abi"]


def load_contracts(w3: Web3) -> dict:
    """The five deployed contracts, keyed by contract name."""
    if not DEPLOYED_ADDRESSES.exists():
        raise SetupError(f"Missing {DEPLOYED_ADDRESSES}. Run `npm run deploy:local`.")
    addresses = json.loads(DEPLOYED_ADDRESSES.read_text())
    contracts = {}
    for name in CONTRACT_NAMES:
        address = addresses[f"DigitalIdentityPlatform#{name}"]
        if w3.eth.get_code(address) in (b"", b"\x00"):
            raise SetupError(
                f"No code at {address} ({name}). The node was probably restarted: "
                "run `npm run deploy:local -- --reset`."
            )
        contracts[name] = w3.eth.contract(address=address, abi=load_abi(name))
    return contracts


def hardhat_account(index: int) -> LocalAccount:
    """Account #index of `npx hardhat node` (#0 deploys the contracts and is the admin)."""
    return Account.from_mnemonic(HARDHAT_MNEMONIC, account_path=f"m/44'/60'/0'/0/{index}")


def derived_account(seed: str, label: str) -> LocalAccount:
    """A fresh, reproducible account for the simulation: same seed + label, same key."""
    return Account.from_key(Web3.keccak(text=f"{seed}/{label}"))


@dataclass
class Pending:
    tx_hash: bytes
    sender: str
    sent_at: float
    label: str


@dataclass
class Sent:
    tx_hash: str
    sender: str
    label: str
    receipt: dict
    latency_s: float


class TxSender:
    """Signs transactions locally and tracks nonces, so one account can have
    several transactions in flight (needed when blocks are mined on an interval)."""

    GAS_LIMIT = 300_000  # fixed, so no estimate is needed; above any function's cost (max ~210k) yet 50 fit in a block

    def __init__(self, w3: Web3):
        self.w3 = w3
        self.chain_id = w3.eth.chain_id
        self.nonces: dict[str, int] = {}

    def _base_tx(self, account: LocalAccount) -> dict:
        address = account.address
        if address not in self.nonces:
            self.nonces[address] = self.w3.eth.get_transaction_count(address, "pending")
        nonce = self.nonces[address]
        self.nonces[address] += 1
        return {
            "from": address,
            "nonce": nonce,
            "chainId": self.chain_id,
            "maxFeePerGas": Web3.to_wei(20, "gwei"),
            "maxPriorityFeePerGas": Web3.to_wei(1, "gwei"),
        }

    def send(self, account: LocalAccount, call: ContractFunction, label: str, gas: int = GAS_LIMIT) -> Pending:
        """Send a contract call, e.g. `contract.functions.registerUser(...)`."""
        tx = call.build_transaction({**self._base_tx(account), "gas": gas})
        return self._send_signed(account, tx, label)

    def send_eth(self, account: LocalAccount, to: str, value_wei: int, label: str = "fund") -> Pending:
        tx = {**self._base_tx(account), "to": to, "value": value_wei, "gas": 21_000}
        tx.pop("from")
        return self._send_signed(account, tx, label)

    def _send_signed(self, account: LocalAccount, tx: dict, label: str) -> Pending:
        signed = account.sign_transaction(tx)
        sent_at = time.perf_counter()
        tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
        return Pending(tx_hash, account.address, sent_at, label)

    def wait(self, pending: Pending, require_success: bool = True) -> Sent:
        receipt = self.w3.eth.wait_for_transaction_receipt(pending.tx_hash, timeout=300, poll_latency=0.02)
        latency = time.perf_counter() - pending.sent_at
        if require_success and receipt["status"] != 1:
            raise RuntimeError(f"{pending.label} from {pending.sender} reverted: {pending.tx_hash.hex()}")
        return Sent("0x" + pending.tx_hash.hex().removeprefix("0x"), pending.sender, pending.label, receipt, latency)

    def transact(self, account: LocalAccount, call: ContractFunction, label: str) -> Sent:
        """Send and wait for the receipt."""
        return self.wait(self.send(account, call, label))


def increase_time(w3: Web3, seconds: int) -> None:
    """Move the local chain's clock forward and mine a block (Hardhat only)."""
    w3.provider.make_request("evm_increaseTime", [seconds])
    w3.provider.make_request("evm_mine", [])
