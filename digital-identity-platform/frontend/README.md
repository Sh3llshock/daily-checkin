# Front-end (Step 6, bonus)

A single page that talks to the contracts on the local Hardhat network with **viem**,
using the same local-chain setup as the Lab 5 demo (`frontend/lib/wagmi.ts` there).
No wallet extension is needed: you pick one of the node's 10 test accounts (they all
come from Hardhat's public test mnemonic and hold ETH only locally), and the page
signs with it.

> AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01; must be
> reviewed by the team and declared in the report's AI statement.

| Tab | What you can do |
|---|---|
| **Patient** | Register (pick your fake `id_front.json` / `id_back.json`; the page hashes them with SHA-256 and registers the hashes + your gatekeeper link), grant consent (provider, scope, 1–365 days), see and revoke your consents |
| **Provider** | Request access to a patient; on GRANTED, sign a request and fetch the files from the gatekeeper, then check each file's hash against the chain |
| **Admin** | Approve or remove requesters (account #0 only) |
| **Audit log** | Read any patient's access log (it's public) |

"Your consents" and the provider/patient lists are rebuilt from contract events
(`ConsentGranted`, `ConsentRevoked`, `UserRegistered`, `RequesterStatusChanged`)
instead of extra view functions, which is the TASKS A6 alternative.

## Run it

From `digital-identity-platform/`:

```bash
npx hardhat node                              # terminal 1
npm run deploy:local                          # terminal 2 (after a node restart: -- --reset)
python offchain/gatekeeper.py                 # terminal 2 or 3: serves offchain/data on :8600
npm run frontend                              # open http://127.0.0.1:5173
```

A quick tour with the demo accounts:

1. **#0 Admin** → Admin tab → approve `#2 Provider (demo)`.
2. **#1 Patient (demo)** → Patient tab → register with any `…@example.invalid` email and
   the two files in `offchain/data/0x70997970C51812dc3A010C7d01b50e0d17dc79C8/`
   (skip if `python offchain/demo.py` already registered it) → grant consent to #2.
3. **#2 Provider** → Provider tab → pick #1 → Request access → GRANTED → Fetch the
   files: both show "hash matches the chain".
4. **#1** → revoke. **#2** → request again → DENIED: REVOKED.
5. Audit log tab → pick #1: both attempts, in order.

For another test account, first create its fake files with
`python offchain/fake_data.py <address>` (the page shows the exact command).

## Files

| File | Role |
|---|---|
| `index.html`, `style.css` | Layout and styling (light and dark, works at phone width) |
| `app.js` | viem clients, contract reads/writes, event queries, gatekeeper request |
| `vite.config.js` | Dev server; serves `/deployment.json` (addresses from Ignition + ABIs from `artifacts/`) |
| `wireframes.md` | Step 6 wireframes and screenshots of the result |

Verified on 2026-10-01 with headless Chrome: the whole tour above, no console
errors, no horizontal scrolling at 390 px.
