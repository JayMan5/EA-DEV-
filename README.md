# EA-DEV-

Tradie — a single-operator, rules-enforced forex trading system (OANDA).

## Documentation

| Document | Purpose |
|---|---|
| [`docs/Tradie PRD v2.md`](docs/Tradie%20PRD%20v2.md) | **PRD of record** — proposed rewrite: decision gates G0–G5, cost model, crash safety, validation statistics |
| [`docs/rule-spec.md`](docs/rule-spec.md) | **G1 deliverable** — the actual 9 checklist rules, specified as a staged setup state machine, with parameters and fixtures |
| [`docs/decisions.md`](docs/decisions.md) | **For redline** — proposed answers to all 15 G1 decisions, with reasoning, sensitivity analysis and a trade-frequency estimate |
| [`docs/source/Trading_Checklist.pdf`](docs/source/Trading_Checklist.pdf) | **Rule authority** — the operator's original checklist (01C) |
| [`docs/PRD-REVIEW.md`](docs/PRD-REVIEW.md) | Review of v1: limitations, tradeoffs, feasibility, and the rationale for every v2 change |
| [`docs/Tradie PRD.md`](docs/Tradie%20PRD.md) | v1.0.0-draft (retained for reference) |
| [`docs/Tradie PRD_APPENDIX.md`](docs/Tradie%20PRD_APPENDIX.md) | v1 technical appendix (retained for reference) |

## Status

Pre-implementation. Blocked on two gates:

- **G0 — broker/API capability.** OANDA's v20 REST API is documented as unavailable on OANDA Global Markets, the entity serving Nigerian residents. Must be verified before any live-path code. Failure ⇒ the project proceeds as backtest-only (a valid outcome).
- **G1 — rule specification.** The checklist is received and specified. **15 decisions (D-01…D-15)** have proposed answers in `decisions.md` but none are ratified. G1 is independent of G0 and can be advanced now.

No trading code exists yet. Nothing in this repository is financial advice, and no strategy described here has demonstrated an edge.
