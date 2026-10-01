# Step 4 — Testing and Gas

## Required Deliverable (as specified in the project brief)

> Tables reporting all successfully performed tests and tables showing the deployment
> costs and cost for executing each function.

The brief also asks, for each tested functionality, why it is critical for the
platform, and to optimise contract logic where appropriate. Both are below.

> AI-assisted: the tests, the benchmark script and these tables were produced with
> Claude Code (Claude Opus 5.5) on 2026-09-30 / 2026-10-01. The team must review
> them and declare this in the report's AI statement.

## How to reproduce

```bash
cd digital-identity-platform
npx hardhat test                    # 80 Solidity tests
npx hardhat test --coverage         # + line coverage
npm run test:gas                    # + per-function gas over the whole test suite
npm run gas:bench                   # per-scenario gas from real transactions (tables below)
# Python gatekeeper tests (need `npx hardhat node` + `npm run deploy:local`):
python -m unittest discover -s offchain -v
```

## 1. Tests

### 1.1 Approach

- **Unit tests**, one file per contract, named after the contract it verifies
  (`DigitalIdentityRegistry.t.sol`, `ConsentManager.t.sol`, `AccessToken.t.sol`,
  `AccessLogger.t.sol`, `DataSharingManager.t.sol`), written in Solidity with forge-std
  as in Lab 3 and run by Hardhat 3.
- **Integration tests** in `DigitalIdentityPlatform.t.sol`: all five contracts deployed
  and wired exactly as the Ignition module does, driven through whole workflows.
- **Negative tests** for every rule: expected reverts (`vm.expectRevert`), denials that
  must *not* revert, and expiry by moving time (`vm.warp`). Two **fuzz tests** check
  expiry and the access decision for 256 random inputs each.
- **No personal data**: identities are `address(0x1001)`-style placeholders, links
  use the reserved `example.invalid` domain, and hashes are of strings such as
  `"test-user-1-front"`.
- **Gatekeeper tests** (Python, `offchain/test_gatekeeper.py`) run against the local
  chain and cover every reason the gatekeeper refuses to release files.

**Result:** 80 / 80 Solidity tests pass and 15 / 15 gatekeeper tests pass (run on
2026-10-01). Line and statement coverage is **100 %** for all five platform contracts
(`npx hardhat test --coverage`); the only uncovered file is the gas experiment
`contracts/experiments/EventsOnlyAccessLogger.sol`, which is exercised by the gas
benchmark instead. Not covered: behaviour on a public network (block reorgs, real
fees) and the HTTP gatekeeper under concurrent load.

### 1.2 Tested functionality and why it is critical (report-sized table)

| Functionality | Tests | Why it is critical for the platform |
|---|---|---|
| Registration stores only hashes + link; empty values rejected | Registry 2, 3, 4, 7–9 | The chain is public, so registration must never accept or store personal data, and a record with an empty hash couldn't be integrity-checked later |
| One identity per address and per email hash | Registry 5, 6 | Prevents duplicate or impersonating identities, the basis of every consent and log entry |
| Document updates by the owner only | Registry 10–13, Integration 76 | A renewed ID must replace the old hashes, and only the identity owner may change their own record |
| Admin-only whitelist of requesters | Registry 1, 14, 15 | Only vetted healthcare providers may receive consent or request access |
| Consent is scoped, time-limited (1–365 days) and per requester | Consent 16–19, 23, 24 | The brief's core requirement: users decide *who* sees *what* and *for how long* |
| Consent only for registered users and whitelisted requesters | Consent 20–22 | Stops consent to typo'd, malicious or removed addresses |
| Expiry happens by itself at `expiresAt` | Consent 25–27, Integration 75 | Access must stop on time without anyone sending a cleanup transaction |
| Only the owner can revoke, once, with immediate effect | Consent 28–33 | Revocation is the user's main control; nobody (requester or admin) may revoke or keep consent on the user's behalf |
| ACT reward once per (user, requester), owner-only rate | Consent 34–39 | Incentivises sharing without letting users farm tokens by re-granting |
| Only ConsentManager can mint; wiring is one-time | Token 40–48, Integration 79 | Otherwise the admin could mint unlimited ACT; one-time wiring makes that impossible after deployment |
| Only DataSharingManager can write the log; wiring is one-time | Logger 49–53, Integration 79 | Otherwise anyone, or the admin, could forge log entries |
| The log is append-only, ordered, per user, and public | Logger 54–59 | An audit trail is only trustworthy if entries can't change or disappear; reading it is public by design (A3) |
| Granted access returns exactly what the scope allows, and is logged | DSM 60–64 | Scope must be enforced and every successful access must leave a trace |
| Each denial (NO_CONSENT, REVOKED, EXPIRED) is logged without reverting | DSM 65–69, Integration 74, 75 | A revert would erase the DENIED entry; failed attempts must be visible to the user |
| Tokens never grant access | DSM 70 | The brief: access comes from consent only; tokens are an incentive |
| Non-whitelisted callers revert; removed requesters lose access | DSM 72, 73, Integration 78 | Stops log spam by strangers and cuts off a provider the admin no longer trusts |
| Full workflows across all contracts | Integration 74–80 | Shows the contracts work together the way the design says, including isolation between users |
| Gatekeeper releases files only for a fresh, signed GRANTED transaction | Python G1–G15 | The on-chain link is public, so the gatekeeper is what actually protects the files |

