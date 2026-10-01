"""Step 5: multi-user simulation on the local Hardhat network.

Roles: 1 admin (Hardhat account #0, which deployed the contracts), N users and
M requesters. Users and requesters are fresh accounts generated with
eth_account and funded with ETH from account #0, so N isn't limited to the
node's 20 built-in accounts.

For each N (default 5, 10, 25, 50) it runs, phase by phase:
    register -> whitelist requesters -> grant consent -> access (granted)
    -> gatekeeper fetch -> revoke -> access (denied) -> gatekeeper refusal
and records each transaction's `gasUsed` and send-to-receipt time, plus the
time of each gatekeeper round trip. A final experiment pushes extra entries
into one user's log to show what does and doesn't grow.

Prerequisites (from digital-identity-platform/):
    npx hardhat node                 # terminal 1
    npm run deploy:local             # terminal 2 (after a node restart: -- --reset)
    python offchain/simulate.py      # writes offchain/results/

Options: --users 5 10 --requesters 3 --block-time 12 (mine on an interval
instead of instantly, to approximate a public chain), --seed (reproduce a run).

All identity data is fake (see fake_data.py).

AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01. Per the
coursebook GenAI rules it must be reviewed by the team and declared in the
report's AI statement.
"""

from __future__ import annotations

import argparse
import csv
import logging
import secrets
import shutil
import statistics
import time
from dataclasses import dataclass, field
from pathlib import Path

from eth_account.signers.local import LocalAccount
from web3 import Web3
from web3.contract.contract import ContractFunction
from web3.logs import DISCARD

from common import OFFCHAIN_DIR, REASONS, SCOPES, Sent, SetupError, TxSender, connect, derived_account, hardhat_account, load_contracts
from fake_data import write_user_files
from gatekeeper import AccessRefused, Gatekeeper, request_files, start_server, user_link, verify_files, FILES_FOR_SCOPE
from hash_tool import registration_values

logger = logging.getLogger("simulate")

DEFAULT_USERS = (5, 10, 25, 50)
DEFAULT_REQUESTERS = 3
CONSENT_DAYS = 30
FUNDING = Web3.to_wei(1, "ether")
LOG_GROWTH_ENTRIES = (2, 10, 25, 50)

# Platform operations in the order the scenario runs them; "fund (setup)" is
# excluded from the summary because real users would already hold ETH.
TX_OPS = (
    "registerUser",
    "setRequesterStatus",
    "setConsent",
    "requestAccess (granted)",
    "revokeConsent",
    "requestAccess (denied)",
)


@dataclass
class RunResult:
    n_users: int
    n_requesters: int
    txs: list[dict] = field(default_factory=list)
    gatekeeper: list[dict] = field(default_factory=list)
    total_time_s: float = 0.0


