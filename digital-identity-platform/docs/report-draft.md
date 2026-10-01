# Report draft: structure and prompts

> **How to use this file**
> - This is a **skeleton, not the report**. Every bullet is a prompt telling you what to cover. Write the actual sentences **in your own words**.
> - The `step1/2/3-deliverable.md` docs are source material only. Don't paste them in: condense them, then rewrite them.
> - Everyone writes the section for their own workstream (see `TASKS.md` D2). D merges the sections and formats the final PDF.

---

## Format rules (coursebook)

- **10pt Times New Roman, double spaced, A4, 1" margins on all sides.**
- **Maximum 10 pages.** References and code don't count towards this; everything else does.
- **Cover page:** case title + names of all contributors + student IDs.
- **Pages numbered**; figures readable and actually useful.
- **References:** a clear, verifiable list for every idea that isn't ours, in one consistent style.
- **Ends with:** each member's contribution + where and how AI was used.

**Page budget.** Double spaced at 10pt is about **450 words per page** of plain text, and tables and figures eat space fast.

| Part | Pages |
|---|---|
| Cover page | 1 (ask a TA whether it counts; assume yes) |
| 1. Introduction | 1 |
| 2. Architecture | 2.5 |
| 3. Implementation | 1.75 |
| 4. Experimental Results | 2 |
| 5. Discussion & Conclusion | 1 |
| 6. Contributions & AI statement | 0.75 |
| References | not counted |

## How it's graded (Annex A rubric)

| Rubric item | Points | What earns them | Where |
|---|---|---|---|
| Introduction: problem statement | 10 | The problem is framed correctly; aims and objectives are stated; the solution is **not** given away here | §1 |
| Analysis: data + solution | **60** | Shows we understand the problem; methods fit the problem; the solution is well developed and explained; the approach can be followed step by step; results are given **and discussed**; arguments are consistent | §2–4 |
| Report clarity | 15 | Gets to the point; **reflects on course topics**; academic writing | all |
| Conclusion | 10 | Sums up; clear and definite; consistent with the introduction; **no new ideas** | §5 |
| Presentation | 5 | Cover page, section headers, page numbers, readable figures, no typos | all |

Also graded: adequacy, clarity, logical coherence, **use of course content**, conformance to the layout rules.

---

## Cover page

- Case title, e.g. *Decentralized Digital Identity and Government-ID Sharing for Healthcare*.
- Course name, group number, date.
- All 4 names + student IDs.

---

## 1. Introduction (~1 page) · writer: D

*Rubric: frame the problem, state the aims. Save the solution for §2.*

- **The problem in our domain, in 3–4 sentences:**
  - Healthcare providers have to verify patients' government IDs.
  - Today, copies of those IDs sit in each provider's systems.
  - Explain why that's bad: breach "honeypots", no visibility for the patient, no way to revoke, no trustworthy audit trail, the patient gets no benefit.
  - Connect it to the brief's problem statement: centralised platforms control user data.
- **How others solve it:** a condensed version of the 5-system table from Step 1 §1.2.
  - **Add a real reference for every row.** There are none yet (TASKS D3).
  - Keep only the columns *system | what works | what doesn't*.
- **Our angle:**
  - The patient keeps the ID data.
  - The blockchain holds only hashes, consent records and an immutable access log.
  - The patient earns a token for sharing.
  - Just state the idea. No contracts or functions here.
- **Aims and objectives:** 3–5 bullets turned into a short list, e.g. *user-controlled consent (1–365 days), every access attempt logged, tamper-evident data, measured cost and scalability*.
- **Scope and assumptions:**
  - Local Hardhat network only.
  - Fake data only.
  - Requesters are verified off-chain before the admin whitelists them.

## 2. Architecture (~2.5 pages) · writers: D + A

*Rubric: methodology, model and assumptions. **No implementation details**: talk about components and how they interact, not Solidity code.*

