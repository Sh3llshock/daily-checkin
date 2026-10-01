# TASKS: Digital Identity & Data Sharing Platform

The master checklist for finishing the Blockchains group project. Tick a box when it's done, and put your name in the **Owner** column.

- **Brief:** `Project Assignment.pdf` (Canvas).
- **Report draft:** `digital-identity-platform/docs/report-draft.md`
- **Slide plan:** `digital-identity-platform/docs/presentation-draft.md`

> **Status (1 Oct):** every task a computer can do is done and ticked below (contracts, tests, gas, off-chain Python, docs, diagrams, references, report assembly, slides, front-end). What's left needs a person: the TA question, repo admin, names, the Canvas lab format, **writing the report text in your own words**, contributions, rehearsal, the demo video and emailing the slides. Nothing has been committed yet; the work is on branch `finish-project` as uncommitted changes. All of it was produced with Claude Code: each new or changed file says so in its header, and it has to be reviewed and declared in the report's AI statement (`report-draft.md` §6).

---

## ⏰ Deadlines

| What | When | Notes |
|---|---|---|
| **Project (report + code)** | **Fri 2 Oct, 23:59** | The coursebook says Fri 2 Oct, Canvas says Sun 4 Oct. **Plan for Friday until a TA confirms.** Late work = project fails. Aim to submit by **20:00** as a buffer. |
| **Slides emailed to the instructors** | **Mon 5 Oct, 12:00** | |
| **Presentation** | Lab 6 (Mon) / Lab 7 (Wed), Week 6 | Check the format in the **Week 6 Lab on Canvas**. |

## 📏 Team rules (read this once)

1. **Everyone must be able to explain all of the code**, not just their own part. Examiners can ask follow-up questions or ask for a demo.
2. **No personal data in tests or the simulation.** Use made-up names, fake ID fields, `makeAddr("patient1")`, and so on.
3. Work on a branch per task (`a1-one-time-wiring`, `b1-registry-tests`, …). Get 1 teammate to review, then merge to `main`.
4. Keep `main` green: `npx hardhat compile && npx hardhat test` must pass before you merge.

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
  - *(Needs a person.)* The Canvas assignment page saved in the Obsidian vault (`Project Assignment.pdf`, printed 30 Sep) says **"Due Sunday by 23:59 · Available until 4 Oct 23:59"**. Still confirm with a TA, since the coursebook says Friday. A ready-to-send message is in `docs/messages.md`.
- [ ] **D0.2** *(Needs a person: Luka.)* Luka makes the GitHub repo **private**.
  - ⚠️ Checked 1 Oct: `Sh3llshock/daily-checkin` is still **PUBLIC**, and `finish-project` is pushed there. Only the owner can change this (`jack-bikar` has push but not admin rights): Settings → General → Danger Zone → Change visibility.
  - [x] The zip is ready to build: `digital-identity-platform/scripts/make-submission-zip.sh` → `dist/digital-identity-platform.zip` (code, docs, results, report PDF; no `node_modules` or build output). Rebuild it after the report is final. Other groups have the same brief, and copying could implicate us too. Submit a **zip** on Canvas, because graders can't open a private URL.
- [ ] **D0.3** *(Needs a person.)* Everyone fills in their name in the Workstreams table.
- [ ] **D0.4** *(Needs a person: Canvas isn't reachable from here, and the Week 6 Lab isn't in the vault.)* Open the Week 6 Lab on Canvas and note the presentation format (length, required slides) in `presentation-draft.md`.
- [ ] **D0.5** *(Needs each person.)* Everyone runs the project locally (all README steps were checked on a clone-equivalent copy on 1 Oct, so this should just work):
  ```bash
  git pull
  cd digital-identity-platform
  npm install
  npx hardhat compile
  ```

---

## A: Contracts

- [x] **A1. One-time wiring.** Done: both setters require the current value to be `address(0)`; tests `test_MinterCanOnlyBeSetOnce`, `test_ManagerCanOnlyBeSetOnce`, plus the integration admin test.
  - ⚠️ "The constructor can't be used" is only true for five independently deployed contracts. ConsentManager could deploy the token itself (`new AccessToken(address(this))`), or the addresses could be precomputed (CREATE/CREATE2, Lecture 4 §4.11). Step 2 §B.4 now says this; say it honestly in the report too.
  - The problem: `AccessToken.setMinter` and `AccessLogger.setDataSharingManager` can be changed at any time by the owner. The admin can point the minter at their own wallet and mint unlimited ACT, or point the logger at themselves and write fake log entries. The docs claim neither is possible.
  - Make each setter work **once only**: require that the current value is still `address(0)`.
  - The constructor can't be used for this, because the contracts depend on each other in a circle. Explain that in the report.
  - *Done when:* a second call reverts, and B1 has tests for it.