Numbers refer to the full table below.

### 1.3 All tests

All results: ✅ passed (`npx hardhat test`, 2026-10-01).

| # | Test | Contract | What it checks | Why it's critical for the platform | Result |
|---:|---|---|---|---|:---:|
| 1 | `test_DeployerIsAdmin` | Registry | The deployer owns the registry | The admin role exists and belongs to the deployer | ✅ |
| 2 | `test_RegisterStoresReferenceData` | Registry | `registerUser` stores the email hash, link and both image hashes; `getUserRecord` returns them | Requesters verify files against exactly these values | ✅ |
| 3 | `test_RegisterEmitsEvent` | Registry | `UserRegistered` is emitted with the right fields | Off-chain tools discover users from events | ✅ |
| 4 | `test_UnregisteredUserHasEmptyRecord` | Registry | Unknown addresses read as unregistered and empty | No phantom identities | ✅ |
| 5 | `test_CannotRegisterTwice` | Registry | A second registration from the same address reverts | One identity per address | ✅ |
| 6 | `test_EmailHashCanOnlyBeUsedOnce` | Registry | Another address can't reuse an email hash | Blocks duplicate identities | ✅ |
| 7 | `test_RejectsEmptyEmailHash` | Registry | A zero email hash reverts | The uniqueness check (and the registered flag) depend on it | ✅ |
| 8 | `test_RejectsEmptyLink` | Registry | An empty link reverts | A record without a link can't be served | ✅ |
| 9 | `test_RejectsEmptyImageHashes` | Registry | Zero front or back hash reverts | Without hashes the files can't be integrity-checked | ✅ |
| 10 | `test_UpdateDocumentReplacesLinkAndHashes` | Registry | `updateDocument` replaces link and hashes, keeps the email hash | Renewed IDs stay verifiable without re-registering | ✅ |
| 11 | `test_UpdateDocumentEmitsEvent` | Registry | `DocumentUpdated` is emitted | Changes to a record are visible | ✅ |
| 12 | `test_UpdateDocumentRequiresRegistration` | Registry | Unregistered callers can't update | Only owners change their own records | ✅ |
| 13 | `test_UpdateDocumentRejectsEmptyValues` | Registry | Empty link or hash reverts on update | Same integrity rules as registration | ✅ |
| 14 | `test_AdminWhitelistsAndRemovesRequester` | Registry | The admin can approve and remove a requester; event emitted | The whitelist is the admin's only lever | ✅ |
| 15 | `test_OnlyAdminCanWhitelist` | Registry | Non-owners can't whitelist | Nobody can approve themselves as a provider | ✅ |
| 16 | `test_SetConsentStoresScopedTimeLimitedRecord` | ConsentManager | Scope, grant time and expiry are stored; consent is valid | The consent record drives every access decision | ✅ |
| 17 | `test_SetConsentEmitsEvent` | ConsentManager | `ConsentGranted` has the right scope and expiry | Grants are auditable off-chain | ✅ |
| 18 | `test_ConsentIsPerRequester` | ConsentManager | Consent to one requester doesn't cover another | Consent is specific to who receives it | ✅ |
| 19 | `test_RegrantUpdatesScopeAndExpiry` | ConsentManager | Granting again replaces scope and expiry | Users can change the terms | ✅ |
| 20 | `test_RejectsUnregisteredUser` | ConsentManager | Unregistered callers can't grant | Only identity owners grant consent | ✅ |
| 21 | `test_RejectsNonWhitelistedRequester` | ConsentManager | Consent to a non-whitelisted address reverts | No consent to unknown parties | ✅ |
| 22 | `test_RejectsRequesterRemovedFromWhitelist` | ConsentManager | Consent to a removed requester reverts | Removal takes effect for new grants | ✅ |
| 23 | `test_AcceptsDurationBounds` | ConsentManager | 1 and 365 days work | The brief's 1–365-day range is honoured | ✅ |
| 24 | `test_RejectsDurationOutOfRange` | ConsentManager | 0 and 366 days revert | Same | ✅ |
| 25 | `test_ConsentValidUntilExpiryInclusive` | ConsentManager | Valid exactly at `expiresAt`, invalid 1 s later | Off-by-one errors here would grant or deny wrongly | ✅ |
| 26 | `testFuzz_ExpiryMatchesDuration` | ConsentManager | For any 1–365 days, expiry = grant time + days and lapses after it (256 runs) | Expiry is right for every allowed duration | ✅ |
| 27 | `test_ExpiredConsentCanBeRenewed` | ConsentManager | An expired consent can be granted again | Users can restore access | ✅ |
| 28 | `test_UserCanRevoke` | ConsentManager | Revoking marks the consent revoked and invalid | Revocation is immediate | ✅ |
| 29 | `test_RevokeEmitsEvent` | ConsentManager | `ConsentRevoked` is emitted | Revocations are auditable | ✅ |
| 30 | `test_CannotRevokeMissingConsent` | ConsentManager | Revoking non-existent consent reverts | No meaningless state changes | ✅ |
| 31 | `test_CannotRevokeTwice` | ConsentManager | A second revoke reverts | Same | ✅ |
| 32 | `test_NobodyElseCanRevokeUsersConsent` | ConsentManager | Neither the requester nor the admin can revoke a user's consent | Only the owner controls their consent | ✅ |
| 33 | `test_RegrantAfterRevokeRestoresConsent` | ConsentManager | Granting after a revoke makes consent valid again | Users can change their mind | ✅ |
| 34 | `test_FirstGrantMintsReward` | ConsentManager | The first grant mints 10 ACT | The incentive works | ✅ |
| 35 | `test_RegrantDoesNotMintAgain` | ConsentManager | Re-granting mints nothing | Prevents reward farming | ✅ |
| 36 | `test_RevokeThenRegrantDoesNotMintAgain` | ConsentManager | 5 revoke/re-grant loops still give 10 ACT total | Prevents reward farming | ✅ |
| 37 | `test_EachNewRequesterIsRewardedOnce` | ConsentManager | Two requesters, two rewards | Rewards count real sharing relationships | ✅ |
| 38 | `test_RewardAmountChangeAppliesToLaterGrants` | ConsentManager | A new reward rate applies to later grants | The admin's only economic lever works | ✅ |
| 39 | `test_OnlyAdminCanSetRewardAmount` | ConsentManager | Non-owners can't change the rate | Nobody else can inflate rewards | ✅ |
| 40 | `test_Metadata` | AccessToken | Name, symbol, decimals, zero initial supply, owner | Standard ERC-20 behaviour | ✅ |
| 41 | `test_NoMinterByDefault` | AccessToken | A fresh token has no minter and nobody can mint | No minting before wiring | ✅ |
| 42 | `test_MinterCanMintReward` | AccessToken | The minter can mint | ConsentManager can pay rewards | ✅ |
| 43 | `test_StrangerCannotMint` | AccessToken | Others can't mint | No free tokens | ✅ |
| 44 | `test_AdminCannotMintDirectly` | AccessToken | The admin can't mint | The admin has no economic backdoor | ✅ |
| 45 | `test_SetMinterEmitsEvent` | AccessToken | Wiring a fresh token emits `MinterUpdated` | The wiring is publicly visible | ✅ |
| 46 | `test_MinterCanOnlyBeSetOnce` | AccessToken | A second `setMinter` reverts; the original minter still works | The admin can't redirect minting to themselves (A1) | ✅ |
| 47 | `test_OnlyAdminCanSetMinter` | AccessToken | Non-owners can't wire the token | Same | ✅ |
| 48 | `test_RejectsZeroMinter` | AccessToken | The zero address is rejected | Wiring can't be "used up" by mistake | ✅ |
| 49 | `test_SetDataSharingManager` | AccessLogger | Wiring a fresh logger emits `DataSharingManagerUpdated` | The wiring is publicly visible | ✅ |
| 50 | `test_OnlyAdminCanSetDataSharingManager` | AccessLogger | Non-owners can't wire the logger | Nobody else can become the log writer | ✅ |
| 51 | `test_RejectsZeroManager` | AccessLogger | The zero address is rejected | Wiring can't be "used up" by mistake | ✅ |
| 52 | `test_OnlyDataSharingManagerCanLog` | AccessLogger | Strangers, users and the admin can't write entries | No forged log entries | ✅ |
| 53 | `test_ManagerCanOnlyBeSetOnce` | AccessLogger | A second `setDataSharingManager` reverts | The admin can't point the logger at themselves (A1) | ✅ |
| 54 | `test_LogAppendsEntry` | AccessLogger | An entry stores requester, time, outcome, reason | The log answers who / when / granted or denied | ✅ |
| 55 | `test_LogEmitsEvent` | AccessLogger | `AccessLogged` is emitted with all fields | Independent off-chain verification | ✅ |
| 56 | `test_EntriesAreKeptInOrder` | AccessLogger | Three entries keep their order and timestamps | The history reads correctly | ✅ |
| 57 | `test_OldEntriesNeverChange` | AccessLogger | Later entries leave the first entry untouched | Append-only: logs can't be altered | ✅ |
| 58 | `test_LogsArePerUser` | AccessLogger | Each user has their own log | Attempts are attributed to the right person | ✅ |
| 59 | `test_AnyoneCanReadLogs` | AccessLogger | User, requester, stranger and admin can all read | The log is transparent by design; a caller check wouldn't be privacy (A3) | ✅ |
| 60 | `test_BothScopeReleasesLinkAndBothHashes` | DataSharingManager | BOTH returns the link and both hashes | Granted access delivers what was consented | ✅ |
| 61 | `test_FrontOnlyScopeWithholdsBackHash` | DataSharingManager | FRONT_ONLY returns an empty back hash | Scope is enforced | ✅ |
| 62 | `test_BackOnlyScopeWithholdsFrontHash` | DataSharingManager | BACK_ONLY returns an empty front hash | Scope is enforced | ✅ |
| 63 | `test_GrantedAccessIsLogged` | DataSharingManager | A granted request adds a GRANTED entry | Every access leaves a trace | ✅ |
| 64 | `test_GrantedAccessEmitsEvents` | DataSharingManager | `AccessLogged` and `AccessGranted` are emitted | The gatekeeper relies on `AccessGranted` | ✅ |
| 65 | `test_NoConsentIsDeniedAndLogged` | DataSharingManager | No consent: `granted = false`, nothing released, DENIED: NO_CONSENT logged | Failed attempts are visible, not hidden by a revert | ✅ |
| 66 | `test_RevokedConsentIsDenied` | DataSharingManager | After revoke: DENIED: REVOKED | Revocation really stops access | ✅ |
| 67 | `test_ExpiredConsentIsDenied` | DataSharingManager | After expiry: DENIED: EXPIRED | Expiry really stops access | ✅ |
| 68 | `test_DeniedAccessEmitsEvents` | DataSharingManager | `AccessLogged` and `AccessDenied` are emitted with the reason | Denials are auditable | ✅ |
| 69 | `test_ConsentForOneRequesterDoesNotCoverAnother` | DataSharingManager | Another whitelisted requester is denied | Consent is per requester | ✅ |
| 70 | `test_TokenBalanceDoesNotGrantAccess` | DataSharingManager | A requester holding ACT but no consent is denied | Tokens never buy access | ✅ |
| 71 | `test_EveryAttemptIsLogged` | DataSharingManager | Denied, granted and denied attempts give 3 entries | Complete audit trail | ✅ |
| 72 | `test_NonWhitelistedCallerReverts` | DataSharingManager | A stranger's request reverts and leaves no entry | Strangers can't spam a user's log (A2) | ✅ |
| 73 | `test_DewhitelistedRequesterLosesAccess` | DataSharingManager | After removal the requester reverts despite valid consent; re-approval restores access | The admin can cut off an untrusted provider (A2) | ✅ |
| 74 | `test_FullLifecycle` | Integration | register → whitelist → grant (+10 ACT) → GRANTED → revoke → DENIED: REVOKED; log has 2 entries in order | The brief's core workflow works end to end | ✅ |
| 75 | `test_ConsentExpiresAndCanBeRenewed` | Integration | 1-day consent → GRANTED → after 1 day + 1 s DENIED: EXPIRED → renew → GRANTED, no extra reward | Expiry and renewal across contracts | ✅ |
| 76 | `test_DocumentUpdateReachesConsentedRequester` | Integration | After `updateDocument` a consented requester gets the new link and hashes | Renewed IDs reach providers | ✅ |
| 77 | `test_MultipleUsersAndRequestersAreIsolated` | Integration | Two users, two requesters: A's consent never gives access to B's data; logs and rewards stay separate | No cross-user leakage | ✅ |
| 78 | `test_UnapprovedRequesterIsBlocked` | Integration | A never-approved address can't receive consent, and its request reverts | Unknown parties are kept out entirely | ✅ |
| 79 | `test_AdminCannotBypassUserControl` | Integration | The admin can't request access unless whitelisted, gets DENIED even then, can't revoke, log, mint or re-wire | The admin stays out of the data path | ✅ |
| 80 | `testFuzz_AccessDecisionMatchesConsentValidity` | Integration | For random durations, elapsed times and revoke choices, `requestAccess` agrees with `isConsentValid` (256 runs) | `requestAccess` now checks validity itself (A4); this proves it can't drift from ConsentManager | ✅ |

