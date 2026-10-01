# Study guide: explaining the code

For the team rule "everyone must be able to explain all of the code". Read it with
the code open next to it; every claim points to a file and line. It's study
material, not report text: don't paste it into the report.

> AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01 from the
> code as it is on branch `finish-project`. If the code changes, check the line
> numbers.

## 1. The whole system in six sentences

1. A patient keeps the two ID files (front, back) in a local data store and puts
   only their **SHA-256 hashes**, a hash of the email and a **link to the gatekeeper**
   on-chain (`DigitalIdentityRegistry`).
2. The admin **whitelists** providers; a patient grants a whitelisted provider
   **consent** with a scope (front / back / both) and a duration of 1–365 days
   (`ConsentManager`), earning 10 ACT the first time (`AccessToken`).
3. A provider calls **`requestAccess(patient)`** (`DataSharingManager`), which checks
   the whitelist and the consent and **always logs** the attempt (`AccessLogger`):
   GRANTED, or DENIED with a reason, never a revert for a whitelisted provider.
4. The provider shows its GRANTED transaction, **signed with its own key**, to the
   **gatekeeper**, which re-checks everything on-chain and releases only the files the
   scope allows (`offchain/gatekeeper.py`).
5. The provider **re-hashes** the files and compares them with the on-chain hashes, so
   it doesn't have to trust the gatekeeper for integrity.
6. Everything on-chain is public, so privacy comes from what we *don't* put there,
   and from the gatekeeper; the log is transparent by design.

## 2. One access request, call by call

```
Provider ──requestAccess(patient)──▶ DataSharingManager
  1. registry.isApprovedRequester(provider)?   no → revert "requester not whitelisted"
  2. consentManager.getConsent(patient, provider)   (one external read)
  3. _denialReason(expiresAt, revoked, exists)  → NONE / NO_CONSENT / REVOKED / EXPIRED
  4a. NONE:  registry.getUserRecord(patient) → zero the hash the scope hides
             accessLogger.logAccess(…, GRANTED, NONE); emit AccessGranted
  4b. else:  accessLogger.logAccess(…, DENIED, reason); emit AccessDenied; return false
```

`contracts/DataSharingManager.sol:36-78`. Why each step is there:

- **Step 1** (A2): strangers can't fill a patient's log with spam, and a provider
  the admin removes loses access at once. It's a `require`, so the call reverts and
  leaves no log entry; the failed transaction is still visible on-chain.
- **Step 2** (A4): one call instead of `isConsentValid` + `getConsent`. The
  validity rule is now in two places (`ConsentManager.sol:98` and
  `DataSharingManager.sol:69`); the fuzz test
  `testFuzz_AccessDecisionMatchesConsentValidity` proves they agree.
- **Step 4b doesn't revert**: a revert undoes *all* state changes of the transaction,
  including the DENIED log entry (Lecture 4 §4.5). Returning `false` keeps the entry.

## 3. Contract by contract

### DigitalIdentityRegistry (`contracts/DigitalIdentityRegistry.sol`)

| What | Where | Why |
|---|---|---|
| `Identity {emailHash, documentLink, frontHash, backHash}` | :16 | Minimal data only, never name/DOB/ID number. No `registered` field: `emailHash != 0` means registered (A4, saves one SSTORE ≈ 22k gas) |
| `usedEmailHashes` | :24 | Uniqueness: one identity per email. That's why the email hash is **unsalted**, which also makes it guessable (limitation) |
| `registerUser` | :39 | Rejects re-registration, zero hashes, empty link, reused email |
| `updateDocument` | :64 | Renewed ID: new link + hashes, same identity (`onlyRegistered`) |
| `setRequesterStatus` | :82 | `onlyOwner` (OpenZeppelin `Ownable`): the admin's one real power |
| `getUserRecord` | :96 | Public read. Providers use it to get the hashes to check files against, because an EOA can't read a mined transaction's return value |

### ConsentManager (`contracts/ConsentManager.sol`)

