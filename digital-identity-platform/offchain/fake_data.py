"""Generates a user's local identity files with FAKE data only.

Every value is made up: placeholder names, a "TST-" ID number, the fictional
ICAO specimen country "UTO" (Utopia) and `.invalid` email addresses, so no
real person's data is ever used (brief Step 4, TASKS B3).

Layout, one directory per user:
    <data-dir>/<user-address>/id_front.json   front of the ID card
    <data-dir>/<user-address>/id_back.json    back of the ID card
    <data-dir>/<user-address>/profile.json    local only (the email to hash)

Usage:
    python offchain/fake_data.py 0xUserAddress [--data-dir offchain/data]

AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01. Per the
coursebook GenAI rules it must be reviewed by the team and declared in the
report's AI statement.
"""

from __future__ import annotations

import argparse
import json
import random
from datetime import date, timedelta
from pathlib import Path

from web3 import Web3

from hash_tool import BACK_FILE, FRONT_FILE, PROFILE_FILE

DEFAULT_DATA_DIR = Path(__file__).resolve().parent / "data"

GIVEN_NAMES = ["Alex", "Sam", "Jordan", "Taylor", "Casey", "Robin", "Jamie", "Morgan", "Riley", "Avery"]
SURNAMES = ["Specimen", "Example", "Sample", "Placeholder", "Testperson", "Mockford", "Dummington", "Fakeley"]


def _write_json(path: Path, value: dict) -> None:
    # Fixed formatting, so the bytes (and therefore the hash) are reproducible.
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def fake_identity(address: str) -> dict:
    """Deterministic fake identity: the same address always gets the same data."""
    rng = random.Random(address.lower())
    given = rng.choice(GIVEN_NAMES)
    surname = rng.choice(SURNAMES)
    born = date(1950, 1, 1) + timedelta(days=rng.randrange(365 * 55))
    expires = date(2027, 1, 1) + timedelta(days=rng.randrange(365 * 8))
    id_number = f"TST-{rng.randrange(10**4):04d}-{rng.randrange(10**4):04d}"
    return {
        "front": {
            "synthetic_test_data": True,
            "document": "NATIONAL IDENTITY CARD (SPECIMEN)",
            "country": "UTO",
            "surname": surname.upper(),
            "given_names": given.upper(),
            "id_number": id_number,
            "date_of_birth": born.isoformat(),
            "expiry_date": expires.isoformat(),
            "photo": "placeholder-no-real-photo",
        },
        "back": {
            "synthetic_test_data": True,
            "address": f"{rng.randrange(1, 200)} Example Street, Testville",
            "issuing_authority": "Ministry of Placeholder Affairs",
            "issue_date": (expires - timedelta(days=365 * 10)).isoformat(),
            "mrz": f"IDUTO{id_number.replace('-', '')}<<<<<<<<<<<<<<<",
        },
        "profile": {
            "synthetic_test_data": True,
            "email": f"{given}.{surname}.{address[2:8]}@example.invalid".lower(),
        },
    }


def write_user_files(address: str, data_dir: Path = DEFAULT_DATA_DIR) -> Path:
    """Create (or overwrite) a user's fake ID files; returns the user's directory."""
    address = Web3.to_checksum_address(address)
    identity = fake_identity(address)
    user_dir = Path(data_dir) / address
    user_dir.mkdir(parents=True, exist_ok=True)
    _write_json(user_dir / FRONT_FILE, identity["front"])
    _write_json(user_dir / BACK_FILE, identity["back"])
    _write_json(user_dir / PROFILE_FILE, identity["profile"])
    return user_dir


def main() -> None:
    parser = argparse.ArgumentParser(description="Write fake ID files for a user address.")
    parser.add_argument("address")
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    args = parser.parse_args()
    print(write_user_files(args.address, args.data_dir))


if __name__ == "__main__":
    main()
