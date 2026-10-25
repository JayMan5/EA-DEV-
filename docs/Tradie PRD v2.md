# Tradie — Product Requirements Document

> **Version:** 2.0.0-proposed
> **Date:** 2026-10-25
> **Author:** Proposed rewrite (supersedes v1.0.0-draft by Va_d3R)
> **Classification:** CONFIDENTIAL — Internal Use Only
> **Status:** Proposed — pending owner sign-off on the open items in Appendix H
> **Companion docs:** `rule-spec.md` (the G1 deliverable — the actual 9 rules, specified), `source/Trading_Checklist.pdf` (rule authority), `PRD-REVIEW.md` (rationale for every change), `Tradie PRD.md` + `Tradie PRD_APPENDIX.md` (v1, retained for reference)

---

## Table of Contents

1. [What changed and why](#1-what-changed-and-why)
2. [Executive summary](#2-executive-summary)
3. [Decision gates — the spine of this project](#3-decision-gates--the-spine-of-this-project)
4. [Vision, scope, non-goals](#4-vision-scope-non-goals)
5. [Operator model](#5-operator-model)
6. [Architecture invariants](#6-architecture-invariants)
7. [Functional requirements](#7-functional-requirements)
8. [Data model & configuration](#8-data-model--configuration)
9. [Non-functional requirements](#9-non-functional-requirements)
10. [Validation & statistics specification](#10-validation--statistics-specification)
11. [Milestones and exit criteria](#11-milestones-and-exit-criteria)
12. [Risk register](#12-risk-register)
13. [Deferred and explicitly-not-now](#13-deferred-and-explicitly-not-now)
14. [Appendices](#appendix-a--rule-specification-contract)

---

## 1. What changed and why

v1.0 was a strong *engineering* document with three unaddressed problems: the strategy itself was never defined, the validation gates could not detect what they claimed to, and every money-losing failure mode (crash, duplicate order, orphan position, no kill switch) was absent. This version keeps v1's good decisions and restructures the project around **gates you must pass before spending or risking anything**.

| # | Change | Why |
|---|---|---|
| 1 | **Added G0–G5 decision gates** (§3). No milestone starts until the prior gate passes | Converts a 10-feature monolith into an evidence-driven sequence |
| 2 | **Broker/API access is now Gate 0, not an assumption** | OANDA's v20 REST API is documented as unavailable on OANDA Global Markets — the entity that serves Nigerian residents. Nothing else is worth building until this is answered |
| 3 | **The 9 rules are now a P0 deliverable with a formal contract** (Appendix A) | `RULES_IDS` was a list of names. The rule set *is* the product |
| 4 | **Replaced the validation gates** ("3 months, win rate ≥60%, Sharpe ≥1.2") with cost-aware walk-forward OOS testing, minimum trade counts, expectation-vs-noise checks and a cost-stress test (§10) | 3 months ≈ 60–180 trades; Sharpe SE at T=0.25y is ≈2.0. The old gates could pass on noise — or on a bug |
| 5 | **Added a cost model** (spread by session, slippage, swap, commission) as a first-class requirement | v1 had no costs anywhere. For an M15 system this is 10–25% of theoretical edge |
| 6 | **Added crash safety**: intent-then-confirm journal, idempotent order submission, startup reconciliation, `tradie panic` | The `MonitorState → TradeClosed` state machine assumed the process never dies |
| 7 | **Added a correlation/net-currency exposure cap** | 4 of the 5 pairs are one USD trade. "1% per trade" was silently 3–4% |
| 8 | **Fixed the risk arithmetic** (risk 0.5–1.0%, daily loss halt 3%, equity brake 4%) | v1's 3% DD breaker was unreachable at 1% risk and collided with the 2-loss breaker at 2% risk |
| 9 | **Backtester is event-driven, not vectorized; one shared `evaluate()`** | The rules are path-dependent and stateful. Two implementations would silently diverge |
| 10 | **Resolved 10 internal contradictions** (news window, RR, paths, entry points, day boundaries, schema) | See Appendix G |
| 11 | **Uptime is now measured, not declared** | "98% monthly" had no observer. Replaced with auditable loop-availability and off-host detection |
| 12 | **Split v1.0 into v0.1 → v1.0** with exit criteria | One-person scope: research + engine + execution + ops in one release is 5–7 months of unpriced risk |
| 13 | **Rule set received and specified** (`docs/rule-spec.md`) — the real checklist replaced v1's invented `RULES_IDS` | v1's rule list was wrong: slot 8 is `MENTAL STATE`, not `CIRCUIT_BREAKERS`, and slot 7 duplicates slot 1 |
| 14 | **Rules are a staged setup state machine**, not 9 simultaneous booleans (`STR-07`, INV-10) | Conditions accrue over days/hours; requiring them all on one M15 bar would produce ~0 trades |

**Deliberately unchanged** (these were right): static SL/TP attached at entry with no trailing; the daemon is not in the exit path; CLI-first; single user, no RBAC; market entry only; no MT4/MT5; bare metal; Python 3.11; OANDA as primary venue; Telegram as primary alert channel.

---

## 2. Executive summary

**Tradie** is a single-operator, CLI-driven forex system that trades a mechanical, fully-specified rule set on OANDA. It has two halves, and they are sequenced, not parallel:

- **Tradie BT** — an event-driven backtesting and validation engine that establishes whether the rule set has a net-of-cost edge. Shippable without any live broker access.
- **Tradie Live** — an execution daemon that applies the *same* rule code to live M15 closes, with broker-side exits, circuit breakers, crash-safe state and Telegram reporting.

**Product thesis:** discipline is not a feeling, it is an enforced precondition. A trade happens only when every rule evaluates true; one false ⇒ no trade, forever, including when the operator wants it to.

**On the rules:** the checklist has now been received (`docs/source/Trading_Checklist.pdf`) and is specified in `docs/rule-spec.md`. Two findings from that work are structural, not cosmetic:

- The 9 rules are a **sequence**, not 9 simultaneous booleans. Conditions accrue from the daily bias down to a single M15 engulfing bar, so the engine is a **staged setup state machine** (`STR-07`), and setups must survive a restart (INV-10). v1's "evaluate all 9 atomically on every M15 close" reading would produce essentially zero trades.
- Only **8 of the 9 are independent checks.** Rule 7 (bias alignment) restates rule 1 and becomes an assertion (INV-9). Rule 8 (**mental state**) cannot be evaluated by software and becomes a proxy plus a daily operator check-in (`RSK-11`) — it is the one rule that must never be quietly deleted.

The checklist also defines **entries only**: it contains no exit/target rule, no session filter and no supply/demand definition. Those are owner decisions (`rule-spec.md` §10), not implementation details.

**The honest position on edge:** none is demonstrated yet, and the gates below are *filters*, not proof. A 0.1R edge cannot be established with fewer than ~800 trades at conventional power (App. D). The plan therefore treats "minimum-size live" as the final evidence-gathering stage rather than pretending a 3-month backtest settles it.

---

## 3. Decision gates — the spine of this project

Every gate has an owner, a method, pass criteria and a defined fail action. **No work on the next milestone may begin before the gate passes.** Gates are recorded in `docs/gates/Gn-<date>.md` with the evidence attached.

### G0 — Broker & account capability · *owner: Va_d3R · blocks: everything downstream*

| | |
|---|---|
| **Question** | Can this account be driven programmatically, and what is the execution surface? |
| **Method** | (1) Open/find an OANDA account for your residency. (2) Generate an API token in the account portal. (3) `GET /v3/accounts` → expect 200. (4) `GET /v3/accounts/{id}` and record `guaranteedStopLossOrderMode`, `marginRate`, `hedgingEnabled`, `currency`. (5) `POST` a 1-unit market order with `stopLossOnFill` on **practice**. |
| **Pass** | 200 on (3); order accepted on (5); capability fields recorded |
| **Fail** | **Tradie Live is out of scope for v1.0.** Project continues as **Tradie BT only** (v0.1), plus an evaluation of an alternate venue (cTrader Open API, FXCM REST, Darwinex) as a *separate* decision — not a rushed pivot |
| **Also decided at G0** | Whether GSLO is `ALLOWED`/`REQUIRED`/`DISABLED` (drives EX-06), and whether hedging is enabled (drives EX-09) |

> ⚠️ If GSLO is `DISABLED`, the phrase "stop-loss guaranteed" is removed from this PRD and the backtest's slippage assumption must include gap risk (App. D.4).

### G1 — Rule specification complete · *owner: Va_d3R · blocks: STR-02*

| | |
|---|---|
| **Source** | `docs/source/Trading_Checklist.pdf` (the real checklist, received 2026-10-25) |
| **Draft** | `docs/rule-spec.md` v0.1.0-draft exists — **13 open decisions remain, so G1 is not passed** |
| **Pass** | Every rule in `docs/rule-spec.md` §4 has no `PROPOSED` or `TBD` in a normative position, ≥2 pass + ≥2 fail fixtures in `tests/fixtures/rules/`, a mutation test per parameter, and a declared `rule → granularity` mapping. Decisions D-01…D-13 all answered |
| **Fail** | No rule engine code is written. Data layer and backtester scaffolding may proceed |
| **Review** | The spec is reviewed by a second trader if one is available; otherwise each rule must include one worked example annotated on real candles |
| **Note** | G1 is **independent of G0** — it can be advanced while broker access is unresolved, and it is the cheapest work in the project |

### G2 — Edge within costs · *owner: Va_d3R · blocks: EX-01*

| | |
|---|---|
| **Pass (all)** | ≥100 OOS trades · net expectancy ≥ **+0.10R** · profit factor ≥ **1.20** · net expectancy ≥ 0 after **1.5× cost stress** · positive in ≥3 of 5 pairs · no single pair >50% of total net profit · max closed-trade drawdown ≤ 12R |
| **Conditional** | Net expectancy in (0, 0.10R): proceed to **paper only**, at minimum size, no live capital. Edge remains unproven |
| **Fail** | Net expectancy ≤ 0, or the strategy only works gross, or it collapses under cost stress ⇒ **do not trade it.** Return to the rule spec, not to the code |
| **Anti-pattern rule** | Any result implying >150% annualized return is treated as a **defect signal** (look-ahead, cost omission, or fill optimism) and must be explained before it is believed |

### G3 — Parity & crash safety certified · *owner: Va_d3R · blocks: paper soak*

| | |
|---|---|
| **Pass (all)** | (a) Replay of a recorded session through `evaluate()` reproduces every decision bit-for-bit; (b) `kill -9` at 6 injected points leaves the books reconciled within 30s of restart, with zero duplicate orders; (c) `tradie panic` flattens from a *dead* daemon; (d) dry-run over a full trading day produces zero orders and zero exceptions |
| **Fail** | No paper trading. Duplicate-order and orphan-position classes are the single most expensive category of bug in this project |

### G4 — Paper soak · *owner: Va_d3R · blocks: live capital*

| | |
|---|---|
| **Pass (all)** | ≥**8 calendar weeks** *and* ≥30 paper trades · zero unhandled exceptions · zero unreconciled states · ≥99.5% of expected M15 evaluations actually performed (computed from the event log) · realized slippage within the modelled assumption · paper per-trade distribution statistically consistent with backtest (not materially better or worse) |
| **Fail** | Extend. This gate is calendar-bound — it cannot be compressed by working harder |

### G5 — Minimum-size live · *owner: Va_d3R*

| | |
|---|---|
| **Entry** | G4 passed **and** account funded at an amount the owner is genuinely willing to lose |
| **Exit** | 100 live trades **or** any material divergence from paper (slippage >2× model, fill rejects >2%, expectancy outside the paper CI) ⇒ **stop, return to paper** |
| **Purpose** | This is the only stage that produces evidence about real fills, real spreads, and real psychology. Capital at risk is deliberately immaterial |

---

## 4. Vision, scope, non-goals

**For:** a single disciplined operator who wants mechanical forex execution without discretionary drift.
**Unlike:** EAs and discretionary trading, Tradie cannot be talked into a trade. The rule set is the only authority.
**Product promise:** *no capital is risked before the strategy has been defined, tested against costs, and proven operationally safe.*

### 4.1 In scope — v1.0

| Area | Included |
|---|---|
| Venue | OANDA v20 REST (primary). Alternate venues are a separate future decision |
| Instruments | `EUR_USD, GBP_USD, AUD_USD, USD_JPY, USD_CAD` (configurable allowlist) |
| Decision cadence | M15 candle close; HTF context from H1 / H4 / broker-D |
| Strategy | One strategy, one rule set, versioned |
| Entries | Market orders with SL + TP attached on fill |
| Exits | Broker-side SL/TP only, plus operator panic |
| Research | Cost-aware event-driven backtester, walk-forward OOS reporting |
| Operations | systemd service, crash-safe state, circuit breakers, Telegram reporting, off-host watchdog |
| Interface | CLI only |

### 4.2 Out of scope — do not build

| Item | Reason |
|---|---|
| MT4/MT5, Wine, X11 | Fragile headless; adds points of failure. **Revisit only if G0 fails** |
| TradingView | Not needed; OANDA data is sufficient |
| GUI / web dashboard | Not until v1.0 has traded live for 3 months. Also constrained by OANDA's data-redistribution terms |
| Multi-user, RBAC, auth | Single operator. Adding users adds an attack surface with no benefit |
| Strategy override / "skip rules" | The rule set is non-negotiable. (Stopping the bot is **not** an override — see §5) |
| Trailing stops, partial closes, break-even moves, pyramiding | Keeps the daemon out of the exit path. Revisit after 100 live trades |
| Limit / pending entries | Fill certainty beats entry optimisation while the edge is unproven |
| News-based trading, hedging, arbitrage, HFT | Different products |
| ML / parameter search as a decision mechanism | Optimisation is how a 3-month sample becomes a lie |
| Signal selling, managed accounts, copy trading | Regulatory exposure; OANDA data licence limits redistribution |

---

## 5. Operator model

One role. Its powers are deliberately lopsided.

| Capability | Allowed | Rationale |
|---|---|---|
| Configure pairs, risk %, news window | ✅ | Parameter change requires restart; `strategy_version` changes |
| Read status, journal, reports | ✅ | `tradie status`, `tradie journal` |
| **Halt** new entries | ✅ | Leaves open positions protected by broker-side exits |
| **Panic** — flatten everything, stop | ✅ | Works with the daemon dead |
| Resume | ✅ | Explicit, logged, requires confirmation |
| **Force a trade / skip a rule / override a rejection** | ❌ **Never** | This is the discipline the product sells |
| Modify an open trade's SL/TP | ❌ | v1: no manual management. If a trade is wrong, panic and let the rule set be wrong instead |

**Design principle:** everything the operator can do reduces risk. Nothing the operator can do increases it.

---

## 6. Architecture invariants

These are constraints on the codebase, not aspirations. Each has a test in `tests/invariants/`.

| ID | Invariant | Enforcement |
|---|---|---|
| **INV-1** | **One evaluation path.** `evaluate(market, account, risk_state) -> Decision` is a pure function used identically by backtest, paper, live, and replay | Replay test (G3a): same inputs ⇒ identical `Decision`; a second implementation is a review-blocking defect |
| **INV-2** | **The daemon is not in the exit path.** SL and TP are attached `onFill` and live at the broker | Kill the daemon mid-trade; position must still exit |
| **INV-3** | **Intent-then-confirm.** Every mutating action is appended to the durable event log *before* the API call and reconciled *after* | Crash injection (G3b) at the gap |
| **INV-4** | **Idempotent submission.** Every order carries `clientExtensions.id = "{strategy_version}:{instrument}:{candle_ts}"`; retries reuse it | Duplicate-submit test: same id twice ⇒ one position |
| **INV-5** | **No look-ahead by construction.** Only `complete == true` candles; `decision_ts == last closed candle ts`; `MarketView` is truncated at that ts | Future-blindness test: mutate all bars after `decision_ts`, assert identical `Decision` |
| **INV-6** | **Determinism.** No wall-clock, no RNG, no network, no filesystem access inside `evaluate()`. Time and account are injected | Same-input hash equality across processes |
| **INV-7** | **Fail closed.** Any uncertainty (stale feed, ambiguous API response, missing news data) ⇒ **no new entries**; existing positions keep their broker-side exits | Staleness injection tests |
| **INV-8** | **Reversibility.** Stopping and flattening are single commands that do not depend on the strategy process being healthy | `tradie panic` exercised with a dead daemon |
| **INV-9** | **Bias alignment is an assertion.** `sign(direction) == bias` at the submit boundary. A failure raises and alerts; it is never a soft rejection | Unit test; any mismatch is treated as a P1 defect |
| **INV-10** | **Setups persist.** The rule set is a staged state machine; a restart mid-setup resumes the same setup, never resets it | Kill -9 at each setup state; state must be identical after restart |

---

## 7. Functional requirements

Every requirement has an acceptance test. "Done" means the test exists and passes.

### 7.1 Strategy layer

| ID | Requirement | Acceptance criteria |
|---|---|---|
| **STR-01** | `docs/rule-spec.md` defines all 9 rules per Appendix A: inputs, granularity, parameters with defaults/ranges, pseudocode predicate, evidence fields, ≥2 pass + ≥2 fail fixtures, known failure modes | Zero `TBD`s; specs reproducible by a second reader |
| **STR-02** | Rule engine evaluates the 9 rules as pure functions over `MarketView` + `RiskState`. Gates (`RISK_MANAGEMENT`, `CIRCUIT_BREAKERS`, `TRADE_LIMIT`) evaluated **first** and short-circuit | Unit tests per rule; gate ordering asserted |
| **STR-03** | Every evaluation — **including rejections** — emits a `Decision` record with per-rule booleans and evidence. Rejected-signal journal is retained and is queryable | Journal contains rejections with the first failing rule named |
| **STR-04** | Rule parameters live in `config.yaml` under a `strategy:` block; `strategy_version` = short hash of the resolved parameter set, recorded on every decision, order, trade and report | Changing a parameter changes `strategy_version` |
| **STR-05** | ~~Two rules are recognised as the same check~~ **RESOLVED (H-04):** `BIAS_ALIGNMENT_GATE` restates `BIAS_HTF` and is not an independent condition. It becomes **INV-9** (an assertion), leaving **8 independent checks**, not 9 | Unit test asserts a mismatch raises |
| **STR-06** | `rule → granularity` mapping is explicit and configurable (see Appendix A.2 and `rule-spec.md` §2) | No rule infers its own timeframe |
| **STR-07** | **The rule set is a staged setup state machine, not a conjunction over one bar.** Conditions accrue over hours/days: bias (D) → sweep (M15) → structure shift (M15) → retrace (M15) → engulf (one bar). A `setup_id` is issued at the sweep, persisted, and carries a TTL | `rule-spec.md` §3; evaluating all conditions on a single bar would produce ~0 trades and is a spec defect |
| **STR-08** | `R8_MENTAL_STATE` is not machine-evaluable. It is implemented as **(a)** structural satisfaction, **(b)** mechanical proxies (loss-streak breaker, trade cap, setup expiry, force-trade cooldown) and **(c)** a required daily operator check-in | `RSK-11`; `tradie session check-in` recorded in `events` |

### 7.2 Data layer

| ID | Requirement | Acceptance criteria |
|---|---|---|
| **DAT-01** | Download OHLCV from `/v3/instruments/{i}/candles`, paginating 5,000-candle pages, for M5/M15/H1/H4/D across the instrument allowlist | ≥18 months of M15 available for all 5 pairs; no gaps >1 bar where the market was open |
| **DAT-02** | Cache to **parquet**, UTC-indexed, one file per `(instrument, granularity)`, with a sidecar manifest (row count, first/last ts, content hash, download ts, source) | Manifest verified on every read; mismatch ⇒ hard error |
| **DAT-03** | Store only `complete == true` candles. Re-download the last 2 bars each cycle to capture revisions | No incomplete bar in cache, ever |
| **DAT-04** | Every backtest run embeds the data manifest hashes for its inputs ⇒ byte-identical reruns | `--verify-rerun` reproduces the report exactly |
| **DAT-05** | Calendar module behind a `NewsSource` interface; primary = ForexFactory weekly export, polled ≤1/5min, cached, **archived daily to parquet** | Archive grows; source swappable by config |
| **DAT-06** | If news data is older than `news.max_staleness_hours` (default 12), treat as unknown ⇒ block new entries and alert (INV-7) | Staleness injection test |
| **DAT-07** | Timezone discipline: all internal timestamps UTC; news feed offsets parsed correctly; NTP verified at startup, refuse to start if skew >5s | DST-crossing fixture test |
| **DAT-08** | Two distinct day concepts, never conflated: **`trading_day`** = 00:00–24:00 UTC (counters, breakers, reports) and **`broker_day`** = OANDA's D-candle boundary (HTF bias only, boundary recorded in reports) | Both appear in every daily report |

### 7.3 Backtesting & validation

| ID | Requirement | Acceptance criteria |
|---|---|---|
| **BT-01** | **Event-driven** replay over M15 with the full state machine (open positions, streaks, counters, breakers). Vectorised sweeps may be added later *only* over the same `evaluate()` | Reference run completes in ≤5 min for 5 pairs × 2 years |
| **BT-02** | Cost model applied to every fill: per-pair spread by session bucket (normal / rollover / news), slippage = `k × spread` (default k=0.3) on market entries, swap for positions held overnight, commission if applicable | Every report prints gross P&L, total costs, net P&L, and mean cost per trade in pips and in R |
| **BT-03** | Fill assumptions declared, not implicit: entry at the *next* tick after the decision candle closes (approximated as close ± cost); SL/TP evaluated against subsequent bar extremes with gap handling if the bar opens beyond the level | Documented in `docs/fill-model.md`; a bar that opens through the SL must fill at the open, not the SL price |
| **BT-04** | Walk-forward harness: in-sample optimisation window, out-of-sample validation window, rolled forward; **OOS results are the only results reported as performance** | OOS-only summary is the headline; IS shown separately and labelled |
| **BT-05** | Holdout discipline: the most recent 6 months are locked until parameters are frozen; a `--unlock-holdout` run is a one-shot event recorded in the report | Unlock is logged with a timestamp and the frozen `strategy_version` |
| **BT-06** | Reports written to `reports/backtest-<ts>.{json,csv,md}` including the full env fingerprint (git SHA, dependency lock hash, data manifest hash, config hash, `strategy_version`) | Two machines, same inputs ⇒ same hashes |
| **BT-07** | Metrics exactly as defined in §10; a JSON schema exists so reports are machine-comparable across runs | Schema validated in the test suite |
| **BT-08** | `--dry-run` and `--replay <session.jsonl>` modes reuse the live pipeline against recorded market data | Used by G3 |

### 7.4 Live execution

| ID | Requirement | Acceptance criteria |
|---|---|---|
| **EX-01** | Market entry via `POST /v3/accounts/{id}/orders`, `type=MARKET`, `timeInForce=FOK`, SL and TP attached `onFill`, `clientExtensions.id` per INV-4 | Order payload snapshot test; duplicate submit produces one position |
| **EX-02** | Sizing: `units = floor(risk_amount / (sl_distance × pip_value_in_account_ccy))`, rounded to instrument precision, clamped to `[minimumTradeSize, maximumOrderUnits]`. JPY-cross pip values computed correctly and unit-tested per pair | Table-driven test across all 5 pairs incl. account-currency conversion |
| **EX-03** | Pre-flight margin check against `marginAvailable`; insufficient margin ⇒ skip + alert (never a rejected order storm) | Simulated low-margin test |
| **EX-04** | Startup reconciliation: fetch open trades, open orders, recent transactions; diff against the local journal in both directions; adopt or flatten unmatched positions; never re-fire an adopted signal | Reconcile-after-crash test with 3 divergent scenarios |
| **EX-05** | Ambiguous responses (timeout, 5xx) resolve by querying `clientExtensions.id` before any retry | Fault-injection test |
| **EX-06** | If `guaranteedStopLossOrderMode` is `ALLOWED`/`REQUIRED`, attach GSLO and record the premium estimate; if `DISABLED`, attach a plain SL and record `gap_risk=true` on the trade | Capability read at startup; header line in every report |
| **EX-07** | One position per instrument; no pyramiding; no reversing without closing first | Enforced in the gate layer |
| **EX-08** | Weekend policy: no entries within 30 min of Friday close, flatten (configurable, **default on**) by `friday_flatten_utc` (default 20:45), no entries in the first 15 min after Sunday open | Config test; explicit log line on flatten |
| **EX-09** | If `hedgingEnabled` is false, net positions are real: enforce single-direction per instrument in code | Startup assertion |
| **EX-10** | Every fill records `signal_price`, `fill_price`, `slippage_pips`; alert if slippage > `alerts.slippage_alert_pips` (default 2× model) | Daily report shows slippage distribution |

### 7.5 Risk & circuit breakers

Precedence is explicit and total (resolves v1's contradictory overlaps):

```
L5  equity brake    → flatten all, halt until next trading_day   (most severe)
L4  daily loss halt → no new entries until next trading_day
L3  loss streak     → no new entries for N hours
L2  news blackout   → no new entries in a per-instrument window
L1  trade cap       → no new entries once cap reached
```

| ID | Requirement | Default | Rationale |
|---|---|---|---|
| **RSK-01** | Risk per trade | **0.5–1.0%** (default 0.75%) | Narrowed from 1–2%: 2% × 3 trades = 6% daily exposure on an unproven system is unjustifiable. Widen after 100 profitable live trades |
| **RSK-02** | Minimum reward:risk at entry | ≥ 2.0 | Computed on the *actual* SL/TP, asserted before submission; violations are rejections, and any observed avg RR < 2.0 in reporting indicates a bug |
| **RSK-03** | Max concurrent positions | 2 | 5 pairs are ~2 independent bets |
| **RSK-04** | **Net currency exposure cap** | ≤ 2.0% aggregate risk per currency | 4 USD-major pairs are one trade in four costumes. This is the v1 gap that would have mattered most |
| **RSK-05** | Trade cap per `trading_day` | 3 | Hard stop; resets at 00:00 UTC |
| **RSK-06** | Loss-streak pause | 2 consecutive losses ⇒ 2h pause (L3) | Unchanged from v1, now unambiguous |
| **RSK-07** | Daily loss halt | closed P&L ≤ **−3.0%** of start-of-`trading_day` equity ⇒ halt to next day | Reachable: 3 losses at 1% = −3%. v1's −3% "pause 4h" was unreachable at 1% risk |
| **RSK-08** | Equity brake | session equity DD (incl. floating) ≥ **4.0%** ⇒ flatten + halt | The emergency brake, beyond the arithmetic of 3×1% |
| **RSK-09** | News blackout | ±45 min around **high-impact** events for either currency; block new entries; do not force-close | Widened from ±30 min for realism; per-pair, not global. Fail closed if data is stale |
| **RSK-10** | All breaker state persists across restarts (SQLite) and survives a crash mid-transition | Restart-during-breaker test |
| **RSK-11** | **Mental-state precondition (rule R8).** No entries unless a `trading_day` check-in exists (`tradie session check-in`), and no entry within `force_trade_cooldown_min` (30) of a realised loss. Open positions are unaffected | Missing check-in ⇒ zero entries, alert raised; cooldown asserted in the gate layer |
| **RSK-12** | **Cross-day setup policy:** setups persist across the 00:00 UTC boundary (a setup begun at 23:50 is valid at 00:10); only the `R9` counter resets | Boundary fixture test |

### 7.6 Alerts & reporting

| ID | Requirement | Acceptance criteria |
|---|---|---|
| **ALR-01** | Real-time Telegram events: entry filled, exit filled, breaker fired, halt/panic, reconciliation anomaly, slippage breach, data staleness | Delivery ≤10s p95 from the trigger |
| **ALR-02** | Daily report at `trading_day` close (00:05 UTC) with the format in Appendix B: trades vs cap, wins/losses in R, gross/net P&L, costs, drawdown, balance, win rate, avg RR, MAE/MFE, active breakers, slippage stats | Generated from the DB, not from logs |
| **ALR-03** | Alert outbox: every alert is persisted then sent with retry/backoff; failures are retried on the next cycle and eventually escalated | Kill-network test ⇒ queued, then delivered |
| **ALR-04** | One non-Telegram fallback channel (email / ntfy / SMS) for breaker and failure events | Configurable; tested |
| **ALR-05** | Off-host dead-man switch: the daemon pings an external endpoint each cycle; absence of >3 pings escalates to the fallback channel | Simulated host death detected ≤5 min |
| **ALR-06** | Inbound Telegram commands restricted to a single allowlisted `chat_id`, disabled by default (`alerts.telegram_commands: false`). No command mutates trading state except `halt` | Unauthorised chat id ignored + logged |

### 7.7 Operations & supervision

| ID | Requirement | Acceptance criteria |
|---|---|---|
| **OPS-01** | Runs as a `systemd` service: `Restart=always`, `RestartSec=10`, `WatchdogSec=180` with `sd_notify` heartbeats, journald + file logging | Kill the process ⇒ auto-restart within 15s |
| **OPS-02** | Crash-safe state in **SQLite** (WAL). The daemon is the only writer; cron jobs open read-only | Concurrent-write test fails loudly rather than corrupting |
| **OPS-03** | Log rotation: 7 daily files, compressed; rotation is coupled to the retention policy for reports (90 days) | Disk usage bounded and asserted |
| **OPS-04** | Health assertions each cycle: disk free, RAM, clock skew, API latency, data freshness, DB writability | Each failure has a defined alert + action |
| **OPS-05** | Runbooks: deploy, rollback, token rotation, "bot is misbehaving at 3am", "position on the wrong side" | `docs/runbooks/*.md` |
| **OPS-06** | Deploy is a checklist, not a `git pull`: frozen deps, restart, dry-run smoke test, reconciliation check, status confirmation | `docs/deploy.md`, executed and signed off each time |
| **OPS-07** | **Loop availability** is computed each day: expected vs actual M15 evaluations per pair (from the event log) | Reported daily; target ≥99.5% |
| **OPS-08** | `tradie init`/`tradie verify` validates config against schema (unknown keys are errors, not warnings) before any run | Bad config never reaches the API |

### 7.8 Security

| ID | Requirement | Acceptance criteria |
|---|---|---|
| **SEC-01** | Secrets in `.env` at `0600`, injected via `systemd EnvironmentFile=`. Never passed on the command line, never exported in an interactive shell | `.env` in `.gitignore`; no secret in `git log -S` output |
| **SEC-02** | Log redaction filter: `Bearer` tokens, API keys, Telegram token path segment, account numbers partially masked. Applied at the sink, tested | Fixture log line with a token is redacted |
| **SEC-03** | Separate practice and live tokens; separate config files; live requires `--live` **and** an interactive confirmation; startup banner prints `LIVE` for 10s | A live run cannot be started by accident |
| **SEC-04** | Host hardening: SSH keys only, `PermitRootLogin no`, `ufw` default-deny inbound, `fail2ban`, `unattended-upgrades` | Checklist with evidence |
| **SEC-05** | Bot is bound to a **single `OANDA_ACCOUNT_ID`**, ideally a dedicated sub-account, so it cannot reach other funds | Config assertion at startup |
| **SEC-06** | Token rotation runbook, exercised at least once before live | Documented drill |
| **SEC-07** | Rate-limit discipline: a token-bucket client capped well below 120 req/s, with 429 backoff honouring `Retry-After` | Load test asserts no 429s in normal operation |

### 7.9 CLI surface

| Command | Semantics |
|---|---|
| `tradie` | Start the daemon (paper by default; `--live` required for live) |
| `tradie --dry-run` | Full pipeline, zero orders, verbose decisions |
| `tradie status` | Positions, breakers, counters, last evaluation per pair, data freshness, `strategy_version` |
| `tradie journal [--since]` | Trades + rejections with rule attribution |
| `tradie backtest --pair … --from … --to … [--walk-forward]` | Run BT-01..BT-07 |
| `tradie backtest --replay <session.jsonl>` | Parity replay (G3a) |
| `tradie report --daily [--date]` | Generate/send the daily report |
| `tradie halt` / `tradie resume` | Stop/allow new entries; existing positions untouched |
| **`tradie panic`** | Halt, cancel working orders, close all positions, verify flat, write an incident record. **Works with the daemon dead** |
| `tradie init` / `tradie verify` | Config validation, connectivity and capability checks |
| `tradie reset-counter --confirm` | Manual `trading_day` counter reset (logged; requires reason) |

---

## 8. Data model & configuration

### 8.1 Core record: `Decision`

Replaces v1's invalid `Order` TypedDict. A rejected evaluation is a first-class record; `direction=None` is the normal case and is still stored.

```python
@dataclass(frozen=True)
class Decision:
    decision_id: str                  # uuid4, stable across retries
    strategy_version: str             # hash of resolved rule params
    instrument: str                   # "EUR_USD"
    candle_ts: datetime               # UTC, the closed M15 bar evaluated
    created_at: datetime              # UTC, actual evaluation time
    direction: Literal["long", "short"] | None
    signal_rules: dict[str, bool]     # 6 price rules
    gates: dict[str, bool]            # RISK_MANAGEMENT, CIRCUIT_BREAKERS, TRADE_LIMIT
    first_failure: str | None         # attribution for rejections
    units: int | None                 # OANDA units, never lots
    entry_ref: float | None
    sl: float | None
    tp: float | None
    rr: float | None
    risk_pct: float | None
    evidence: dict[str, float]        # rule-specific diagnostics (swept_level, atr, ...)
    # added with the real rule set (rule-spec.md §9)
    setup_id: str | None              # None when no setup is active
    setup_state: Literal["swept","shifted","retraced","confirmed","invalidated","expired"] | None
    retrace_depth: float | None       # actual retracement achieved, e.g. 0.47
    body_ratio: float | None          # R5 engulfing quality
    displacement_atr: float | None    # R3b MSS strength
    efficiency_ratio: float | None    # R3a chop filter
```

### 8.2 SQLite tables

| Table | Purpose |
|---|---|
| **`setups`** | **Staged rule state machine (`STR-07`, INV-10).** `setup_id`, `instrument`, `state ∈ {swept, shifted, retraced, confirmed, invalidated, expired}`, `state_entered_at`, `sweep_extreme`, `mss_level`, `leg_len_pips`, `zone_low`, `zone_high`, `expires_at`, `invalidation_reason`, `strategy_version` |
| `decisions` | Every evaluation, including rejections (the research asset). References `setup_id` |
| `orders` | Intent rows: `client_order_id`, `state ∈ {intent, submitted, accepted, rejected, filled, cancelled}`, raw request/response |
| `trades` | `trade_id`, open/close ts & prices, units, `pnl`, `pnl_r`, `slippage_pips`, `cost_pips`, `gap_risk`, `strategy_version` |
| `events` | Append-only operational log (INV-3). The audit trail of record |
| `breaker_events` | Level, trigger, window, resolution |
| `equity_snapshots` | Per-cycle equity incl. floating (for RSK-08 and DD metrics) |
| `news_events` | Archived calendar entries used for blackouts |
| `backtest_runs` | Config + data manifest hashes + metrics JSON |
| `alerts` | Outbox with state and retry count |

### 8.3 Configuration

`.env` holds secrets only (`OANDA_API_KEY`, `OANDA_ACCOUNT_ID`, `OANDA_ENVIRONMENT`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`). Everything else lives in `config.yaml`, schema-validated, unknown keys rejected.

```yaml
version: 1
account:
  environment: practice
  account_id_env: OANDA_ACCOUNT_ID
instrument:
  allowlist: [EUR_USD, GBP_USD, AUD_USD, USD_JPY, USD_CAD]
  max_concurrent_positions: 2
  max_net_currency_exposure_pct: 2.0
strategy:
  version_file: docs/rule-spec.md
  rules:                          # parameters per Appendix A; TBD until G1
    BIAS_HTF: { granularity: D, params: {} }
    LIQUIDITY_SWEEP: { granularity: M15, params: {} }
    MARKET_STRUCTURE: { granularity: H1, params: {} }
    ENTRY_MODEL_RETRACE: { granularity: M15, params: {} }
    ENGULFING_CONFIRMATION: { granularity: M15, params: {} }
risk:
  risk_per_trade_pct: 0.75         # 0.50–1.00 in v1
  min_rr: 2.0
  daily_trade_cap: 3
  loss_streak_pause: { losses: 2, hours: 2 }
  daily_loss_halt_pct: 3.0
  equity_brake_pct: 4.0
session:
  trading_day_tz: UTC
  friday_flatten_utc: "20:45"
  entry_blackout_after_open_min: 15
news:
  source: forexfactory
  blackout_minutes: 45
  impacts: [high]
  max_staleness_hours: 12
costs:
  slippage_spread_multiple: 0.3
  spread_model: session_aware
  swap: broker
exits:
  gslo: auto                       # auto | require | disable
alerts:
  channel: telegram
  fallback: email
  telegram_commands: false
  slippage_alert_pips: auto        # 2x modelled
ops:
  db_path: state/tradie.db
  log_dir: logs
  log_retention_days: 7
  report_retention_days: 90
  heartbeat_url_env: HEALTHCHECK_URL
```

---

## 9. Non-functional requirements

Replaces v1's aspirational table with measurable targets.

| Requirement | Target | How it is measured |
|---|---|---|
| Decision latency | p95 ≤ 3s from candle close to decision recorded | `events` timestamps |
| Order submission latency | p95 ≤ 2s from decision to acknowledgement | `orders` timestamps |
| Alert latency | p95 ≤ 10s from trigger to Telegram delivery | Alert outbox timestamps |
| Loop availability (market hours) | ≥99.5% of expected M15 evaluations performed | OPS-07, computed daily |
| Failure detection | ≤5 min from host/process death | Off-host dead-man switch (ALR-05) |
| Restart-to-reconciled | ≤30s | G3b drill |
| Backtest speed | 5 pairs × 2 years ≤ 5 min (reference box) | Benchmark in CI (`make bench`) |
| Determinism | Identical report hashes for identical inputs | `--verify-rerun` |
| Crash safety | 0 duplicate orders across 6 injected crash points | Fault-injection suite |
| Platform | Ubuntu 22.04/24.04, Debian 12; Python 3.11+ | Deploy checks |
| Backtest→live parity | 100% decision agreement on replayed sessions | G3a |

**Removed from v1:** "≥90% rule logic coverage" — coverage of an undefined predicate is meaningless. Replacement: every rule has ≥4 fixtures and a mutation test (mutating the parameter set must change the outcome for at least one fixture, otherwise the parameter is dead code). **"Uptime ≥98%"** — replaced by the measurable metrics above; a declared number with no observer is not a requirement.

---

## 10. Validation & statistics specification

### 10.1 Definitions

| Metric | Definition |
|---|---|
| **R** | The risk unit of a trade = `entry − SL` distance × size, in account currency at entry |
| **`pnl_r`** | Realised P&L ÷ R. Includes costs |
| **Expectancy** | `mean(pnl_r)` over **net** P&L, reported per pair and pooled, with a 90% bootstrap CI (10k resamples) |
| **Profit factor** | `Σ wins ÷ Σ abs(losses)` on net P&L |
| **Win rate** | Reported, **never gated** (a 1:2 strategy is profitable at 40%) |
| **Max drawdown** | Two numbers, always labelled: `max_dd_equity` (mark-to-market, from `equity_snapshots`) and `max_dd_closed` (realised curve) |
| **Sharpe** | Mean ÷ SD of **daily** net returns over `trading_day` boundaries, annualised ×√252. Reported with its CI, never as a standalone pass criterion |
| **Cost drag** | Mean all-in cost per trade, in pips and in R |
| **MAE / MFE** | Worst/best excursion during the trade, in R |

### 10.2 What this can and cannot prove

Sample-size reality (one-sample, 80% power, α=0.05, trade-level SD ≈1R):

| Trades | Smallest detectable net expectancy | Verdict |
|---|---|---|
| 50 | ≈ 0.40R | Noise |
| 100 | ≈ 0.28R | Weak filter |
| 200 | ≈ 0.20R | Usable filter |
| ~800 | ≈ 0.10R | Meaningful |

**Consequence, stated plainly:** G2 is a *filter against bad strategies*, not proof of a good one. A 0.1R edge — a perfectly good retail edge — cannot be established before live trading. This is why G5 (minimum-size live, 100 trades) exists and why v1's "3 months proves the strategy" framing is removed.

### 10.3 Required report contents (every run)

1. OOS-only headline metrics; in-sample shown separately and labelled.
2. Gross → costs → net reconciliation table.
3. Per-pair breakdown + pooled, with confidence intervals.
4. **Cost stress**: net expectancy at 1.0×, 1.5×, 2.0× modelled costs.
5. Trade-count and distribution diagnostics (trades/day, hold time, MAE/MFE medians).
6. Rejected-signal funnel: how many evaluations reached each rule, and which rule is the binding constraint. *This is how the rule set gets improved.*
7. Env fingerprint: git SHA, lock hash, data manifest hashes, config hash, `strategy_version`.

### 10.4 The too-good-to-be-true rule

> Any annualised return >150%, profit factor >3, or win rate >75% at ≥1:2 is treated as a **defect**, not a success. It must be explained (look-ahead, missing costs, fill optimism, survivorship in the pair list) before it is reported upward.

---

## 11. Milestones and exit criteria

| Milestone | Scope | Exit criteria | Estimate |
|---|---|---|---|
| **G0** | Broker capability | §3 G0 pass | 1 day |
| **M1 — spec** | `docs/rule-spec.md`, parameter registry, fixtures | G1 pass | 3–4 days |
| **v0.1 — Tradie BT** | DAT-*, BT-01..08, reports, walk-forward | G2 pass **or** a documented "no edge" result (a valid, money-saving outcome) | 3–4 weeks |
| **v0.2 — Tradie Live (paper)** | STR-, EX-, RSK-, ALR-, OPS- (minus live capital), SQLite state | G3 pass | 3–4 weeks |
| **v0.3 — paper soak** | Run it. Do not add features | G4 pass | ≥8 weeks *(calendar-bound)* |
| **v1.0 — live, minimum size** | Live safeguards, runbooks, rotation drill | G5 exit criteria met | 1 week + ongoing |
| **v1.1 — deferred features** | Trailing/partials, limit entries, second venue, dashboard | Only after 100 profitable live trades | TBD |

Total engineering: **~9–11 weeks**. Calendar to first live trade: **~5–6 months**, dominated by the soak. That is the honest number, and the soak is the most valuable part of it.

---

## 12. Risk register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R-01 | OANDA v20 API unavailable for the operator's jurisdiction | **High** | **Fatal to Live** | G0 before any code; BT-only fallback plan pre-agreed |
| R-02 | Rules remain undefined or drift during implementation | **High** | Fatal to validity | G1 enforced; parameter registry; mutation tests |
| R-03 | Parameter overfitting to a short sample | **High** | High | Walk-forward, locked holdout, cost stress, reject-too-good |
| R-04 | Duplicate order / orphan position after a crash | Medium | **High** | INV-3/4, EX-04/05, G3b fault injection |
| R-05 | Look-ahead in HTF resampling | **High** (silent) | High | INV-5, `complete` flag, future-blindness test |
| R-06 | Costs/spread wider than modelled | Medium | High | Session-aware spreads, cost stress, slippage logging + alerts |
| R-07 | Correlated USD exposure | **High** if uncapped | High | RSK-04 net-currency cap, RSK-03 concurrency cap |
| R-08 | Overnight/weekend gap through a "guaranteed" SL | Medium | High | GSLO capability check, Friday flatten default, gap-risk flag |
| R-09 | News feed blocked / stale / ToS | Medium | Medium | Fail closed, daily archive, swappable source, export endpoint not HTML scrape |
| R-10 | Silent daemon death during market hours | Medium | High | systemd watchdog + off-host dead-man switch + loop availability metric |
| R-11 | Secret leakage via logs or repo | Low | **High** | SEC-01/02, gitignore, redaction fixture, rotation drill |
| R-12 | Operator abandons discipline (disables a rule, force-trades) | Medium | High | No override capability exists; `panic` and `halt` are risk-reducing only |

---

## 13. Deferred and explicitly-not-now

Recorded so they are decisions rather than omissions: second venue/cTrader; trailing & partial exits; limit entries at the retrace level (the `ENTRY_MODEL_RETRACE` rule arguably *describes* one — revisit after v1.0); multiple strategies and portfolio allocation; web dashboard; multi-user; paid news calendar with historical actuals; parameter optimisation as a sanctioned workflow; MT5 bridge as a G0 fallback.

---

## Appendix A — Rule specification contract

### A.1 Per-rule template (this is what G1 requires)

```markdown
## RULE: LIQUIDITY_SWEEP

- **kind:** signal | **granularity:** M15 | **lookback_bars:** 96
- **params:** `sweep_lookback` (int, 48, 12–200), `min_penetration_pips` (float, 1.0, 0.5–10),
  `max_penetration_pips` (float, 15.0, 5–50), `require_reclaim_close` (bool, true)
- **inputs:** candles[M15][-lookback:], swing_high(n), swing_low(n), pip_size
- **predicate (pseudocode):**
    for each of the last `k` bars, find the prior swing high H over `sweep_lookback`
    swept = bar.high > H + min_penetration  and  bar.high < H + max_penetration
             and (not require_reclaim_close or bar.close < H)
    return any(swept) within `recency` bars
- **evidence written:** `swept_level`, `penetration_pips`, `bars_since_sweep`
- **true fixture:**  <bars reference + annotation>
- **false fixture:** <bars reference + annotation, "no reclaim close">
- **known failure modes:** low-liquidity Asian sessions produce wick noise; must be combined
  with MARKET_STRUCTURE to avoid sweeping the same range repeatedly
- **status:** DEFINED / TBD
```

### A.2 Rule inventory — from the real checklist

Source of truth: `docs/source/Trading_Checklist.pdf`. Full specification: `docs/rule-spec.md` §2–§4.

| Checklist item | Rule ID | Kind | Granularity | Mechanical? |
|---|---|---|---|---|
| 1. Bias (higher timeframe) | `R1_BIAS_HTF` | regime | D (fallback H4) | ✅ |
| 2. Liquidity sweep | `R2_LIQUIDITY_SWEEP` | trigger | M15 (context H1) | ✅ |
| 3a. Structure clean (not choppy) | `R3a_STRUCTURE_QUALITY` | filter | H1 window | ✅ (needs metric) |
| 3b. Structure shifting in bias direction | `R3b_STRUCTURE_SHIFT` | confirmation | M15 | ✅ |
| 4. Entry model — 50% retracement | `R4_ENTRY_RETRACE` | zone | M15 | ✅ |
| 5. Confirmation — M15 engulfing | `R5_ENGULFING_CONFIRMATION` | trigger | **one M15 bar** | ✅ |
| 6. Risk management | `R6_RISK_MANAGEMENT` | gate | account | ✅ |
| 7. Bias alignment | `R7_BIAS_ALIGNMENT` | **assertion** | — | ✅ (INV-9) |
| 8. Mental state | `R8_MENTAL_STATE` | **human → proxy** | operator + state | ⚠️ partial |
| 9. Trade limit | `R9_TRADE_LIMIT` | gate | `trading_day` | ✅ |

> **Corrections to v1's rule list.** v1's `RULES_IDS` was invented and wrong in two places: slot 8 was `CIRCUIT_BREAKERS`, but the checklist's rule 8 is **MENTAL STATE**; and `BIAS_ALIGNMENT_GATE` (slot 7) restates `BIAS_HTF` (slot 1). Circuit breakers are a separate risk layer (`RSK-01`…`RSK-12`), not a checklist rule.
>
> **Honest count:** 5 staged price conditions + 2 gates + 1 assertion + 1 human precondition. **Eight independent checks, not nine.**

### A.3 Evaluation order

```
R9 trade limit → R6 risk/margin → R8 mental-state proxy → R1 bias
   ── if a setup exists ──
R2 sweep → R3a structure quality → R3b structure shift → R4 retrace → R5 engulf
   ── R7 assertion at submit (raises, never soft-rejects) ──
```

Gates are cheap and fail first, which keeps the rejection funnel in the daily report meaningful (one non-trade, one attributed rule).

### A.4 The 13 decisions G1 still requires

Listed with defaults and leverage in `docs/rule-spec.md` §10. The four that move results most: **D-05** (50% of *which* leg), **D-04** (chop metric), **D-09** (exit/TP rule — absent from the checklist entirely), **D-01** (bias definition and D/H4 conflict).

### A.5 Known strategy gaps (not fixable by coding)

The checklist defines **entries only**. It contains no exit/target rule, no session/time filter, no instrument-selection rule and no setup-invalidation semantics. See `rule-spec.md` §8. The missing exit rule in particular blocks `R6`'s `rr_actual` check from being meaningful — `min_rr` cannot be enforced with confidence until D-09 is answered.

---

## Appendix B — Telegram formats

Preserved from v1's brand direction (palette and monospace code blocks retained), with the arithmetic corrected and costs made explicit.

```
☕ TRADIE — DAILY REPORT
trading_day (UTC): 2026-10-25 00:00 → 2026-10-26 00:00
strategy_version: 3f9c1a2   account: practice   gslo: ALLOWED

▶️ Trades: 2 (cap 3)
✅ Winners: 1 (+1.85R)
❌ Losers: 1 (-1.00R)
💰 Gross: +0.55%   Costs: -0.12%   NET: +0.43%
📉 DD (equity, intraday): -0.8%
🏦 Balance: $10,043.00

📊 Metrics
- Win rate: 50.0%
- Avg RR (closed): 1:2.05     ← must be ≥ 2.00
- Expectancy: +0.43R
- Slippage: mean 0.4p, max 1.1p (modelled 0.6p)
- MAE median: -0.42R

🔋 Breakers: none
🔍 Evaluations: 96/96 M15 (5 pairs) — funnel: gates 61%, LIQUIDITY_SWEEP 22%, STRUCTURE 11%, ENGULFING 6%
```

```
🚨 TRADIE — BREAKER
L3 loss streak: 2 consecutive losses
Entries paused until 2026-10-25 14:30 UTC
Open positions remain protected by broker-side SL/TP.
```

Brand tokens retained for alert emphasis: Bullish `#5FFF5F`, Bearish `#FF5F5F`, DrawRestraint `#FFBF00` (breakers), LogoAccent `#0066FF`. Font: JetBrains Mono in code blocks.

---

## Appendix C — State machine

```
[*] --> Starting
Starting --> Reconcile: load state, verify config, capabilities, clock
Reconcile --> Halted: divergence found (flat + alert)
Reconcile --> Idle: books match

Idle --> Evaluating: M15 complete candle
Evaluating --> Idle: any gate or rule FALSE  (Decision stored, attribution logged)
Evaluating --> Submitting: all 9 TRUE
Submitting --> AwaitingFill: accepted (client_order_id recorded)
Submitting --> Idle: rejected / ambiguous -> query by client_order_id
AwaitingFill --> Monitoring: filled (SL/TP confirmed at broker)
AwaitingFill --> Idle: rejected / cancelled
Monitoring --> Monitoring: heartbeat, equity snapshot
Monitoring --> Idle: closed at broker (reconciled by transaction poll)
Monitoring --> Panic: breaker L5 or operator panic
Panic --> Halted
Idle --> Halted: breaker L3/L4 window open
Halted --> Idle: window expires / operator resume
Idle --> Idle: trading_day rollover (00:00 UTC reset)
[*] --> Panic: `tradie panic` (works with daemon dead)
```

Key additions vs v1: an explicit **Reconcile** entry state; **Halted** as a real state; **no path from Monitoring to a trade closure that the daemon must observe** (INV-2 — closure is detected by polling transactions, so a dead daemon cannot strand a trade); and **Panic reachable from outside the process**.

---

## Appendix D — Cost model & fill assumptions

| Component | Model (configurable) |
|---|---|
| Spread | Per-pair, per-session: `normal` (London/NY), `rollover` (21:00–22:00 UTC, 3–5×), `news` (±45 min, 2–4×). Defaults seeded from observed practice-account spreads, then recalibrated from live data |
| Slippage | `k × spread` per market order, default k=0.3; recorded actual vs modelled on every live fill |
| Swap | OANDA financing rates per instrument for positions held across 21:00 UTC; Wednesday triple-swap modelled |
| Commission | 0 for spread-only accounts; configurable |
| Fill price | Entry at the next tick after the decision candle closes. **If a bar opens beyond SL/TP, fill at the open** (no free gap) |
| GSLO premium | If GSLO active, premium charged only on trigger; modelled at the broker's published rate and logged per trade |

**D.4 If GSLO is unavailable:** add a gap-risk adjustment to the SL fill model (adverse open beyond stop), state it in every report, and prefer Friday flatten.

---

## Appendix E — Project structure

```
Tradie/
├── docs/
│   ├── Tradie PRD.md            ← v1, retained for reference
│   ├── Tradie PRD_APPENDIX.md   ← v1, retained for reference
│   ├── Tradie PRD v2.md         ← this document (of record)
│   ├── PRD-REVIEW.md            ← change rationale
│   ├── rule-spec.md             ← G1 deliverable
│   ├── fill-model.md            ← BT-03
│   ├── deploy.md                ← OPS-06
│   ├── runbooks/
│   └── gates/G0..G5-*.md
├── src/tradie/
│   ├── strategy/    rules/, evaluate.py, params.py, registry.py
│   ├── data/        candles.py, cache.py, news.py, clock.py
│   ├── backtest/    engine.py, costs.py, walkforward.py, metrics.py, report.py
│   ├── execution/   broker.py, orders.py, reconcile.py, sizing.py
│   ├── risk/        breakers.py, exposure.py, state.py
│   ├── alerts/      telegram.py, outbox.py, fallback.py
│   ├── ops/         health.py, watchdog.py, cli.py
│   └── store/       db.py, migrations/
├── config.yaml
├── requirements.lock
├── .env                 ← never committed
├── .gitignore
└── tests/
    ├── fixtures/        ← rule fixtures, golden decisions
    ├── invariants/      ← one test per INV
    └── fault_injection/
```

*Note: v1's `src/config.yaml`, `src/state.json` and `scripts/backtest.py` are replaced — config at repo root, state in SQLite, and a single `tradie` entry point.*

---

## Appendix F — Environment variables

| Variable | Required | Notes |
|---|---|---|
| `OANDA_API_KEY` | ✅ | Practice and live tokens kept separate |
| `OANDA_ACCOUNT_ID` | ✅ | Bot is bound to this single account (SEC-05) |
| `OANDA_ENVIRONMENT` | ✅ | `practice` \| `live` — live additionally requires `--live` + confirmation |
| `TELEGRAM_BOT_TOKEN` | ✅ | Never logged (SEC-02) |
| `TELEGRAM_CHAT_ID` | ✅ | Allowlisted; all other chats ignored |
| `HEALTHCHECK_URL` | ✅ for live | Off-host dead-man switch |
| `FALLBACK_WEBHOOK_URL` | — | Non-Telegram escalation channel |
| `LOG_LEVEL` | — | Default `INFO` |

**Removed/relocated from v1:** `LOG_FILE_PREFIX` (now `ops.log_dir`), `NEWS_BLACKOUT_HOURS` (now `news.blackout_minutes`, resolving the ±30 min vs ±1 h contradiction), `NEWS_SOURCE` (now `news.source`).

---

## Appendix G — Changelog vs v1.0.0-draft

| v1 | v2 | Why |
|---|---|---|
| No gates; one "v1.0" release with F-01–F-10 | G0–G5 gates; v0.1 → v1.0 milestones | A solo 10-feature release is unpriced risk; gates make stopping early a success |
| OANDA v20 assumed available | G0 verifies it; BT-only is a valid outcome | Documented restriction for the operator's likely entity |
| `RULES_IDS` only (and partly wrong) | `docs/rule-spec.md` — 10 rules/checks from the real checklist; Appendix A.2 | v1 invented rule 8 (`CIRCUIT_BREAKERS`); the checklist's rule 8 is `MENTAL_STATE` |
| 9 rules = 9 atomic booleans on one bar | Staged setup state machine + `setups` table (`STR-07`, INV-10) | The conditions are sequential by construction; the atomic reading never trades |
| No treatment of `MENTAL_STATE` | `RSK-11` proxy + daily operator check-in (`STR-08`) | A bot cannot evaluate "not emotional"; deleting the rule silently would be worse |
| 3 months / WR ≥60% / Sharpe ≥1.2 | Walk-forward OOS, ≥100 trades, expectancy ≥0.10R, cost stress, CI reporting | Old gates pass on noise or on bugs |
| No costs anywhere | Cost model (App. D), cost drag in every report | 10–25% of edge |
| 3-month replay gate before live | 8-week *paper soak* + G5 minimum-size live | Calendar-bound evidence that actually reflects the system |
| ±30 min news (F-05) vs ±1 h (App. A) | ±45 min, single source of truth | Contradiction C-01 |
| "Min 1:2 RR" vs "Avg RR 1:1.8" in the sample | RR ≥2.0 asserted before submission; report flags <2.0 | Contradiction C-02 |
| 3% DD pause 4h / 2 losses pause 2h | L1–L5 precedence, 3% daily halt, 4% equity brake, risk 0.5–1% | C-05: unreachable at 1%, colliding at 2% |
| JSON state, no reconciliation | SQLite WAL, INV-3/4, EX-04/05, `panic` | Crash safety |
| `Order` TypedDict (invalid Python) | `Decision` dataclass + SQLite schema | C-08 |
| "lot size 0.015" | integer units + pip value + margin preflight | C-10, JPY sizing bug |
| VectorBT vectorised replay | Event-driven, one `evaluate()`; VectorBT optional later | Path-dependent rules; parity |
| `backtest.py` / `tradie.py --backtest` / `scripts/backtest.py` | `tradie backtest` | C-04 |
| `Tradie/backtests/` vs `reports/trades-*.csv` | `reports/backtest-<ts>.{json,csv,md}` | C-03 |
| "98% monthly uptime" | Loop availability ≥99.5% + off-host detection ≤5 min | Measurable, auditable |
| "≥90% rule logic coverage" | ≥4 fixtures + mutation test per rule | Coverage of a predicate that didn't exist |
| Heartbeat on the same host | systemd `WatchdogSec` + off-host dead-man switch | A host cannot report its own death |
| Telegram as only channel | ALR-04 fallback + ALR-03 outbox | Silent failure is the worst failure |
| "No manual override" (all) | Operator can halt/panic/resume, never force a trade | Stopping is not overriding |
| No correlation control | RSK-04 net-currency exposure cap | 4 USD-majors are one trade |
| No weekend policy | EX-08 Friday flatten default | Gap risk through static SL |
| "DAILY HYDRO SUMMARY" | "DAILY REPORT", with gross/costs/net split | Costs made visible; name unexplained |
| Brand: full section | Appendix B tokens retained | Still used by alerts |

---

## Appendix H — Open items requiring owner decision

Blocking; each needs a decision before the dependent milestone.

| # | Question | Blocks | Default if unanswered |
|---|---|---|---|
| H-01 | Does an OANDA account with v20 API access exist for your residency? Which entity? | **Everything** | Project proceeds as BT-only |
| H-02 | `guaranteedStopLossOrderMode`, `marginRate`, `hedgingEnabled`, account currency, account size | EX-06, RSK-01 | Plain SL, gap-risk flag on, risk 0.5% |
| ~~H-03~~ | ~~The 9 rules in concrete terms~~ **RESOLVED 2026-10-25** — `docs/source/Trading_Checklist.pdf` received; specified in `docs/rule-spec.md`, 13 decisions still open (D-01…D-13) | G1 | — |
| ~~H-04~~ | ~~Is `BIAS_ALIGNMENT_GATE` distinct from `BIAS_HTF`?~~ **RESOLVED** — no, it restates it; becomes INV-9 ⇒ 8 independent checks | STR-05 | — |
| H-05 | Realistic setups per day — is the 3-trade cap a ceiling you expect to hit, or a rail? | RSK-05, sample-size planning | Kept at 3; expect ~0.5–2/day |
| H-06 | Willing to run practice-only for ~2 months if G0 fails? | Roadmap | Assumed yes |
| H-07 | Is 5 pairs the right universe, or should correlated USD-majors be reduced to 2–3? | RSK-03/04 | Universe kept; exposure cap enforced |
| H-08 | News calendar: free + archived (fail-closed, no history), or paid with actuals? | ALR/RSK-09 | Free + daily archive; R8 backtested disabled and the gap documented |
| H-09 | **Exit / take-profit rule** — the checklist defines entries only (D-09) | R6, G2 | Fixed 1:2 from PRD v1 F-06 |
| H-10 | **Session/time filter** — none in the checklist; Asian-session sweeps are likely noise (D-10) | R2, G2 | None in v1 (not recommended) |
| H-11 | **50% of which leg** (D-05) and **chop metric** (D-04) — the two highest-leverage parameters | R3a, R4, G2 | Displacement leg; efficiency ratio ≥ 0.30 |
| H-12 | **Supply/demand zones** — referenced by rule 5 but never defined (D-08) | R5 | R4 zone doubles as the zone in v1 |
| H-13 | **Mental-state check-in** — accept a daily operator confirmation as the implementation of rule 8 (D-12) | RSK-11 | Check-in required; 30 min force-trade cooldown |

---

*[Tradie · PRD v2.0.0-proposed · 2026-10-25]*
*This document is confidential and intended for internal use only.*
