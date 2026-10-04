# ID Share: decentralized digital identity platform

BCS3210 Blockchains group project. Patients keep the photos of their government ID off-chain and only put hashes on the blockchain. Healthcare providers (requesters) can only get the photos with valid, time-limited consent. Every access attempt is logged on-chain, and patients get ACT tokens for giving consent.

## Requirements

- Node.js 22 or newer (Hardhat 3 does not run on older versions)
- Python 3.10 or newer (off-chain part and plots)

## Setup

```
npm install
npx hardhat compile
```

Python part:

```
python -m venv .venv
.venv\Scripts\activate           (Windows)
source .venv/bin/activate        (Linux / macOS)
pip install -r offchain/requirements.txt
```

## Project structure

| Path | Content |
|---|---|
| `contracts/` | `DigitalIdentity`, `ConsentManager`, `DataSharing`, `AccessToken` and small interfaces |
| `test/` | Solidity unit tests (`*.t.sol`) and integration tests |
| `ignition/modules/Platform.ts` | Deploys and connects the four contracts |
| `scripts/demo.ts` | Walks through the whole flow (in-process network) |
| `scripts/gas-report.ts` | Deployment cost and gas per function |
| `scripts/simulate.ts` | Simulation with 5 to 100 patients (time and gas) |
| `scripts/plot_results.py` | Plot of the simulation results |
| `offchain/` | Python: hashing, patient vault, end-to-end demo |
| `results/` | Saved measurements |

## Tests and gas

```
npx hardhat test                    # 65 Solidity tests
npx hardhat test --gas-stats        # same, with gas table
npm run gas-report                  # scenario gas report -> results/gas-report-latest.json
```

## Demo without a node

```
npm run demo
```

## Commands that need a local node

Terminal 1 (keep it running):

```
npx hardhat node
```

Terminal 2:

```
npm run deploy:local                # Ignition, addresses in ignition/deployments/chain-31337/
npm run simulate                    # simulation -> results/simulation-localhost.json
python offchain/make_sample_data.py # fake patient in offchain/vault/
python offchain/demo.py             # vault + hash check end-to-end
python -m unittest discover -s offchain -p "test_*.py"   # 11 vault tests
```

If you restart the node, run `npm run deploy:local` again (it uses `--reset`).

The scripts and the vault use the public Hardhat test accounts, which only work on the local chain. No real personal data is used anywhere: the sample patient and images are generated.
