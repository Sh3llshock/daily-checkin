# TASKS: Digital Identity & Data Sharing Platform

The master checklist for finishing the Blockchains group project. Tick a box when it's done, and put your name in the **Owner** column.

- **Brief:** `Project Assignment.pdf` (Canvas).
- **Rules:** the coursebook (report format, rubric, AI policy).
- **Report draft:** `digital-identity-platform/docs/report-draft.md`
- **Slide plan:** `digital-identity-platform/docs/presentation-draft.md`

---

## ⏰ Deadlines

| What | When | Notes |
|---|---|---|
| **Project (report + code)** | **Fri 2 Oct, 23:59** | The coursebook says Fri 2 Oct, Canvas says Sun 4 Oct. **Plan for Friday until a TA confirms.** Late work = project fails. Aim to submit by **20:00** as a buffer. |
| **Slides emailed to the instructors** | **Mon 5 Oct, 12:00** | |
| **Presentation** | Lab 6 (Mon) / Lab 7 (Wed), Week 6 | Check the format in the **Week 6 Lab on Canvas**. |

## 📏 Team rules (read this once)

1. **Everyone must be able to explain all of the code**, not just their own part. Examiners can ask follow-up questions or ask for a demo.
2. **AI policy (coursebook "Option 2"):**
   - Allowed: explanations, debugging and review.
   - Not allowed: AI writing the solution, or submitting AI output you haven't fully reviewed.
   - Note every use of AI in the report's contribution section and in code comments.
3. **No personal data in tests or the simulation.** Use made-up names, fake ID fields, `makeAddr("patient1")`, and so on.
4. Work on a branch per task (`a1-one-time-wiring`, `b1-registry-tests`, …). Get 1 teammate to review, then merge to `main`.
5. Keep `main` green: `npx hardhat compile && npx hardhat test` must pass before you merge.

## 👥 Workstreams

| Workstream | Focus | Owner |
|---|---|---|
| **A: Contracts** | Security fixes, gas optimisation, keeping the docs matching the code | |
| **B: Tests** | Solidity unit + integration tests, gas tables | |
| **C: Off-chain (Python)** | Local data, gatekeeper, multi-user simulation, scaling tables | |
| **D: Report & slides** | Report assembly and formatting, diagrams, references, slides, admin | |

**Order that matters:**
- A1 + A2 first, because B and C test the final contracts.
- B5 (the gas baseline) must come **before** A4 (the optimisation), so the report can show before/after numbers.

---

## Day 0 (today): setup

- [ ] **D0.1** Ask a TA: is the deadline **Fri 2 Oct or Sun 4 Oct**? Post the answer in the group chat and update the table above.
- [ ] **D0.2** Luka makes the GitHub repo **private**. Other groups have the same brief, and copying could implicate us too. Submit a **zip** on Canvas, because graders can't open a private URL.
- [ ] **D0.3** Everyone fills in their name in the Workstreams table.
- [ ] **D0.4** Open the Week 6 Lab on Canvas and note the presentation format (length, required slides) in `presentation-draft.md`.
- [ ] **D0.5** Everyone runs the project locally:
  ```bash
  git pull
  cd digital-identity-platform
  npm install
  npx hardhat compile
  ```

---

## A: Contracts

- [ ] **A1. One-time wiring.**
  - The problem: `AccessToken.setMinter` and `AccessLogger.setDataSharingManager` can be changed at any time by the owner. The admin can point the minter at their own wallet and mint unlimited ACT, or point the logger at themselves and write fake log entries. The docs claim neither is possible.
  - Make each setter work **once only**: require that the current value is still `address(0)`.
  - The constructor can't be used for this, because the contracts depend on each other in a circle. Explain that in the report.
  - *Done when:* a second call reverts, and B1 has tests for it.
- [ ] **A2. Whitelist check in `DataSharingManager.requestAccess`.**
  - The problem: right now **any** address can call it and fill any user's log with spam. And a requester that the admin removes from the whitelist keeps its access.
  - Require `registry.isApprovedRequester(msg.sender)`. Non-whitelisted callers **revert**, since they aren't requesters at all.
  - Whitelisted requesters without valid consent still return `granted = false` and are **logged as DENIED, with no revert**. Keep that behaviour.
  - *Done when:* strangers revert, and de-whitelisted requesters are denied. B1 tests both.
