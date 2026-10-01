# References

One consistent style: numbered, IEEE-like. Cite in the text as [n]. Web
sources were accessed on 1 October 2026. Every entry below was checked to
exist; the team should still open each one before citing it for a specific
claim, and keep only the ones the report actually uses.

## Existing systems (Step 1 §1.2 comparison table)

| # | Reference | Supports |
|---|---|---|
| [1] | Epic Systems Corporation, "MyChart." [Online]. Available: https://www.mychart.org/ | Hospital-managed patient portals (row 1) |
| [2] | UnitedHealth Group / U.S. Dept. of Health and Human Services, "Change Healthcare Cybersecurity Incident: Frequently Asked Questions," HHS Office for Civil Rights. [Online]. Available: https://www.hhs.gov/hipaa/for-professionals/special-topics/change-healthcare-cybersecurity-incident-frequently-asked-questions/index.html | Centralised health data as a breach "honeypot": the Feb 2024 Change Healthcare attack, ~190 million people affected (row 1, problem statement) |
| [3] | European Parliament and Council, "Regulation (EU) No 910/2014 on electronic identification and trust services for electronic transactions in the internal market (eIDAS)," *Official Journal of the EU*, L 257, 2014. [Online]. Available: https://eur-lex.europa.eu/eli/reg/2014/910/oj | National eID schemes (row 2) |
| [4] | European Parliament and Council, "Regulation (EU) 2024/1183 amending Regulation (EU) No 910/2014 as regards establishing the European Digital Identity Framework," *Official Journal of the EU*, L series, 30 Apr. 2024. [Online]. Available: https://eur-lex.europa.eu/eli/reg/2024/1183/oj/eng | eIDAS 2 / EU Digital Identity Wallet, selective disclosure, zero-knowledge proofs (row 2, future work) |
| [5] | M. Nemec, M. Sys, P. Svenda, D. Klinec and V. Matyas, "The Return of Coppersmith's Attack: Practical Factorization of Widely Used RSA Moduli," in *Proc. ACM CCS*, 2017. [Online]. Available: https://crocs.fi.muni.cz/public/papers/rsa_ccs17 | ROCA: one flaw in a central eID card design (Estonia, 2017) affects every card at once (row 2) |
| [6] | Privacy International, "Access to the details of 1 billion entries of the Aadhaar database available for only 500 rupees" (on R. Khaira, *The Tribune*, 3 Jan. 2018). [Online]. Available: https://privacyinternational.org/examples-abuse/2288/access-deatils-1-billion-entries-aadhaar-database-available-only-500-rupees | Aadhaar: centralised verification authority as a single point of failure (row 2) |
| [7] | J. Cox, "ID Verification Service for TikTok, Uber, X Exposed Driver Licenses," *404 Media*, 26 Jun. 2024. [Online]. Available: https://www.404media.co/id-verification-service-for-tiktok-uber-x-exposed-driver-licenses-au10tix/ (summary: EFF, https://www.eff.org/deeplinks/2024/06/hack-age-verification-company-shows-privacy-danger-social-media-laws) | KYC vendors keep ID images and leak them (row 3) |
| [8] | Discord, statement on the third-party customer-service vendor incident (≈70,000 government-ID images exposed), Oct. 2025; reported in "Discord says third-party customer service system breached, 70K users' government IDs exposed." [Online]. Available: https://www.kiro7.com/news/trending/discord-says-third-party-customer-service-system-breached-70k-users-government-ids-exposed/I45TDHUZWBFUJLVKCEJU2YUT5E/ | KYC/ID-check copies held by third parties get breached (row 3) |
| [9] | W3C, "Decentralized Identifiers (DIDs) v1.0," W3C Recommendation, 19 Jul. 2022. [Online]. Available: https://www.w3.org/TR/did-core/ | Self-sovereign identity (row 4) |
| [10] | W3C, "Verifiable Credentials Data Model v2.0," W3C Recommendation, 15 May 2025. [Online]. Available: https://www.w3.org/TR/vc-data-model-2.0/ | Verifiable credentials, selective disclosure (row 4, future work) |

Row 5 of the table (paper photocopies at the front desk) describes common
practice; it needs no source if the report presents it as an observation, or
it can lean on [2] for the breach risk of copies kept by providers.

## Law and standards used in the Discussion

