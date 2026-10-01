# Decentralized Digital Identity & Government-ID Sharing Platform

**Domain:** Healthcare — patient identity verification via government-issued ID (front/back)
**Course:** Introduction to Blockchains, DACS, Maastricht University (2026 group project)

This folder is a self-contained project covering every step of the project brief:
research and design (Steps 1–2), the Solidity contracts and Python off-chain modules
(Step 3), tests and gas measurements (Step 4), local deployment and a multi-user
simulation (Step 5), and an optional viem front-end (Step 6).

## Concept in one line

A patient keeps the front and back of their government ID **off-chain**, in a local
data store served by a **gatekeeper**. The blockchain stores only a hash of the email,
the gatekeeper link and a **SHA-256 hash of each ID file**. A healthcare provider gets
the files only while the patient has granted it **time-limited, revocable, scoped
consent**: the provider first calls `requestAccess` on-chain (every attempt, granted
or denied, goes into an append-only audit log), then shows that GRANTED transaction to
the gatekeeper, which checks it on-chain and releases only the files the consent
covers. The provider re-hashes the files against the on-chain hashes. The patient
earns **Access Tokens (ACT)** the first time they consent to each provider; tokens are
an incentive only and never grant access. All identity data in this repository is fake.

## Repository layout

| Path | Contents |
|---|---|
| `contracts/*.sol` | The 5 contracts: `DigitalIdentityRegistry`, `ConsentManager`, `DataSharingManager`, `AccessLogger`, `AccessToken` |
| `contracts/*.t.sol` | Solidity unit tests (one file per contract) and integration tests (`DigitalIdentityPlatform.t.sol`) |
| `contracts/experiments/` | `EventsOnlyAccessLogger.sol`, a gas experiment that is never deployed |
| `ignition/modules/DigitalIdentityPlatform.ts` | Deploys the 5 contracts and wires them together (once) |
| `scripts/gas-benchmark.ts` | Gas per scenario from real transactions (`npm run gas:bench`) |
| `offchain/` | Python: fake local data, SHA-256 hash tool, gatekeeper, simulation, demo, gatekeeper tests |
| `frontend/` | Optional single-page viem UI for the local network (Step 6) |
| `docs/` | Step 1–5 write-ups, diagrams, gas data, references, report and slide drafts |

| Document | Covers |
|---|---|
| [`docs/step1-deliverable.md`](docs/step1-deliverable.md) | Problem statement, prior-art research, user roles, functional requirements, interaction overview |
| [`docs/step2-deliverable.md`](docs/step2-deliverable.md) | Data model, consent model, audit log, smart-contract design, architecture and gatekeeper diagrams |
| [`docs/step3-deliverable.md`](docs/step3-deliverable.md) | Implementation: contracts and Python modules |
| [`docs/step4-deliverable.md`](docs/step4-deliverable.md) | All tests, why each is critical, deployment and per-function gas, before/after optimisation |
| [`docs/step5-deliverable.md`](docs/step5-deliverable.md) | Local deployment and the multi-user simulation: scaling in time and cost |
| [`docs/references.md`](docs/references.md) | Sources for the research and the course material |
| [`docs/study-guide.md`](docs/study-guide.md) | For the team: how every part of the code works, likely examiner questions, self-check exercises |

## Prerequisites

- **Node.js 22 or newer** (tested with 24.15) and npm.
- **Python 3.10 or newer** (tested with 3.12).
- Ports 8545 (Hardhat node) and 8600 (gatekeeper) free.

## 1. Install, compile, test

```bash
cd digital-identity-platform
npm install
npx hardhat compile
npx hardhat test                 # 80 Solidity tests (unit + integration)
npx hardhat test --coverage      # same, with line coverage
npm run test:gas                 # same, with per-function gas statistics
npm run gas:bench                # gas per scenario from real transactions (Step 4 tables)
```

## 2. Deploy to a local chain

```bash
npx hardhat node                 # terminal 1: local chain on http://127.0.0.1:8545, keep it running
npm run deploy:local             # terminal 2: deploys and wires the 5 contracts
```

`npx hardhat node` starts from an empty chain every time. After restarting it,
redeploy with `npm run deploy:local -- --reset` (Ignition otherwise remembers the old
deployment and skips it). The addresses are written to
`ignition/deployments/chain-31337/deployed_addresses.json`, which the Python scripts
and the front-end read.

## 3. Off-chain components and the simulation (Python)

Run these from `digital-identity-platform/`, in terminal 2, with the node from step 2
still running:

```bash
python3 -m venv .venv && source .venv/bin/activate     # Windows: .venv\Scripts\activate
pip install -r offchain/requirements.txt

python offchain/simulate.py      # Step 5: N = 5, 10, 25, 50 users -> offchain/results/
python offchain/demo.py          # the short presentation demo (one patient, one provider)
python -m unittest discover -s offchain -v      # 15 gatekeeper tests
```

- `simulate.py` creates its own accounts, funds them from Hardhat account #0, starts
  the gatekeeper on port 8600, and writes per-transaction CSVs plus
  `offchain/results/automine_summary.md` (the Step 5 tables). Options:
  `--users 5 10`, `--requesters 3`, `--block-time 12` (mine on an interval, like a
  public chain), `--seed <text>` (reproduce a run on a fresh chain).
- The gatekeeper can also run on its own: `python offchain/gatekeeper.py` (serves
  `offchain/data/` on port 8600).
- Hash a user's files: `python offchain/hash_tool.py offchain/data/<address>`.

## 4. Front-end (optional, Step 6)

With the node running and the contracts deployed (step 2):

```bash
python offchain/gatekeeper.py    # serves offchain/data on :8600 (needed to fetch files)
npm run frontend                 # serves http://127.0.0.1:5173
```

Pick a Hardhat test account, then register, grant or revoke consent, request access
as a provider, and view the audit log. See [`frontend/README.md`](frontend/README.md).

## Diagrams

The figures in `docs/diagrams/` are rendered from the `.mmd` sources with
`docs/diagrams/render.sh` (uses `npx @mermaid-js/mermaid-cli`).

## Worked example used in the docs (fictional)

| Field | Example value |
|---|---|
| User | George Papadopoulos (fictional patient) |
| Wallet address | `0xGeorge...` |
| Document link | the gatekeeper URL for George, e.g. `http://127.0.0.1:8600/users/0xGeorge...` |
| Front-of-ID hash (SHA-256) | `3f9a1c2e...` |
| Back-of-ID hash (SHA-256) | `d2b7e4a1...` |
| Requester | Dr. Elena Kostas, Athens General Hospital (fictional) |
| Consent duration | 30 days |