class Simulation:
    def __init__(self, w3: Web3, contracts: dict, gatekeeper_url: str, data_dir: Path, seed: str, batch: bool):
        self.w3 = w3
        # With instant mining each transaction is sent and confirmed before the
        # next one; with interval mining a whole phase is sent first, so it
        # lands in the next block(s) the way it would on a public chain.
        self.batch = batch
        self.c = contracts
        self.sender = TxSender(w3)
        self.admin = hardhat_account(0)
        self.gatekeeper_url = gatekeeper_url
        self.data_dir = data_dir
        self.seed = seed

    # --- helpers ---

    def _phase(self, run: RunResult, op: str, jobs: list[tuple[LocalAccount, ContractFunction, str]]) -> list[Sent]:
        """Run one phase's transactions and record their gas and confirmation time."""
        if self.batch:
            pending = [(self.sender.send(account, call, op), target) for account, call, target in jobs]
            results = [(self.sender.wait(p), target) for p, target in pending]
        else:
            results = [(self.sender.wait(self.sender.send(account, call, op)), target) for account, call, target in jobs]
        sent = []
        for result, target in results:
            sent.append(result)
            if op != "fund (setup)":
                run.txs.append(
                    {
                        "n_users": run.n_users,
                        "n_requesters": run.n_requesters,
                        "op": op,
                        "sender": result.sender,
                        "target": target,
                        "tx_hash": result.tx_hash,
                        "block": result.receipt["blockNumber"],
                        "gas_used": result.receipt["gasUsed"],
                        "latency_ms": round(result.latency_s * 1000, 2),
                    }
                )
        return sent

    def _fund(self, accounts: list[LocalAccount]) -> None:
        pending = [self.sender.send_eth(self.admin, a.address, FUNDING) for a in accounts]
        for p in pending:
            self.sender.wait(p)

    def _gatekeeper_call(self, run: RunResult, check: str, requester: LocalAccount, user: str, tx_hash: str, expect: str) -> None:
        link = self.c["DigitalIdentityRegistry"].functions.getUserRecord(user).call()[1]
        started = time.perf_counter()
        try:
            files = request_files(link, requester, user, tx_hash)
            outcome = "released"
        except AccessRefused as refused:
            files, outcome = {}, refused.code
        elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
        if outcome != expect:
            raise RuntimeError(f"gatekeeper {check}: expected {expect}, got {outcome} (user {user}, tx {tx_hash})")
        if files:
            _, _, front, back, _ = self.c["DigitalIdentityRegistry"].functions.getUserRecord(user).call()
            verify_files(files, front, back)  # the requester re-hashes what it received
            scope = SCOPES[self.c["ConsentManager"].functions.getConsent(user, requester.address).call()[0]]
            if tuple(sorted(files)) != tuple(sorted(FILES_FOR_SCOPE[scope])):
                raise RuntimeError(f"gatekeeper released {sorted(files)} for scope {scope}")
        run.gatekeeper.append(
            {
                "n_users": run.n_users,
                "n_requesters": run.n_requesters,
                "check": check,
                "requester": requester.address,
                "user": user,
                "outcome": outcome,
                "files": "+".join(sorted(files)),
                "hashes_match": bool(files),
                "latency_ms": elapsed_ms,
            }
        )

    def _events(self, sent: Sent, name: str) -> list:
        event = getattr(self.c["DataSharingManager"].events, name)()
        return [e for e in event.process_receipt(sent.receipt, errors=DISCARD) if e["address"] == self.c["DataSharingManager"].address]

    # --- the scenario ---

    def run(self, n_users: int, n_requesters: int) -> RunResult:
        run = RunResult(n_users, n_requesters)
        label = f"{self.seed}/N{n_users}"
        users = [derived_account(label, f"user-{i}") for i in range(n_users)]
        requesters = [derived_account(label, f"requester-{j}") for j in range(n_requesters)]
        registry, consent, dsm = self.c["DigitalIdentityRegistry"], self.c["ConsentManager"], self.c["DataSharingManager"]
        if registry.functions.isRegistered(users[0].address).call():
            raise SetupError(f"Seed {self.seed!r} was already used on this chain; pass a different --seed.")

        # Setup (not measured): fake local data for each user, ETH for gas.
        for user in users:
            write_user_files(user.address, self.data_dir)
        self._fund(users + requesters)
        requester_of = {u.address: requesters[i % n_requesters] for i, u in enumerate(users)}

        started = time.perf_counter()

        jobs = []
        for user in users:
            email, front, back = registration_values(self.data_dir / user.address)
            link = user_link(self.gatekeeper_url, user.address)
            jobs.append((user, registry.functions.registerUser(email, link, front, back), user.address))
        self._phase(run, "registerUser", jobs)

        self._phase(run, "setRequesterStatus", [(self.admin, registry.functions.setRequesterStatus(r.address, True), r.address) for r in requesters])

        jobs = [
            (u, consent.functions.setConsent(requester_of[u.address].address, i % len(SCOPES), CONSENT_DAYS), requester_of[u.address].address)
            for i, u in enumerate(users)
        ]
        self._phase(run, "setConsent", jobs)

        granted = self._phase(run, "requestAccess (granted)", [(requester_of[u.address], dsm.functions.requestAccess(u.address), u.address) for u in users])
        for user, sent in zip(users, granted):
            if not self._events(sent, "AccessGranted"):
                raise RuntimeError(f"expected AccessGranted for {user.address}")

        for user, sent in zip(users, granted):
            self._gatekeeper_call(run, "fetch after GRANTED", requester_of[user.address], user.address, sent.tx_hash, "released")

        self._phase(run, "revokeConsent", [(u, consent.functions.revokeConsent(requester_of[u.address].address), requester_of[u.address].address) for u in users])

        denied = self._phase(run, "requestAccess (denied)", [(requester_of[u.address], dsm.functions.requestAccess(u.address), u.address) for u in users])
        for user, sent in zip(users, denied):
            events = self._events(sent, "AccessDenied")
            if not events or REASONS[events[0]["args"]["reason"]] != "REVOKED":
                raise RuntimeError(f"expected AccessDenied(REVOKED) for {user.address}")

        for user, old, new in zip(users, granted, denied):
            requester = requester_of[user.address]
            self._gatekeeper_call(run, "old GRANTED tx after revoke", requester, user.address, old.tx_hash, "consent_not_valid")
            self._gatekeeper_call(run, "DENIED tx", requester, user.address, new.tx_hash, "access_not_granted")

        run.total_time_s = time.perf_counter() - started

        # Each user's log now holds exactly GRANTED, then DENIED(REVOKED).
        for user in users:
            entries = self.c["AccessLogger"].functions.getLogs(user.address).call()
            if [(e[2], REASONS[e[3]]) for e in entries] != [(1, "NONE"), (0, "REVOKED")]:
                raise RuntimeError(f"unexpected log for {user.address}: {entries}")
        return run

    def log_growth(self, entries_targets: tuple[int, ...] = LOG_GROWTH_ENTRIES) -> list[dict]:
        """Push more entries into one user's log: the write stays flat, the read grows."""
        user = derived_account(f"{self.seed}/growth", "user")
        requester = derived_account(f"{self.seed}/growth", "requester")
        self._fund([user, requester])
        registry, consent, dsm, logger_c = (self.c[n] for n in ("DigitalIdentityRegistry", "ConsentManager", "DataSharingManager", "AccessLogger"))
        write_user_files(user.address, self.data_dir)
        email, front, back = registration_values(self.data_dir / user.address)
        self.sender.transact(user, registry.functions.registerUser(email, user_link(self.gatekeeper_url, user.address), front, back), "register")
        self.sender.transact(self.admin, registry.functions.setRequesterStatus(requester.address, True), "whitelist")
        self.sender.transact(user, consent.functions.setConsent(requester.address, 2, CONSENT_DAYS), "grant")

        rows = []
        count = 0
        for target in entries_targets:
            gas = []
            while count < target:
                gas.append(self.sender.transact(requester, dsm.functions.requestAccess(user.address), "requestAccess").receipt["gasUsed"])
                count += 1
            rows.append(
                {
                    "log_entries": count,
                    "requestAccess_gas_last_write": gas[-1] if gas else "",
                    "getLogs_gas_estimate": logger_c.functions.getLogs(user.address).estimate_gas(),
                }
            )
        return rows


