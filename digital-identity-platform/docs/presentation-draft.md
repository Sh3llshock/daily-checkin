# Presentation draft: slides, talking points, demo, Q&A

> **How to use this file**
> - Each slide lists **what goes on it** and **talking points**. These are the ideas to get across, **not a script**. Say them in your own words, and practise out loud once.
> - The rubric and the AI policy both expect us to explain our own work, and examiners may ask follow-up questions.
> - **Check the Week 6 Lab on Canvas for the official format** (length, required parts), then adjust the timings below (TASKS D0.4).
> - **Deadline:** email the slides to the instructors **before Mon 5 Oct, 12:00**. We present in Lab 6 (Mon) or Lab 7 (Wed).

**Assumed format:** about 10 minutes of talk, then questions. Rule of thumb: 1 idea per slide, about 45–60 s per slide, big diagrams, few words.

| Speaker | Workstream | Slides | Time |
|---|---|---|---|
| Speaker 1 | D: report | 1–3, 11–12 | ~3 min |
| Speaker 2 | A: contracts | 4–6 | ~2.5 min |
| Speaker 3 | C: off-chain | 7–8 (demo) | ~2.5 min |
| Speaker 4 | B: tests | 9–10 | ~2 min |

---

## Slide 1: Title · Speaker 1 · 15 s
- **On the slide:** project title, the domain line (*government-ID verification for healthcare*), 4 names, course, date.
- **Say:**
  - Who we are, and the one-line idea: patients control who sees their ID, and every look is logged on-chain.

## Slide 2: The problem · Speaker 1 · 50 s
- **On the slide:** one picture. Many hospitals each hold a copy of the patient's ID, with a 🔓 on each.
- **Say:**
  - Providers must verify IDs. Today each one keeps its own copy.
  - The consequences: a breach "honeypot", no visibility, no way to revoke, logs you can't trust, and the patient gets nothing.
  - Map it to the brief's problem statement: centralised platforms control user data.

## Slide 3: Our approach · Speaker 1 · 45 s
- **On the slide:** 3 icons, *data stays with the user* · *consent on-chain* · *every access logged*, plus the token reward.
- **Say:**
  - What goes on-chain (hashes, consent, logs) and what stays off (the actual ID data).
  - Name 1–2 existing systems (e.g. eIDAS, W3C DID/VC) and what we do differently.

## Slide 4: Roles and flow · Speaker 2 · 50 s
- **On the slide:** the sequence diagram (report Figure, Step 1 §1.5), simplified to 6–7 arrows.
- **Say:**
  - The patient registers, the admin whitelists the provider, the patient grants consent for X days, the provider requests access, and the attempt is logged.
  - What the admin **can't** do: read data, grant consent, edit logs.

## Slide 5: Architecture and data model · Speaker 2 · 60 s
- **On the slide:** the architecture diagram (5 contracts + gatekeeper), plus a mini on-chain/off-chain table.
- **Say:**
  - One line per contract: Registry, ConsentManager, DataSharingManager, AccessLogger, AccessToken.
  - Why the system is split into small contracts: separation of concerns, testability, and the admin stays out of the data path.
  - The rule of thumb: what identifies a person stays off-chain; proofs and permissions go on-chain.

## Slide 6: Key design decisions · Speaker 2 · 60 s
- **On the slide:** 4–5 short bullets, each with an icon:
  - denied access doesn't revert
  - lazy expiry
  - reward once
  - whitelist check
  - one-time wiring
- **Say, picking the 2–3 most interesting:**
  - **No revert on denial:** a revert would erase the DENIED log (Lecture 4, require/revert roll back).
  - **Lazy expiry:** there's no cleanup transaction; the next check just fails, which saves gas.
  - **Reward once per requester:** otherwise tokens could be farmed. Tokens never grant access.
  - Why the contracts are wired only once: so the admin can't mint tokens or forge logs.

## Slide 7: Off-chain data and the gatekeeper · Speaker 3 · 50 s
- **On the slide:** the gatekeeper flow diagram (report Figure 3).
- **Say:**
  - The problem we found: everything on-chain is public, so a link alone protects nothing (Lecture 7).
  - The fix: the gatekeeper releases files only if the requester shows their own granted `requestAccess` transaction, **and** consent is still valid, **and** the transaction is recent.
  - The result: no log, no data. And the scope (front/back) is finally enforced.
  - The requester re-hashes the files and checks them against the on-chain hashes.

