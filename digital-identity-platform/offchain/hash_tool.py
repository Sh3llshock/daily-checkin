"""
Hashing helpers. The results are what the patient puts on-chain.
"""

import hashlib
import os
import sys
from web3 import Web3


def sha256_file(path):
    """SHA-256 of a file, returned as 0x... hex (fits a bytes32)."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return "0x" + h.hexdigest()


def new_salt():
    """Random 32 byte salt as 0x... hex."""
    return "0x" + os.urandom(32).hex()


def email_hash(salt, email):
    """
    Same as keccak256(abi.encodePacked(salt, email)) in Solidity.
    The email is lowercased first so the patient can reproduce it later.
    """
    return Web3.solidity_keccak(["bytes32", "string"], [salt, email.strip().lower()]).to_0x_hex()


if __name__ == "__main__":
    # usage: python hash_tool.py <file> [<file> ...]
    if len(sys.argv) < 2:
        print("usage: python hash_tool.py <file> [<file> ...]")
    for p in sys.argv[1:]:
        print(p, sha256_file(p))