| What | Where | Why |
|---|---|---|
| `Scope {FRONT_ONLY, BACK_ONLY, BOTH}` | :14 | What the provider may see; enforced on the files by the gatekeeper |
| `Consent {scope, uint64 grantedAt, uint64 expiresAt, revoked, exists}` | :20 | 19 bytes = **one storage slot** (A4: first grant 163k → 97k gas). `uint64` seconds lasts ~585 billion years |
| `consents[user][requester]` | :36 | Consent is per (patient, provider) pair |
| `setConsent` | :55 | Caller must be registered, provider whitelisted, 1–365 days. `expiresAt = now + days × 1 days`. Overwrites any earlier record, so re-granting after revoke/expiry works |
| reward | :65, :82 | `firstGrant = !exists` *before* writing; `exists` is never cleared, so revoke + re-grant can't farm ACT |
| `revokeConsent` | :89 | Only touches `consents[msg.sender][…]`, so only the patient can revoke their own consent; no admin override |
| `isConsentValid` | :98 | `exists && !revoked && now <= expiresAt`: **lazy expiry**, no transaction needed |

### AccessToken (`contracts/AccessToken.sol`)

- ERC-20 "ACT" from OpenZeppelin. `mintReward` (:35) only for `minter`.
- `setMinter` (:26) works **once**: `require(minter == address(0))` (A1). Before A1 the
  owner could re-point minting at their own wallet and mint unlimited ACT.
- Why not in the constructor? ConsentManager needs the token's address in *its*
  constructor, so the token is deployed first and wired after
  (`ignition/modules/DigitalIdentityPlatform.ts`). Honest caveat: it *could* be done
  in a constructor (ConsentManager deploying the token, or precomputed CREATE2
  addresses, Lecture 4 §4.11); we chose five independent contracts.
- ERC-20 not NFT: the reward is fungible and divisible (Tutorial 3).
- Tokens **never** grant access: nothing in `DataSharingManager` reads a balance
  (`test_TokenBalanceDoesNotGrantAccess`).

### AccessLogger (`contracts/AccessLogger.sol`)

