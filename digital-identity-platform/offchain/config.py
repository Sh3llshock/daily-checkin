"""
Settings shared by the off-chain scripts.
"""

import json
import os
from web3 import Web3

RPC_URL = "http://127.0.0.1:8545"

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(BASE_DIR)
VAULT_DIR = os.path.join(BASE_DIR, "vault")
DOWNLOAD_DIR = os.path.join(BASE_DIR, "downloads")

ARTIFACTS_DIR = os.path.join(PROJECT_DIR, "artifacts", "contracts")
DEPLOYMENT_FILE = os.path.join(PROJECT_DIR, "ignition", "deployments", "chain-31337", "deployed_addresses.json")

# Default hardhat node accounts. These keys are public (printed by
# `npx hardhat node`) and only work on the local test chain.
ADMIN = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
PATIENT = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
DOCTOR = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
STRANGER = "0x90F79bf6EB2c4f870365E785982E1f101E93b906"

DOCTOR_KEY = "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
STRANGER_KEY = "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"

# how long a granted request can be used to fetch the files (seconds)
MAX_REQUEST_AGE = 10 * 60


def connect():
    w3 = Web3(Web3.HTTPProvider(RPC_URL))
    if not w3.is_connected():
        raise SystemExit("Cannot reach " + RPC_URL + ", start it with: npx hardhat node")
    return w3


def load_contract(w3, name):
    """Load a deployed contract using the ignition addresses and the hardhat artifact."""
    if not os.path.exists(DEPLOYMENT_FILE):
        raise SystemExit("Contracts not deployed yet, run: npm run deploy:local")

    with open(DEPLOYMENT_FILE) as f:
        addresses = json.load(f)
    with open(os.path.join(ARTIFACTS_DIR, name + ".sol", name + ".json")) as f:
        abi = json.load(f)["abi"]

    address = addresses["PlatformModule#" + name]
    return w3.eth.contract(address=address, abi=abi)