- [x] **A2. Whitelist check in `DataSharingManager.requestAccess`.** Done: non-whitelisted callers revert, including a requester the admin removed (it loses access at once and regains it if re-approved); whitelisted requesters without consent are still logged as DENIED. Tests: `test_NonWhitelistedCallerReverts`, `test_DewhitelistedRequesterLosesAccess`, `test_UnapprovedRequesterIsBlocked`.
  - Interpretation to confirm: "de-whitelisted requesters are denied" is implemented as a **revert**, so their attempts are not in the AccessLogger (the failed transaction is still visible on-chain). Noted in the report draft's Discussion.
  - The problem: right now **any** address can call it and fill any user's log with spam. And a requester that the admin removes from the whitelist keeps its access.
  - Require `registry.isApprovedRequester(msg.sender)`. Non-whitelisted callers **revert**, since they aren't requesters at all.
  - Whitelisted requesters without valid consent still return `granted = false` and are **logged as DENIED, with no revert**. Keep that behaviour.
  - *Done when:* strangers revert, and de-whitelisted requesters are denied. B1 tests both.
- [x] **A3. Be honest about what's public.** Done, with a decision for the team to confirm: the `getLogs` caller restriction is **removed** (the log is public by design; `test_AnyoneCanReadLogs`), the NatSpec explains why, and the report draft's Discussion records it. To choose the other option instead, put the `require` back and swap that test.
  - All contract state and all events are public (Lecture 7 §2.1). The document link and `getLogs` are readable by anyone.
  - Keep the link public, because the gatekeeper (C3) now protects the data itself.
  - For `getLogs`, either remove the `msg.sender` restriction or keep it and document that it is **not** privacy. A read-only call can set any `from` address.
  - Decide as a team and note the choice in the report's Discussion.
- [x] **A4. Gas optimisation (after B5).** Try each change, re-measure, and keep the ones that save gas. Done, each step measured on its own (`docs/step4-deliverable.md` §2.4, data in `docs/gas/`):
  - [x] Store the denial reason as an **enum** instead of a string, in both `AccessLogger` and `DataSharingManager._denialReason`. (−2.9k to −4.0k per access.)
  - [x] In `requestAccess`, read `consentManager.getConsent` **once** and check validity locally, instead of calling `isConsentValid` and then `getConsent`. (−1.3k per access; a fuzz test checks it never disagrees with `isConsentValid`.)
  - [x] Compare **logging with events only** against the current storage array plus event. SSTORE vs LOG costs are in Lecture 4 §3.2 and §4.8. If you remove storage, `getLogs` must be rebuilt from events off-chain. Discuss the trade-off. (Events-only saves another ~28k per access; **storage + events kept**, reasons in §2.5; experiment contract in `contracts/experiments/`.)
  - [x] Extra, found while measuring: pack a log entry into one storage slot (−44k per access), pack a consent record into one slot (−66k per first grant), derive `registered` from the email hash (−22k per registration). Overall: denied access 128k → 72k, granted 146k → 89k, first grant 163k → 97k gas.
  - *Done when:* B5's table has a "before" and an "after" column, with a one-line reason per change.
- [x] **A5. Make docs and comments match the code.** Fix these known mismatches:
  - [x] The README intro still says "currently covers Step 1 and Step 2". (README rewritten.)
  - [x] `step2-deliverable.md` says "four small contracts". There are five.
  - [x] Step 2 §B.4 says the minter is "set once at deployment… including the admin". This becomes true only after A1. (True now, and §B.4 explains the one-time setter.)
  - [x] The Step 1 admin row says "random addresses can't spam", and Step 2 §B.5 says "any whitelisted requester". Both become true only after A2. (True now; both docs updated.)
  - [x] Step 2 says "never other requesters" can read logs. Fix per A3. (Now: anyone can, by design.)
  - [x] Step 2 says "encrypted at the link", but nothing defines who encrypts or holds the key. Replace this with the gatekeeper design (C3), or define it. (Replaced with the gatekeeper, Step 2 §A.2 and new §B.7.)
  - [x] Update the architecture diagram to include the gatekeeper (see D1).
  - [x] Also fixed: the consent state diagram showed Revoked/Expired as final states, but the code lets the owner grant again; Step 3 now lists the Python modules; the `revokeConsent` pseudocode no longer claims a registration check the code doesn't have.