### 1.4 Gatekeeper tests (Python)

`python -m unittest discover -s offchain -v` against the local chain; all ✅.

| # | Test | What it checks | Why it's critical |
|---:|---|---|---|
| G1 | `test_granted_request_returns_files_matching_on_chain_hashes` | Over HTTP via the on-chain link: both files released, hashes match | The whole data path works |
| G2 | `test_front_only_scope_releases_only_the_front` | FRONT_ONLY → only `id_front.json` | Scope is enforced on the actual data |
| G3 | `test_back_only_scope_releases_only_the_back` | BACK_ONLY → only `id_back.json` | Same |
| G4 | `test_tampered_file_fails_the_requesters_hash_check` | A modified file fails the requester's re-hash | Integrity doesn't depend on trusting the gatekeeper |
| G5 | `test_unknown_transaction_is_refused` | Made-up tx hash → `no_transaction` | No log, no data |
| G6 | `test_signature_from_someone_else_is_refused` | Someone copies a public tx hash → `wrong_sender` | Tx hashes are public; only the requester can use its own |
| G7 | `test_transaction_for_another_user_is_refused` | A GRANTED tx for user A can't fetch user B → `access_not_granted` | No cross-user leakage |
| G8 | `test_denied_transaction_is_refused` | A DENIED tx → `access_not_granted` | Only granted attempts release data |
| G9 | `test_transaction_to_another_contract_is_refused` | A `setConsent` tx → `not_an_access_request` | Only real access requests count |
| G10 | `test_revoked_consent_is_refused` | Old GRANTED tx after revoke → `consent_not_valid` | Revocation also stops off-chain release |
| G11 | `test_expired_consent_is_refused` | Old GRANTED tx after expiry → `consent_not_valid` | Expiry also stops off-chain release |
| G12 | `test_stale_transaction_is_refused` | GRANTED tx older than 5 min → `stale_transaction` | An old approval can't be saved up and used later |
| G13 | `test_dewhitelisted_requester_is_refused` | Removed requester → `requester_not_whitelisted` | Removal also stops off-chain release |
| G14 | `test_each_transaction_releases_files_only_once` | Second use of the same tx → `already_used` | Every release matches exactly one GRANTED log entry |
| G15 | `test_refusal_over_http_is_a_403_with_the_reason` | The HTTP API returns 403 + reason | Requesters learn why they were refused |

