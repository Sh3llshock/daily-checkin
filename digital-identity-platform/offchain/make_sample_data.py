"""
Creates a fake patient in the local vault: a profile json and two
generated ID card images. Everything is made up, no real personal data.
"""

import json
import os
from PIL import Image, ImageDraw

from config import VAULT_DIR
from hash_tool import new_salt

PATIENT_ID = "patient1"

profile = {
    "full_name": "Test Patient One",
    "email": "patient1@example.test",
    "date_of_birth": "1990-01-01",
    "id_type": "National ID card",
    "id_number": "TEST-000-001",
    "blood_type": "O+",
}


def make_card(path, lines, color):
    img = Image.new("RGB", (640, 400), color)
    draw = ImageDraw.Draw(img)
    draw.rectangle([10, 10, 630, 390], outline="black", width=3)
    y = 40
    for line in lines:
        draw.text((40, y), line, fill="black")
        y += 40
    img.save(path)


def main():
    folder = os.path.join(VAULT_DIR, PATIENT_ID)
    os.makedirs(folder, exist_ok=True)

    with open(os.path.join(folder, "profile.json"), "w") as f:
        json.dump(profile, f, indent=2)

    make_card(os.path.join(folder, "id_front.png"), [
        "SPECIMEN - NOT A REAL DOCUMENT",
        "NATIONAL ID CARD (front)",
        "Name: " + profile["full_name"],
        "Date of birth: " + profile["date_of_birth"],
        "ID number: " + profile["id_number"],
    ], (200, 220, 255))

    make_card(os.path.join(folder, "id_back.png"), [
        "SPECIMEN - NOT A REAL DOCUMENT",
        "NATIONAL ID CARD (back)",
        "Blood type: " + profile["blood_type"],
        "Issued by: Test Authority",
    ], (220, 255, 220))

    # the salt is only kept by the patient, never put on-chain
    salt_file = os.path.join(folder, "salt.txt")
    if not os.path.exists(salt_file):
        with open(salt_file, "w") as f:
            f.write(new_salt())

    print("Sample data written to", folder)


if __name__ == "__main__":
    main()
