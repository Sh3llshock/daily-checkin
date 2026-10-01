# Step 2 — Platform/System Design

## Required Deliverable (as specified in the project brief)

> Architecture diagram (UML or others) showing your chosen design and how the
> components of the system interact with one another.

The brief also directs the design work leading up to that diagram: design the data
model (with an on-chain/off-chain/hashed table), design the consent model (types of
data, duration, who can grant/revoke, expiry behavior, workflows), design the audit
log (what's recorded, that logs can't be deleted), and design the smart contracts for
the Digital Identity and Data Sharing components. All of that is included below,
since the architecture diagram is meaningless without the design decisions it
depicts.

---

## A. Data Model

### A.1 Identity Attributes

The only attributes strictly necessary to (a) uniquely identify a user on-chain and
(b) let a requester verify + integrity-check a government ID are:

- A **wallet address** (the on-chain identity/account).
- An **email hash** (used off-chain for account recovery/notifications; hashed
  on-chain purely to allow a uniqueness check without exposing the raw email).
- A **document reference link** — the URL of the gatekeeper endpoint that holds the
  user's front/back ID files (e.g. `http://127.0.0.1:8600/users/0x7099…79C8`). The link
  is public like everything on-chain; the gatekeeper, not the secrecy of the link,
  decides who gets the files (see A.5).
- A **SHA-256 hash of the front-of-ID image**.
- A **SHA-256 hash of the back-of-ID image**.

Everything else (real name, physical ID number, date of birth, the images themselves)
lives off-chain, under the user's control, and is never written to the ledger.

### A.2 On-chain / Off-chain / Hashed Table

