# Tradie — Rule Specification (G1 deliverable)

> **Version:** 0.1.0-draft
> **Date:** 2026-10-25
> **Status:** **DRAFT — G1 NOT PASSED.** Every `PROPOSED` value below needs owner ratification (see §10). G1 passes only when no `TBD` and no `PROPOSED` remains in a normative position.
> **Authority:** `docs/source/Trading_Checklist.pdf` ("01C — TRADING CHECKLIST (STRICT RULES)"). Where this document and the checklist disagree, **the checklist wins** and this document is wrong.
> **Implements:** PRD v2 `STR-01`, `STR-02`, `STR-03`, `STR-05`, `STR-06`
> **Draft answers:** `docs/decisions.md` — proposed answers to every decision below, for owner redline. Where they differ from §4, `decisions.md` wins (§4 revisions listed there).

---

## 0. Read this first — three findings that change the architecture

### Finding 1 — The 9 rules are a **sequence**, not 9 simultaneous booleans

The checklist reads as a progression:

> *bias → has price taken highs/lows → is structure shifting → retracement → engulfing confirmation → enter*

These conditions are established at **wildly different timescales**: bias on the daily (days), the sweep and structure shift on M15/H1 (hours), the retracement (hours), the engulfing candle (**a single 15-minute bar**).

The v1 PRD (F-03) specified: *"Evaluates the 9 pre-trade rules atomically on every M15 candle close. One rule failure = hard reject."* **Taken literally, that bot would almost never trade** — it would require a daily bias, a liquidity sweep, a structure shift, a 50% retracement and an engulfing candle to all be simultaneously true on one M15 bar. Those conditions are sequential by construction: the engulfing candle *is* the resolution of the retracement, which *follows* the structure shift, which *follows* the sweep.

**Therefore:** `evaluate()` is a **setup state machine**, not a conjunction over one bar. The setup has an identity, a lifetime, and it must survive process restarts. This is the single most consequential correction in this document (§3).

### Finding 2 — Only 7 of the 9 are mechanical, and rule 8 cannot be automated

| Checklist item | Verdict |
|---|---|
| 1–5 | Mechanical (given definitions in §4) |
| 6, 9 | Mechanical gates |
| 7 "BIAS ALIGNMENT" | **Not an independent condition** — it restates rule 1. Becomes an assertion (§5) |
| 8 "MENTAL STATE" | **Human-only. A bot cannot evaluate "not emotional".** Becomes a documented proxy + operator precondition (§6) |

So the honest count is: **5 staged price conditions + 2 gates + 1 assertion + 1 human precondition.**

The v1 PRD's rule list was also **wrong about rule 8**: it invented `CIRCUIT_BREAKERS` where the checklist has `MENTAL STATE`. Circuit breakers are a separate risk layer (PRD v2 `RSK-01`…`RSK-10`), not a checklist rule.

### Finding 3 — The checklist defines **entries**, and says nothing about exits

There is no take-profit, no target, no trailing, no exit condition anywhere in the checklist. "Risk management" covers sizing and stop placement only. **Exit logic must be specified by the owner** (D-09) — it is not derivable from this document. This is a genuine gap in the source material, not an oversight in transcription.

---

## 1. Source text (verbatim, for reference)

> **01C — TRADING CHECKLIST (STRICT RULES)**
> Before you take ANY trade, run through this. If one condition is missing → NO TRADE.
>
> **1. BIAS (HIGHER TIMEFRAME)** — Confirm clear direction/starting point to finish point (Bullish or Bearish). No guessing, no "it looks like". ■ No clear bias = NO TRADE
> **2. LIQUIDITY SWEEP** — Has price taken highs or lows? Is the sweep clean and obvious? ■ No liquidity taken = NO TRADE
> **3. MARKET STRUCTURE** — Is structure clean (not choppy)? Is it shifting in your bias direction? ■ Messy structure = NO TRADE
> **4. ENTRY MODEL** — Valid liquidity retracement (e.g. 50%). Setup aligns with bias. ■ No proper 50% retracement = NO TRADE
> **5. CONFIRMATION** — Clear 15mins engulfing candle on supply & demand before entry. No prediction entries. ■ No confirmation = NO TRADE
> **6. RISK MANAGEMENT** — Fixed risk per trade (no exceptions). Stop loss set BEFORE entry. ■ Overleveraging = NO TRADE
> **7. BIAS ALIGNMENT** — Only trade WITH your bias. ■ Buying in bearish / Selling in bullish (counter trade) = NO TRADE
> **8. MENTAL STATE** — Not emotional. Not forcing trades. Not chasing losses. ■ Bad mental state = NO TRADE
> **9. TRADE LIMIT** — Max 3 trades per day. ■ Overtrading = STOP
>
> **FINAL RULE** — "If I lose this trade, I'm okay because I followed all my rules." If you can't say that → DON'T ENTER.
> **REMEMBER:** Discipline pays. Impulse destroys. Trade like a pro, not a gambler.