### 2.1 Actors and permissions
- Three roles: **Identity owner** (patient), **Requester** (doctor, hospital, insurer), **Administrator**.
- For each role: what it can start, and what it **cannot** do. The admin can't read data, grant or revoke consent, or edit logs.
- Include **Table 1: Roles and permissions**, condensed from Step 1 §1.3. Filled in from the final code:

| Role | Initiates | Allowed | Not allowed |
|---|---|---|---|
| Identity owner (patient) | Registration, document updates, consent grants and revocations | Register hashes + gatekeeper link; grant scoped consent (1–365 days) to whitelisted requesters; revoke at any time; read the access log; earn 10 ACT on the first grant to each requester | Change anyone else's record or consent |
| Requester (provider) | Access requests | Once whitelisted: call `requestAccess`; with its own fresh GRANTED transaction, fetch the files the scope allows from the gatekeeper | Give itself consent; get files without valid consent; alter or suppress log entries; gain access through ACT |
| Administrator | Deployment, whitelist, reward rate | Deploy and wire the contracts once; whitelist or remove requesters; set the reward amount | Get files without consent; grant or revoke consent; write or delete log entries; mint ACT; re-wire the minter or logger |

### 2.2 Functional requirements
- Explain in 1–2 sentences how you arrived at them.
- List the requirements compactly: the core ones from the brief plus our domain additions (requester whitelist, hash-based integrity check, gatekeeper).
- Source: Step 1 §1.4. **Update it**: the reward happens once per requester, and data is released through the gatekeeper.

### 2.3 Data model
- Explain the rule of thumb in your own words: what identifies a person stays off-chain; what proves integrity or permission goes on-chain.
- Include **Table 2: Attribute → On-chain? → Off-chain? → Hashed?**, required by the brief. Source: Step 2 §A.2 (already updated: the files are served by the gatekeeper, not "encrypted at a link"):

| Attribute | On-chain? | Off-chain? | Hashed? |
|---|:---:|:---:|---|
| Wallet address | ✅ | — | No (already a pseudonymous identifier) |
| Full name, date of birth, ID number | ❌ | ✅ (inside the ID files) | No |
| Email | ❌ | ✅ (local profile) | ✅ SHA-256 on-chain, for the uniqueness check |
| Document link (gatekeeper URL) | ✅ | — | No |
| Front / back of the ID | ❌ | ✅ (local data store, released only by the gatekeeper) | ✅ SHA-256 of each file on-chain |
| Consent record (requester, scope, granted/expiry time, revoked) | ✅ | — | No (contracts must read it) |
| Access log entry (requester, time, outcome, reason) | ✅ | — | No |
| ACT balances | ✅ | — | No |
- Explain why the email is hashed (the uniqueness check). Mention that an unsalted hash of a guessable value can be brute-forced, and point forward to §5.
- **Course link:** Lecture 1 on hash functions (preimage resistance). Lecture 7 §2.1: a dApp's code and all its state are public.

### 2.4 Consent model
- **Data types that can be shared:** the scopes FRONT_ONLY, BACK_ONLY, BOTH. Say what each means now that the gatekeeper enforces it.
- **Duration:** 1–365 days, stored as an absolute expiry time.
- **Who can grant or revoke:** only the identity owner. Not the admin, not the requester.
- **What happens on expiry:** no transaction is needed; the next check just fails. Explain why that saves gas.
- **Reward:** ACT is minted on the **first** grant to each requester. Explain why: re-granting could otherwise be used to farm tokens. Tokens never gate access, and data ownership never moves.
- Include **Figure 1: Consent lifecycle** (state diagram, TASKS D1). You may add pseudocode for grant, revoke and validity.

### 2.5 Audit log
- Answer the brief's four questions: *who* accessed *what*, *when*, *granted or denied*, and *can logs be deleted? (no)*.
- Explain **why** entries can't be deleted: the contract only ever adds, and immutability comes from the chain itself (hash-linked blocks + consensus, Lectures 2–3).
- State that the log is public: the audit trail is transparent, not private.

