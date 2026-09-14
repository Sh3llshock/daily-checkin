# Step 3 — Implementation

## Required Deliverable (as specified in the project brief)

> Solidity implementation of the smart contracts with their functionalities.
> Implementation of any other modules that complement the functionality of
> smart-contracts and blockchain.

---

## What was implemented

All five contracts from the Step 2 design are implemented in Solidity `^0.8.24`,
using OpenZeppelin `Ownable`/`ERC20` for access control and the token, and wired
together with a Hardhat project so they compile and deploy locally.

| Contract | File | Implements |
|---|---|---|
| `DigitalIdentityRegistry` | `contracts/DigitalIdentityRegistry.sol` | `registerUser`, `updateDocument`, `getUserRecord`, `setRequesterStatus` (admin), `isApprovedRequester`, `isRegistered` |
| `ConsentManager` | `contracts/ConsentManager.sol` | `setConsent` (1–365 days, scoped, mints ACT reward), `revokeConsent`, `isConsentValid`, `getConsent`, admin `setRewardAmount` |
| `AccessLogger` | `contracts/AccessLogger.sol` | Append-only `logAccess` (callable only by `DataSharingManager`), `getLogs` (self or admin only), `getLogCount` — no delete/edit function exists |
| `DataSharingManager` | `contracts/DataSharingManager.sol` | `requestAccess` — checks consent via `ConsentManager`, releases the link + hash(es) allowed by the granted scope, and logs every attempt (granted or denied) via `AccessLogger` |
| `AccessToken` (`ACT`, ERC-20) | `contracts/AccessToken.sol` | `mintReward` restricted to a single `minter` address (set to `ConsentManager`); never referenced by any access-control check |

### Design decisions carried from Step 2 into code

- **Data ownership never moves** — `DigitalIdentityRegistry` stores only
  `emailHash`, `documentLink`, `frontHash`, `backHash`. No function anywhere accepts
  or stores the actual ID images.
- **Consent is scoped** — `ConsentManager.Scope` (`FRONT_ONLY` / `BACK_ONLY` / `BOTH`)
  is enforced in `DataSharingManager.requestAccess`, which zeroes out the hash the
  requester wasn't granted.
- **Consent is self-service and time-boxed** — `setConsent`/`revokeConsent` can only
  be called by the identity owner for their own record; `MIN_DURATION_DAYS = 1`,
  `MAX_DURATION_DAYS = 365` are enforced on-chain; expiry is a pure timestamp
  comparison (`isConsentValid`) with no separate "expire" transaction needed.
- **Every access attempt is logged, success or failure** — `requestAccess` always
  calls `accessLogger.logAccess(...)` on both the granted and denied paths, recording
  a machine-readable `reason` (`NO_CONSENT` / `EXPIRED` / `REVOKED`) for denials.
- **Logs are immutable** — `AccessLogger` exposes only `logAccess` (append) and two
  read functions; there is no delete/update function in the contract at all, and
  `logAccess` is further restricted to be callable only by the `DataSharingManager`
  contract address, not any externally-owned account.
- **Tokens incentivize, never gate access** — `AccessToken.mintReward` is called only
  from inside `ConsentManager.setConsent`, once per grant; `DataSharingManager` never
  reads an ACT balance anywhere in its access-check logic.
- **Requester whitelisting (domain addition)** — `ConsentManager.setConsent` requires
  `registry.isApprovedRequester(requester)`, so consent can only ever be granted to
  an address the admin has recognized as a legitimate healthcare provider.

## Project layout added in this step

```
digital-identity-platform/
├── contracts/
│   ├── AccessToken.sol
│   ├── DigitalIdentityRegistry.sol
│   ├── ConsentManager.sol
│   ├── AccessLogger.sol
│   └── DataSharingManager.sol
├── scripts/
│   └── deploy.js          # deploys all 5 contracts and wires them together
├── hardhat.config.js
├── package.json
└── .gitignore              # node_modules/, artifacts/, cache/ excluded from git
```

## How to compile and deploy locally

```bash
cd digital-identity-platform
npm install
npx hardhat compile
npx hardhat run scripts/deploy.js --network hardhat   # in-memory network, one-shot
# or, for a persistent local chain across multiple terminals:
npx hardhat node                                        # terminal 1
npx hardhat run scripts/deploy.js --network localhost   # terminal 2
```

Both compilation and a full deploy-and-wire run (`AccessToken` → `DigitalIdentityRegistry`
→ `ConsentManager` → `AccessLogger` → `DataSharingManager`, followed by
`accessToken.setMinter(consentManager)` and `accessLogger.setDataSharingManager(dataSharingManager)`)
were verified locally against Hardhat's built-in network as part of this step.

---

## Our Actual Deliverable for Step 3

- **Solidity implementation** of all five contracts identified in the Step 2 design
  (`DigitalIdentityRegistry`, `ConsentManager`, `AccessLogger`, `DataSharingManager`,
  `AccessToken`), matching the function tables and access-control rules from
  `step2-deliverable.md`.
- **Supporting modules**: a Hardhat project (`hardhat.config.js`, `package.json`) and
  a deployment script (`scripts/deploy.js`) that deploys and wires all five contracts
  together, confirmed to compile and deploy successfully on Hardhat's local network.
- Formal unit/integration tests and gas-usage measurement are the Step 4 deliverable
  and are not included here.