- [ ] **A3. Be honest about what's public.**
  - All contract state and all events are public (Lecture 7 §2.1). The document link and `getLogs` are readable by anyone.
  - Keep the link public, because the gatekeeper (C3) now protects the data itself.
  - For `getLogs`, either remove the `msg.sender` restriction or keep it and document that it is **not** privacy. A read-only call can set any `from` address.
  - Decide as a team and note the choice in the report's Discussion.
- [ ] **A4. Gas optimisation (after B5).** Try each change, re-measure, and keep the ones that save gas:
  - [ ] Store the denial reason as an **enum** instead of a string, in both `AccessLogger` and `DataSharingManager._denialReason`.
  - [ ] In `requestAccess`, read `consentManager.getConsent` **once** and check validity locally, instead of calling `isConsentValid` and then `getConsent`.
  - [ ] Compare **logging with events only** against the current storage array plus event. SSTORE vs LOG costs are in Lecture 4 §3.2 and §4.8. If you remove storage, `getLogs` must be rebuilt from events off-chain. Discuss the trade-off.
  - *Done when:* B5's table has a "before" and an "after" column, with a one-line reason per change.
- [ ] **A5. Make docs and comments match the code.** Fix these known mismatches:
  - [ ] The README intro still says "currently covers Step 1 and Step 2".
  - [ ] `step2-deliverable.md` says "four small contracts". There are five.
  - [ ] Step 2 §B.4 says the minter is "set once at deployment… including the admin". This becomes true only after A1.
  - [ ] The Step 1 admin row says "random addresses can't spam", and Step 2 §B.5 says "any whitelisted requester". Both become true only after A2.
  - [ ] Step 2 says "never other requesters" can read logs. Fix per A3.
  - [ ] Step 2 says "encrypted at the link", but nothing defines who encrypts or holds the key. Replace this with the gatekeeper design (C3), or define it.
  - [ ] Update the architecture diagram to include the gatekeeper (see D1).
- [ ] **A6 (stretch, only if doing the front-end).** Add view helpers, e.g. listing a user's consents or the users who consented to a requester. Otherwise, rebuild these from events.

## B: Tests (Step 4)

Write them in Solidity, the way Lab 3 did (see `blockchains/labs/lab3/contracts/MessageBoard.t.sol` for the style). Put each test file in `contracts/`, named after the contract it verifies. Run them with `npx hardhat test`.

Useful helpers:
- `vm.prank` / `vm.startPrank`: act as another user
- `vm.expectRevert`: expect a call to fail
- `vm.warp`: move time forward, for expiry
- `makeAddr`: create a fake address
- `assertEq` / `assertTrue`

> **Status (30 Sep):** a first version of B1 + B2 exists on branch **`finish-project`**.
> - 6 files, **77 tests, all passing**.
> - They are **AI-generated** (each file says so in its header comment). The B owner must **review every test and be able to explain it** before this is merged into `main`, and it must be declared in the AI statement (D4).
> - The integration file is `DigitalIdentityPlatform.t.sol`, not `Integration.t.sol`.
> - **These tests will break after A1–A3, on purpose, because they check today's behaviour:**
>   - [ ] `AccessToken.t.sol` → `test_RepointingMinterRevokesOldMinter`: after A1, re-pointing must **revert**. Rewrite it as "minter can only be set once".
>   - [ ] `AccessLogger.t.sol` → `test_RepointedManagerRevokesOldManager`: same, after A1.
>   - [ ] `DigitalIdentityPlatform.t.sol` → `test_UnapprovedRequesterIsBlocked`: it currently expects a non-whitelisted `requestAccess` to be **logged as NO_CONSENT**. After A2 it must **revert**.
>   - [ ] `AccessLogger.t.sol` → `test_OthersCannotReadUsersLogs`: keep it or delete it, depending on the A3 decision. Either way, note that the restriction isn't real privacy.
>   - [ ] After A4 (enum reasons), update every assertion that compares `reason` to a string such as `"NO_CONSENT"`.
>
> Use the checklist below to review what the tests cover.