| Attribute | Stored On-Chain? | Stored Off-Chain? | Hashed? |
|---|:---:|:---:|:---:|
| Wallet address | ✅ | — | No (it's already a public key-derived identifier) |
| Full name | ❌ | ✅ | No |
| Email address | ❌ | ✅ (plaintext, for notifications) | ✅ hash stored on-chain for uniqueness check |
| Government ID number/type | ❌ | ✅ | Optional — a hash *can* be stored on-chain to block duplicate registrations without revealing the number |
| Document link (the gatekeeper URL for this user) | ✅ | (points to the gatekeeper, which holds the files) | No |
| Front-of-ID image (actual photo) | ❌ | ✅ (local data store; released only by the gatekeeper) | ✅ SHA-256 hash stored on-chain |
| Back-of-ID image (actual photo) | ❌ | ✅ (local data store; released only by the gatekeeper) | ✅ SHA-256 hash stored on-chain |
| Consent record (requester, scope, expiry, revoked flag) | ✅ | — | No (needs to be readable/checkable by contracts) |
| Access log entry (requester, timestamp, outcome) | ✅ | — | No |
| ACT token balances | ✅ | — | No |

**Rule of thumb applied throughout:** anything that identifies a *person* stays
off-chain; anything needed to *verify integrity* or *enforce/prove permission* goes
on-chain, and only ever as a hash, link, or access-control record — never as raw PII.

**Everything marked "on-chain" is public** (Lecture 7 §2.1): any node can read the
contracts' storage and events, including the link, the hashes, every consent record
and every log entry. The email hash is unsalted so the registry can reject a reused
email, which also means a guessable email can be recovered from it by brute force.

### A.3 Consent Model

**What can be shared (data scope):**

| Scope value | Meaning |
|---|---|
| `FRONT_ONLY` | Requester may retrieve the link + front-of-ID hash only |
| `BACK_ONLY` | Requester may retrieve the link + back-of-ID hash only |
| `BOTH` | Requester may retrieve the link + both hashes (typical case for identity verification) |

**Duration:** 1–365 days, chosen by the user per grant (`setConsent` rejects 0 or
>365). Stored as an absolute `expiresAt = block.timestamp + durationInDays * 1 days`.

**Who can grant/revoke:**
- Only the identity owner (`msg.sender == user`) can call `setConsent` or
  `revokeConsent` for their own record — enforced in every state-changing function.
- Requesters can never grant themselves consent.
- The Administrator can never grant or revoke consent on a user's behalf — the admin
  role is limited to whitelisting requester addresses and setting the token reward
  parameter, keeping it out of the actual data-access decision path.

**What happens on expiry:**
- No transaction is required to "expire" a consent (this avoids wasted gas from
  someone having to proactively clean up state). Instead, `isConsentValid(user,
  requester)` is a pure read computed as:
  `consent.exists && !consent.revoked && block.timestamp <= consent.expiresAt`.
- Any `requestAccess` call after expiry is treated exactly like "no consent" — it is
  denied and logged as `DENIED`.

**Consent lifecycle (state diagram):**

![Consent lifecycle](diagrams/2-consent-lifecycle.png)

Source: [`diagrams/2-consent-lifecycle.mmd`](diagrams/2-consent-lifecycle.mmd). An
earlier version showed Revoked and Expired as final states; the code has always let
the owner grant again from either state (`setConsent` overwrites the record), so the
diagram now shows those transitions, and that only the very first grant to a
requester mints ACT.

**Consent workflow (pseudocode):**

```
function setConsent(requester, durationDays, scope):
    require(msg.sender is a registered user)
    require(requester is a whitelisted healthcare provider)
    require(1 <= durationDays <= 365)
    firstGrant = NOT consents[msg.sender][requester].exists
    consents[msg.sender][requester] = Consent(
        scope: scope,
        grantedAt: now,
        expiresAt: now + durationDays * 1 day,
        revoked: false
    )
    emit ConsentGranted(msg.sender, requester, scope, expiresAt)
    if firstGrant:                                        # once per (user, requester)
        AccessToken.mintReward(msg.sender, REWARD_AMOUNT) # incentive, not access control

function revokeConsent(requester):
    require(consents[msg.sender][requester] exists)   # only the caller's own record
    require(NOT consents[msg.sender][requester].revoked)
    consents[msg.sender][requester].revoked = true
    emit ConsentRevoked(msg.sender, requester)

function isConsentValid(user, requester) -> bool:
    c = consents[user][requester]
    return c.exists AND NOT c.revoked AND now <= c.expiresAt
```

### A.4 Audit Log Design

**Events recorded per access attempt:**
- `user` — whose identity record was targeted.
- `requester` — who attempted the access.
- `timestamp` — `block.timestamp` of the attempt.
- `outcome` — `GRANTED` or `DENIED`.
- `reason` (for denials) — `NO_CONSENT`, `EXPIRED`, or `REVOKED` (`NONE` on granted
  entries), stored as a one-byte enum rather than a string to save gas (Step 4).

**Can logs be deleted?** No. The log contract exposes only *append* functionality
(`logAccess`, callable exclusively by the `DataSharingManager` contract); there is no
`delete`/`remove`/`update` function of any kind, and log entries are additionally
emitted as `event`s, which are permanently part of the blockchain's transaction
history regardless of contract state. This gives every user an immutable, independently
verifiable record of exactly who looked at their identity reference and when —
addressing the "no visibility into who accesses data" and "no immutable audit trail"
problems directly.

**Who can read the log?** Anyone. `getLogs` has no caller restriction: contract
storage and events are public anyway, and a `msg.sender` check on a view function is
not privacy, because an `eth_call` can set any `from` address. The audit trail is
transparent by design; it contains only addresses, timestamps and outcomes, never
personal data. (An earlier version restricted `getLogs` to the user and the admin and
described that as privacy; that restriction was removed — TASKS A3.)

**Access logging workflow (pseudocode):**

```
function requestAccess(user):
    require(msg.sender is a whitelisted requester)   # strangers revert: no log spam
    c = getConsent(user, msg.sender)                 # one read gives validity + scope
    reason = NO_CONSENT if not c.exists
             else REVOKED if c.revoked
             else EXPIRED if now > c.expiresAt
             else NONE
    if reason == NONE:
        logAccess(user, msg.sender, GRANTED, NONE)
        return (true, documentLink[user], hashes allowed by c.scope)
    else:
        logAccess(user, msg.sender, DENIED, reason)
        return (false, "", 0, 0)   # NOT revert: a revert would erase the DENIED log
```

## B. Smart Contract Design

The system is split into five small, single-responsibility contracts rather than one
monolith, so each piece can be reasoned about (and gas-profiled) independently in
Step 4:

| Contract | Responsibility |
|---|---|
| `DigitalIdentityRegistry.sol` | User registration; stores email hash, document link, front/back image hashes; requester whitelisting (admin) |
| `ConsentManager.sol` | Create/revoke consent records; validity checks; triggers ACT reward on grant |
| `AccessLogger.sol` | Append-only audit trail of every access attempt (granted or denied) |
| `DataSharingManager.sol` | Entry point for requesters; orchestrates the consent check → release reference → log flow |
| `AccessToken.sol` (ERC-20) | The incentive token (ACT); minting restricted to `ConsentManager` |

### B.1 Digital Identity component — `DigitalIdentityRegistry.sol`

| Function | Signature | Caller | Description |
|---|---|---|---|
| Register User | `registerUser(bytes32 emailHash, string calldata documentLink, bytes32 frontHash, bytes32 backHash)` | Any new user | Requires the caller isn't already registered; stores the four fields keyed by `msg.sender`. Minimal data — no name, DOB, or ID number ever touches this function. |
| Update Document | `updateDocument(string calldata newLink, bytes32 newFrontHash, bytes32 newBackHash)` | Registered user, self only | Lets a user point to a re-uploaded/renewed ID without re-registering their whole account. |
| Retrieve User Info | `getUserRecord(address user) view returns (bytes32 emailHash, string memory documentLink, bytes32 frontHash, bytes32 backHash, bool registered)` | Anyone (public read) — the *link/hashes* are not secret (all chain state is public); the files themselves are protected by the gatekeeper, which only serves a requester with a fresh GRANTED `requestAccess` | Query a user's stored reference/hash data. Requesters use it to read the hashes they check the received files against (an EOA can't read a mined transaction's return values). |
| Whitelist Requester | `setRequesterStatus(address requester, bool approved)` | Admin (`onlyOwner`) only | Marks an address as a recognized healthcare provider, a precondition checked by `ConsentManager.setConsent`. |

### B.2 Consent functions (also in `ConsentManager.sol`, called by/for the identity owner)

| Function | Signature | Caller | Description |
|---|---|---|---|
| Set Consent | `setConsent(address requester, uint8 scope, uint256 durationDays)` | Registered user, self only | Validates `1 <= durationDays <= 365` and that `requester` is whitelisted; writes the consent record; on the user's first grant to this requester only, calls `AccessToken.mintReward(msg.sender)` (re-granting never mints again, so tokens can't be farmed) — minting itself is restricted so **only** `ConsentManager` (the token's designated minter, wired once at deployment and never changeable afterwards) can trigger it, and **no** tokens move during data access, only at grant time. |
| Revoke Consent | `revokeConsent(address requester)` | Registered user, self only | Sets `revoked = true` on the existing record; effective immediately; no token clawback (reward was for the act of granting, not for the access that may or may not follow). |
| Check Validity | `isConsentValid(address user, address requester) view returns (bool)` | Anyone (used internally by `DataSharingManager`) | Pure/view computation described in A.3. |

### B.3 Data Sharing component — `DataSharingManager.sol` + `AccessLogger.sol`

| Function | Signature | Caller | Description |
|---|---|---|---|
| Share Data (implicit) | — (handled by `registerUser` / `updateDocument` above, plus the off-chain gatekeeper) | User | The user keeps the actual files in a local data store (`offchain/data/<address>/id_front.json`, `id_back.json`), served by the gatekeeper; the contract only ever stores the link + hashes, never the file bytes. |
| Access Data | `requestAccess(address user) returns (bool granted, string memory link, bytes32 frontHash, bytes32 backHash)` | Whitelisted requester | Reverts for callers the admin hasn't whitelisted. Otherwise reads `ConsentManager.getConsent(user, msg.sender)` once and checks validity locally. If valid: calls `AccessLogger.logAccess(user, msg.sender, GRANTED, NONE)`, emits `AccessGranted`, and returns `granted = true` with the link and the hash(es) the scope allows. If not: logs `DENIED` with the reason, emits `AccessDenied`, and returns `granted = false` with no data. A denial deliberately does not revert, since a revert would also erase the DENIED log entry. |
| Update Log | `logAccess(address user, address requester, uint8 outcome, uint8 reason)` | Only `DataSharingManager` (`onlyDataSharingManager` modifier) | Appends a new immutable entry (one storage slot) to `logs[user]` and emits `AccessLogged(...)`. No delete/edit function exists anywhere in the contract. |
| Read Log | `getLogs(address user) view returns (LogEntry[] memory)`, `getLogCount(address user)` | Anyone | The log is public by design (see A.4): the user sees their own full access history, and so can auditors and requesters. |

### B.4 Token component — `AccessToken.sol`

- Standard ERC-20 (`ACT`).
- `mintReward(address user, uint256 amount)` is restricted to the `ConsentManager`
  contract address. `setMinter` works **once only** (it requires the minter to still
  be `address(0)`), and the deployment module calls it right after deploying, so no
  other account — including the admin — can ever mint arbitrary tokens, and anyone
  can check `minter()` against the ConsentManager address. `AccessLogger` uses the
  same one-time `setDataSharingManager`, so the admin can't later point the logger at
  their own wallet and forge entries.
- Why a one-time setter rather than a constructor argument: `ConsentManager` needs
  the token's address in its own constructor, so the token must be deployed first
  and can't know the minter yet (likewise `DataSharingManager` needs the logger).
  Constructor-only wiring would be possible by deploying the token *from inside*
  ConsentManager's constructor, or by precomputing addresses with CREATE/CREATE2
  (Lecture 4 §4.11); we chose the setter to keep five independently deployable and
  testable contracts with a simple deployment script.
- Tokens are a pure incentive signal: they are never checked by `DataSharingManager`
  when deciding access, and no function anywhere transfers ACT in exchange for
  *reading* data — only for *granting* consent. This keeps "tokens grant access only"
  literally true in the sense the brief intends (tokens are the reward mechanism
  layered on top of consent, not a payment-for-data-access mechanism, and they never
  represent or transfer ownership of the underlying ID images).

### B.5 Access Control Summary

| Action | Who is allowed |
|---|---|
| `registerUser` / `updateDocument` | The user themself, for their own record |
| `setRequesterStatus` | Admin only |
| `setConsent` / `revokeConsent` | The identity owner, for their own consents only |
| `requestAccess` | Any currently whitelisted requester (consent is still checked per user); anyone else reverts |
| `logAccess` | Only the `DataSharingManager` contract (no EOA can call it directly) |
| `getLogs` / `getLogCount` | Anyone (public by design, see A.4) |
| `mintReward` | Only the `ConsentManager` contract |
| `setMinter` / `setDataSharingManager` | Admin, **once** at deployment; reverts afterwards |
| `setRewardAmount` | Admin only (never affects access) |

### B.6 Architecture Diagram

![Architecture](diagrams/3-architecture.png)

Source: [`diagrams/3-architecture.mmd`](diagrams/3-architecture.mmd). Steps 0–8 are
on-chain; 9–11 are the off-chain gatekeeper, detailed below.

### B.7 Off-chain data access through the gatekeeper

Because all on-chain data is public, the document link alone can't protect the
files. The link therefore points at the **gatekeeper** (`offchain/gatekeeper.py`),
which holds the user's files and enforces consent itself. It releases files only if
the requester presents its own successful `requestAccess(user)` transaction that
emitted `AccessGranted(user, requester)`, signed with the key that sent it (tx
hashes are public, so the signature stops anyone else from replaying one), while the
requester is still whitelisted and the consent still valid, and only if the
transaction is recent (5 minutes) and hasn't been used before. It returns only the
files the consent scope allows; the requester re-hashes them against the on-chain
hashes. So every release corresponds to exactly one GRANTED log entry.

![Gatekeeper data-access flow](diagrams/4-gatekeeper-flow.png)

Source: [`diagrams/4-gatekeeper-flow.mmd`](diagrams/4-gatekeeper-flow.mmd).

This satisfies the core invariants from the brief: **data ownership never moves**
(only a link + hashes are ever on-chain, and the files stay in the user's data
store), **access is gated purely by consent** (`DataSharingManager` never checks token
balances), **every attempt is logged immutably** (`AccessLogger` is append-only), and
**users are incentivized** (ACT minted on a user's first consent grant to each requester) without incentives ever
becoming a way to buy access.

---

## Our Actual Deliverable for Step 2

- **Data model** — Section A.1/A.2: identity attributes list plus the required
  on-chain / off-chain / hashed table (wallet address, email hash, document link,
  front/back ID hashes on-chain; name, email, ID number, actual files off-chain in a
  local data store behind the gatekeeper).
- **Consent model** — Section A.3: data scopes (`FRONT_ONLY` / `BACK_ONLY` / `BOTH`),
  1–365 day duration, grant/revoke restricted to the identity owner only, automatic
  expiry with no cleanup transaction, a state diagram of the consent lifecycle
  (including re-granting after a revoke or expiry), and pseudocode for `setConsent` /
  `revokeConsent` / `isConsentValid`.
- **Audit log design** — Section A.4: what's recorded per attempt (user, requester,
  timestamp, outcome, denial reason), confirmation that logs are append-only with no
  delete/edit function, that the log is public by design, and pseudocode for the
  access-check-and-log flow.
- **Smart contract design** — Section B: five contracts (`DigitalIdentityRegistry`,
  `ConsentManager`, `DataSharingManager`, `AccessLogger`, `AccessToken`) with full
  function tables for the Digital Identity and Data Sharing components (Register
  User, Retrieve User Info, Set/Revoke Consent, Log Access, Share/Access Data, Update
  Log), the one-time wiring of minter and logger, and an access-control summary.
- **Architecture diagram** — Section B.6: a diagram showing the local data store and
  gatekeeper, all five contracts, and the numbered interaction sequence between User,
  Requester, and Administrator — the explicit deliverable the brief asks for — plus
  the gatekeeper's data-access flow (B.7).
