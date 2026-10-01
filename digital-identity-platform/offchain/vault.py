"""
The patient's vault. It holds the ID photos off-chain and only hands them
to a requester that can show a successful requestAccess transaction on-chain.
So every download is also in the on-chain audit log.
"""

import os
import shutil
from eth_account import Account
from eth_account.messages import encode_defunct
from web3.logs import DISCARD

from config import VAULT_DIR, MAX_REQUEST_AGE

# Scope enum from ConsentManager.sol
FRONT_ONLY, BACK_ONLY, BOTH = 0, 1, 2


class Vault:
    def __init__(self, w3, patient_address, patient_id, data_sharing, consent_manager):
        self.w3 = w3
        self.patient = patient_address
        self.folder = os.path.join(VAULT_DIR, patient_id)
        self.data_sharing = data_sharing
        self.consent_manager = consent_manager
        self.used_requests = set()   # a granted tx can only be used once

    def release(self, tx_hash, signature, out_folder):
        """
        Checks the request and copies the allowed files to out_folder.
        Returns the list of copied files, raises PermissionError otherwise.
        """
        if tx_hash in self.used_requests:
            raise PermissionError("request already used")

        receipt = self.w3.eth.get_transaction_receipt(tx_hash)
        if receipt["status"] != 1 or receipt["to"] != self.data_sharing.address:
            raise PermissionError("not a DataSharing transaction")

        # look for the AccessGranted event for this patient
        events = self.data_sharing.events.AccessGranted().process_receipt(receipt, errors=DISCARD)
        events = [e for e in events if e["args"]["patient"] == self.patient]
        if len(events) == 0:
            raise PermissionError("access was not granted on-chain")
        requester = events[0]["args"]["requester"]
        scope = events[0]["args"]["scope"]

        # the person asking must own the requester address (signature check)
        signer = Account.recover_message(encode_defunct(text=tx_hash), signature=signature)
        if signer != requester:
            raise PermissionError("signature does not match the requester")

        block = self.w3.eth.get_block(receipt["blockNumber"])
        latest = self.w3.eth.get_block("latest")
        if latest["timestamp"] - block["timestamp"] > MAX_REQUEST_AGE:
            raise PermissionError("request is too old, request access again")

        # consent could have been revoked after the request
        if not self.consent_manager.functions.isConsentValid(self.patient, requester).call():
            raise PermissionError("consent is not valid anymore")

        files = []
        if scope in (FRONT_ONLY, BOTH):
            files.append("id_front.png")
        if scope in (BACK_ONLY, BOTH):
            files.append("id_back.png")

        os.makedirs(out_folder, exist_ok=True)
        for name in files:
            shutil.copy(os.path.join(self.folder, name), os.path.join(out_folder, name))

        self.used_requests.add(tx_hash)
        return files