- [x] **A6 (stretch, only if doing the front-end).** Add view helpers, e.g. listing a user's consents or the users who consented to a requester. Otherwise, rebuild these from events. (Done the "otherwise" way: the front-end rebuilds consents, patients and requesters from events, so no contract change.)

## B: Tests (Step 4)

Write them in Solidity, the way Lab 3 did (see `blockchains/labs/lab3/contracts/MessageBoard.t.sol` for the style). Put each test file in `contracts/`, named after the contract it verifies. Run them with `npx hardhat test`.

Useful helpers:
- `vm.prank` / `vm.startPrank`: act as another user
- `vm.expectRevert`: expect a call to fail
- `vm.warp`: move time forward, for expiry
- `makeAddr`: create a fake address
- `assertEq` / `assertTrue`

> **Status (1 Oct):** updated for A1–A4: 6 files, **80 tests, all passing**, 100 % line coverage of the five contracts. Every planned break below was fixed.
>
> **Status (30 Sep):** a first version of B1 + B2 exists on branch **`finish-project`**.
> - 6 files, **77 tests, all passing**.
> - The B owner must **review every test and be able to explain it** before this is merged into `main`.
> - The integration file is `DigitalIdentityPlatform.t.sol`, not `Integration.t.sol`.
> - **These tests will break after A1–A3, on purpose, because they check today's behaviour:**
>   - [x] `AccessToken.t.sol` → `test_RepointingMinterRevokesOldMinter`: after A1, re-pointing must **revert**. Rewrite it as "minter can only be set once".
>   - [x] `AccessLogger.t.sol` → `test_RepointedManagerRevokesOldManager`: same, after A1.
>   - [x] `DigitalIdentityPlatform.t.sol` → `test_UnapprovedRequesterIsBlocked`: it currently expects a non-whitelisted `requestAccess` to be **logged as NO_CONSENT**. After A2 it must **revert**.
>   - [x] `AccessToken.t.sol` → `test_SetMinterEmitsEvent` and `AccessLogger.t.sol` → `test_SetDataSharingManager`: `setUp` already sets the minter / manager, so after A1 the second call in these tests reverts. Test the event on a fresh contract instead.
>   - [x] `AccessToken.t.sol` → `test_RejectsZeroMinter` and `AccessLogger.t.sol` → `test_RejectsZeroManager`: the value is already set in `setUp`, so the revert message these tests see depends on which `require` comes first after A1.
>   - [x] `DataSharingManager.t.sol` → `test_EveryAttemptIsLogged` (calls as `stranger`) and `test_TokenBalanceDoesNotGrantAccess` (calls as `holder`, a user, not a requester): both callers aren't whitelisted, so after A2 they revert.
>   - [x] `DigitalIdentityPlatform.t.sol` → `test_AdminCannotBypassUserControl`: the admin calls `requestAccess` without being whitelisted, so after A2 it reverts instead of returning `granted = false`.
>   - [x] `AccessLogger.t.sol` → `test_OthersCannotReadUsersLogs` (replaced by `test_AnyoneCanReadLogs`, per A3): keep it or delete it, depending on the A3 decision. Either way, note that the restriction isn't real privacy.
>   - [x] After A4 (enum reasons), update every assertion that compares `reason` to a string such as `"NO_CONSENT"`.
>
> Use the checklist below to review what the tests cover.

