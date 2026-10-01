"""
End-to-end demo of the off-chain part against a running hardhat node.

  terminal 1:  npx hardhat node
  terminal 2:  npm run deploy:local
               python offchain/make_sample_data.py
               python offchain/demo.py
"""

import json
import os
from eth_account import Account
from eth_account.messages import encode_defunct
from web3.logs import DISCARD

import config
from hash_tool import sha256_file, email_hash
from make_sample_data import PATIENT_ID
from vault import Vault, BOTH

REASONS = ["None", "NotApproved", "NoConsent", "Revoked", "Expired"]


def send(fn, sender):
    """Send a transaction from one of the unlocked hardhat accounts."""
    tx_hash = fn.transact({"from": sender})
    return config.connect().eth.wait_for_transaction_receipt(tx_hash)


def request_access(w3, data_sharing, requester, key):
    """Requester calls requestAccess and signs the tx hash for the vault."""
    receipt = send(data_sharing.functions.requestAccess(config.PATIENT), requester)
    tx_hash = receipt["transactionHash"].to_0x_hex()
    signature = Account.sign_message(encode_defunct(text=tx_hash), private_key=key).signature
    granted = len(data_sharing.events.AccessGranted().process_receipt(receipt, errors=DISCARD)) > 0
    return tx_hash, signature, granted


def check_hashes(identity, folder, files):
    """Requester side: compare the downloaded files with the hashes on-chain."""
    user = identity.functions.getUser(config.PATIENT).call()
    on_chain = {"id_front.png": user[1], "id_back.png": user[2]}
    all_ok = True
    for name in files:
        local = sha256_file(os.path.join(folder, name))
        ok = local == "0x" + on_chain[name].hex()
        all_ok = all_ok and ok
        print("   ", name, "hash matches on-chain" if ok else "HASH MISMATCH, file was changed")
    return all_ok


def main():
    w3 = config.connect()
    identity = config.load_contract(w3, "DigitalIdentity")
    consent = config.load_contract(w3, "ConsentManager")
    sharing = config.load_contract(w3, "DataSharing")
    token = config.load_contract(w3, "AccessToken")

    folder = os.path.join(config.VAULT_DIR, PATIENT_ID)
    if not os.path.exists(folder):
        raise SystemExit("No sample data, run: python offchain/make_sample_data.py")

    print("\n=== Off-chain demo ===\n")

    # 1. admin approves the doctor
    if not identity.functions.isApprovedRequester(config.DOCTOR).call():
        send(identity.functions.approveRequester(config.DOCTOR), config.ADMIN)
    print("1. Doctor approved by admin")

    # 2. patient hashes the files and registers
    with open(os.path.join(folder, "profile.json")) as f:
        profile = json.load(f)
    with open(os.path.join(folder, "salt.txt")) as f:
        salt = f.read().strip()
    front = sha256_file(os.path.join(folder, "id_front.png"))
    back = sha256_file(os.path.join(folder, "id_back.png"))
    e_hash = email_hash(salt, profile["email"])
    print("2. Patient hashes computed")
    print("    email hash:", e_hash)
    print("    front     :", front)
    print("    back      :", back)
    if not identity.functions.isRegistered(config.PATIENT).call():
        send(identity.functions.registerUser(e_hash, "vault://" + PATIENT_ID, front, back), config.PATIENT)
    else:
        send(identity.functions.updateDocument("vault://" + PATIENT_ID, front, back), config.PATIENT)
    print("   Patient registered on-chain")

    vault = Vault(w3, config.PATIENT, PATIENT_ID, sharing, consent)

    # 3. patient gives the doctor consent for both sides, 30 days
    send(consent.functions.grantConsent(config.DOCTOR, BOTH, 30), config.PATIENT)
    balance = token.functions.balanceOf(config.PATIENT).call()
    print("3. Consent granted (Both, 30 days), patient ACT balance:", w3.from_wei(balance, "ether"))

    # 4. doctor requests access and downloads from the vault
    tx_hash, sig, granted = request_access(w3, sharing, config.DOCTOR, config.DOCTOR_KEY)
    print("4. Doctor requestAccess ->", "GRANTED" if granted else "DENIED")
    out = os.path.join(config.DOWNLOAD_DIR, "doctor")
    files = vault.release(tx_hash, sig, out)
    print("   Vault released:", files)
    check_hashes(identity, out, files)

    # 5. the same request cannot be used twice
    try:
        vault.release(tx_hash, sig, out)
    except PermissionError as e:
        print("5. Reusing the same request ->", e)

    # 6. someone else tries to use the doctor's transaction
    stranger_sig = Account.sign_message(encode_defunct(text=tx_hash), private_key=config.STRANGER_KEY).signature
    tx_hash2, sig2, _ = request_access(w3, sharing, config.DOCTOR, config.DOCTOR_KEY)
    try:
        vault.release(tx_hash2, stranger_sig, os.path.join(config.DOWNLOAD_DIR, "stranger"))
    except PermissionError as e:
        print("6. Stranger uses doctor's request ->", e)

    # 7. the file is changed after leaving the vault (e.g. on the way), the doctor notices it
    tampered = os.path.join(config.DOWNLOAD_DIR, "doctor_tampered")
    files = vault.release(tx_hash2, sig2, tampered)
    with open(os.path.join(tampered, "id_front.png"), "ab") as f:
        f.write(b"changed")
    print("7. Front photo changed after download:")
    check_hashes(identity, tampered, files)

    # 8. patient revokes, the doctor is denied and the vault refuses
    send(consent.functions.revokeConsent(config.DOCTOR), config.PATIENT)
    tx_hash3, sig3, granted = request_access(w3, sharing, config.DOCTOR, config.DOCTOR_KEY)
    print("8. Consent revoked, doctor requestAccess ->", "GRANTED" if granted else "DENIED")
    try:
        vault.release(tx_hash3, sig3, out)
    except PermissionError as e:
        print("   Vault ->", e)

    # 9. audit log from the chain
    print("9. Audit log of the patient (on-chain):")
    for i, log in enumerate(sharing.functions.getLogs(config.PATIENT).call()):
        requester, scope, result, reason, timestamp = log
        who = "doctor" if requester == config.DOCTOR else requester
        if result == 0:
            print("    #%d GRANTED %s scope=%d" % (i, who, scope))
        else:
            print("    #%d DENIED  %s reason=%s" % (i, who, REASONS[reason]))
    print()


if __name__ == "__main__":
    main()