## 2. Gas

### 2.1 Method

- **Per-scenario costs** come from `npm run gas:bench` (`scripts/gas-benchmark.ts`):
  it deploys the five contracts on Hardhat's in-process network, then sends each
  scenario as a real transaction for 5 different users and records the receipt's
  `gasUsed`. This includes the 21,000 base cost and calldata, i.e. what a user pays,
  and it separates cases the test-suite statistics mix together (granted vs denied,
  first grant vs re-grant). The numbers are deterministic: re-running gives identical
  results. Raw data: `docs/gas/bench-*.json`.
- `npm run test:gas` reports per-function statistics over the whole test suite
  (`docs/gas/gas-before.json`, `gas-after.json`). Those calls come from the test
  contract, so they exclude the 21,000 base cost and mix scenarios; they are kept as
  supporting data, not used in the tables.
- "Before" is the code after the security fixes A1–A3 (one-time wiring, whitelist
  check, public log) and before any optimisation. "After" is the final code.

### 2.2 Deployment cost

| Contract | Deployment gas (before) | Deployment gas (after) | Change | Bytecode (before → after, bytes) |
|---|---:|---:|---:|---:|
| `AccessToken` | 696,804 | 696,804 | +0.0% | 2,615 → 2,615 |
| `DigitalIdentityRegistry` | 772,744 | 759,768 | −1.7% | 3,208 → 3,148 |
| `ConsentManager` | 702,661 | 729,611 | +3.8% | 2,772 → 2,897 |
| `AccessLogger` | 634,505 | 514,920 | −18.8% | 2,569 → 2,016 |
| `DataSharingManager` | 613,162 | 507,916 | −17.2% | 2,582 → 2,093 |
| **Total (5 contracts)** | **3,419,876** | **3,209,019** | **−6.2%** | |