# --- reporting ---------------------------------------------------------------


def _write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        return
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def summarise(run: RunResult) -> dict:
    gas = [t["gas_used"] for t in run.txs]
    latency = [t["latency_ms"] for t in run.txs]
    gk = [g["latency_ms"] for g in run.gatekeeper]
    return {
        "n_users": run.n_users,
        "n_requesters": run.n_requesters,
        "total_txs": len(run.txs),
        "avg_gas_per_tx": round(statistics.mean(gas)),
        "total_gas": sum(gas),
        "avg_confirmation_ms": round(statistics.mean(latency), 2),
        "max_confirmation_ms": round(max(latency), 2),
        "gatekeeper_calls": len(gk),
        "avg_gatekeeper_ms": round(statistics.mean(gk), 2),
        "total_time_s": round(run.total_time_s, 2),
        "throughput_tx_per_s": round(len(run.txs) / run.total_time_s, 1),
    }


def per_op(runs: list[RunResult]) -> list[dict]:
    rows = []
    for op in TX_OPS:
        row = {"op": op}
        for run in runs:
            values = [t["gas_used"] for t in run.txs if t["op"] == op]
            row[f"avg_gas_N{run.n_users}"] = round(statistics.mean(values)) if values else ""
        numbers = [v for k, v in row.items() if k != "op" and v != ""]
        row["spread_pct"] = round((max(numbers) - min(numbers)) / min(numbers) * 100, 2) if numbers else ""
        rows.append(row)
    return rows


