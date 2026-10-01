"""SHA-256 hashing of a user's local ID files, as bytes32 values ready for
`DigitalIdentityRegistry.registerUser`.

The hash covers the file's exact bytes, so the requester can re-hash what the
gatekeeper sends and compare it with the on-chain `frontHash` / `backHash`.

Usage:
    python offchain/hash_tool.py offchain/data/<user-address>

AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01. Per the
coursebook GenAI rules it must be reviewed by the team and declared in the
report's AI statement.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

FRONT_FILE = "id_front.json"
BACK_FILE = "id_back.json"
PROFILE_FILE = "profile.json"  # local only, never served by the gatekeeper


def sha256_bytes(data: bytes) -> bytes:
    """32-byte SHA-256 digest; web3.py passes it to a bytes32 argument as-is."""
    return hashlib.sha256(data).digest()


def sha256_file(path: Path) -> bytes:
    return sha256_bytes(Path(path).read_bytes())


def email_hash(email: str) -> bytes:
    """Hash of the normalised email, used on-chain only for the uniqueness check.

    Unsalted on purpose (the registry must detect a reused email), which also
    means a guessable email can be brute-forced from its hash; see the report's
    Discussion.
    """
    return sha256_bytes(email.strip().lower().encode())


def document_hashes(user_dir: Path) -> tuple[bytes, bytes]:
    """(frontHash, backHash) for the ID files in a user's data directory."""
    user_dir = Path(user_dir)
    return sha256_file(user_dir / FRONT_FILE), sha256_file(user_dir / BACK_FILE)


def registration_values(user_dir: Path) -> tuple[bytes, bytes, bytes]:
    """(emailHash, frontHash, backHash) for `registerUser`."""
    profile = json.loads((Path(user_dir) / PROFILE_FILE).read_text())
    front, back = document_hashes(user_dir)
    return email_hash(profile["email"]), front, back


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("user_dir", type=Path, help="e.g. offchain/data/<user-address>")
    args = parser.parse_args()

    email, front, back = registration_values(args.user_dir)
    print(f"emailHash: 0x{email.hex()}")
    print(f"frontHash: 0x{front.hex()}  ({FRONT_FILE})")
    print(f"backHash:  0x{back.hex()}  ({BACK_FILE})")


if __name__ == "__main__":
    main()
