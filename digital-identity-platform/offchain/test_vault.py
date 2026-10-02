"""
Tests for the patient's vault (vault.py) against a running local node.

  terminal 1:  npx hardhat node
  terminal 2:  npm run deploy:local
               python -m unittest discover -s offchain -p "test_*.py" -v

Each test is one release or refusal case the vault must handle. They only use
the public Hardhat test accounts and generated files, no personal data.

AI-assisted: written with Claude Code on 2026-10-02; reviewed by the team and
declared in the report's AI statement.
"""

import os
import secrets
import shutil
import tempfile
import unittest

from eth_account import Account
from eth_account.messages import encode_defunct
from web3.logs import DISCARD

import config
from hash_tool import sha256_file
from vault import Vault, FRONT_ONLY, BACK_ONLY, BOTH

# More public hardhat node keys (printed by `npx hardhat node`), local chain only.
PATIENT_A_KEY = "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a"  # account #4
LAB_KEY = "0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba"        # account #5
PATIENT_B_KEY = "0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e"  # account #6

PATIENT_A_ID = "test-vault-a"
PATIENT_B_ID = "test-vault-b"


def _fake_file(label):
    """A small generated file standing in for an ID photo. Not an image, no personal data."""
    return b"\x89PNG\r\n\x1a\n" + label.encode() + secrets.token_bytes(64)


class VaultTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.w3 = config.connect()
        cls.identity = config.load_contract(cls.w3, "DigitalIdentity")
        cls.consent = config.load_contract(cls.w3, "ConsentManager")
        cls.sharing = config.load_contract(cls.w3, "DataSharing")

        cls.doctor = config.DOCTOR
        cls.lab = Account.from_key(LAB_KEY).address
        cls.patient_a = Account.from_key(PATIENT_A_KEY).address
        cls.patient_b = Account.from_key(PATIENT_B_KEY).address
        unlocked = set(cls.w3.eth.accounts)
        for addr in (cls.doctor, cls.lab, cls.patient_a, cls.patient_b, config.STRANGER):
            assert addr in unlocked, addr + " is not an unlocked hardhat account"

        for requester in (cls.doctor, cls.lab):
            if not cls.identity.functions.isApprovedRequester(requester).call():
                cls._send(cls.identity.functions.approveRequester(requester), config.ADMIN)

        cls.folders = []
        cls._setup_patient(cls.patient_a, PATIENT_A_ID)
        cls._setup_patient(cls.patient_b, PATIENT_B_ID)
        cls.vault_a = Vault(cls.w3, cls.patient_a, PATIENT_A_ID, cls.sharing, cls.consent)
        cls.vault_b = Vault(cls.w3, cls.patient_b, PATIENT_B_ID, cls.sharing, cls.consent)

    @classmethod
    def tearDownClass(cls):
        for folder in cls.folders:
            shutil.rmtree(folder, ignore_errors=True)

    @classmethod
    def _send(cls, fn, sender):
        tx_hash = fn.transact({"from": sender})
        return cls.w3.eth.wait_for_transaction_receipt(tx_hash)

    @classmethod
    def _setup_patient(cls, address, patient_id):
        """Generated vault files plus an on-chain record whose hashes match them."""
        folder = os.path.join(config.VAULT_DIR, patient_id)
        os.makedirs(folder, exist_ok=True)
        cls.folders.append(folder)
        for name in ("id_front.png", "id_back.png"):
            with open(os.path.join(folder, name), "wb") as f:
                f.write(_fake_file(patient_id + name))
        front = sha256_file(os.path.join(folder, "id_front.png"))
        back = sha256_file(os.path.join(folder, "id_back.png"))
        ref = "vault://" + patient_id
        if cls.identity.functions.isRegistered(address).call():
            cls._send(cls.identity.functions.updateDocument(ref, front, back), address)
        else:
            email_hash = "0x" + secrets.token_hex(32)
            cls._send(cls.identity.functions.registerUser(email_hash, ref, front, back), address)

    # --- helpers ---------------------------------------------------------

    def _grant(self, patient, requester, scope, days=30):
        self._send(self.consent.functions.grantConsent(requester, scope, days), patient)

    def _revoke_if_active(self, patient, requester):
        if self.consent.functions.isConsentValid(patient, requester).call():
            self._send(self.consent.functions.revokeConsent(requester), patient)

    def _request(self, patient, requester, key):
        """Requester calls requestAccess and signs the tx hash for the vault, like demo.py."""
        receipt = self._send(self.sharing.functions.requestAccess(patient), requester)
        tx_hash = receipt["transactionHash"].to_0x_hex()
        signature = Account.sign_message(encode_defunct(text=tx_hash), private_key=key).signature
        granted = len(self.sharing.events.AccessGranted().process_receipt(receipt, errors=DISCARD)) > 0
        return tx_hash, signature, granted

    def _out(self):
        folder = tempfile.mkdtemp(prefix="vault-test-")
        self.addCleanup(shutil.rmtree, folder, ignore_errors=True)
        return folder

    def _on_chain_hashes(self, patient):
        user = self.identity.functions.getUser(patient).call()
        return {"id_front.png": "0x" + user[1].hex(), "id_back.png": "0x" + user[2].hex()}

    # --- release ---------------------------------------------------------

    def test_release_both_files_with_matching_hashes(self):
        self._grant(self.patient_a, self.doctor, BOTH)
        tx_hash, sig, granted = self._request(self.patient_a, self.doctor, config.DOCTOR_KEY)
        self.assertTrue(granted)

        out = self._out()
        files = self.vault_a.release(tx_hash, sig, out)

        self.assertEqual(sorted(files), ["id_back.png", "id_front.png"])
        expected = self._on_chain_hashes(self.patient_a)
        for name in files:
            self.assertEqual(sha256_file(os.path.join(out, name)), expected[name])

    def test_front_only_scope_releases_only_the_front(self):
        self._grant(self.patient_a, self.lab, FRONT_ONLY)
        tx_hash, sig, _ = self._request(self.patient_a, self.lab, LAB_KEY)

        out = self._out()
        files = self.vault_a.release(tx_hash, sig, out)

        self.assertEqual(files, ["id_front.png"])
        self.assertFalse(os.path.exists(os.path.join(out, "id_back.png")))

    def test_back_only_scope_releases_only_the_back(self):
        self._grant(self.patient_a, self.lab, BACK_ONLY)
        tx_hash, sig, _ = self._request(self.patient_a, self.lab, LAB_KEY)

        out = self._out()
        files = self.vault_a.release(tx_hash, sig, out)

        self.assertEqual(files, ["id_back.png"])
        self.assertFalse(os.path.exists(os.path.join(out, "id_front.png")))

    # --- refusals --------------------------------------------------------

    def test_same_request_cannot_be_used_twice(self):
        self._grant(self.patient_a, self.doctor, BOTH)
        tx_hash, sig, _ = self._request(self.patient_a, self.doctor, config.DOCTOR_KEY)
        self.vault_a.release(tx_hash, sig, self._out())

        with self.assertRaisesRegex(PermissionError, "already used"):
            self.vault_a.release(tx_hash, sig, self._out())

    def test_signature_must_come_from_the_requester(self):
        self._grant(self.patient_a, self.doctor, BOTH)
        tx_hash, _, _ = self._request(self.patient_a, self.doctor, config.DOCTOR_KEY)
        # a stranger who saw the public tx hash signs it with their own key
        stranger_sig = Account.sign_message(encode_defunct(text=tx_hash), private_key=config.STRANGER_KEY).signature

        with self.assertRaisesRegex(PermissionError, "signature does not match"):
            self.vault_a.release(tx_hash, stranger_sig, self._out())

    def test_denied_request_is_refused(self):
        self._revoke_if_active(self.patient_a, self.doctor)
        tx_hash, sig, granted = self._request(self.patient_a, self.doctor, config.DOCTOR_KEY)
        self.assertFalse(granted)  # logged on-chain as denied, so there is no AccessGranted event

        with self.assertRaisesRegex(PermissionError, "not granted"):
            self.vault_a.release(tx_hash, sig, self._out())

    def test_request_for_another_patient_is_refused(self):
        self._grant(self.patient_a, self.doctor, BOTH)
        tx_hash, sig, _ = self._request(self.patient_a, self.doctor, config.DOCTOR_KEY)

        # a granted request for patient A is shown to patient B's vault
        with self.assertRaisesRegex(PermissionError, "not granted"):
            self.vault_b.release(tx_hash, sig, self._out())

    def test_transaction_to_another_contract_is_refused(self):
        # a real, successful transaction, but a grantConsent, not a requestAccess
        receipt = self._send(self.consent.functions.grantConsent(self.doctor, BOTH, 30), self.patient_a)
        tx_hash = receipt["transactionHash"].to_0x_hex()
        sig = Account.sign_message(encode_defunct(text=tx_hash), private_key=PATIENT_A_KEY).signature

        with self.assertRaisesRegex(PermissionError, "not a DataSharing transaction"):
            self.vault_a.release(tx_hash, sig, self._out())

    def test_unknown_transaction_is_refused(self):
        tx_hash = "0x" + secrets.token_hex(32)
        sig = Account.sign_message(encode_defunct(text=tx_hash), private_key=config.DOCTOR_KEY).signature

        with self.assertRaisesRegex(PermissionError, "unknown transaction"):
            self.vault_a.release(tx_hash, sig, self._out())

    def test_revocation_after_the_request_blocks_release(self):
        self._grant(self.patient_a, self.doctor, BOTH)
        tx_hash, sig, granted = self._request(self.patient_a, self.doctor, config.DOCTOR_KEY)
        self.assertTrue(granted)
        self._send(self.consent.functions.revokeConsent(self.doctor), self.patient_a)

        with self.assertRaisesRegex(PermissionError, "not valid anymore"):
            self.vault_a.release(tx_hash, sig, self._out())

    def test_stale_request_is_refused(self):
        self._grant(self.patient_a, self.doctor, BOTH)
        tx_hash, sig, _ = self._request(self.patient_a, self.doctor, config.DOCTOR_KEY)

        # move the chain more than MAX_REQUEST_AGE into the future
        self.w3.provider.make_request("evm_increaseTime", [config.MAX_REQUEST_AGE + 60])
        self.w3.provider.make_request("evm_mine", [])

        with self.assertRaisesRegex(PermissionError, "too old"):
            self.vault_a.release(tx_hash, sig, self._out())


if __name__ == "__main__":
    unittest.main()
