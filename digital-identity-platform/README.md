# Decentralized Digital Identity & Government-ID Sharing Platform

**Domain:** Healthcare — patient identity verification via government-issued ID (front/back)

This folder is a self-contained project workspace and does **not** depend on or modify
anything else in this repository. It currently covers **Step 1 (Research & Planning)**
and **Step 2 (Platform/System Design)** of the project brief. Implementation (Solidity
contracts, tests, deployment) will follow in later steps.

## Concept in one line

A patient uploads the front and back photos of their government ID to an off-chain
storage location (e.g. `https://storage.example.com/docs/george`). The platform never
puts the images or personal data on-chain — instead it stores the **link** plus a
**cryptographic hash of each image** on-chain, e.g.:

```
link:  storage.example.com/george
front: 3f9a1c2e...   (SHA-256 of front-of-ID image)
back:  d2b7e4a1...   (SHA-256 of back-of-ID image)
```

A healthcare provider (doctor, hospital admissions desk, lab, insurer) who needs to
verify "is this really George's ID, and did George approve me seeing it?" can only
retrieve the link if George has granted that provider **time-limited, revocable
consent**. Every access attempt — successful or denied — is written to an immutable
on-chain audit log, and George earns platform **Access Tokens (ACT)** each time he
grants consent, as an incentive for participating (tokens grant *access*, never
ownership — the ID images always remain George's).

## Contents

| Document | Covers |
|---|---|
| [`docs/01-research-and-planning.md`](docs/01-research-and-planning.md) | Problem statement, prior-art research, user roles, functional requirements, high-level interaction overview |
| [`docs/02-system-design.md`](docs/02-system-design.md) | Data model, consent model, audit log design, smart-contract design, architecture diagram |

## Worked example used throughout the docs

| Field | Example value |
|---|---|
| User | George Papadopoulos |
| Wallet address | `0xGeorge...` |
| Off-chain document link | `link.com/george` |
| Front-of-ID hash (SHA-256) | `3huifh4gyvbgugy3g3gyg3...` |
| Back-of-ID hash (SHA-256) | `d2hufhyfgu3gbfu3guy3guygyuf...` |
| Requester | Dr. Elena Kostas, Athens General Hospital |
| Consent duration | 30 days |