## Slide 8: Live demo · Speaker 3 · ~2 min
- **On the slide:** "Live demo", plus the backup video, ready to play.
- **Demo script** (terminal, pre-deployed before the talk):
  1. `npx hardhat node` is already running, and the contracts are deployed (`npm run deploy:local`).
  2. Run the simulation for a small N, or a short demo script:
     - the patient registers → the admin whitelists → the patient grants 30 days → the provider gets **GRANTED** and the gatekeeper returns the files, with matching hashes;
     - the patient revokes → the provider tries again → **DENIED (REVOKED)**, and the gatekeeper refuses.
  3. Show the patient's access log: 2 entries, GRANTED then DENIED, with timestamps.
- **Say:** narrate each step in one sentence, pointing at the output.
- **Backup:** if anything fails, switch to the recorded video immediately (TASKS D5). Don't debug live.

## Slide 9: Testing · Speaker 4 · 50 s
- **On the slide:** big numbers, "N tests · 5 contracts + integration · all passing", plus 4–5 example test names.
- **Say:**
  - Unit tests per contract, integration workflows, and negative tests (reverts, denials, expiry with `vm.warp`).
  - Pick 2 tests and say **why they're critical**, e.g. "denied access is logged" and "reward can't be farmed".
  - No personal data was used.

## Slide 10: Gas and scaling · Speaker 4 · 60 s
- **On the slide:** Table 5 (gas per function, before/after) and Table 6 or a chart (N users vs gas and time). Highlight 1–2 numbers.
- **Say:**
  - The most expensive operation, and why (storage writes).
  - The best optimisation and how much it saved (Lecture 4: SSTORE vs events).
  - Scaling: whether cost per operation stays flat as users grow, and what local timing does and doesn't tell us about a real network (Lecture 6).

## Slide 11: Limitations and future work · Speaker 1 · 45 s
- **On the slide:** 2 columns, *Limitations* | *Next steps*.
- **Say:**
  - **Limitations:**
    - on-chain data is public, and addresses can be linked to people;
    - an unsalted email hash can be guessed (Lecture 7 commitments);
    - we have to trust the admin and the gatekeeper;
    - GDPR vs an immutable log;
    - local-only results.
  - **Next:** zero-knowledge proofs or selective disclosure (Lecture 7), a multisig admin, encryption, Layer 2 (Lecture 6).

## Slide 12: Conclusion + questions · Speaker 1 · 20 s
- **On the slide:** 3 takeaways + "Questions?"
- **Say:**
  - Problem → what we built → the key result, then invite questions.

---

## Likely questions (prepare an answer for each)

| Question | Who answers | Where the answer is |
|---|---|---|
| Why not store the ID data on-chain? | 2 | Public state and cost (Lecture 7 §2.1, Lecture 4 gas); report §2.3 |
| Can the admin tamper with anything? | 2 | After A1: no minting and no log forging. The admin can only whitelist. Report §3.2, §5.2 |
| What happens when consent expires? | 2 | Lazy expiry: the next `isConsentValid` fails and the attempt is logged as EXPIRED. Report §2.4 |
| Why doesn't denied access just revert? | 2 | A revert rolls back the log entry (Lecture 4 §4.5). Report §3.2 |
| Why don't tokens give access? | 2 | The brief says access comes from consent only; the token is an incentive; ownership never moves. Report §2.4 |
| Is the data on-chain private? | 3 | No. It's all public (Lecture 7). That's why only hashes are stored and the gatekeeper exists. Report §5.2 |
| How does the gatekeeper know who the requester is? | 3 | The signed `requestAccess` transaction plus its receipt and event (Tutorial 1 ECDSA). Report §3.3 |
| What if the gatekeeper lies or goes offline? | 3 | It's a trust assumption: integrity is checkable through the hashes, availability isn't guaranteed. Report §5.2 |
| What's the most expensive function, and why? | 4 | Report §4.3, Table 5 |
| How would this scale on a real network? | 4 | Report §4.4, Lecture 6 |
| Can someone guess the email from its hash? | 1 | Yes, if unsalted; commitments add a salt (Lecture 7 §5.3). Report §5.2 |
| Where did you use AI? | 1 | Report §6, the contribution statement. Be open about it. |

## Before the talk (checklist)

- [ ] Slides emailed before **Mon 5 Oct, 12:00**.
- [ ] Timings rehearsed once, all 4 speakers, with a stopwatch.
- [ ] Demo machine: node running, contracts deployed, terminal font enlarged.
- [ ] Backup demo video on the laptop and on a USB stick.
- [ ] Everyone has read the Q&A table.
