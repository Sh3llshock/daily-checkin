# Step 7: Report and Documentation

<p class="subtitle">BCS3210 Blockchains group project: Decentralized Digital Identity and Data Sharing Platform</p>

## What we did in this step

We wrote the final report, made the presentation, and documented the code so that someone else can run everything on a local Hardhat network.

| Deliverable | File |
|---|---|
| Final report (coursebook format) | `deliverables/report.pdf` |
| Presentation (12 slides) | `deliverables/presentation.pdf` |
| Step deliverables 1-7 | `deliverables/stepN-deliverable.pdf` |
| Code with run instructions | `digital-identity-platform/` and its `README.md` |
| Raw measurements | `results/` (test output, gas reports, simulation JSON, plot) |

## 1. Report

The report follows the structure and the format rules of the coursebook:

| Coursebook requirement | How we did it |
|---|---|
| Cover page with title, names and IDs | Page 1 (names and IDs still to be filled in) |
| Introduction, Architecture, Implementation, Experimental Results, Discussion and Conclusion | Sections 1 to 5 |
| No implementation details in the Architecture section | Section 2 only describes roles, data, components and flows |
| Max 10 pages without references and code | 10 pages including cover and references |
| 10 pt Times New Roman, double spaced, A4, 1 inch margins, page numbers | Set in the report stylesheet; page numbers added when the PDF is built |
| Consistent, verifiable references | Numbered references [1] to [10] |
| Contribution of each member, where and how AI was used | Section 6 with a transparency statement (to be completed by the team) |

## 2. Project brief checklist

| Requirement from the brief | Where |
|---|---|
| Problem statement, roles, functional requirements, interaction overview | Step 1, report 1 and 2.1 |
| Attribute table (on-chain / off-chain / hashed) | Step 2, report 2.2 |
| Consent model: data types, 1-365 days, who grants/revokes, expiry, workflows | Step 2, report 2.4 |
| Audit log: who, what, when, granted/denied, not deletable | Step 2, report 2.5, `DataSharing.sol` |
| Architecture diagram | Step 2, report Figure 1 |
| Register user, retrieve info, set consent (with token reward), revoke consent, log access | `DigitalIdentity.sol`, `ConsentManager.sol`, `DataSharing.sol` |
| Data stays with the user, only hashes on-chain, access only with valid consent | Python vault (`offchain/`), report 2.5 |
| Tokens reward sharing, only the contract can mint, no tokens move during access | `AccessToken.sol`, tests `test_RevertsWhenNonMinterMints`, `test_NoTokensMoveDuringAccess` |
| Solidity unit tests named after the contracts, why each is critical | `test/*.t.sol` (64 passing), Step 4 |
| Gas table: deployment and average per function, optimisation | Step 4, report 4.2 |
| Integration tests of the full workflow | `Integration.t.sol`, `offchain/demo.py` |
| No personal data in tests | Generated addresses, fake hashes, generated ID images |
| Local deployment with Hardhat | Ignition module, `npm run deploy:local` |
| Simulation with several roles, gas and time, scaling tables | Step 5, report 4.3 |
| Front-end with Viem.js on the local network (bonus) | Step 6, `frontend/` |
| Instructions to compile, deploy and test | `README.md` |

## 3. How to reproduce everything

```
cd digital-identity-platform
npm install
npx hardhat compile
npx hardhat test                   # 64 tests
npm run gas-report                 # gas per function
npm run demo                       # walk-through
npx hardhat node                   # second terminal
npm run deploy:local
npm run simulate                   # scaling results
python offchain/make_sample_data.py && python offchain/demo.py
npm run frontend                   # http://localhost:5173
python deliverables/build_pdf.py               # rebuild step PDFs
python deliverables/build_pdf.py    report slides
```

We tested these steps on a fresh copy of the project (only the source files, `npm install` from scratch) before submitting.

## 4. Still to do by the team before the deadline

- Fill in names and student IDs on the cover page, the contribution table and the title slide.
- Check and adjust the AI transparency statement in Section 6 of the report.
- Every member reads the code and the report so they can explain it.
- Submit the project before **Sunday 4 October 2026, 23:59 CEST** and send the presentation to the instructors before **12:00 on Monday 5 October**.