Wiring after deployment costs `setMinter` 47,464 + `setDataSharingManager` 47,408 gas
(unchanged). ConsentManager grows slightly because reading and writing a packed slot
needs extra masking code; that one-off cost is repaid after the first grant.

### 2.3 Gas per function, before and after optimisation

Min / avg / max over 5 users (setRequesterStatus: 3 approvals).

| Function (scenario) | Before min / avg / max | After min / avg / max | Avg change | What changed |
|---|---:|---:|---:|---|
| `registerUser` | 228,236 / 228,236 / 228,236 | 205,958 / 205,958 / 205,958 | −22,278 (−9.8%) | No separate `registered` flag: one storage slot fewer (step 5) |
| `setRequesterStatus` (approve) | 47,775 / 47,779 / 47,787 | 47,775 / 47,779 / 47,787 | 0 | Not changed |
| `setRequesterStatus` (remove) | 25,863 / 25,863 / 25,863 | 25,863 / 25,863 / 25,863 | 0 | Not changed |
| `setConsent` (first grant, mints ACT) | 159,250 / 162,670 / 176,350 | 93,261 / 96,681 / 110,361 | −65,989 (−40.6%) | Consent record packed into 1 slot instead of 4 (step 4) |
| `setConsent` (re-grant, no mint) | 48,354 / 48,354 / 48,354 | 39,265 / 39,265 / 39,265 | −9,089 (−18.8%) | 1 slot rewritten instead of 3 (step 4) |
| `revokeConsent` | 28,811 / 28,811 / 28,811 | 28,825 / 28,825 / 28,825 | +14 | Masking the packed flag; negligible |
| `requestAccess` (granted, user's 1st log entry) | 163,012 | 106,330 | −56,682 (−34.8%) | All of steps 1–5 |
| `requestAccess` (granted, later entry) | 145,912 | 89,230 | −56,682 (−38.8%) | All of steps 1–5 |
| `requestAccess` (denied: NO_CONSENT) | 127,828 | 72,282 | −55,546 (−43.5%) | Steps 1–4 |
| `requestAccess` (denied: REVOKED) | 127,968 | 72,302 | −55,666 (−43.5%) | Steps 1–4 |
| `requestAccess` (denied: EXPIRED) | 128,112 | 72,327 | −55,785 (−43.5%) | Steps 1–4 |
| `updateDocument` | 48,741 / 48,751 / 48,753 | 48,729 / 48,739 / 48,741 | −12 | Not targeted; a by-product of the step 5 code change |

`requestAccess` had min = avg = max within each scenario, so only one value is shown.
The max of `setConsent` (first grant) is the very first grant on the platform, which
also turns ACT's `totalSupply` from zero to non-zero.

### 2.4 Optimisation steps (TASKS A4), one at a time

Each change was made alone, the tests re-run (80/80 each time), and the benchmark
re-measured. Average gas per scenario after each step:

| Function (scenario) | Before | 1 enum | 2 one read | 3 packed log | 4 packed consent | 5 = After | Events-only (experiment) |
|---|---:|---:|---:|---:|---:|---:|---:|
| `registerUser` | 228,236 | 228,236 | 228,236 | 228,236 | 228,236 | 205,958 | 205,958 |
| `setConsent` (first grant) | 162,670 | 162,670 | 162,670 | 162,670 | 96,687 | 96,681 | 96,681 |
| `setConsent` (re-grant) | 48,354 | 48,354 | 48,354 | 48,354 | 39,271 | 39,265 | 39,265 |
| `revokeConsent` | 28,811 | 28,811 | 28,811 | 28,811 | 28,825 | 28,825 | 28,825 |
| `requestAccess` (granted, 1st entry) | 163,012 | 160,109 | 158,794 | 114,733 | 108,457 | 106,330 | 61,066 |
| `requestAccess` (granted, later entry) | 145,912 | 143,009 | 141,694 | 97,633 | 91,357 | 89,230 | 61,066 |
| `requestAccess` (denied: NO_CONSENT) | 127,828 | 123,846 | 122,619 | 78,558 | 72,282 | 72,282 | 44,118 |
| `requestAccess` (denied: REVOKED) | 127,968 | 123,986 | 122,639 | 78,578 | 72,302 | 72,302 | 44,138 |
| `requestAccess` (denied: EXPIRED) | 128,112 | 124,130 | 122,664 | 78,603 | 72,327 | 72,327 | 44,163 |

| Step | Change | Kept? | One-line reason |
|---|---|:---:|---|
| 1 | Denial reason as a one-byte `enum` instead of a `string` (AccessLogger, DataSharingManager) | ✅ | No string to copy, store or emit: −2.9k to −4.0k per access, −129k deployment of AccessLogger |
| 2 | `requestAccess` reads `getConsent` once and checks validity locally, instead of `isConsentValid` then `getConsent` | ✅ | One external call fewer: −1.3k per access, −60k deployment of DataSharingManager; fuzz test 80 guards against drift from `isConsentValid` |
| 3 | `LogEntry` packed into one slot (`address` 20 B + `uint64` timestamp 8 B + 2 enums) | ✅ | Each entry was 3 new slots (≈ 20,000 + 2,100 gas each, Lecture 4 §3.2), now 1: −44k per access |
| 4 | `Consent` packed into one slot (`uint64` grantedAt/expiresAt + scope + 2 bools) | ✅ | First grant writes 1 new slot instead of 4 (−66k), and every access reads 1 slot instead of 4 (−6.3k) |
| 5 | `registered` derived from `emailHash != 0` instead of stored | ✅ | One new slot fewer per registration (−22k) and one cold read fewer per granted access (−2.1k) |
| — | Events-only log (`contracts/experiments/EventsOnlyAccessLogger.sol`) | ❌ (experiment) | A further −28k per access (−45k for a user's first entry), but nothing on-chain could read the log back; see 2.5 |

Biggest single win: packing (steps 3 and 4). Storage writes dominate, exactly as the
SSTORE costs in Lecture 4 §3.2 predict; after optimisation a denied access costs
about 72k gas, of which the one new log slot (≈ 22k) plus the array length update
is the largest part.

### 2.5 Storage + event vs events only (the trade-off)

Logging with **events only** would make `requestAccess` cost 61k (granted) and 44k
(denied) instead of 89–106k and 72k, and AccessLogger's deployment 334k instead of
515k, because an event is far cheaper than an SSTORE (Lecture 4 §4.8). Events are
just as permanent and can't be deleted. We **kept the storage array plus the event**
because:

- contracts can't read past events (Lecture 4 §4.8), so `getLogs` / `getLogCount`
  would disappear and every reader (user, auditor, front-end) would have to rebuild
  the log from `eth_getLogs` filtered on the indexed `user`;
- Ethereum nodes are dropping old history under EIP-4444 (partial history expiry
  since July 2025), so a log that exists only as events depends on archive nodes or
  indexers staying available, while contract storage is always served;
- the gatekeeper already relies on events (it checks `AccessGranted` in the
  requester's receipt), so the off-chain path keeps working either way.

If cost per access mattered more than on-chain readability (e.g. very frequent
access), switching to events-only is a one-contract change: the experiment contract
has the same interface, and the benchmark shows the saving.

Not tried, possible next steps: custom errors instead of `require` strings (smaller
bytecode and cheaper reverts, Lecture 4 §4.5), and making the whitelist check part of
`getConsent` to save one more external call.