---

## 2. Rule inventory

| # | Rule ID | Kind | Evaluated on | Timescale | Mechanical? |
|---|---|---|---|---|---|
| R1 | `R1_BIAS_HTF` | Regime | Broker-D (fallback H4) | Days | ✅ |
| R2 | `R2_LIQUIDITY_SWEEP` | Trigger | M15 (context H1) | Hours | ✅ |
| R3a | `R3a_STRUCTURE_QUALITY` | Filter | H1 | Hours | ✅ (needs metric) |
| R3b | `R3b_STRUCTURE_SHIFT` | Confirmation | M15 | Hours | ✅ |
| R4 | `R4_ENTRY_RETRACE` | Zone | M15 | Hours | ✅ |
| R5 | `R5_ENGULFING_CONFIRMATION` | Trigger | M15 | **One bar** | ✅ |
| R6 | `R6_RISK_MANAGEMENT` | Gate | Account | Pre-submit | ✅ |
| R7 | `R7_BIAS_ALIGNMENT` | **Assertion** | — | Pre-submit | ✅ (invariant) |
| R8 | `R8_MENTAL_STATE` | **Human → proxy** | Operator + state | Session | ⚠️ Partial |
| R9 | `R9_TRADE_LIMIT` | Gate | State | `trading_day` | ✅ |