- [ ] **B1. Unit tests, one file per contract**
  - [ ] `DigitalIdentityRegistry.t.sol`: register succeeds; registering twice reverts; a duplicate email hash reverts; empty fields revert; `updateDocument` only works for registered users; only the owner can call `setRequesterStatus`; `getUserRecord` returns the stored values.
  - [ ] `ConsentManager.t.sol`:
    - The user must be registered and the requester whitelisted.
    - Duration limits: **0 and 366 revert, 1 and 365 work**.
    - Expiry with `vm.warp`: valid exactly at `expiresAt`, invalid 1 second later.
    - Revoke rules: consent must exist, can't be revoked twice, can only be revoked by its owner.
    - Reward: 10 ACT on the **first** grant only. Re-granting, or revoking and re-granting, mints nothing.
    - `setRewardAmount` is owner-only.
  - [ ] `AccessToken.t.sol`: only the minter can call `mintReward`; `setMinter` works once only (after A1); `setMinter` is owner-only.
  - [ ] `AccessLogger.t.sol`: only the DataSharingManager can call `logAccess`; entries only get added (count goes up, old entries unchanged); `setDataSharingManager` works once only (after A1).
  - [ ] `DataSharingManager.t.sol`:
    - The granted path returns the link and hashes, and writes a GRANTED log.
    - Each denial reason (**NO_CONSENT, REVOKED, EXPIRED**) is logged **without reverting**.
    - Scope `FRONT_ONLY` returns an empty back hash, and `BACK_ONLY` an empty front hash.
    - A non-whitelisted caller reverts (after A2).
    - A de-whitelisted requester is denied (after A2).
- [ ] **B2. `Integration.t.sol`: full workflows**
  - [ ] register → admin whitelists → grant → access GRANTED → revoke → access DENIED (REVOKED) → the log has 2 entries in the right order.
  - [ ] Grant 1 day → `vm.warp` past it → access DENIED (EXPIRED).
  - [ ] Two users and two requesters: A's consent never gives access to B's data.
- [ ] **B3. No personal data** anywhere in the tests. Use made-up strings and `makeAddr`.
- [ ] **B4. Test table for the report**, one row per test with these columns: *Test | Contract | What it checks | Why it's critical for the platform | Result*. The brief explicitly asks for the "why critical" column.
- [ ] **B5. Gas baseline (do this before A4)**
  - [ ] Run `npm run test:gas`, or `npx hardhat test --gas-stats --gas-stats-json gas-before.json` to save it to a file.
  - [ ] Table 1: **deployment cost** per contract.
  - [ ] Table 2: **min / average / max gas** for the key functions: `registerUser`, `setConsent`, `revokeConsent`, `requestAccess` (granted), `requestAccess` (denied), `setRequesterStatus`.
  - [ ] After A4, rerun into `gas-after.json` and add an "after" column.

## C: Off-chain Python (Step 3 extras + Step 5)

The brief says *"User stores actual data locally (JSON file…)"* and *"prefer python for any additional components"*. It lives in a new folder, `digital-identity-platform/offchain/`.

- [ ] **C1. Setup.**
  - Add `offchain/requirements.txt` with `web3` and `eth-account`.
  - The course `.venv` in `~/Workspace/Uni/blockchains/` already has web3 8.0.0 and eth_account 0.14, so match those versions.
- [ ] **C2. Local data + hashing.**
  - `offchain/data/<user-address>/id_front.json` and `id_back.json` hold **fake** ID fields: made-up name, fake ID number, expiry date.
  - `hash_tool.py` computes the **SHA-256** of each file as `bytes32`, ready for `registerUser`. Use SHA-256, because the docs already say SHA-256.