- [x] **B1. Unit tests, one file per contract** (the B owner still has to review and be able to explain every test)
  - [x] `DigitalIdentityRegistry.t.sol`: register succeeds; registering twice reverts; a duplicate email hash reverts; empty fields revert; `updateDocument` only works for registered users; only the owner can call `setRequesterStatus`; `getUserRecord` returns the stored values.
  - [x] `ConsentManager.t.sol`:
    - The user must be registered and the requester whitelisted.
    - Duration limits: **0 and 366 revert, 1 and 365 work**.
    - Expiry with `vm.warp`: valid exactly at `expiresAt`, invalid 1 second later.
    - Revoke rules: consent must exist, can't be revoked twice, can only be revoked by its owner.
    - Reward: 10 ACT on the **first** grant only. Re-granting, or revoking and re-granting, mints nothing.
    - `setRewardAmount` is owner-only.
  - [x] `AccessToken.t.sol`: only the minter can call `mintReward`; `setMinter` works once only (after A1); `setMinter` is owner-only.
  - [x] `AccessLogger.t.sol`: only the DataSharingManager can call `logAccess`; entries only get added (count goes up, old entries unchanged); `setDataSharingManager` works once only (after A1).
  - [x] `DataSharingManager.t.sol`:
    - The granted path returns the link and hashes, and writes a GRANTED log.
    - Each denial reason (**NO_CONSENT, REVOKED, EXPIRED**) is logged **without reverting**.
    - Scope `FRONT_ONLY` returns an empty back hash, and `BACK_ONLY` an empty front hash.
    - A non-whitelisted caller reverts (after A2).
    - A de-whitelisted requester is denied (after A2).
- [x] **B2. `Integration.t.sol`: full workflows** (in `DigitalIdentityPlatform.t.sol`)
  - [x] register → admin whitelists → grant → access GRANTED → revoke → access DENIED (REVOKED) → the log has 2 entries in the right order.
  - [x] Grant 1 day → `vm.warp` past it → access DENIED (EXPIRED).
  - [x] Two users and two requesters: A's consent never gives access to B's data.
  - [x] Extra: a fuzz test that `requestAccess` always agrees with `isConsentValid` (guards the A4 change).
- [x] **B3. No personal data** anywhere in the tests. (Also in the simulation and demo: `offchain/fake_data.py` makes obviously fake ID files.) Use made-up strings and `makeAddr`.
- [x] **B4. Test table for the report**, one row per test with these columns: *Test | Contract | What it checks | Why it's critical for the platform | Result*. The brief explicitly asks for the "why critical" column. (`docs/step4-deliverable.md` §1.3: all 80 + the 15 gatekeeper tests; §1.2 is a report-sized version, one row per tested functionality.)
- [x] **B5. Gas baseline (do this before A4)**
  - [x] Run `npm run test:gas`, or `npx hardhat test --gas-stats --gas-stats-json gas-before.json` to save it to a file. (`docs/gas/gas-before.json`. The test-suite stats mix scenarios, so `npm run gas:bench` (new) measures each scenario as a real transaction: `docs/gas/bench-before.json`.)
  - [x] Table 1: **deployment cost** per contract.
  - [x] Table 2: **min / average / max gas** for the key functions: `registerUser`, `setConsent`, `revokeConsent`, `requestAccess` (granted), `requestAccess` (denied), `setRequesterStatus`.
  - [x] After A4, rerun into `gas-after.json` and add an "after" column. (`docs/gas/gas-after.json`, `bench-after.json`; tables in `docs/step4-deliverable.md` §2.)

## C: Off-chain Python (Step 3 extras + Step 5)

The brief says *"User stores actual data locally (JSON file…)"* and *"prefer python for any additional components"*. It lives in a new folder, `digital-identity-platform/offchain/`.

- [x] **C1. Setup.** (`offchain/requirements.txt`: web3 8.0.0, eth-account 0.14.0.)
  - Add `offchain/requirements.txt` with `web3` and `eth-account`.
  - The course `.venv` in `~/Workspace/Uni/blockchains/` already has web3 8.0.0 and eth_account 0.14, so match those versions.
- [x] **C2. Local data + hashing.** (`offchain/fake_data.py`, `offchain/hash_tool.py`, demo data in `offchain/data/<Hardhat account #1>/`.)
  - `offchain/data/<user-address>/id_front.json` and `id_back.json` hold **fake** ID fields: made-up name, fake ID number, expiry date.
  - `hash_tool.py` computes the **SHA-256** of each file as `bytes32`, ready for `registerUser`. Use SHA-256, because the docs already say SHA-256.