| What | Where | Why |
|---|---|---|
| `Outcome`, `Reason` enums | :12, :17 | One byte each instead of a string (A4) |
| `LogEntry {address, uint64 timestamp, Outcome, Reason}` | :22 | 30 bytes = **one slot** per entry (A4: −44k gas per access) |
| `setDataSharingManager` | :49 | One-time, like `setMinter` (A1): the admin can't become the log writer |
| `logAccess` | :58 | `onlyDataSharingManager`; only `push` exists, no delete/edit anywhere: **append-only** |
| `AccessLogged` event | :33 | The same data in the transaction receipt (cheap, permanent, but contracts can't read it) |
| `getLogs` | :81 | **Public** on purpose (A3): storage is readable with `eth_getStorageAt` anyway, and an `eth_call` can fake `msg.sender` |

Immutability doesn't come from the contract alone: the contract has no delete
function, and the chain's hash-linked blocks + consensus make rewriting history
infeasible (Lectures 2–3).

### DataSharingManager (`contracts/DataSharingManager.sol`)

Holds `immutable` references to the other three contracts (:14-16), set in the
constructor: these can never change. See section 2 for `requestAccess`.

## 4. Off-chain (Python, `offchain/`)

| File | Know this |
|---|---|
| `fake_data.py` | Deterministic fake identity per address (`random.Random(address)`); "UTO" is the ICAO specimen country, `.invalid` is a reserved domain |
| `hash_tool.py` | `sha256(file bytes)` → 32 bytes = `bytes32`. Files are written with fixed JSON formatting, so the bytes and the hash are reproducible |
| `gatekeeper.py` | `Gatekeeper.release` (:127) runs the checks in order, below |
| `common.py` | ABIs from `artifacts/`, addresses from Ignition, local signing, nonce tracking, timing |
| `simulate.py` | N users / M requesters, phases, CSVs + tables; `--block-time 12` for interval mining |
| `test_gatekeeper.py` | One test per refusal reason |

**The gatekeeper's checks** (`offchain/gatekeeper.py:127-200`), and the attack each stops:

1. Receipt: mined, succeeded, sent **to DataSharingManager** → made-up or failed transactions, calls to other contracts.
2. **Signature** over `(user, tx hash)` recovers to the transaction's sender → someone who copied a public tx hash (ECDSA, Tutorial 1; EIP-191 message).
3. Receipt has `AccessGranted(user, sender)` → a DENIED transaction, or a grant for another patient.
4. Requester still whitelisted, `isConsentValid` still true **now** → reusing an old grant after revoke, expiry or removal.
5. Mined in the last 5 minutes → saving up a grant for later.
6. Only the files the consent scope allows are read (missing files → refused).
7. Tx hash not used before → one release per GRANTED log entry (checked last, so a refused request doesn't burn the hash).

"Now" is `max(wall clock, latest block time)` (:122) so tests that move the chain's
clock forward still work.

## 5. Tests

- Solidity tests (forge-std, Lab 3 style): `vm.prank` (act as someone), `vm.expectRevert`,
  `vm.warp` (move time), `vm.expectEmit`, `bound` in fuzz tests. The test contract
  itself deploys everything, so it is the admin.
- Integration tests wire the contracts exactly as the Ignition module does.
- Run one file: `npx hardhat test contracts/ConsentManager.t.sol`.

## 6. Gas, in one paragraph

Writing a storage slot from zero costs 20,000 gas + 2,100 for the first (cold)
access (Lecture 4 §3.2); everything else is small next to that. So the optimisations
are about writing fewer slots: one slot per log entry, one per consent, no separate
`registered` flag. A denied access now costs 72k gas: 21k base, ~22k for the new log
slot, the rest calls and reads. Events-only logging would save ~28k more, but
contracts can't read events and nodes may prune old ones (EIP-4444), so we kept
storage. Numbers: `docs/step4-deliverable.md` §2.

## 7. Questions examiners are likely to ask

| Question | Short answer | Where |
|---|---|---|
| Why not store the ID on-chain? | All chain data is public and storage is expensive (~22k gas per 32 bytes) | Lecture 7 §2.1, Lecture 4 §3.2 |
| Can the admin cheat? | Can whitelist and set the reward rate. Can't read files, consent, revoke, log, mint or re-wire (one-time setters) | `test_AdminCannotBypassUserControl` |
| What happens at expiry? | Nothing is sent; the next check compares the timestamp and fails (DENIED: EXPIRED) | `ConsentManager.sol:98` |
| Why doesn't denial revert? | A revert would also erase the DENIED log entry | `DataSharingManager.sol:61-63` |
| Why did strangers revert then? | They aren't requesters; logging them would allow spam. Trade-off: their attempts aren't in the log (the failed tx is) | `DataSharingManager.sol:40` |
| Why don't tokens give access? | The brief: access only through consent; ACT is an incentive, ownership never moves | `test_TokenBalanceDoesNotGrantAccess` |
| Is the log private? | No, public by design; it holds only addresses, times and outcomes | `AccessLogger.sol:74-83` |
| How does the gatekeeper know who's asking? | The request is signed with the key that sent the GRANTED transaction | `gatekeeper.py:148-157` |
| Why both a signature and a tx hash? | Tx hashes are public; without the signature anyone could replay one | `test_signature_from_someone_else_is_refused` |
| What if the gatekeeper lies? | Wrong files fail the re-hash check; but it could refuse or go offline (availability is trusted) | `verify_files`, `gatekeeper.py:290` |
| Can someone guess the email from its hash? | Yes, if guessable: it's unsalted to allow the uniqueness check; a salted commitment would hide it but break that check | Lecture 7 §5.3 |
| What's most expensive? | `registerUser` (206k): 4+ new slots including the link string | Step 4 §2.3 |
| Does it scale? | Gas per operation is flat in N; total grows linearly; time is set by block interval and the block gas limit | Step 5 |
| What about GDPR erasure? | Only hashes and addresses are on-chain, but log entries can't be erased: a real tension | Discussion |
| Where did you use AI? | Be open: Steps 1–3 docs and contracts, the fixes, tests, gas work, off-chain code, docs and slides were AI-assisted, then reviewed by us | report §6 |

## 8. Check yourself (10 minutes each)

1. In `ConsentManager.sol`, move `firstGrant` below the write of the new record. Which
   test fails, and why? (Undo it afterwards.)
2. Change `requestAccess` to `revert` on denial. Run the tests: what breaks, and what
   would a patient lose?
3. Delete the `require(minter == address(0))` line. Which test catches it?
4. With the node running, run `python offchain/demo.py`, then call the gatekeeper with
   the old GRANTED transaction. Which check refuses it?
5. Explain, without notes, why a log entry fits in one storage slot.