### 2.6 System architecture
- Components:
  - 5 contracts: DigitalIdentityRegistry, ConsentManager, DataSharingManager, AccessLogger, AccessToken.
  - The off-chain **gatekeeper** and the local data store.
  - The actors.
- **Figure 2: Architecture diagram**, required by the brief. Show which component calls which, with numbered steps.
- **Figure 3: Data-access flow through the gatekeeper:** requester calls `requestAccess` on-chain → gets logged → presents the transaction to the gatekeeper → the gatekeeper checks it and serves only the permitted files → the requester re-hashes the files.
- Explain in 2–3 sentences why the system is split into several small contracts: separation of concerns, each part can be tested and gas-measured on its own, and the admin stays out of the data path.
- **Course link:** Lab 4 (inter-contract communication).

## 3. Implementation (~1.75 pages) · writers: A (contracts) + C (off-chain)

*Rubric: how each component was built and its main functions. Short code snippets are fine, but explain the **decisions** rather than walking through the code.*

### 3.1 Tooling
- Solidity 0.8.28, OpenZeppelin (Ownable, ERC-20), Hardhat 3 with viem, Solidity tests (forge-std), Hardhat Ignition for deployment, Python with web3.py for the off-chain parts.
- Say why this stack: it's the course lab setup, and the brief prefers Python.

### 3.2 Smart contracts
- 2–4 bullets per contract: its role, its key functions, and **one design decision** with the reason. Decisions to cover:
  - [ ] **Denied access doesn't revert:** a revert would undo the DENIED log entry. **Course link:** Lecture 4 §4.5 (require/revert roll back all state changes).
  - [ ] **Expiry by timestamp comparison**, with no cleanup transaction.
  - [ ] **Reward once per (user, requester)**, based on the existing `exists` flag, so no extra storage is needed.
  - [ ] **Whitelist check in `requestAccess`:** stops spam, and removes access from de-whitelisted requesters (after TASKS A2).
  - [ ] **One-time wiring** of the minter and logger. Explain why the constructor couldn't do this: the contracts depend on each other in a circle (after TASKS A1).
  - [ ] **Access control:** `Ownable`, the custom modifiers, and `msg.sender` checks. **Course link:** Lecture 4 §4.4.
  - [ ] **ACT token:** why ERC-20 and not an NFT. It's a fungible reward. **Course link:** Tutorial 3 (ERC-20/721/1155).
- Optionally, a small table of contract → key functions → who may call them. Source: Step 2 §B.5, updated.

### 3.3 Off-chain components (Python)
- **Local data store + hash tool:** the file format, fake data only, SHA-256 as bytes32.
- **Gatekeeper:** the checks it runs, in order: valid transaction receipt from the requester, `AccessGranted` event present, consent still valid, recent transaction, then the scope filter.
  - Explain why the signed transaction proves who the requester is. **Course link:** Tutorial 1 (ECDSA keys and signatures).
- **Simulation script:** how the accounts and roles are created, and what gets measured.