- [x] **C3. `gatekeeper.py`: the data holder.** Done, with 15 tests (`offchain/test_gatekeeper.py`) covering the success path and every refusal (no tx, wrong sender, wrong user, denied tx, other contract, revoked, expired, stale, de-whitelisted, reused).
  - ⚠️ **Flaw in the design as written below, fixed:** a transaction hash is public, so anyone watching the chain could present a requester's hash and get the files. The requester now also **signs the request** with the key that sent the transaction (that's what really proves who it is), and each hash can be used **once**, so every release matches exactly one GRANTED entry. The gatekeeper also re-checks that the requester is still whitelisted.
  - Also found: an EOA can't read a mined transaction's return values, so the requester reads the hashes to check against with `getUserRecord`. This solves the "the link is public" problem. The on-chain link can point at the gatekeeper, because the gatekeeper enforces consent itself. It hands out a user's files only if **all** of these hold:
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
- [x] **C4. `simulate.py`: the multi-user simulation (Step 5).** Done: N = 5, 10, 25, 50 with instant mining and with 12-second blocks; results in `offchain/results/`, tables in `docs/step5-deliverable.md`. Gas per operation is flat in N; a log write stays flat while reading a whole log grows with its length.
  - Reads the ABIs from `artifacts/contracts/<Name>.sol/<Name>.json` and the addresses from `ignition/deployments/chain-31337/deployed_addresses.json`. The keys look like `DigitalIdentityPlatform#ConsentManager`.
  - Roles: 1 admin (account #0), N users, M requesters.
    - `npx hardhat node` gives 20 accounts.
    - For more, generate accounts with `eth_account` and fund them with ETH from account #0.
    - For a viem version of the same pattern, see `blockchains/labs/lab5/LAB_DEMO-main/scripts/distribute-tokens.ts`.
  - For **N = 5, 10, 25, 50 users**, run: register → whitelist requesters → grant consent → access (granted) → revoke → access (denied) → gatekeeper fetch.
  - Record `gasUsed` from each receipt and the **time from send to receipt**. Write them to `offchain/results/*.csv`.
  - Produce the Step 5 table: *N users | avg gas per operation | total gas | avg confirmation time | total time*.
  - Also note whether any operation's gas **grows with N**, such as reading logs or pushing to the log array, or stays flat.
- [x] **C5. Run instructions** in the README, so a stranger can reproduce everything (tested on 1 Oct on a clone-equivalent copy with a fresh `npm install`, a fresh Python 3.10 venv, fresh chain: every step worked):
  ```bash
  npx hardhat node                    # terminal 1
  npm run deploy:local                # terminal 2  (after restarting the node: add -- --reset)
  pip install -r offchain/requirements.txt
  python offchain/simulate.py
  ```
  Test the instructions on a fresh clone.

## D: Report, slides, admin

- [x] **D1. Diagrams as images.** The report is a PDF, so export these Mermaid diagrams (e.g. with mermaid.live) and make them readable: (`docs/diagrams/`: `.mmd` sources, PNG + SVG, `render.sh` to re-render)
  - [x] the interaction sequence diagram (Step 1 §1.5);
  - [x] the consent lifecycle state diagram (Step 2 §A.3);
  - [x] the architecture diagram (Step 2 §B.6), updated with the gatekeeper;
  - [x] a **new** gatekeeper data-access flow (C3);
  - [x] optional: a chart of the scaling results (C4). (`python offchain/plot_results.py`.)
- [ ] **D2. Assemble the report** from `docs/report-draft.md`. *(Assembly done; the writing needs each person.)* `docs/report/report.md` has the cover, all section headers, every figure and table with final numbers, and the references; `docs/report/build.sh` builds the PDF in the coursebook format (checked: A4, Times New Roman, 10pt, double spaced, 1" margins, page numbers). Yellow boxes mark where each workstream writes, in their own words.
  - ⚠️ **Page budget:** the figures and tables alone already fill 7 content pages, leaving about 2–3 pages for all the prose. `docs/report/README.md` lists ways to make room.
  - Each person **writes their own sections in their own words**:
    - A: Implementation (contracts)
    - B: Results (tests + gas)
    - C: Implementation (off-chain) + Results (scaling)
    - D: Introduction, Architecture, Discussion, with input from everyone
  - Format: **10pt Times New Roman, double spaced, A4, 1" margins, ≤10 pages** not counting references and code. It needs a cover page (case title + names + student IDs), page numbers and the required section headers.
- [x] **D3. References.** (`docs/references.md`: 23 checked sources + the course lectures/tutorials/labs with their real titles, one numbered style; the Step 1 table now cites them. Open each before relying on it for a specific claim.)
  - The research table in Step 1 currently has **zero** sources. Find real ones: MyChart-style portals, eIDAS, Aadhaar, W3C DID/VC, KYC-vendor breaches.
  - Cite the course lectures you use.
  - Use one consistent style.
- [ ] **D4. Contributions.** *(Needs each person: only you know what you did.)*
  - Each member describes what they did.
- [ ] **D5. Presentation.** *(Slides built; the rest needs people.)*
  - [x] Build the slides from `docs/presentation-draft.md`. ([Deck, 13 slides](https://claude.ai/artifact/Mu3VBe5h2sf3FLTAvUH48f): download as PowerPoint/PDF; it's private until shared from its Share menu. Fill in names on the cover. `python offchain/demo.py` is the live demo.)
  - [x] Backup video of the demo: `docs/demo/backup-demo.mp4` (55 s, captioned, the whole flow in the front-end on a fresh local chain). Copy it to the laptop and a USB stick.
  - [ ] *(Needs people.)* Rehearse once with timing, and email the slides (draft in `docs/messages.md`).
  - Rehearse once, with timing.
  - Record a **backup video of the demo**. ✔ Done: `docs/demo/backup-demo.mp4`.
  - Email the slides to the instructors **before Mon 5 Oct, 12:00**.
- [x] **D6 (stretch, only after everything above is done). Front-end (bonus).** Done anyway, since it was asked for: `frontend/` (`npm run frontend`), wireframes in `frontend/wireframes.md`; checked end to end in headless Chrome, plus a UI review whose findings were fixed.
  - Wireframes, plus a minimal page: register, grant/revoke consent, view logs.
  - Use viem against `http://127.0.0.1:8545`, and copy the setup in `blockchains/labs/lab5/LAB_DEMO-main/frontend/lib/wagmi.ts`.

## Everyone *(needs each person)*

Start with `digital-identity-platform/docs/study-guide.md`: a walkthrough of every contract and the gatekeeper with file:line pointers, likely examiner questions, and five self-check exercises.

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
| 2. Deliverable | **Architecture diagram** showing how components interact | Report §2 figure | ☑ |
| 3. Implementation | Solidity contracts + complementary modules (Python off-chain) | `contracts/`, `offchain/`, Report §3 | ☑ |
| 4. Unit tests | `.t.sol` per contract + "why critical" per tested function | `contracts/*.t.sol`, Report §4 | ☑ code + table · ☐ report text |
| 4. Gas | Deployment cost + average gas per function, with optimisation | Report §4 tables | ☑ tables · ☐ report text |
| 4. Integration tests | register → consent → access → revoke workflow | `contracts/DigitalIdentityPlatform.t.sol`, Report §4 | ☑ |
| 4. Privacy | No personal data used in tests | All tests and fake data | ☑ |
| 5. Deployment + simulation | Local deploy; users, requesters and admin interacting | `offchain/simulate.py` | ☑ |
| 5. Deliverable | **Tables: how the solution scales in time and cost** for our number of users | Report §4 | ☑ tables · ☐ report text |
| 6. Front-end (bonus) | Wireframes + viem UI on the local Hardhat network | Optional (D6) | ☑ |
| 7. Documentation | Report covering design, architecture, functionality | The report PDF | ☐ |
| 7. Instructions | Clear compile / deploy / test steps that can be reproduced | `README.md` | ☑ |
| 7. Presentation | Slides in the Week 6 Lab format | Slides (emailed by Mon 12:00) | ☐ |
| Final | Report + presentation + **documented code** | Canvas zip | ☐ |

**Report rules from the coursebook**

| Rule | ☐ |
|---|---|
| 10pt Times New Roman, double spaced, A4, 1" margins | ☑ |
| ≤10 pages, not counting references and code | ☐ |
| Cover page: case title + names + student IDs | ☐ |
| Pages numbered; figures readable | ☑ |
| Sections: Introduction, Architecture, Implementation, Experimental Results, Discussion & Conclusion | ☑ |
| Consistent, clear list of references for all ideas that aren't ours | ☑ list · ☐ cite in text |
| Contribution of each member | ☐ |
| No spelling or grammar mistakes (one full proofread) | ☐ |
| Code: NatSpec/comments | ☑ |
