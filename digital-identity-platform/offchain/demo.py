"""Short live demo for the presentation (slide 8): one patient, one provider.

    patient registers -> admin whitelists the provider -> patient grants 30 days
    -> provider: GRANTED, gatekeeper releases the files, hashes match
    -> patient revokes -> provider: DENIED (REVOKED), gatekeeper refuses
    -> the patient's on-chain access log

Uses Hardhat accounts #0 (admin), #1 (patient) and #2 (provider), and the fake
files in offchain/data/<patient-address>/. Safe to run more than once: steps
that are already done (registration, whitelisting) are skipped.

    npx hardhat node && npm run deploy:local     # first, in another terminal
    python offchain/demo.py

AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01. Per the
coursebook GenAI rules it must be reviewed by the team and declared in the
report's AI statement.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone

from web3.logs import DISCARD

from common import OFFCHAIN_DIR, OUTCOMES, REASONS, TxSender, connect, hardhat_account, load_contracts
from fake_data import write_user_files
from gatekeeper import AccessRefused, Gatekeeper, request_files, start_server, user_link, verify_files
from hash_tool import registration_values

DATA_DIR = OFFCHAIN_DIR / "data"
SCOPE_BOTH = 2


def step(text: str) -> None:
    print(f"\n▶ {text}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Presentation demo: grant, access, revoke, deny.")
    parser.add_argument("--port", type=int, default=8600, help="gatekeeper port")
    args = parser.parse_args()

    w3 = connect()
    c = load_contracts(w3)
    registry, consent, dsm, log = (c[n] for n in ("DigitalIdentityRegistry", "ConsentManager", "DataSharingManager", "AccessLogger"))
    sender = TxSender(w3)
    admin, patient, provider = hardhat_account(0), hardhat_account(1), hardhat_account(2)
    base_url = f"http://127.0.0.1:{args.port}"
    server = start_server(Gatekeeper(w3, c, DATA_DIR), port=args.port)

    try:
        step(f"Patient {patient.address} keeps fake ID files locally and hashes them (SHA-256)")
        user_dir = DATA_DIR / patient.address
        if not user_dir.exists():
            write_user_files(patient.address, DATA_DIR)
        email_hash, front, back = registration_values(user_dir)
        print(f"  frontHash 0x{front.hex()}\n  backHash  0x{back.hex()}")

        step("Patient registers: only the email hash, the gatekeeper link and the two hashes go on-chain")
        if registry.functions.isRegistered(patient.address).call():
            print("  already registered (skipped)")
        else:
            sent = sender.transact(patient, registry.functions.registerUser(email_hash, user_link(base_url, patient.address), front, back), "register")
            print(f"  registerUser: {sent.receipt['gasUsed']:,} gas")

        step(f"Admin whitelists provider {provider.address}")
        if registry.functions.isApprovedRequester(provider.address).call():
            print("  already whitelisted (skipped)")
        else:
            sent = sender.transact(admin, registry.functions.setRequesterStatus(provider.address, True), "whitelist")
            print(f"  setRequesterStatus: {sent.receipt['gasUsed']:,} gas")

        step("Patient grants the provider consent: both sides of the ID, 30 days")
        balance_before = c["AccessToken"].functions.balanceOf(patient.address).call()
        sent = sender.transact(patient, consent.functions.setConsent(provider.address, SCOPE_BOTH, 30), "grant")
        minted = c["AccessToken"].functions.balanceOf(patient.address).call() - balance_before
        print(f"  setConsent: {sent.receipt['gasUsed']:,} gas, ACT reward minted: {minted / 1e18:g} (only on the first grant)")

        step("Provider requests access")
        granted = sender.transact(provider, dsm.functions.requestAccess(patient.address), "requestAccess")
        if not dsm.events.AccessGranted().process_receipt(granted.receipt, errors=DISCARD):
            raise RuntimeError("expected AccessGranted: is the provider whitelisted and the consent valid?")
        print(f"  GRANTED and logged ({granted.receipt['gasUsed']:,} gas), tx {granted.tx_hash}")

        step("Provider shows that transaction to the gatekeeper, signed with its own key")
        _, link, front_on_chain, back_on_chain, _ = registry.functions.getUserRecord(patient.address).call()
        files = request_files(link, provider, patient.address, granted.tx_hash)
        verify_files(files, front_on_chain, back_on_chain)
        print(f"  received {', '.join(sorted(files))}; re-hashed: both match the on-chain hashes ✔")

        step("Patient revokes consent")
        sent = sender.transact(patient, consent.functions.revokeConsent(provider.address), "revoke")
        print(f"  revokeConsent: {sent.receipt['gasUsed']:,} gas")

        step("Provider requests access again")
        denied = sender.transact(provider, dsm.functions.requestAccess(patient.address), "requestAccess")
        reason = REASONS[dsm.events.AccessDenied().process_receipt(denied.receipt, errors=DISCARD)[0]["args"]["reason"]]
        print(f"  DENIED ({reason}), logged, no revert ({denied.receipt['gasUsed']:,} gas)")

        step("Provider tries the gatekeeper with its old GRANTED transaction")
        try:
            request_files(link, provider, patient.address, granted.tx_hash)
            print("  ✘ files released (this should not happen)")
        except AccessRefused as refused:
            print(f"  refused: {refused.code} ({refused.detail})")

        step("The patient's on-chain access log (append-only, public)")
        for requester, timestamp, outcome, why in log.functions.getLogs(patient.address).call()[-2:]:
            when = datetime.fromtimestamp(timestamp, timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
            print(f"  {when}  {OUTCOMES[outcome]:<8} {REASONS[why] if outcome == 0 else '':<8} requester {requester}")
    finally:
        server.shutdown()


if __name__ == "__main__":
    main()