### 3.4 Deployment
- The Ignition module deploys the 5 contracts in dependency order, then makes the two wiring calls.
- Local chain: `npx hardhat node`.
- Point to the README for step-by-step instructions (the brief's Step 7 "Instructions"). Don't repeat them here, because they'd eat pages.

## 4. Experimental Results (~2 pages) · writers: B (tests + gas) + C (scaling)

*Rubric: results **given and discussed**. Every table needs 1–3 sentences of interpretation below it.*

### 4.1 Testing approach
- The kinds of tests: unit tests per contract, integration workflows, and negative tests (expected reverts, denials).
- Tools: forge-std helpers (`vm.prank`, `vm.expectRevert`, `vm.warp`).
- State that **no personal data** was used, as the brief requires.

### 4.2 Test results
- **Table 3: Test results**. Required: the brief asks for tables of all successful tests **plus why each tested functionality is critical**.
  - Data is ready in `step4-deliverable.md`: §1.2 is a report-sized table (18 rows, one per tested functionality); §1.3 has all 80 tests, one row each, and §1.4 the 15 gatekeeper tests.
  - **Page budget:** the full 80-row table would take 3+ pages. Suggestion: put §1.2 in the body and the full tables in an appendix (ask a TA whether an appendix counts towards the 10 pages).
  - Facts for the text: **80/80 Solidity tests and 15/15 gatekeeper tests pass; 100 % line and statement coverage** for the five contracts (`npx hardhat test --coverage`). Not covered: a public network (reorgs, real fees) and the gatekeeper under concurrent load.
- Add 1–2 sentences on coverage: what's tested and what isn't.

### 4.3 Gas costs and optimisation
- **Table 4: Deployment cost per contract**, from `npm run gas:bench` (real deployment transactions; `step4-deliverable.md` §2.2):

| Contract | Deployment gas (before → after) | Bytecode size, bytes (before → after) |
|---|---:|---:|
| AccessToken | 696,804 → 696,804 | 2,615 → 2,615 |
| DigitalIdentityRegistry | 772,744 → 759,768 | 3,208 → 3,148 |
| ConsentManager | 702,661 → 729,611 | 2,772 → 2,897 |
| AccessLogger | 634,505 → 514,920 | 2,569 → 2,016 |
| DataSharingManager | 613,162 → 507,916 | 2,582 → 2,093 |
| **Total** | **3,419,876 → 3,209,019 (−6.2 %)** | |

- **Table 5: Gas per function, before and after optimisation** (TASKS B5 + A4).

Filled in from `step4-deliverable.md` §2.3–2.4 (gasUsed of real transactions, 5 users each):

| Function | Avg gas (before) | Avg gas (after) | Change | What changed |
|---|---:|---:|---:|---|
| `registerUser` | 228,236 | 205,958 | −9.8 % | `registered` flag derived from the email hash: one storage slot fewer |
| `setConsent` (first grant) | 162,670 | 96,681 | −40.6 % | Consent record packed into 1 slot instead of 4 |
| `setConsent` (re-grant) | 48,354 | 39,265 | −18.8 % | 1 slot rewritten instead of 3 |
| `revokeConsent` | 28,811 | 28,825 | +0.0 % | Not targeted |
| `requestAccess` (granted, later entry) | 145,912 | 89,230 | −38.8 % | Enum reason, one consent read, packed log entry and consent |
| `requestAccess` (denied) | 127,968 | 72,302 | −43.5 % | Same |
| `setRequesterStatus` | 47,779 | 47,779 | 0 | Not targeted |

- Interpret the numbers:
  - Which operations are expensive, and why? Think storage writes and strings.
  - Which optimisation helped most?
  - **Course link:** Lecture 4 §3.2 (SSTORE costs 20,000+ gas from zero to non-zero; events are much cheaper, §4.8).
- If you tested an events-only log, report the trade-off: cheaper, but contracts can't read it back, and `getLogs` must be rebuilt off-chain.
  - **We did:** events-only would cost 61,066 (granted) / 44,118 (denied) instead of 89,230 / 72,282, i.e. another ~28k per access. **Kept storage + event** (reasons in `step4-deliverable.md` §2.5: contracts can't read events, EIP-4444 history expiry). The team can still flip this; it's a one-contract change.

### 4.4 Simulation and scalability (Step 5)
- The setup: number of users, requesters and admins; the sequence of operations; the local Hardhat node with a block mined per transaction.
- **Table 6: Scaling in cost and time**, required by the brief.

Filled in from `offchain/results/automine_summary.md` (local node, instant mining; `step5-deliverable.md` has the 12-second-block run and the per-operation table):

| Users (N) | Requesters (M) | Total txs | Avg gas / op | Total gas | Avg confirmation time | Total run time |
|---:|---:|---:|---:|---:|---:|---:|
| 5 | 3 | 28 | 96,206 | 2,693,763 | 2.9 ms | 0.63 s |
| 10 | 3 | 53 | 98,300 | 5,209,898 | 3.4 ms | 1.19 s |
| 25 | 3 | 128 | 100,076 | 12,809,771 | 2.6 ms | 2.78 s |
| 50 | 3 | 253 | 100,696 | 25,476,186 | 2.7 ms | 5.65 s |

- Facts for the text: gas per operation is flat in N (spread 0.0 % for every operation except `setConsent` at N = 5, where the platform's very first grant also turns ACT's total supply from zero to non-zero). Total gas and total time grow linearly with N. Writing a log entry stays at 89,230 gas however long the user's log is, while reading the whole log with `getLogs` grows linearly (30k gas at 2 entries → 173k at 50).

- Optional **Figure 4:** a chart of gas or time against N.
- Interpret the results:
  - Does the per-operation cost stay flat as N grows? Say which operations grow, if any (e.g. log arrays, `getLogs` read size).
  - What does local timing say, and **not** say, about a real network? Local blocks are instant; a public chain has roughly 12-second blocks.
  - **Course link:** Lecture 6 (the scaling problem, throughput limits).

## 5. Discussion & Conclusion (~1 page) · writer: D, with input from everyone

*Rubric: be critical, and say when it works and when it doesn't. The conclusion is short, definite, consistent with §1, and brings **no new ideas**. Keep the discussion here and put the "next steps" in it, not in the conclusion.*

### 5.1 What works
- Map the results back to the aims in §1, one line per aim.

### 5.2 Limitations (be honest; examiners reward this)
- **Everything on-chain is public:** links, hashes, consent records, logs. Pseudonymous addresses can be linked to people. **Course link:** Lecture 7 §2.1 and §3.3.
  - **Decision taken for TASKS A3 (confirm as a team):** `getLogs` no longer restricts the caller. A `msg.sender` check on a view function isn't privacy (an `eth_call` can set any `from`, and storage and events are readable anyway), so the log is transparent by design and the gatekeeper protects the files. If the team prefers the other option (keep the check and say it isn't privacy), revert that one line and `test_AnyoneCanReadLogs`.
- **Design gaps found while building:** a transaction's return values can't be read by the requester off-chain, so the requester reads the hashes with `getUserRecord`; and a transaction hash is public, so the gatekeeper also needs the requester's signature (otherwise anyone could replay it). Both are handled; say why.
- **De-whitelisted requesters revert, so their attempts are not in the AccessLogger** (the failed transaction is still visible on-chain). Trade-off: no log spam vs a complete log of every attempt.
- **An unsalted email hash can be brute-forced.** A salted commitment would hide it, but would break the uniqueness check. Explain the trade-off. **Course link:** Lecture 7 §5.3 (commitments, hiding/binding).
- **Trust assumptions:**
  - The admin is a single key. Only the whitelist depends on the admin now (after A1).
  - The gatekeeper holds the data, so we trust it to enforce the rules. What if it lies or goes offline?
- **GDPR tension:** the right to be forgotten versus an immutable log. Mention that only hashes and addresses are on-chain.
- **Local-only evaluation:** no real network latency or fees.

### 5.3 Next steps
- Zero-knowledge proofs or selective disclosure, e.g. prove "ID is valid" without sharing the photo (Lecture 7 §5.4 zk-SNARKs; W3C Verifiable Credentials).
- A multisig or DAO admin.
- Encryption with per-requester key sharing.
- A Layer-2 / rollup deployment to cut costs (Lecture 6).
- The front-end, if not done.

### 5.4 Conclusion
- 4–6 sentences: the problem, what we built, the key result (numbers), and the main limitation. Nothing new.

## 6. Contributions & AI use (~0.75 page) · everyone writes their own line

- **Per member:** name, which workstream, what they built or wrote. Contributions must look adequate: members who didn't contribute get a 0.
- **AI transparency statement.** Use the coursebook template:
  - *I used generative AI for: …*
  - *The tool(s) I used were: …*
  - *The parts of my work affected by this use were: …*
  - *I have checked the accuracy and quality of the submitted work and take responsibility for it.*
- **Must mention:** the Step 1–3 design docs and contracts, the two bug fixes (denied-access logging, reward farming), the Hardhat 3 migration and the first version of the Step 4 test suite were AI-assisted, and the team reviewed and reworked them. Add anything else each of us used AI for.
  - Also AI-assisted (Claude Code, 1 Oct 2026): the A1–A4 contract changes and test updates, the gas benchmark script and gas tables, all of `offchain/` (data, hash tool, gatekeeper, simulation, demo, tests), the diagrams, the doc fixes (A5), the reference list, the Step 4/5 write-ups, the front-end and the slide deck. Each file says so in its header.

## References (doesn't count towards the page limit)

- One consistent style, e.g. numbered [1] or APA. **Done in [`references.md`](references.md)** (numbered, IEEE-like), and the Step 1 research table now cites them. Keep only the entries the report actually uses.
- Cover:
  - [x] Every row of the §1 comparison table ([1]–[10])
  - [x] W3C DID / Verifiable Credentials spec ([9], [10])
  - [x] OpenZeppelin Contracts docs ([18])
  - [x] Hardhat 3 / Ignition docs ([19])
  - [x] Solidity docs ([17])
  - [x] web3.py docs ([21])
  - [x] The course lectures cited (Lectures 1–7, Tutorials 1 and 3, Labs 3–5: [L1]–[L7], [T1], [T3], [Lab3]–[Lab5])

---

## Figure and table list (check before submitting)

| # | Item | Section | Owner | Ready in | ☐ |
|---|---|---|---|---|---|
| Table 1 | Roles and permissions | 2.1 | D | this file, §2.1 | ☑ data |
| Table 2 | Data model (on/off-chain/hashed) | 2.3 | D | this file, §2.3 | ☑ data |
| Figure 1 | Consent lifecycle | 2.4 | D | `diagrams/2-consent-lifecycle.png` | ☑ |
| Figure 2 | Architecture diagram | 2.6 | A | `diagrams/3-architecture.png` | ☑ |
| Figure 3 | Gatekeeper access flow | 2.6 | C | `diagrams/4-gatekeeper-flow.png` | ☑ |
| (extra) | Interaction overview (sequence) | 2.1 or 2.6 | D | `diagrams/1-interaction-sequence.png` | ☑ |
| Table 3 | Test results + why critical | 4.2 | B | `step4-deliverable.md` §1.2–1.4 | ☑ data |
| Table 4 | Deployment cost | 4.3 | B | this file, §4.3 | ☑ data |
| Table 5 | Gas per function, before/after | 4.3 | B | this file, §4.3 | ☑ data |
| Table 6 | Scaling in time and cost | 4.4 | C | this file, §4.4 | ☑ data |
| Figure 4 | Scaling chart (optional) | 4.4 | C | `diagrams/5-scaling.png` | ☑ |

## Course content to cite (the rubric rewards this)

| Source | Use it for |
|---|---|
| Lecture 1: cryptographic primitives | Why hashes; the limits of hashing guessable data |
| Lectures 2–3: Bitcoin mechanics, consensus | Where immutability of the log comes from |
| Lecture 4 §3.2: gas / SSTORE costs | Gas analysis, storage vs events |
| Lecture 4 §4.4: modifiers and access control | Roles, `onlyOwner`, whitelist |
| Lecture 4 §4.5: require/revert roll back | Why denied access doesn't revert |
| Lecture 4 §4.8: event logs | Audit log design, events are cheaper |
| Lecture 5 §1.1: ERC-20 recap | The ACT token |
| Lecture 6: scaling, rollups | Scaling discussion, future Layer 2 |
| Lecture 7 §2.1, §3.3: Ethereum isn't private, linking addresses to people | Limitations |
| Lecture 7 §5.3–5.4: commitments, zk-SNARKs | Salted hashes, future selective disclosure |
| Tutorial 1: keys, ECDSA signatures | Gatekeeper authentication |
| Tutorial 3: ERC-20/721/1155 | Choice of token standard |
| Labs 3 / 4 / 5 | Solidity tests / inter-contract calls / DApp + viem |
