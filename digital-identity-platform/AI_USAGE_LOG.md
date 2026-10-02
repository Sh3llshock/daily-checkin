# AI Usage Log

Record of where generative AI (Claude, Anthropic) was used. It feeds the report's contribution and transparency statement (coursebook: "Describe where and how AI was used").

| Date | File(s) | What the AI did | Reviewed by |
|---|---|---|---|
| 2026-09-30 | `CODING_GUIDE.md` | Summarised the course materials (coursebook, tutorials, labs) into an internal coding reference: toolchain, conventions, test and deploy patterns | _(team member)_ |
| 2026-09-30 | `PLAN.md` | Reviewed the earlier cloud version against the course material and drafted the 7-step plan | _(team member)_ |
| 2026-09-30 | `platform/contracts/*`, `platform/ignition/`, `platform/scripts/demo.ts` | Wrote the 4 contracts, deployment module and demo script following the course lab patterns | _(team member)_ |
| 2026-09-30 | `platform/offchain/*` | Wrote the Python hashing tool, vault and end-to-end demo | _(team member)_ |
| 2026-09-30 | `deliverables/` | Drafted the Step 1-3 deliverable texts and the PDF build script; checked references (MedRec, Ancile, Change Healthcare breach) | _(team member)_ |
| 2026-09-30 | `platform/test/*.t.sol`, `scripts/gas-report.ts`, contract optimisation | Wrote the 64 Solidity tests, gas measurement script and the storage-packing optimisation | _(team member)_ |
| 2026-09-30 | `scripts/simulate.ts`, `scripts/plot_results.py` | Wrote the multi-user simulation and plot | _(team member)_ |
| 2026-09-30 | `platform/frontend/*`, `scripts/export-frontend.mjs` | Wrote the viem front-end and tested it in the browser | _(team member)_ |
| 2026-09-30 | `deliverables/src/step4-7.md`, `report.md`, `slides.html` | Drafted steps 4-7 deliverables, the final report and the presentation | _(team member)_ |
| 2026-10-02 | `offchain/test_vault.py`, `offchain/vault.py` | Reviewed the tests against the brief; added 11 Python tests for the vault (release per scope with matching hashes; refusal of reused, foreign-signed, denied, foreign-patient, wrong-contract, unknown, revoked and stale requests); made the vault refuse an unknown tx hash instead of crashing | _(team member)_ |