| # | Reference | Supports |
|---|---|---|
| [11] | European Parliament and Council, "Regulation (EU) 2016/679 (General Data Protection Regulation)," *Official Journal of the EU*, L 119, 2016, Art. 17 "Right to erasure." [Online]. Available: https://eur-lex.europa.eu/eli/reg/2016/679/oj | GDPR vs. an immutable log |
| [12] | G. Kadianakis, lightclient and A. Stokes, "EIP-4444: Bound Historical Data in Execution Clients," Ethereum Improvement Proposals. [Online]. Available: https://eips.ethereum.org/EIPS/eip-4444 ; and Ethereum Foundation, "Partial history expiry announcement," 8 Jul. 2025. [Online]. Available: https://blog.ethereum.org/2025/07/08/partial-history-exp | Why the log is also kept in contract storage, not only as events: nodes may stop serving old receipts/logs |
| [13] | V. Buterin and M. Swende, "EIP-2929: Gas cost increases for state access opcodes." [Online]. Available: https://eips.ethereum.org/EIPS/eip-2929 | Cold/warm SLOAD and SSTORE costs behind the gas numbers |
| [14] | F. Vogelsteller and V. Buterin, "EIP-20: Token Standard." [Online]. Available: https://eips.ethereum.org/EIPS/eip-20 | ACT token |
| [15] | M. Swende and N. Johnson, "EIP-191: Signed Data Standard." [Online]. Available: https://eips.ethereum.org/EIPS/eip-191 | The gatekeeper's signed request (`personal_sign` message) |
| [16] | S. Nakamoto, "Bitcoin: A Peer-to-Peer Electronic Cash System," 2008. [Online]. Available: https://bitcoin.org/bitcoin.pdf | Hash-linked, append-only history (immutability of the log) |

## Tools and libraries

| # | Reference |
|---|---|
| [17] | Solidity Team, "Solidity v0.8.28 documentation." [Online]. Available: https://docs.soliditylang.org/en/v0.8.28/ |
| [18] | OpenZeppelin, "OpenZeppelin Contracts 5.x" (Ownable, ERC20). [Online]. Available: https://docs.openzeppelin.com/contracts/5.x/ |
| [19] | Nomic Foundation, "Hardhat 3 documentation" (Solidity tests, gas statistics, Ignition). [Online]. Available: https://hardhat.org/docs |
| [20] | Foundry contributors, "forge-std" (Test, cheatcodes `vm.prank`, `vm.warp`, `vm.expectRevert`). [Online]. Available: https://github.com/foundry-rs/forge-std |
| [21] | Ethereum Foundation, "web3.py v8 documentation." [Online]. Available: https://web3py.readthedocs.io/ |
| [22] | wevm, "viem documentation." [Online]. Available: https://viem.sh/ |
| [23] | Mermaid contributors, "Mermaid: diagramming and charting tool." [Online]. Available: https://mermaid.js.org/ |

## Course material (Introduction to Blockchains, DACS, Maastricht University, 2026)

| # | Reference | Use it for |
|---|---|---|
| [L1] | C. Jin, "Lecture 1 – Foundations: Introduction and Cryptographic Primitives." | §4.2 hash properties (preimage resistance), §5.1 hash as commitment, §6 signatures |
| [L2] | C. Jin, "Lecture 2 – Bitcoin Mechanics: Transactions, Scripts & Key Management." | Keys and transaction signing |
| [L3] | C. Jin, "Lecture 3 – Consensus Protocols: Byzantine Agreement → Nakamoto Consensus → Proof-of-Stake." | Where immutability of the log comes from |
| [L4] | C. Jin, "Lecture 4 – Ethereum & Smart Contracts: The EVM, Solidity, and the Anatomy of an Exploit." | §3.2 gas/SSTORE costs, §4.4 modifiers, §4.5 require/revert (and custom errors), §4.8 event logs, §4.9 ERC-20, §4.10 calling other contracts, §4.11 CREATE/CREATE2 |
| [L5] | C. Jin, "Lecture 5 – Decentralized Finance (DeFi): Stablecoins, Lending, AMMs, and MEV." | §1.1 ERC-20 recap |
| [L6] | C. Jin, "Lecture 6 – Scaling the Blockchain: Payment Channels and Rollups." | §1.2 throughput limits, §3–4 rollups (future work) |
| [L7] | C. Jin, "Lecture 7 – Privacy on the Blockchain: De-anonymization, Mixing, and Zero-Knowledge Private Transactions." | §2.1 Ethereum is not private, §3.3 linking addresses to identities, §5.3 commitments, §5.4 zk-SNARKs |
| [T1] | "Tutorial 1: Ethereum Cryptography." | ECDSA keys and signatures (gatekeeper authentication) |
| [T3] | "Tutorial 3: Understanding Tokenization." | ERC-20 vs ERC-721/1155 for ACT |
| [Lab3] | "Lab 3: Understanding Smart Contracts." | Solidity unit tests with forge-std |
| [Lab4] | "Lab 4: Inter-Contract Communication." | Contracts calling each other |
| [Lab5] | A. Lohachab, "Campus Bounty Platform" (Lab 5 demo DApp). | viem + local Hardhat front-end setup |