**Directional coherence (worth stating explicitly, because it is the model's logic):** the trade direction *is* the bias direction (R1, R7). The sweep (R2) is therefore always of **counter-bias liquidity** — for a long setup in a bullish bias, price must sweep a prior **low**; for a short in a bearish bias, a prior **high**. This is the classic "liquidity grab before continuation" and it is the only reading that satisfies both rule 2 and rule 7.

---

## 3. Setup state machine

```
                     R1: bias resolved (D, fallback H4)
        IDLE ─────────────────────────────────────► BIASED
                                                      │
                     R2: counter-bias sweep            │
                     + R3a: structure clean enough     │
                                                      ▼
                              setup_id issued ──►  SWEPT
                                                      │  sweep_extreme recorded
                     R3b: MSS in bias direction        │
                                                      ▼
                                                  SHIFTED
                                                      │  leg = sweep_extreme → MSS_extreme
                                                      │  zone = 50% of leg ± tolerance
                     R4: price trades into zone        │
                                                      ▼
                                                  RETRACED
                                                      │
                     R5: engulfing close in zone       │
                                                      ▼
                                                 CONFIRMED
                                                      │
                     R6 + R9 + R8-proxy + breakers     │  (all must pass, else reject)
                                                      ▼
                                      SUBMIT ──► broker ──► IDLE
```

**Invalidation — any state returns to `IDLE`** (the setup is dead, not paused):

| Trigger | Effect |
|---|---|
| M15 close beyond `sweep_extreme` | Setup invalidated (the sweep failed) |
| Opposing MSS (structure shifts against bias) | Setup invalidated |
| `setup_ttl_bars` exceeded (PROPOSED 96 = 24h of M15) | Setup expires |
| R1 bias changes or becomes ambiguous | All setups on that instrument invalidated |
| Breaker `L3`/`L4`/`L5` active, or operator `halt` | Setups freeze, do not invalidate (resume on release) |
| `trading_day` rollover | Setups **carry over** (a setup begun at 23:50 is still valid at 00:10); only the R9 counter resets. See D-11 |

**Critical consequence for the data model:** the setup must be **persisted** and survive a daemon restart. A crash at `RETRACED` must not lose the setup. This adds a `setups` table (PRD v2 §8.2) and makes `Decision` reference `setup_id`.

---

## 4. Per-rule specification

Conventions: prices in instrument quote terms; `pip_size` = 0.0001 (0.01 for JPY pairs); all params `PROPOSED` until ratified. Every parameter must have a mutation test (changing it must change at least one fixture outcome), per PRD v2 §9.

```python
# Shared types
Bar   = {ts, open, high, low, close, volume, complete: bool}
Swing = {index, price, kind: "high"|"low", confirmed_at_index}
```

### R1 — `R1_BIAS_HTF`

| | |
|---|---|
| **Checklist intent** | "Clear direction/starting point to finish point (Bullish or Bearish). No guessing." |
| **Interpretation** | Bias = direction of the current **completed HTF leg**. "Starting point to finish point" is a swing leg: low→high = bullish, high→low = bearish. |
| **Granularity** | Broker-D (primary), H4 (fallback when D is unavailable/ambiguous) |
| **Parameters** | `htf = "D"` · `htf_fallback = "H4"` · `swing_left = 3` · `swing_right = 3` · `min_leg_bars = 5` · `conflict_policy = "no_trade"` |
| **Definition** | A *swing high* = bar whose high is strictly greater than the `swing_left` bars before and `swing_right` bars after (mirror for lows). A swing is *confirmed* only at `index + swing_right`. Bias: take the two most recent **confirmed** opposing swings. If the later is a high and the earlier is a low ⇒ **bullish**. If the later is a low and the earlier is a high ⇒ **bearish**. Otherwise ⇒ `none`. |
| **Fails when** | `Bias == none`; leg has fewer than `min_leg_bars`; D and H4 disagree and `conflict_policy == "no_trade"` |
| **Pseudocode** | `bias = leg_direction(last_confirmed_swing, previous_opposing_swing)`; `if bias == none → False` |
| **Evidence** | `bias`, `leg_start_ts`, `leg_start_price`, `leg_end_ts`, `leg_end_price`, `leg_bars`, `htf_used` |

**Ambiguities → decisions:** what if D is bullish but H4 is bearish? The checklist does not say. `conflict_policy = no_trade` (fail closed, consistent with "no guessing"); alternatives are D-wins or H4-wins. → **D-01**

**Alternative formalisations considered** (and why rejected as defaults): EMA(50) slope on D (too slow, and a slope is not a "leg with a start and finish"); HTF close vs a dealing-range midpoint (no explicit range in the checklist); higher-highs/higher-lows counting (equivalent to the leg definition but brittle in ranges).

---

### R2 — `R2_LIQUIDITY_SWEEP`

| | |
|---|---|
| **Checklist intent** | "Has price taken highs or lows? Is the sweep clean and obvious? No liquidity taken = NO TRADE" |
| **Interpretation** | Within the lookback window, price **traded beyond** a significant prior swing (counter to bias: low for longs, high for shorts) and then **closed back inside** the prior range. That is "taking liquidity". |
| **Granularity** | M15 (context H1) |
| **Parameters** | `lookback_bars = 96` · `swing_lookback = 48` · `min_penetration_pips = 1.0` · `max_penetration_pips = 20.0` · `require_reclaim_close = true` · `reclaim_within_bars = 1` (reclaim is the *same or next* bar) · `equal_level_tolerance_pips = 0.5` · `freshness_bars = 8` |
| **Definition** | Let `L` = most recent qualifying **sell-side** level (for long setups) = a confirmed swing low within `swing_lookback` bars, or the prior trading-day low, tolerance-adjusted for equal lows. Sweep = ∃ bar `b` in the last `freshness_bars` where `b.low < L - min_penetration` **and** `b.low > L - max_penetration` **and** (`b.close > L`) within `reclaim_within_bars`. Mirror for buy-side levels (swing high / prior day high) for shorts. |
| **Fails when** | No level swept; penetration below min (noise) or above max (not a sweep, a breakout); no reclaim close (price accepted below ⇒ continuation, not a grab); sweep older than `freshness_bars` |
| **Evidence** | `swept_level`, `swept_level_kind`, `swept_level_source` (swing / prior-day), `penetration_pips`, `reclaim_bar_offset`, `sweep_extreme`, `sweep_bar_index` |
| **Sets** | `setup_id`, `sweep_extreme` (= the extreme of the sweep leg — the invalidation level and, later, the SL anchor) |

**"Clean and obvious" quantified:** single- or two-bar penetration (not a grind), bounded penetration (`max_penetration_pips`), and an immediate reclaim (`reclaim_within_bars ≤ 2`). A slow multi-bar break with no reclaim is a **breakout** and must be rejected — this is the parameter that separates the two. → **D-02** (bounds and reclaim timing)

**Ambiguities:** do *equal* highs/lows (double tops) count as one level? PROPOSED: yes, within `equal_level_tolerance_pips`. Are session/Asian-range extremes valid levels, or only swing points? PROPOSED: swing points + prior-day high/low only, for v1. → **D-03**

---

### R3a — `R3a_STRUCTURE_QUALITY` (the chop filter)

| | |
|---|---|
| **Checklist intent** | "Is structure clean (not choppy)? Messy structure = NO TRADE" |
| **Interpretation** | A regime filter: the leg *into* the sweep must be directional, not overlapping/choppy. |
| **Granularity** | H1 (windowed), evaluated at the sweep bar |
| **Parameters** | `metric = "efficiency_ratio"` · `er_window_bars = 20` · `er_min = 0.30` · `max_swing_density = 6` (swings per 20 bars) |
| **Definition** | Kaufman Efficiency Ratio over the `er_window_bars` ending at the sweep bar: `ER = abs(close[t] - close[t-n]) / Σ abs(close[i] - close[i-1])`. Pass if `ER ≥ er_min` **and** confirmed swing count in that window `≤ max_swing_density`. |
| **Rationale** | ER = 1.0 is a perfect trend; ~0.1 is pure chop. It is a single, well-understood, testable number — and `max_swing_density` catches the case ER misses (overlapping bars that still net-move). |
| **Fails when** | Either condition fails |
| **Evidence** | `er`, `er_window_bars`, `swing_density` |

**Why a metric and not "looks messy":** every other candidate (ADX, ATR expansion, body/range ratio, "number of structure breaks") was considered. ER is preferred because it is scale-free across the 5 pairs (no per-pair threshold tuning) and has exactly one parameter with an intuitive anchor. → **D-04** (threshold; must be tuned on a fixture set, not on P&L)

---

### R3b — `R3b_STRUCTURE_SHIFT` (MSS)

| | |
|---|---|
| **Checklist intent** | "Is it shifting in your bias direction?" |
| **Interpretation** | After the sweep, price **closes beyond** the swing point that formed between the sweep extreme and the reversal — a market structure shift (MSS) in the bias direction. |
| **Granularity** | M15 |
| **Parameters** | `mss_level_source = "intervening_swing"` · `require_close_beyond = true` · `max_bars_after_sweep = 24` · `min_displacement_atr = 0.5` |
| **Definition** | Let `S` = the first confirmed swing **point** in the bias direction formed after `sweep_extreme` (for a long setup: the swing **high** between the sweep low and the current bar). MSS = an M15 **close** `> S.price` within `max_bars_after_sweep` of the sweep bar = bullish MSS. Displacement gate: the move from `sweep_extreme` to the MSS close must be `≥ min_displacement_atr × ATR(14)` — this rejects a limp drift through the level. |
| **Fails when** | No intervening swing found; no close beyond it in time; displacement too small; opposite MSS occurs first |
| **Evidence** | `mss_level`, `mss_close`, `bars_after_sweep`, `displacement_atr` |
| **Sets** | `leg = (sweep_extreme → MSS close)`, which R4 measures the retracement against |

**Design note:** R2 + R3b together are the recognisable "sweep → MSS" pattern. Specifying them jointly (rather than as independent booleans) is what makes them testable — the level R3b must break is defined by R2's output, not by a global "structure".

---

### R4 — `R4_ENTRY_RETRACE`

| | |
|---|---|
| **Checklist intent** | "Valid liquidity retracement (e.g. 50%). Setup aligns with bias. No proper 50% retracement = NO TRADE" |
| **Interpretation** | After the MSS, price retraces into the **50% area of the displacement leg** and the entry is taken from there. |
| **Granularity** | M15 |
| **Parameters** | `retrace_anchor = "sweep_extreme_to_mss_close"` · `retrace_target = 0.50` · `zone_low = 0.45` · `zone_high = 0.55` · `setup_ttl_bars = 96` |
| **Definition** | `leg_len = abs(mss_close - sweep_extreme)`; for a long setup `zone = [mss_close - zone_high×leg_len, mss_close - zone_low×leg_len]`. Pass when any completed M15 bar's range **intersects** `zone` before `setup_ttl_bars`. |
| **Fails when** | Price never reaches the zone (setup expires); price closes beyond `sweep_extreme` (invalidation — priority over a late retrace) |
| **Evidence** | `leg_len_pips`, `zone_low`, `zone_high`, `retrace_bar_ts`, `retrace_depth` (actual %) |
| **Sets** | `zone` (used by R5) |

**The most consequential ambiguity in the whole checklist:** "50%" **of what leg?** Three defensible anchors:

| Anchor | Meaning | Consequence |
|---|---|---|
| **A. sweep_extreme → MSS close** | The displacement leg (PROPOSED) | Tight, fast, high trade frequency; deepest relevance to the setup |
| B. HTF dealing range | 50% of the daily leg from R1 | Far away; setups often expire unfilled; lower frequency, higher RR |
| C. Last opposite leg into the sweep | The impulse that created the sweep | Between A and B; different failure modes |

"e.g. 50%" also implies 50% is an *example*, not a mandate — so the zone bounds (`.45–.55`) and the target itself are both owner decisions. → **D-05**

---

### R5 — `R5_ENGULFING_CONFIRMATION`

| | |
|---|---|
| **Checklist intent** | "Clear 15mins engulfing candle on supply & demand before entry. No prediction entries." |
| **Interpretation** | A completed M15 bar that (a) engulfs the prior bar and closes in the bias direction, and (b) occurs inside the R4 zone. Entry is taken **only after that bar closes** — "no prediction" = no intrabar entry. |
| **Granularity** | M15 |
| **Parameters** | `engulf_mode = "body_and_range"` · `min_body_ratio = 0.50` · `zone_overlap_required = true` · `entry_timing = "next_bar_open"` · `max_spread_multiple = 2.0` |
| **Definition (long)** | `bar.complete == true` **and** `bar.close > bar.open` **and** `bar.close > prev.high` **and** `bar.open <= prev.close` **and** `body_ratio = (bar.close-bar.open)/(bar.high-bar.low) ≥ min_body_ratio` **and** `bar.low ≤ zone_high + tol` **and** `bar.high ≥ zone_low - tol`. Mirror for short. |
| **Fails when** | Candle incomplete (`complete == false`) — **this is the "prediction" guard**; not engulfing; body ratio too small (doji-like); bar does not overlap the zone |
| **Evidence** | `body_ratio`, `engulf_depth_atr`, `zone_overlap_pips`, `spread_at_decision` |

**Two decisions:**
1. **`engulf_mode`** — body-engulf only (common, more signals) vs full-range engulf (`close > prev.high`, stricter, fewer signals). PROPOSED strict. → **D-06**
2. **"on supply & demand" is an undefined dependency.** The checklist references supply/demand zones but never defines them, and no other rule produces a zone. Two readings: (i) the R4 50% zone *is* the demand/supply area — **PROPOSED for v1**, which removes the undefined term; (ii) an explicit order-block / FVG detector is required. Option (ii) is a real feature, not a parameter, and belongs in v1.1 if the owner means it. → **D-08**

---

### R6 — `R6_RISK_MANAGEMENT` (gate)

| | |
|---|---|
| **Checklist intent** | "Fixed risk per trade (no exceptions). Stop loss set BEFORE entry. Overleveraging = NO TRADE" |
| **Definition** | Pass iff: `risk_pct` equals the configured value (no dynamic adjustment) **and** a valid `sl_price` exists before submission (attached `onFill`) **and** computed `units` do not exceed the risk-derived size **and** `margin_available` covers the position (PRD v2 `EX-02`/`EX-03`) **and** `rr_actual ≥ min_rr`. |
| **Parameters (from PRD v2 RSK-01)** | `risk_per_trade_pct = 0.75` (range 0.50–1.00) · `sl_buffer_pips = max(1.5 × spread, 3.0)` · `min_rr = 2.0` |
| **SL placement — not specified in the checklist** | Checklist says *when* to set the SL ("BEFORE entry"), not *where*. PROPOSED: beyond `sweep_extreme` by `sl_buffer_pips`, because that is the setup's logical invalidation level (if price exceeds it, R2 was wrong). This is the only mechanically-derived choice available. → **D-07** |
| **Evidence** | `risk_pct`, `risk_amount`, `units`, `sl_price`, `sl_distance_pips`, `rr_actual`, `margin_used` |

**⚠️ RR feasibility warning.** SL distance is set by structure (sweep extreme), while the TP is set by D-09. If the structural SL is wide (say 35 pips on GBP/USD) and the nearest HTF target is 40 pips away, then `rr_actual = 1.14 < min_rr = 2.0` ⇒ **the trade is rejected by R6 and never taken.** That is the correct behaviour, but it means `min_rr` and `sl` placement **jointly determine trade count**. Expect a real risk that a structure-based SL + 1:2 TP + a fixed-TP rule produces very few trades, or none. This interaction must be measured at G2 before `min_rr` is treated as fixed. → **D-09, D-10**

---

### R7 — `R7_BIAS_ALIGNMENT` → **assertion, not a rule**

| | |
|---|---|
| **Checklist intent** | "Only trade WITH your bias. Buying in bearish / Selling in bullish (counter trade) = NO TRADE" |
| **Reading** | This restates R1. It is not an independent market condition — there is no state of the world where R1 = bullish and R7 legitimately fails. It is a **guard against a coding error**, not a filter. |
| **Implementation** | `assert sign(direction) == bias` at the submit boundary (PRD v2 **INV-9**). A failure is a **bug**, not a rejection: it must raise, alert, and refuse to trade — never silently reject and continue. |
| **Why it still matters** | It is the operator's explicit statement of the model's core discipline, so it stays in the spec and in the journal — but as an invariant with a unit test, not as a `dict[str, bool]` entry that can be puzzled over in a report. |

**This resolves PRD v2 open item H-04.** Rules 1 and 7 are the same condition; there are **8 independent checks**, not 9.

---

### R8 — `R8_MENTAL_STATE` → **human precondition + mechanical proxy**

| | |
|---|---|
| **Checklist intent** | "Not emotional. Not forcing trades. Not chasing losses. Bad mental state = NO TRADE" |
| **Problem** | **This cannot be evaluated by software.** Any system that reports `MENTAL_STATE = true` is lying. Compounding it, there is no human in the loop at decision time, so the rule is *vacuously* satisfied by delegation — which means it silently disappears unless it is deliberately re-expressed. |
| **Three-part treatment** | **1. Structurally satisfied:** the bot makes no discretionary decisions, so "emotional" entries are impossible by construction. This is real, but it covers only the first clause. **2. Mechanically proxied:** "not chasing losses" → loss-streak breaker (`RSK-06`, L3: 2 losses ⇒ 2h pause). "not forcing trades" → `R9` cap + `R4` `setup_ttl_bars` (a setup that expires cannot be chased) + `R3a` chop filter. **3. Human precondition (PROPOSED):** `require_daily_checkin: true` — the operator confirms the mental-state check once per `trading_day` (`tradie session check-in`, recorded in `events`). No check-in ⇒ no entries, positions still protected. |
| **Params** | `require_daily_checkin = true` · `checkin_valid_until_utc = "23:59"` · `force_trade_cooldown_min = 30` (no entry within 30 min of a realised loss) |
| **Fails when** | Check-in absent or stale; `force_trade_cooldown` active; L3 breaker active |
| **Evidence** | `checkin_ts`, `cooldown_remaining_min`, `proxy_reason` |

**Design justification:** this preserves the trader's actual discipline instead of quietly deleting it. It converts an unmeasurable rule into (a) explicit auditable state and (b) a small set of hard mechanical constraints. It also gives the operator a daily moment of agency, which is the part of the checklist that a bot can never take over. → **D-12**

---

### R9 — `R9_TRADE_LIMIT` (gate)

| | |
|---|---|
| **Checklist intent** | "Max 3 trades per day. Overtrading = STOP" |
| **Definition** | `trades_opened_today < daily_trade_cap`. Note "**STOP**", not "no trade": reaching the cap halts entries for the remainder of the `trading_day` (it is a stop, not a per-signal rejection). |
| **Params** | `daily_trade_cap = 3` · `trading_day_tz = "UTC"` · `count_scope = "opened"` (opened trades count, regardless of outcome) |
| **Fails when** | Cap reached or exceeded |
| **Evidence** | `trades_opened_today`, `cap`, `next_reset_ts` |

---

## 5. Evaluation order and short-circuiting

```
1. R9  trade limit          (cheapest: integer compare)
2. R6  risk / margin        (account state)
3. R8  mental-state proxy   (session state)
4. R1  bias                 (HTF, once per D candle — cache)
   ── from here, only if a setup already exists ──
5. R2  sweep                (creates setup_id)
6. R3a structure quality
7. R3b structure shift
8. R4  retracement zone
9. R5  engulfing confirmation → Decision(direction≠None)
10. R7 assertion (raises on failure, never a soft reject)
```

Gates first (cheap, and keeps the rejection funnel meaningful). Within a setup, order is the state machine's order. This ordering must be **stable**, because the rejection funnel in the daily report attributes every non-trade to exactly one rule.

---

## 6. Ambiguity register — every qualitative word, and what it costs

Each "clear / clean / obvious / valid / proper" in the checklist is a **specification gap**, not a stylistic choice. They are the source of nearly all remaining implementation risk.

| # | Checklist words | Hidden decision | PROPOSED default | Decision |
|---|---|---|---|---|
| A-1 | "clear direction … no guessing" | How is bias measured, and what if D and H4 disagree? | Swing-leg on D, conflict ⇒ no trade | **D-01** |
| A-2 | "clean and obvious" (sweep) | Penetration bounds, reclaim timing, how many bars | 1–20 pips, reclaim ≤2 bars | **D-02** |
| A-3 | "taken highs or lows" | Which levels qualify (swings, session, prior day, equal highs) | Swings + prior-day extremes | **D-03** |
| A-4 | "clean (not choppy)" | A numeric chop metric + threshold | Efficiency ratio ≥ 0.30 over 20 bars | **D-04** |
| A-5 | "valid … (e.g. 50%)" | **50% of which leg?** And is 50% the target or an example? | displacement leg, zone 45–55% | **D-05** |
| A-6 | "clear engulfing" | Body-engulf vs full-range; minimum body ratio | full-range + body ≥ 50% | **D-06** |
| A-7 | "Stop loss set BEFORE entry" | *Where* is the SL? By how much beyond the level? | beyond sweep extreme + buffer | **D-07** |
| A-8 | "on supply & demand" | **Term used but never defined anywhere** | R4 zone *is* the zone (v1) | **D-08** |
| A-9 | (absent) | **No exit / TP rule at all** | 1:2 fixed (from PRD v1 F-06) | **D-09** |
| A-10 | (absent) | No session/time-of-day filter | none in v1 (flagged as likely needed) | **D-10** |
| A-11 | "Max 3 trades per day" | Does a setup cross the day boundary? | setups carry over; only counter resets | **D-11** |
| A-12 | "not emotional / not forcing / not chasing" | Machine proxy + operator check-in | check-in + L3 + cooldown | **D-12** |
| A-13 | "shifting in your bias direction" | The MSS break level and whether a close (not a wick) is required | intervening swing, close required | **D-13** |

---

## 7. Fixtures

Every rule needs ≥2 pass and ≥2 fail fixtures (G1). Fixtures are **synthetic bar sequences** committed under `tests/fixtures/rules/<rule>/`, each with an annotation of the decisive bar and a one-line reason. Synthetic is deliberate: real historical carve-outs cannot be shared in the repo (data licence) and cannot be regenerated.

| Rule | Pass fixtures | Fail fixtures (the *interesting* ones) |
|---|---|---|
| R1 | clean D uptrend (HL→HH); clean D downtrend | (a) range with no valid leg pairs; (b) impossible bar (low > high); (c) D bullish / H4 bearish (conflict) |
| R2 | sweep of swing low + reclaim; sweep of prior-day low + reclaim | (a) clean **breakout** with no reclaim; (b) 0.5-pip wick (below `min_penetration`); (c) 40-pip penetration (above max); (d) sweep 20 bars ago (stale) |
| R3a | strong directional leg (ER ≈ 0.6) | (a) overlap-heavy chop (ER ≈ 0.15); (b) net-flat but high swing density |
| R3b | close above intervening swing high + displacement | (a) wick above level, close below (no MSS); (b) MSS 30 bars after sweep (too late); (c) MSS **against** bias |
| R4 | retrace to exactly 50%; retrace to 47% | (a) retrace to 20% then new high (never reaches zone); (b) setup expires at 96 bars; (c) price breaks `sweep_extreme` first |
| R5 | full-range engulf in zone; body ratio 0.62 | (a) `complete == false` (the prediction guard); (b) bullish engulf **outside** the zone; (c) doji, body ratio 0.1 |
| R6 | 0.75% risk, structural SL, rr = 2.3 | (a) rr = 1.4 (below min); (b) margin insufficient; (c) units rounded over the risk cap |
| R7 | direction matches bias | mismatch ⇒ **raises** (assertion test, not a rejection) |
| R8 | fresh check-in, no cooldown | (a) no check-in; (b) 5 min after a realised loss |
| R9 | 2 trades today | (a) 3 trades ⇒ stop; (b) 00:00 UTC resets to 0 |

**Mutation tests:** for each parameter, a fixture pair must exist where changing only that parameter flips the outcome. A parameter with no such fixture is either dead code or under-specified — both are G1 failures.

---

## 8. What is still missing from the strategy (not from this document)

These are *strategy* gaps discovered while formalising the checklist. None can be resolved by a coding decision:

1. **No exit/TP rule** (D-09). Blocks R6's `rr_actual` check from being meaningful.
2. **No session filter** (D-10). ICT-style sweep→MSS patterns are session-dependent; without a filter the Asian session will generate the majority of sweeps, most of them noise. Strongly recommend adding a London + NY window in v1.
3. **No instrument-selection rule.** With 5 pairs, several may present valid setups on the same bar; nothing in the checklist says which to take. PROPOSED: take all that pass, subject to `max_concurrent_positions = 2` and the currency-exposure cap (`RSK-03/04`).
4. **No invalidation semantics** for "bias changed mid-setup" — this document proposes invalidate-all; the checklist is silent.
5. **No rule for what happens after the 3rd trade** — the checklist says STOP; this document reads that as halt-for-the-day, not halt-for-the-hour.

---

## 9. Consequences for the PRD

| PRD v2 item | Change required |
|---|---|
| `STR-01`/`STR-02` | Replace "9 rules as pure predicates over one `MarketView`" with **staged state machine** over a persisted setup |
| `STR-05` | **Resolved**: R7 is an assertion (INV-9); 8 independent checks |
| Data model §8.2 | **Add `setups` table** (`setup_id`, `instrument`, `state`, `state_entered_at`, `sweep_extreme`, `mss_level`, `zone_low/high`, `expires_at`, `strategy_version`) |
| `Decision` | Add `setup_id`, `setup_state`, `retrace_depth`, `body_ratio`, `displacement_atr`, `er` |
| Invariants | **Add INV-9** (bias alignment assertion) and **INV-10** (setup state persists; a restart mid-setup resumes, never resets) |
| `RSK-*` | Add `RSK-11` mental-state proxy + daily check-in |
| G1 pass criteria | Rule spec exists ✅, but **13 open decisions (D-01…D-13)** remain ⇒ G1 **not** passed |
| Appendix A | Replace the invented rule inventory with §2 of this document |
| Appendix H | `H-03` ✅ resolved (checklist received); `H-04` ✅ resolved (R7 = assertion); **new** `H-09…H-13` for the strategy gaps in §8 |

**Sequencing note:** G1 is **independent of G0**. The broker question blocks *all* code that touches OANDA, but the rule specification blocks nothing — it can be advanced now, while G0 is unresolved. Recommendations: do D-01 through D-13 first, in order of how much they change results (D-05, D-04, D-09, D-01 are the biggest levers).

---

## 10. Decisions required (G1 exit criteria)

Each needs an owner answer. Defaults below are what the code will assume if unanswered — they are **not** recommendations to skip the decision.

| ID | Decision | Options | Default if unanswered | Leverage |
|---|---|---|---|---|
| **D-01** | Bias definition + D/H4 conflict | swing-leg / EMA slope / range-midpoint · conflict ⇒ no_trade / D-wins / H4-wins | swing-leg on D, conflict ⇒ no trade | **High** |
| **D-02** | Sweep bounds + reclaim | penetration min/max; reclaim within N bars | 1–20 pips, ≤2 bars | Med |
| **D-03** | Which levels can be swept | swings only / + prior day / + session / + equal highs | swings + prior day | Med |
| **D-04** | Chop metric + threshold | efficiency ratio / ADX / swing density | ER ≥ 0.30, n = 20 | **High** |
| **D-05** | **50% of which leg** + zone width | displacement leg / HTF range / prior impulse · 45–55% / 50–61.8% | displacement leg, 45–55% | **Highest** |
| **D-06** | Engulf definition | body-only / full-range · min body ratio | full-range, body ≥ 50% | Med |
| **D-07** | SL placement | beyond sweep extreme + buffer / ATR-based / beyond zone | sweep extreme + max(1.5×spread, 3p) | **High** |
| **D-08** | Supply/demand zones | R4 zone is the zone / explicit OB or FVG detector | R4 zone (v1); OB/FVG = v1.1 | Med |
| **D-09** | **Exit / TP rule** | fixed RR / opposite liquidity / HTF level / structure | fixed 1:2 | **Highest** |
| **D-10** | Session filter | none / London / London+NY / killzones | none in v1 (**recommend London+NY**) | **High** |
| **D-11** | Setup across day boundary | carry over / invalidate at 00:00 UTC | carry over | Low |
| **D-12** | Mental-state proxy | check-in on/off; cooldown minutes | check-in on, 30 min cooldown | Med |
| **D-13** | MSS break level | intervening swing / last swing / prior bar high · close vs wick | intervening swing, close required | **High** |

**G1 passes when:** D-01…D-15 are answered, §4 contains no `PROPOSED`, every rule has ≥2 pass + ≥2 fail fixtures in the repo, and every parameter has a mutation test.

> **Two decisions were surfaced while drafting the answers** and are not in the table below: **D-14** (tie-break when two setups compete for one slot — required for determinism) and **D-15** (a new sweep while a setup is live — replace vs ignore). Both are specified in `docs/decisions.md` §2.

---

*[Tradie · rule-spec v0.1.0-draft · 2026-10-25]*
*Source authority: `docs/source/Trading_Checklist.pdf`. Confidential — internal use only.*