- [ ] **C3. `gatekeeper.py`: the data holder.** This solves the "the link is public" problem. The on-chain link can point at the gatekeeper, because the gatekeeper enforces consent itself. It hands out a user's files only if **all** of these hold:
  1. The requester presents the **transaction hash** of their own `requestAccess(user)` call. Its receipt must show:
     - it succeeded;
     - `from` is the requester;
     - `to` is the DataSharingManager;
     - it contains an **`AccessGranted(user, requester)`** event.

     This proves who the requester is, because the transaction is signed with their private key (ECDSA, Tutorial 1). It also guarantees that **every data release has a GRANTED log entry**: no log, no data.
  2. `ConsentManager.isConsentValid(user, requester)` is **still true now**, which blocks reusing an old transaction after a revoke.
  3. The transaction's block timestamp is **recent**, within a window you choose, e.g. 5 minutes.
  4. It returns **only the files the consent scope allows**: front, back or both, read from `getConsent`. The scope finally means something.

  *Done when:* the requester re-hashes the files they receive, the hashes match the on-chain `frontHash` / `backHash`, and each failing case is refused (no tx, wrong sender, revoked, expired, stale).
- [ ] **C4. `simulate.py`: the multi-user simulation (Step 5).**
  - Reads the ABIs from `artifacts/contracts/<Name>.sol/<Name>.json` and the addresses from `ignition/deployments/chain-31337/deployed_addresses.json`. The keys look like `DigitalIdentityPlatform#ConsentManager`.
  - Roles: 1 admin (account #0), N users, M requesters.
    - `npx hardhat node` gives 20 accounts.
    - For more, generate accounts with `eth_account` and fund them with ETH from account #0.
    - For a viem version of the same pattern, see `blockchains/labs/lab5/LAB_DEMO-main/scripts/distribute-tokens.ts`.
  - For **N = 5, 10, 25, 50 users**, run: register → whitelist requesters → grant consent → access (granted) → revoke → access (denied) → gatekeeper fetch.
  - Record `gasUsed` from each receipt and the **time from send to receipt**. Write them to `offchain/results/*.csv`.
  - Produce the Step 5 table: *N users | avg gas per operation | total gas | avg confirmation time | total time*.
  - Also note whether any operation's gas **grows with N**, such as reading logs or pushing to the log array, or stays flat.
- [ ] **C5. Run instructions** in the README, so a stranger can reproduce everything:
  ```bash
  npx hardhat node                    # terminal 1
  npm run deploy:local                # terminal 2  (after restarting the node: add -- --reset)
  pip install -r offchain/requirements.txt
  python offchain/simulate.py
  ```
  Test the instructions on a fresh clone.

## D: Report, slides, admin

- [ ] **D1. Diagrams as images.** The report is a PDF, so export these Mermaid diagrams (e.g. with mermaid.live) and make them readable:
  - [ ] the interaction sequence diagram (Step 1 §1.5);
  - [ ] the consent lifecycle state diagram (Step 2 §A.3);
  - [ ] the architecture diagram (Step 2 §B.6), updated with the gatekeeper;
  - [ ] a **new** gatekeeper data-access flow (C3);
  - [ ] optional: a chart of the scaling results (C4).
- [ ] **D2. Assemble the report** from `docs/report-draft.md`.
  - Each person **writes their own sections in their own words**:
    - A: Implementation (contracts)
    - B: Results (tests + gas)
    - C: Implementation (off-chain) + Results (scaling)
    - D: Introduction, Architecture, Discussion, with input from everyone
  - Format: **10pt Times New Roman, double spaced, A4, 1" margins, ≤10 pages** not counting references and code. It needs a cover page (case title + names + student IDs), page numbers and the required section headers.
- [ ] **D3. References.**
  - The research table in Step 1 currently has **zero** sources. Find real ones: MyChart-style portals, eIDAS, Aadhaar, W3C DID/VC, KYC-vendor breaches.
  - Cite the course lectures you use.
  - Use one consistent style.
- [ ] **D4. Contributions + AI statement.**
  - Each member describes what they did.
  - The AI statement follows the coursebook template: *"I used generative AI for… / tool(s)… / parts affected… / I have checked…"*.
  - It must mention that Steps 1–3, the two bug fixes, the Hardhat 3 migration and the first version of the Step 4 tests were AI-assisted, and that we reviewed them.
- [ ] **D5. Presentation.**
  - Build the slides from `docs/presentation-draft.md`.
  - Rehearse once, with timing.
  - Record a **backup video of the demo**.
  - Email the slides to the instructors **before Mon 5 Oct, 12:00**.
- [ ] **D6 (stretch, only after everything above is done). Front-end (bonus).**
  - Wireframes, plus a minimal page: register, grant/revoke consent, view logs.
  - Use viem against `http://127.0.0.1:8545`, and copy the setup in `blockchains/labs/lab5/LAB_DEMO-main/frontend/lib/wagmi.ts`.

## Everyone

- [ ] Read every contract and `gatekeeper.py` until you could explain them without notes.
- [ ] Review at least one teammate's pull request.
- [ ] Proofread the full report once before submitting.

---

## 🗓 Timeline (assuming the Friday deadline)

| When | Tasks |
|---|---|
| **Wed (today, evening)** | D0.x, A1, A2, start B1, C1, C2 |
| **Thu** | Review the `finish-project` tests + update them for A1–A2, then merge into `main`. Then B4, **B5 baseline**, C3, C4. D drafts the Introduction and Architecture; everyone sends D their bullets. |
| **Fri** | A4 + re-measure, C4 tables, A5 docs pass, D1 diagrams, finish the report, **submit a zip by 20:00** |
| **Sat–Sun** | Slides, rehearsal, demo recording. D6 only if there's time. |
| **Mon 12:00** | Slides emailed |

If the TA confirms **Sunday**, move Fri's tasks to Sat–Sun and keep the same order.

---

## ✅ Final submission checklist

**Deliverables from the brief**

| Brief step | Deliverable | Where it lives | ☐ |
|---|---|---|---|
| 1. Research & planning | Problem statement, user roles, functional requirements, high-level interaction overview | Report §1–2 (source: `docs/step1-deliverable.md`) | ☐ |
| 2A. Data model | Table: attribute → on-chain? → off-chain? → hashed? | Report §2 | ☐ |
| 2A. Consent model | Data types, duration (1–365 days), who grants/revokes, what happens on expiry, workflow diagram or pseudocode | Report §2 + lifecycle figure | ☐ |
| 2A. Audit log | Who / what / when / granted or denied / logs can't be deleted | Report §2 | ☐ |
| 2B. Smart contract design | Components and key functions (identity, consent, data sharing) | Report §2–3 | ☐ |
| 2. Deliverable | **Architecture diagram** showing how components interact | Report §2 figure | ☐ |
| 3. Implementation | Solidity contracts + complementary modules (Python off-chain) | `contracts/`, `offchain/`, Report §3 | ☐ |
| 4. Unit tests | `.t.sol` per contract + "why critical" per tested function | `contracts/*.t.sol`, Report §4 | ☐ |
| 4. Gas | Deployment cost + average gas per function, with optimisation | Report §4 tables | ☐ |
| 4. Integration tests | register → consent → access → revoke workflow | `contracts/DigitalIdentityPlatform.t.sol`, Report §4 | ☐ |
| 4. Privacy | No personal data used in tests | All tests and fake data | ☐ |
| 5. Deployment + simulation | Local deploy; users, requesters and admin interacting | `offchain/simulate.py` | ☐ |
| 5. Deliverable | **Tables: how the solution scales in time and cost** for our number of users | Report §4 | ☐ |
| 6. Front-end (bonus) | Wireframes + viem UI on the local Hardhat network | Optional (D6) | ☐ |
| 7. Documentation | Report covering design, architecture, functionality | The report PDF | ☐ |
| 7. Instructions | Clear compile / deploy / test steps that can be reproduced | `README.md` | ☐ |
| 7. Presentation | Slides in the Week 6 Lab format | Slides (emailed by Mon 12:00) | ☐ |
| Final | Report + presentation + **documented code** | Canvas zip | ☐ |

**Report rules from the coursebook**

| Rule | ☐ |
|---|---|
| 10pt Times New Roman, double spaced, A4, 1" margins | ☐ |
| ≤10 pages, not counting references and code | ☐ |
| Cover page: case title + names + student IDs | ☐ |
| Pages numbered; figures readable | ☐ |
| Sections: Introduction, Architecture, Implementation, Experimental Results, Discussion & Conclusion | ☐ |
| Consistent, clear list of references for all ideas that aren't ours | ☐ |
| Contribution of each member + where and how AI was used | ☐ |
| No spelling or grammar mistakes (one full proofread) | ☐ |
| Code: NatSpec/comments; AI assistance acknowledged | ☐ |