def markdown(summaries: list[dict], ops: list[dict], growth: list[dict], mode: str, seed: str) -> str:
    lines = [
        f"# Simulation results ({mode})",
        "",
        f"Generated by `python offchain/simulate.py` (seed `{seed}`). Gas is each receipt's `gasUsed`;",
        "confirmation time is send-to-receipt on the local Hardhat node; total time covers every",
        "platform transaction and gatekeeper call (account funding and data generation excluded).",
        "",
        "## Scaling in cost and time",
        "",
        "| Users (N) | Requesters (M) | Total txs | Avg gas / tx | Total gas | Avg confirmation (ms) | Gatekeeper calls | Avg gatekeeper (ms) | Total time (s) | Throughput (tx/s) |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for s in summaries:
        lines.append(
            f"| {s['n_users']} | {s['n_requesters']} | {s['total_txs']} | {s['avg_gas_per_tx']:,} | {s['total_gas']:,} | "
            f"{s['avg_confirmation_ms']} | {s['gatekeeper_calls']} | {s['avg_gatekeeper_ms']} | {s['total_time_s']} | {s['throughput_tx_per_s']} |"
        )
    header = [k for k in ops[0] if k.startswith("avg_gas_N")]
    lines += [
        "",
        "## Average gas per operation as N grows",
        "",
        "| Operation | " + " | ".join(f"N = {h.removeprefix('avg_gas_N')}" for h in header) + " | Spread |",
        "|---|" + "---:|" * (len(header) + 1),
    ]
    for row in ops:
        lines.append(f"| `{row['op']}` | " + " | ".join(f"{row[h]:,}" for h in header) + f" | {row['spread_pct']}% |")
    if growth:
        lines += [
            "",
            "## One user's log growing (separate experiment)",
            "",
            "| Entries in the user's log | `requestAccess` gas (writing the latest entry) | `getLogs` gas (estimate for reading the whole log) |",
            "|---:|---:|---:|",
        ]
        for g in growth:
            lines.append(f"| {g['log_entries']} | {g['requestAccess_gas_last_write']:,} | {g['getLogs_gas_estimate']:,} |")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Step 5 multi-user simulation.")
    parser.add_argument("--rpc", default="http://127.0.0.1:8545")
    parser.add_argument("--users", type=int, nargs="+", default=list(DEFAULT_USERS))
    parser.add_argument("--requesters", type=int, default=DEFAULT_REQUESTERS)
    parser.add_argument("--block-time", type=float, default=0, help="seconds between blocks; 0 = mine each tx instantly (default)")
    parser.add_argument("--seed", default=None, help="account seed; reuse it on a fresh chain to reproduce a run")
    parser.add_argument("--gatekeeper-port", type=int, default=8600)
    parser.add_argument("--out", type=Path, default=OFFCHAIN_DIR / "results")
    parser.add_argument("--data-dir", type=Path, default=OFFCHAIN_DIR / "sim-data", help="wiped at the start of every run")
    parser.add_argument("--skip-log-growth", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    logging.getLogger("gatekeeper").setLevel(logging.WARNING)

    w3 = connect(args.rpc)
    contracts = load_contracts(w3)
    admin = hardhat_account(0)
    if contracts["DigitalIdentityRegistry"].functions.owner().call() != admin.address:
        raise SetupError("The registry's owner isn't Hardhat account #0; deploy with `npm run deploy:local`.")

    seed = args.seed or secrets.token_hex(4)
    mode = f"block time {args.block_time:g}s" if args.block_time else "automine"
    prefix = f"blocktime{args.block_time:g}s" if args.block_time else "automine"
    shutil.rmtree(args.data_dir, ignore_errors=True)
    args.data_dir.mkdir(parents=True)
    args.out.mkdir(parents=True, exist_ok=True)

    gatekeeper_url = f"http://127.0.0.1:{args.gatekeeper_port}"
    server = start_server(Gatekeeper(w3, contracts, args.data_dir), port=args.gatekeeper_port)
    if args.block_time:
        w3.provider.make_request("evm_setAutomine", [False])
        w3.provider.make_request("evm_setIntervalMining", [int(args.block_time * 1000)])

    sim = Simulation(w3, contracts, gatekeeper_url, args.data_dir, seed, batch=bool(args.block_time))
    runs, summaries = [], []
    try:
        for n in args.users:
            logger.info("N = %d users, M = %d requesters (%s, seed %s)", n, args.requesters, mode, seed)
            run = sim.run(n, args.requesters)
            runs.append(run)
            summaries.append(summarise(run))
            logger.info("  %s", summaries[-1])
            _write_csv(args.out / f"{prefix}_tx_N{n}.csv", run.txs)
            _write_csv(args.out / f"{prefix}_gatekeeper_N{n}.csv", run.gatekeeper)
        growth = [] if args.skip_log_growth else sim.log_growth()
    finally:
        if args.block_time:
            w3.provider.make_request("evm_setIntervalMining", [0])
            w3.provider.make_request("evm_setAutomine", [True])
        server.shutdown()

    ops = per_op(runs)
    _write_csv(args.out / f"{prefix}_summary.csv", summaries)
    _write_csv(args.out / f"{prefix}_gas_per_op.csv", ops)
    _write_csv(args.out / f"{prefix}_log_growth.csv", growth)
    report = markdown(summaries, ops, growth, mode, seed)
    (args.out / f"{prefix}_summary.md").write_text(report)
    print(report)


if __name__ == "__main__":
    main()
