# Tradie — G1 Decisions (draft for redline)

> **Version:** 1.0.0-RATIFIED
> **Date:** 2026-10-25
> **Status:** **RATIFIED by owner (Va_d3R), 2026-10-25.** Answers recorded in §0a. G1 is unblocked; fixture writing is the remaining task.
> **Note:** §2 keeps the original reasoning for the record. Where an owner answer differed from my recommendation, §0a overrides §2 and the deviation is called out.
> **Implements:** `rule-spec.md` §10 (D-01…D-13), plus D-14/D-15 surfaced while drafting
> **Supersedes:** where this document differs from `rule-spec.md` §4, **this document wins** (see §5 for the three revisions and why)

---

## How to use this

Each decision has a recommendation, the reasoning, the alternatives I rejected, and what to watch for. I have written these as **my best answers, not placeholders** — so you can do one of three things per decision:

- **Accept** — tick it; it goes into `config.yaml` and the fixture set.
- **Modify** — write your value in the margin; the reasoning tells you which knob you're turning.
- **Reject** — say why; §5's sensitivity map shows what to watch if you go the other way.

**The fastest useful response is not "yes to all 15."** It's "yes to all, except D-05 and D-09" plus your answer on those two. Those two determine whether this strategy trades once a week or once a month, and whether expectancy is measurable at all.

⚠️ **Read §4 before approving anything.** The conjunction of these rules is far more selective than it looks on paper. My estimate is **~65–130 trades/year** across 5 pairs. That has consequences for how long G2 and G4 take, and it is the single largest planning fact in this project.

---

## 0a. Ratified answers (2026-10-25)

Owner answers verbatim, then the resolved parameter. **Deviations from my recommendation are marked ⚠️ and explained.**

| ID | Owner answer | Resolved as | Deviation |
|---|---|---|---|
| D-01 | Option A | Swing-leg on D; **D authoritative, H4 advisory** | — |
| D-02 | Option A | Penetration `max(1p, 0.05×ATR)`–`0.60×ATR`; reclaim close ≤2 bars | — |
| D-03 | Option A *(question answered in §0b)* | M15 swings + prior-day high/low; equal levels merge | — |
| D-04 | No figure given; "not choppy can also mean the market being in a range" | **Efficiency Ratio ≥ 0.30 over 20 H1 bars** + swing density ≤ 6, **plus a new range-detection check** (§0c) | ⚠️ Owner added a requirement: a *ranging* market is also "choppy". ER alone does not catch a tight range with small net movement — added `range_compression` test |
| D-05 | **Option C**, "50% of the most recent low or high" | **Prior-impulse leg**: most recent opposing swing → sweep extreme. Zone 45–55% | ⚠️ Differs from my recommendation (A). See §0d for the directional worked example |
| D-06 | Option A | Full-range engulf + body ≥ 50% | — |
| D-07 | Option A | Beyond sweep extreme by `max(1.5×spread, 0.15×ATR)`, min 8 pips | — |
| D-08 | **Option C + B combined** (FVG **and** order block) | **POI = OrderBlock ∩ FVG.** Confirmation must occur inside the POI | ⚠️ Strictly more selective than my rec (A); see §0e |
| D-09 | **Option A, fixed 1:3** | `take_profit_rr = 3.0`, `min_rr = 3.0` | ⚠️ 1:2 → 1:3. Break-even win rate rises to **25%**; see §0f |
| D-10 | Option A | 07:00–16:00 UTC entries only | — |
| D-11 | Option A | Setups carry across midnight UTC | — |
| D-12 | Option A | Daily check-in + 30 min loss cooldown | — |
| D-13 | Option A | Intervening swing, close beyond, ≥0.5×ATR displacement | — |
| D-14 | Option A | Rank by `rr_actual` desc, then instrument A→Z | — |
| D-15 | **Keep the old setup; record the new sweep** | Active setup is **not** replaced. A new sweep is recorded as `SUPERSEDED_CANDIDATE` in the journal and ignored for trading until the active setup resolves | ⚠️ Differs from my rec (replace). Implemented as "sticky setup" |
| D-16 | **Option C — add pairs** | Universe expands **5 → 12 pairs** (§0g) | — |
| D-17 | Yes | Fixtures to be written | — |

**Two consequences worth stating plainly:**

1. **D-09 (1:3) + D-08 (OB∩FVG) are both frequency-reducing**, and they land on the same axis. Against the §3 estimate of 35–130 trades/year, 1:3 alone cuts the accepted-trade count further (wider target), and OB∩FVG cuts confirmations again. **D-16 (add pairs) is now load-bearing, not optional** — it is the only choice in your answers that increases sample size. Even so, instrument the funnel first (§3) before trusting any of these numbers.
2. **D-05 option C is a real strategy change from what I recommended.** It is directionally *deeper* than the displacement leg — the retracement target sits further from the sweep extreme. That means fewer, deeper fills: better average entry, fewer trades. Combined with 1:3 and OB∩FVG, expect a low-frequency, high-selectivity system. That may be exactly the strategy you want — I am flagging the composition, not objecting to the choice.

---

## 0h. D-18 & D-19 — sizing and the capital cooldown (added 2026-10-25)

Two operator instructions received after ratification.

### D-18 — Fixed 0.01 lots per trade (RATIFIED)

Every trade uses **0.01 lots**, regardless of balance or SL distance. Implemented as `InpSizingMode = SIZING_FIXED_LOT`, `InpFixedLots = 0.01`.

**What this changes:** `RSK-01` ("risk 0.5–1.0% per trade") **no longer describes what the EA does.** With a fixed lot, risk per trade is a *consequence* of the stop distance and account size, not a control. The EA now logs the actual risk on every trade:

```
Tradie sizing: 0.01 lots | SL 32.4 p | risk 3.24 (0.32% of balance)
```

| Account | 0.01 lots, 30-pip SL | Actual risk/trade |
|---|---|---|
| $500 | ~$3 | **0.6%** |
| $2,000 | ~$3 | 0.15% |
| $10,000 | ~$3 | **0.03%** — negligible; 35% loss would need ~1,100 losing trades |

**Consequence for D-19:** the cooldown threshold is *absolute* (35% of capital) while the loss rate is now *fixed in currency*. On a large account the cooldown is effectively unreachable; on a small account it is reachable and quite fast. **This coupling is the most important thing to understand about these two changes together.**

`InpRiskPercent` is retained but only used when `InpSizingMode = SIZING_RISK_PERCENT`.

### D-19 — Cooldown after 35% of capital is lost (RATIFIED)

Measured on **this EA's own trades only** (magic-filtered), realised + floating:

```
lossPct = -(realisedPnL + floatingPnL) / referenceCapital * 100
```

Trigger at `InpCooldownLossPct = 35.0`. Defaults: pause **168 h (7 days)**, flatten open EA positions, re-anchor on expiry.

Implementation decisions I had to make, stated for the record:

| Question | Answer | Why |
|---|---|---|
| Reference capital — fixed or rolling? | **Fixed**, captured at first init, persisted in a terminal global variable | A rolling reference can be outrun: the balance shrinks as you lose, so a % of *remaining* capital recedes and never triggers |
| Count other trades on the account? | **No** — magic-filtered only | "lost to the EA" was the wording; account-wide would trigger on someone else's trades |
| Include floating P&L? | **Yes** | A 35% drawdown that is still open is the same drawdown |
| What happens after the 7 days? | **Re-anchor** to the new balance (`InpCooldownReanchor`) | Without this the loss is still ≥35% and the check re-arms instantly, forever — a permanent halt. Re-anchoring means repeated losses compound: 100 → 65 → 42 → 27 |
| Flatten positions on trigger? | **Yes** by default (`InpCooldownFlatten`) | It is a stop-trading event, not a pause-for-lunch; leave `false` if you would rather let existing trades run to SL/TP |

### ⚠️ The arithmetic you should see before running this

**35% is not a risk control. It is a last-resort kill switch that fires long after the damage.**

1. **Recovery maths:** after −35% you need **+53.8%** to get back to even. After −35%, −35% again you are at −57.75% and need **+137%**.
2. **It contradicts the PRD by ~9×.** `RSK-08` (the equity brake) is **4%**. This cooldown sits at 35% — meaning the EA can lose nearly nine times what the PRD considers an emergency before anything stops it. The PRD's L1–L5 breaker stack (daily loss halt 3%, streak pause, 4% equity brake) is **not implemented in the EA at all**; D-19 is not a substitute for it.
3. **At 1:3 with ~30% winners, a 35% drawdown is plausible in normal operation.** Sequences of 8–10 consecutive losers happen routinely at 30% win rate (expect one in roughly every 30–60 trades). At 0.01 lots on a $500 account (~0.6% risk/trade), 10 straight losses ≈ −6%. So on a small account the cooldown is comfortably far; but if you ever raise lot size, the same streak becomes far more expensive **while the 35% trigger stays fixed in percentage** — the trigger does not scale with lot size.

**Recommendation, if you want one:** keep 35% as the absolute backstop, and add a *second, lower* threshold — e.g. 15% — that pauses for 24 h without flattening. Two-stage is how you get "stop and think" without waiting for catastrophe. Say the word and I will add it; it is ~20 lines reusing the same machinery.

---

## 0b. Owner question: "is D-03 about the entry?"

**No.** D-03 is about **which price levels are allowed to be the thing that gets swept** — it is a filter on rule 2 (liquidity sweep), which happens *before* the entry.

Concretely, for a long setup: price must take out a prior **low**. D-03 decides *which* lows count as valid targets:

- a swing low formed on the M15 chart, or
- yesterday's low, or
- (rejected for v1) the Asian-session low, London low, etc.

Why it matters: "liquidity" in your checklist means *stops sitting above/below a visible level*. If you count too many levels, everything looks like a sweep; if too few, you never get one. The entry itself is R4 (retracement) + R5 (engulfing) — D-03 never touches it.

---

## 0c. D-04 — adding the range check the owner asked for

Owner: *"not choppy can also mean the market being in a range."*

Correct, and ER alone misses it. A market can oscillate in a tight band with a decent net move and still be untradeable. Added as a second, independent condition:

```
range_compression = (highest(high, 20 H1) - lowest(low, 20 H1)) / ATR(H1, 20)
pass if range_compression >= InpMinRangeATR   (default 2.0)
```

**Plain meaning:** the last 20 hours must span at least **2× the average H1 bar range**. Below that, price is coiled in a range too tight for a 1:3 target to be reachable. This is not a chop detector so much as a *"is there room to move"* detector — which is precisely what a rage-bound market fails.

R3a now requires: `ER ≥ 0.30` **AND** `swing_density ≤ 6` **AND** `range_compression ≥ 2.0`.

---

## 0d. D-05 option C — the worked example (read this, it is the one I'd check)

**Bullish setup (bias up, sweeping a low):**

```
        H0  ← most recent swing high BEFORE the sweep (= prior impulse origin)
         \
          \        ← the prior impulse (this is the leg we measure)
           \
            L0 ──────── sweep extreme (the low that got taken)
              \  ← sweep
               \        M1  ← MSS close (price rallies through structure)
                \      /
                 \    /
                  \  /   ← retracement
                   \/    ← 50% of H0→L0 ... entry zone lives HERE
                    │
                    └─ engulfing confirmation
```

- Leg = `H0 → L0` (the move that **created** the sweep — option C)
- 50% level = `L0 + 0.5 × (H0 − L0)`
- Zone = 45–55% of that leg, i.e. `±0.05 × legLen` around the midpoint

**This is deeper than option A.** Option A would measure `L0 → M1` (the displacement), which sits much closer to `L0`. Option C measures all the way back to `H0`, so the entry zone is **higher** and the stop (below `L0`) is **further away** — deeper pullback, better price, wider stop, larger position-size constraint.

**Why it also means fewer trades:** price has to give back more of the move to reach the zone. Many setups will expire (TTL 96 bars) before getting there. That is the trade you accepted with option C: better entries, fewer of them.

**Mirror for bearish setups** (bias down, sweeping a high): leg = most recent swing **low** → sweep extreme high.

---

## 0e. D-08 — OB ∩ FVG as the POI

Owner asked for **both** order block and fair value gap, combined. Implemented as an **intersection** — both must define an overlapping price area, and that overlap is the point of interest (POI).

| Component | Definition (bullish case) |
|---|---|
| **Order block** | The last **down** candle before the displacement that broke structure. Zone = its `low → high` |
| **Fair value gap** | Three consecutive M15 bars `a, b, c` where `low[c] > high[a]` (a price gap never traded). Zone = `high[a] → low[c]` |
| **POI (combined)** | `lo = max(OB.low, FVG.high_of_a)`, `hi = min(OB.high, FVG.low_of_c)`. Invalid if `lo > hi` |

Rule 5 then requires the engulfing candle's range to **overlap the POI**. If no OB and FVG overlap exists in the displacement, **there is no setup** — that is the strict reading of "combination of both".

**Cost of this choice:** this is the most selective thing in your whole rule set. An OB and an FVG must coexist in the same displacement *and* overlap. If G2 shows almost no trades, this is the first place to look — the single relaxation would be `InpRequireFVG=false` (order block only) or `InpRequireOB=false` (FVG only). Both are exposed as EA inputs so you can measure the difference rather than argue about it.

---

## 0f. D-09 — 1:3 changes what "win rate" means

| Target | Break-even win rate | Expected win rate | Consequence |
|---|---|---|---|
| 1:2 | 33.3% | ~40–45% | comfortable |
| **1:3** | **25.0%** | **~28–33%** | thin margin; needs decent edge |
| 1:3 (if my estimate is optimistic) | 25.0% | ~25% | break-even before costs — **fails** |

Break-even at 1:3 is 25%. Costs make the true break-even ~27–29%. A 1:3 system with 30% winners is genuinely profitable; one with 26% is not. **The margin between success and failure is ~3 percentage points of win rate, over a sample of maybe 60–120 trades per year.**

Practical meaning: **you will not be able to tell whether this works from the first year of data.** That is a statement about sample size, not about your rules. Expect to need 200+ trades before the win rate is distinguishable from break-even at any confidence. Plan the backtest history (3–5 years) accordingly.

Also: because TP is derived as `3 × SL_distance` from a **structural** stop, on wide-stop setups the target can land far beyond any real structure. The EA records `tp_beyond_structure` on every trade for exactly this reason — if more than ~40% of trades have targets outside the prior range, 1:3 is fighting the structure and a structure-based exit (D-09 option b/c) deserves reconsideration at G2.

---

## 0g. D-16 — the 12-pair universe

Owner chose "add pairs". Proposed set, grouped by why:

| Group | Pairs | Rationale |
|---|---|---|
| **Original majors** | EUR_USD, GBP_USD, AUD_USD, USD_JPY, USD_CAD | Baseline — keeps results comparable to any earlier tests |
| **USD crosses** | USD_CHF, NZD_USD | More USD-side setups; cheap diversification *within* the existing logic |
| **JPY crosses** | EUR_JPY, GBP_JPY, AUD_JPY | High volatility, clean sweep/MSS behaviour; these are the pairs ICT-style models are usually built on |
| **EUR/GBP crosses** | EUR_GBP, GBP_AUD | Low USD correlation — genuinely new setups, not the same USD trade in a fifth costume |

**Two warnings that come with 12 pairs:**

1. **Correlation, not diversification.** `EUR_JPY` is roughly `EUR_USD × USD_JPY` — it is not an independent bet. With 12 pairs the net-currency exposure cap (`RSK-04`) stops being a nicety and becomes the primary risk control. Without it, a single USD move can open 8 simultaneous positions and "0.75% risk per trade" becomes ~6%.
2. **Sample size gains are real but partial.** Adding 7 correlated-ish pairs adds maybe 4–5 *independent* bets, not 7. It roughly doubles-to-triples trade count — helpful, not a solution to §0f's sample problem.

**Universe is config, not code.** The EA runs per-chart on whatever symbol you attach it to; the 12-pair list is a testing plan, not a hard-coded array.

---

## 1. Summary

| ID | Question | Recommended answer | Impact | Confidence |
|---|---|---|---|---|
| **D-01** | What is bias, and what if D and H4 disagree? | Swing-leg on broker-D; **D is authoritative, H4 is advisory (no veto)** | High | High |
| **D-02** | What counts as a sweep? | Penetration between `max(1p, 0.05×ATR)` and `0.60×ATR`; reclaim close within **2** bars | Medium | Medium |
| **D-03** | Which levels can be swept? | Confirmed M15 swings + prior-day high/low + equal levels (0.5p tolerance) | Medium | High |
| **D-04** | What is "not choppy"? | Kaufman Efficiency Ratio **≥ 0.30** over 20 H1 bars, swing density ≤ 6 | High | Medium |
| **D-05** | 50% of *which* leg? | **Displacement leg** (sweep extreme → MSS close), zone **45–55%** | **Highest** | Medium |
| **D-06** | What is a "clear engulfing"? | **Full-range** engulf (close beyond prior extreme) + body ≥ 50% of range | Medium | High |
| **D-07** | Where is the stop? | Beyond `sweep_extreme` by `max(1.5×spread, 0.15×ATR)`, min 8 pips | High | High |
| **D-08** | What are "supply & demand" zones? | v1: the R4 50% zone **is** the zone. No separate OB/FVG detector until v1.1 | Medium | Medium |
| **D-09** | Where is the exit? | **Fixed 1:2 RR.** Opposite-liquidity targets are a *research branch*, not v1 | **Highest** | Medium |
| **D-10** | Which hours do we trade? | **07:00–16:00 UTC** (London + NY). No entries outside, ever | High | High |
| **D-11** | Do setups survive midnight UTC? | **Yes** — setups carry over; only the R9 counter resets | Low | High |
| **D-12** | How is "mental state" implemented? | Required daily check-in + 30 min cooldown after a realised loss | Medium | High |
| **D-13** | What must break for structure to have "shifted"? | First intervening swing, **close** beyond it, displacement ≥ 0.5×ATR | High | High |
| **D-14** | Two valid setups, one slot — which? | Rank by `rr_actual` desc, then instrument A→Z (deterministic) | Low | High |
| **D-15** | New sweep while a setup is live? | **Replace** the setup; one setup per instrument at a time | Low | Medium |

---

## 2. The decisions

### D-01 — Bias definition and the D/H4 conflict

> *Checklist: "Confirm clear direction/starting point to finish point (Bullish or Bearish). No guessing, no 'it looks like'."*

**Recommended:** Bias = direction of the current **completed leg on broker-D**, measured from confirmed swing to confirmed swing (low→high = bullish, high→low = bearish). **D is the single authority. H4 provides context and is recorded, but never vetoes.**

**Why the leg, and not a slope or a midpoint:** "starting point to finish point" *is* a leg. An EMA slope has no start or finish; a range midpoint isn't direction. Swings give you a leg you can name in a report (`leg_start_price → leg_end_price`), which matters for auditability.

**Why D over H4 as authority** (this revises my earlier default of "conflict ⇒ no trade" — see §5):

Requiring D and H4 to agree would **exclude the setups you're actually trying to trade**. A pullback against the daily trend is precisely what creates the 50% retracement in D-05 and the M15 structure shift in D-13. If H4 could veto, then every healthy retracement in a strong daily trend — the highest-quality version of your setup — would be filtered out, while you'd keep only the late, extended entries where both timeframes agree because the move is already over.

**So:** the daily leg says *which direction*. M15 structure (D-13) says *when*, and it is already required to shift in that direction. That is the whole model. Adding an H4 veto adds no information and removes your best trades.

**Rejected:** EMA(50) slope on D (no "finish point", unstable at turns); range midpoint (no direction); H4-wins (H4 is inside the daily leg's noise); conflict ⇒ no trade (see above).

**If D has no valid leg** (range, or fewer than `min_leg_bars` = 5 bars between swings) ⇒ **no trade.** This is the honest reading of "no guessing."

**Watch at G2:** if trade count is very low, the temptation is to loosen D-01. Don't. Loosen D-05's zone instead — bias is the thesis, retracement depth is an entry detail.

⚠️ *Fixture note:* the "bias" is only known at `swing + swing_right` bars, i.e. **3 bars after the swing forms**. Backtests must respect that lag or they will look ahead. This is the most likely place for a silent look-ahead bug in the whole system.

---

### D-02 — What counts as a liquidity sweep

> *Checklist: "Has price taken highs or lows? Is the sweep clean and obvious?"*

**Recommended:**
- `min_penetration = max(1.0 pip, 0.05 × ATR(14))` — below this is noise
- `max_penetration = 0.60 × ATR(14)` — above this is a breakout, not a grab
- `require_reclaim_close = true`, `reclaim_within_bars = 2`
- `freshness_bars = 8` (the sweep must be recent — within 2 hours)

**Why ATR-relative bounds rather than fixed pips** (revising "1–20 pips"): a fixed 20-pip ceiling that is generous on EUR/USD is restrictive on GBP/USD and wrong on USD/JPY entirely (different pip size and volatility). ATR-relative bounds are scale-free, so **one parameter set serves all 5 pairs** — which also means one less thing to overfit per pair.

**Why the reclaim close is the whole rule:** the difference between a sweep and a breakout *is* the reclaim. Price that takes the low and closes back above it = liquidity grab. Price that takes the low and keeps going = you are now short a falling market. This single condition is doing more work than the penetration bounds; if you loosen anything, loosen the bounds, never the reclaim.

**Rejected:** wick-only penetration with no reclaim (that's just "price went there"); tight 1–5 pip band (misses the real sweeps); reclaim within 1 bar only (too strict after a fast spike).

**Watch at G2:** count sweep events separately from accepted setups. If sweeps are rare (say <2/week/pair), D-03 is probably too narrow, not D-02.

---

### D-03 — Which levels can be swept

**Recommended (v1):** confirmed M15 swing highs/lows + **prior trading-day** high/low, with equal levels within 0.5 pip treated as one. Nothing else.

**Why prior-day extremes:** they are the most widely-watched liquidity pools in retail forex, and they are objective — every platform shows the same levels. They're also the levels most likely to produce a *clean* sweep, which is what the checklist asks for.

**Why not session extremes / Asian range:** it adds three more level types, roughly triples the sweep count, and most of those additional sweeps are low-quality. It also multiplies the parameters you can overfit. This is the cleanest place to *not* add complexity in v1.

**Rejected:** swings only (too narrow — misses the daily-liquidity grabs); + session highs/lows (noise, defer to v1.1 research); + equal highs/lows as *separate* levels rather than one merged level (double-counts the same pool).

---

### D-04 — How "not choppy" is measured

> *Checklist: "Is structure clean (not choppy)?"*

**Recommended:** Kaufman Efficiency Ratio ≥ **0.30** over **20 H1 bars** (≈20 hours), *and* confirmed swing density ≤ 6 per 20 bars.

**Why Efficiency Ratio:** `ER = abs(close[t] − close[t−n]) / Σ abs(close[i] − close[i−1])`. It is exactly the question being asked — "did price actually go somewhere, or did it thrash?" ER = 1.0 is a perfect trend, ~0.1 is pure noise. It is:
- **scale-free** across all 5 pairs (no per-pair threshold)
- **one parameter** (`n`), with an intuitive anchor
- **cheap to implement and cheap to explain** — you can look at a chart and roughly guess the ER, which makes fixtures easy to write

**Why the swing-density companion:** ER has a blind spot — a market that moves in a wide, slow zigzag can have a decent ER while being completely untradeable structure. The swing count catches that. Two conditions, both cheap.

**Rejected:** ADX (needs smoothing and a threshold per timeframe, and measures strength not cleanliness); ATR expansion (measures volatility, not direction); "count of structure breaks" (circular — it presumes the structure definition you're trying to validate).

**Threshold honesty:** 0.30 is a judgement call. The right way to set it is on **fixtures, not P&L** — pull 20 clean trend windows and 20 chop windows, compute ER for each, and set the threshold where they separate. If you tune 0.30 by backtest profit, you've started fitting. I'd expect the true value to land between 0.25 and 0.40.

**Watch at G2:** D-04 and D-05 together control trade count. If the funnel shows R3a rejecting >60% of sweeps, that's a signal the threshold is doing too much work.

---

### D-05 — 50% of *which* leg? ⭐ *highest leverage*

> *Checklist: "Valid liquidity retracement (e.g. 50%). Setup aligns with bias."*

**Recommended: the displacement leg** — from `sweep_extreme` to the MSS close (D-13). Zone **45–55%** of that leg.

| Anchor | What 50% means | Consequence |
|---|---|---|
| **A. Displacement leg** ✅ | Halfway back into the move that broke structure | Tight, fills within hours, highest relevance |
| B. Daily leg (from D-01) | Halfway back into the entire daily move | Far away; most setups expire unfilled; very low frequency |
| C. Prior impulse | Halfway back into the move that created the sweep | Between A and B; different failure mode |

**Why A:** the retracement must be a retracement *of the leg that just broke structure*, because that is the leg the setup is built on. Option B would mean most setups simply never fill (the daily 50% is often hundreds of pips away), which would silently cut your trade count by an order of magnitude — and it would no longer be an M15 entry model at all.

**Why a 45–55% band and not a single price:** a single 50% level on M15 is hit with zero tolerance roughly half the time by spread and rounding. The band is a *fill tolerance*, not a strategy change. If fill rate is low, widen to **40–60%** — do not move the anchor, and do not move to option B.

**On "e.g.":** the checklist's "e.g. 50%" implies the number is an example. I'm treating 50% as the anchor anyway, because a specific number is testable and "somewhere between 38 and 79%" is not. If you have a reason to prefer 61.8% (OTE), say so — it's one parameter and I'd rather use your number than mine.

**Rejected:** single 50% with zero tolerance (misses fills); 61.8% default (changes the checklist's stated number without evidence); B and C above.

---

### D-06 — What is a "clear engulfing candle"

> *Checklist: "Clear 15mins engulfing candle on supply & demand before entry. No prediction entries."*

**Recommended:** **full-range engulf** + `body_ratio ≥ 0.50`.
- Long: `close > prev.high` **and** `open ≤ prev.close` **and** `close > open` **and** body ≥ 50% of the bar's range.

**Why full-range over body-only:** the checklist asks for "clear" and forbids prediction. A close beyond the prior bar's *extreme* is the least ambiguous, most decisive confirmation available on one bar. Body-only engulf lets through bars that close inside the prior range — visually an engulf, structurally not a break.

**Why the body ratio:** it removes doji-shaped bars that technically engulf but show no conviction. 50% is deliberately mild — this is a quality filter, not a second strategy.

**Why `complete == true` is the actual "no prediction" guard:** the real prediction risk isn't the engulf shape, it's acting on a bar that hasn't closed. That's an invariant (`INV-5`), not a parameter. It should be impossible to violate in code, not just discouraged in config.

**Rejected:** body-only engulf (weaker, more signals but lower quality); requiring a specific wick structure (over-fitting one bar's anatomy); intrabar entry on "almost closed" (this is exactly the prediction the checklist forbids).

---

### D-07 — Where does the stop go?

> *Checklist: "Stop loss set BEFORE entry."* — note: the checklist says *when*, never *where*.

**Recommended:** beyond the `sweep_extreme` by `max(1.5 × current spread, 0.15 × ATR(14))`, with a floor of **8 pips** total SL distance.

**Why the sweep extreme:** it is the setup's own invalidation point. If price trades meaningfully beyond the level that was swept, then rule 2's premise ("liquidity was taken and rejected") is falsified — the trade should not exist. Any other stop placement is arbitrary in a way the checklist didn't intend.

**Why a buffer instead of exactly at the extreme:** stops sat exactly at obvious extremes are the ones that get run. The buffer is not optimisation; it is acknowledgement that the level is visible to everyone.

**Why the 8-pip floor:** very tight stops on M15 noise produce near-certain losses to spread and stop-hunting, and they distort position sizing (tiny SL ⇒ huge position ⇒ a single tick-out costs the same as a real loss, but with terrible RR). If structure gives you a 4-pip stop, **skip the trade** — that's not a setup, it's noise.

**⚠️ The RR interaction you need to decide on:** SL distance is set by structure; TP is set by D-09 (1:2). So a wide structural SL demands a *very* wide TP. On GBP/USD a 35-pip SL needs a 70-pip target — which may be outside the next structure. Those trades will be **rejected by R6** (`rr_actual < 2.0`). That is correct behaviour, but it means **D-07 + D-09 jointly decide how many trades you actually get**. Measure this at G2 before treating `min_rr = 2.0` as fixed.

**Rejected:** fixed pip stop (ignores structure); ATR-only stop (ignores where the setup is wrong); beyond the R4 zone (that's inside the entry, so the stop would be tiny).

---

### D-08 — What are "supply & demand" zones?

> *Checklist: "...engulfing candle on supply & demand..."* — **the term is never defined, and no other rule produces a zone.**

**Recommended (v1):** the **R4 50% zone is the supply/demand zone.** No separate detector.

**Why:** rule 5 requires the engulfing candle to occur *at* the R4 zone already. Introducing a second, independent zone concept means two zones to reconcile, and a new question the checklist doesn't answer ("what if the engulf is in the R4 zone but not the OB?"). For v1, one zone, one meaning.

**Be clear-eyed:** this is a **simplification of your source material**, not a faithful transcription. If "on supply & demand" means a specific order-block or fair-value-gap pattern to you, then this decision is wrong and we need a real detector (an `OrderBlock`/`FVG` module behind an interface, ~2–3 days, and it becomes a first-class rule).

**Rejected for v1, kept as v1.1 candidate:** explicit order-block detection (last down-candle before an up-move that breaks structure); FVG/imbalance entry; both zones required.

**This is the decision most likely to be wrong**, because it's the one where I'm guessing at your intent rather than formalising something you wrote. Flag it explicitly.

---

### D-09 — Where is the exit? ⭐ *highest leverage, and the checklist is silent*

> The checklist specifies **entries only**. There is no target, no trailing rule, no exit condition anywhere in the source document.

**Recommended (v1):** **fixed 1:2 reward:risk**, set at entry, attached to the order, never moved.

**Why fixed RR rather than a smarter target:**
1. It makes expectancy measurable in **R** — every trade is directly comparable, and your statistics don't need to model what the target "would have" been.
2. It makes `min_rr` (R6) enforceable at submit time, before any capital is at risk.
3. It introduces **zero** new undefined variables. A target based on "the next liquidity pool" is a new rule your checklist doesn't contain, and it would need its own spec, fixtures and validation — it's a v2 feature disguised as a parameter.
4. With a static SL/TP, the daemon is not in the exit path (`INV-2`). If the process dies, the trade still exits.

**The honest downside:** 1:2 with a structural stop is a *low win-rate* configuration. Expect ~40–45% winners. If your checklist's edge comes from targeting larger moves, fixed 1:2 will systematically under-capture it and the whole thing may look unprofitable when the underlying model is fine. That's a real risk of this choice.

**Research branch (not v1):** "opposite liquidity" — target the nearest unswept swing high (for longs), which is the ICT-consistent target and probably better expectancy. Run it *as a second experiment at G2* against the 1:2 baseline. If it wins convincingly out-of-sample, it becomes the v1.1 rule — but it must earn that, not be assumed.

**Rejected for v1:** trailing stop (put the daemon in the exit path, and it's untestable in a static-SL framework); partial closes at 1R (complicates R accounting and needs another rule); HTF level target (undefined until D-01's leg endpoints are used, and produces very inconsistent RR, which breaks R6's check); time-based exit (no basis in the checklist).

**Also decided here:** no time stop in v1. But if the median holding period exceeds ~2 days, swap costs become material and a time exit needs adding — check this in the first G2 report.

---

### D-10 — Which hours do we trade?

> The checklist has no session filter. This is a gap, and a load-bearing one.

**Recommended:** entries allowed **07:00–16:00 UTC only**, DST-aware, defined as the London session plus the London/NY overlap. Setups are still *formed* outside these hours; they are simply not actionable.

**Why this is not optional:** an M15 sweep-and-reclaim pattern in the Asian session is mostly range-bound noise, and the resulting "sweeps" are the least clean of the day. Without a session filter, the majority of your setups will come from the lowest-quality hours. This single filter will probably change results more than D-04 and D-06 combined.

**Why the specific window:**
- London: 08:00–17:00 local ⇒ **08:00–17:00 UTC** in winter (GMT), **07:00–16:00 UTC** in summer (BST).
- London/NY overlap: 13:00–17:00 UTC winter, 12:00–16:00 UTC summer.
- `07:00–16:00 UTC` covers London in both DST states and the whole overlap in summer. Being DST-aware (rather than hard-coding UTC) is the correct implementation — the *local* session times are fixed, the UTC offset moves twice a year.

**Also recommended:** no entries in the first 15 minutes after the Sunday open; Friday flatten at 20:45 UTC (already `EX-08`).

**Rejected:** no filter (see above); London only (drops the highest-liquidity hours of the day); per-pair session windows (5× the parameters for no clear benefit); "killzones" as narrow 2–3h windows (too aggressive with an already selective conjunction — see §4).

---

### D-11 — Do setups survive midnight UTC?

**Recommended:** **Yes — setups carry over.** A setup begun at 23:50 is still valid at 00:10. Only the R9 trade counter resets.

**Why:** midnight UTC is an accounting boundary, not a market event. Discarding a `SHIFTED` setup because the clock rolled over would be an arbitrary loss of information — and worse, it would create a subtle behaviour where the bot is systematically less willing to trade just after 00:00, which is nothing but a calendar artefact. (Invalidation rules — sweep extreme broken, opposing MSS, TTL — are the real end-of-life conditions.)

**Rejected:** invalidate at 00:00 UTC (arbitrary); invalidate at session close (would pair with D-10, but then a 07:00–16:00 window means every setup dies daily, which is effectively the same as a 24h TTL — simpler to just use the TTL).

---

### D-12 — How is "mental state" implemented?

> *Checklist: "Not emotional. Not forcing trades. Not chasing losses. Bad mental state = NO TRADE."*

**Recommended:** three layers, all on:
1. **Structurally satisfied** — the bot makes no discretionary decisions. Emotional entries are impossible by construction.
2. **Mechanical proxies** — "not chasing losses" ⇒ loss-streak breaker (2 losses ⇒ 2h pause); "not forcing trades" ⇒ trade cap + setup TTL + `force_trade_cooldown_min = 30` after any realised loss.
3. **Operator check-in** — `tradie session check-in` once per trading day. No check-in ⇒ no entries (positions unaffected).

**Why keep the check-in at all:** because otherwise rule 8 does not exist in the system. It is the only rule in your checklist that no software can verify, and the temptation when specifying a bot is to quietly drop it. A daily confirmation makes it **auditable** — you can look back at the event log and see which days you traded without checking in.

**Why it's cheap:** one CLI command per day, and a 30-minute cooldown after a loss that mostly protects you from the exact behaviour rule 8 names.

**Rejected:** drop rule 8 (dishonest — the bot would report 9/9 passing while implementing 8); require check-in per *trade* (friction that will get disabled within a week); no cooldown (the cooldown is the mechanically useful half).

---

### D-13 — What must break for structure to have "shifted"?

> *Checklist: "Is it shifting in your bias direction?"*

**Recommended:** the **first confirmed intervening swing** in the bias direction, broken by an M15 **close**, with displacement ≥ **0.5 × ATR(14)** from the sweep extreme.

For a long setup: find the first confirmed swing **high** between `sweep_extreme` and the current bar. MSS = an M15 close above it within 24 bars of the sweep.

**Why the intervening swing, and not "the last swing":** the last swing before the current bar is often *inside* the sweep leg itself, which makes the break trivially easy and produces false shifts. The swing formed *between* the sweep and the reversal is the structural high that must fall for the reversal to be real. This is the difference between "an MSS" and "any higher close."

**Why close, not wick:** a wick through a level is not a shift; it's a test. Requiring a close is what makes this a filter rather than a formality.

**Why the displacement gate:** without it, price can drift 10 pips through the level over 6 hours and qualify. Displacement (a fast, ATR-sized move off the sweep extreme) is the evidence that the move is *impulsive* rather than accidental — and it's what distinguishes a genuine shift from chop, which is what rules 3a and 3b together are trying to establish.

**Rejected:** prior-bar high (far too weak); wick-only break (too loose); the swing high *before* the sweep (frequently already broken, so the condition is vacuous); no displacement gate (see above).

---

### D-14 — Two valid setups, one position slot

**Recommended:** rank by `rr_actual` descending; tie-break by instrument alphabetically (`AUD_USD` before `EUR_USD`).

**Why the tie-break matters more than it looks:** `INV-6` requires determinism. If selection depended on iteration order, a dict order, or which API response arrived first, then a backtest and a live run could legitimately differ — and the parity test (G3a) would fail for a reason that looks like a bug but isn't. A named lexicographic tie-break makes the choice reproducible and auditable.

**Why `rr_actual` and not "best setup":** RR is already computed, already used by R6, and is the one comparable scalar across pairs at a decision moment. Everything else ("cleanest structure") would require inventing a scoring model.

---

### D-15 — A new sweep while a setup is already live

**Recommended:** **one setup per instrument at a time.** A new qualifying sweep on the same instrument **replaces** the existing setup (new `setup_id`, previous one recorded as `superseded`), regardless of direction.

**Why one at a time:** two concurrent setups on one instrument means two potential entries, which (with `max_concurrent_positions = 2`) could consume the entire position budget on one correlated idea. One-at-a-time keeps the state machine, the journal and the report unambiguous.

**Why "replace" and not "ignore the new one":** the newer sweep is more current information. Ignoring it because an older setup is still alive would mean the bot trades a stale premise while a fresher one is visible.

**Supersede must be recorded, not deleted** — the funnel report needs to know it happened, or D-02's sweep counts won't reconcile.

---

## 3. What this rule set means for trade frequency

I estimated this rather than guessing, because it changes the project plan.

Assumptions (all defensible, none verified until G2):

| Stage | Pass rate | Reasoning |
|---|---|---|
| Qualifying sweep (prior-day level or swing, with reclaim) | ~1–2/day/pair | Daily extremes get tagged most days |
| → R3a structure clean | ~60% | Chop filter is not aggressive but not trivial |
| → R3b MSS within 24 bars | ~50% | Many sweeps simply continue |
| → R4 50% retrace within 96 bars | ~60% | Most shifts do pull back, but not always that far |
| → R5 engulf in zone | ~40% | One specific bar pattern |
| → R6 RR ≥ 2 accepts | ~70% | Structural stops vs 1:2 targets |

Per pair per day: `1.5 × 0.6 × 0.5 × 0.6 × 0.4 × 0.7 ≈ **0.075**`
Across 5 pairs, then restricted to the **07:00–16:00 UTC** window (≈37% of the day):

**≈ 0.14 setups/day → ≈ 35–50 trades/year pooled.**

Applying a generous error bar, call it **65–130/year** if my pass rates are pessimistic, **35–50/year** if they're realistic.

### Consequences you should weigh before signing

1. **The 3-trade/day cap will essentially never bind.** It is a rail against a bad day, not a constraint on a good one. (This answers `H-05`: it's a ceiling you won't hit — expected is ~0.2/day.)
2. **G2's "≥100 OOS trades" needs 12–24+ months of out-of-sample data.** That is a real planning cost, and it argues for extending DAT-01's history requirement from 18 months to **3+ years**, and for running the walk-forward with longer OOS windows.
3. **G4's "≥30 paper trades" takes ~3–6 months**, not 8 weeks. The 8-week floor will be superseded by the trade count.
4. **A strategy with ~50 trades/year cannot be validated in any reasonable time frame.** With that sample, the confidence interval on expectancy spans roughly 0.5R. You would be live-trading on belief.

### So: one of these has to change

This is the most important paragraph in the document. If my estimate is roughly right, **the rule set as specified is too selective for its own validation.** The options, in order of how much I'd defend them:

| Option | Effect on frequency | Honest cost |
|---|---|---|
| **Widen the R4 zone to 40–60%** | +30–50% | Slightly worse RR on average; small strategy change |
| **Use full session coverage (07:00–21:00 UTC)** instead of London-only | +~50% | Includes NY afternoon chop; some quality loss |
| **Add pairs** (EUR_JPY, GBP_JPY, XAU_USD…) | linear | More params, correlation risk, JPY sizing across more instruments |
| **Relax D-06 to body-only engulf** | +40–60% | Lower-quality confirmations — the rule's whole point |
| **Relax D-13 (wick break, no displacement)** | +50% | The filter stops filtering |
| **Accept ~50 trades/year and extend the industry-standard 2-year test to 5** | none | Years to evidence; or trade live on faith |

**My recommendation: widen D-05 to 40–60% and add the NY session, and leave every quality filter (D-06, D-13, D-02's reclaim) strict.** Trade more setups of the same quality rather than more low-quality setups. But this is genuinely your call — you know your model's edge better than a pass-rate estimate does.

**Verify before deciding:** the whole estimate is a pile of assumed pass rates. **Instrument the funnel in the backtester and measure the actual counts on 3 years of data before changing any parameter.** The funnel report (PRD v2 §10.3 item 6) exists precisely to answer this question with data instead of arithmetic. It's the first thing to build, and it's ~2 days of work once the data layer exists.

---

## 4. Three revisions to `rule-spec.md`

Stated openly, because silently changing a spec is worse than changing it.

| # | Was | Now | Why |
|---|---|---|---|
| 1 | D-01: `conflict_policy = no_trade` | **D authoritative, H4 advisory** | An H4 veto filters out the pullbacks that *are* the setup (see D-01) |
| 2 | D-02: `min 1.0 / max 20.0 pips` fixed | **ATR-relative bounds** | Fixed pips don't transfer across GBP/USD and USD/JPY; one param set for 5 pairs |
| 3 | D-05: `zone 45–55%`, no frequency discussion | **Zone 45–55% as specified, but §3 argues for 40–60%** | The frequency problem was invisible until the rules existed as a conjunction |

All three reduce the chance of a silent failure (too few trades) at some cost in theoretical purity. If you disagree with any, the reasoning above is the thing to attack, not the parameter.

---

## 5. Sensitivity: if you reject the biggest ones

| If you change… | Expect… | Watch for |
|---|---|---|
| D-05 → daily-leg 50% | Trade count collapses (most setups never fill) | If G2 shows <20 trades/year, this was the cause |
| D-05 → 61.8% (OTE) | Fewer, deeper fills; better RR per trade; longer waits | TTL (96 bars) may be too short for deep retraces |
| D-09 → opposite-liquidity target | Higher expectancy but inconsistent RR; R6's check needs redefining | Expectancy comparisons become hard; consider reporting in pips too |
| D-09 → trailing | Daemon enters the exit path — INV-2 is void | This is the single riskiest change to make. It removes the crash-safety property |
| D-10 → no session filter | Roughly 2–3× the trades, at much lower average quality | Asian-session sweeps; expect net expectancy to fall despite more trades |
| D-04 → ADX > 20 | Similar intent, different parameter surface | Two thresholds to tune instead of one; ADX lags |
| D-06 → body-only | More signals, weaker confirmations | Watch win rate and MAE, not just trade count |
| D-13 → no displacement gate | Many more "MSS" events, most of them drift | Rule 3b stops being a filter; D-03's sweep quality carries everything |

---

## 6. Sign-off

G1 requires this section completed. Anything unsigned keeps its §1 recommendation **for backtesting only** — no live capital on an unsigned parameter.

```
Owner: ______________________          Date: ____________

D-01  ☐ Accept   ☐ Modify: ______________________________________
D-02  ☐ Accept   ☐ Modify: ______________________________________
D-03  ☐ Accept   ☐ Modify: ______________________________________
D-04  ☐ Accept   ☐ Modify: ______________________________________
D-05  ☐ Accept   ☐ Modify: ______________________________________    ← highest leverage
D-06  ☐ Accept   ☐ Modify: ______________________________________
D-07  ☐ Accept   ☐ Modify: ______________________________________
D-08  ☐ Accept   ☐ Modify: ______________________________________    ← most likely to be wrong
D-09  ☐ Accept   ☐ Modify: ______________________________________    ← highest leverage
D-10  ☐ Accept   ☐ Modify: ______________________________________
D-11  ☐ Accept   ☐ Modify: ______________________________________
D-12  ☐ Accept   ☐ Modify: ______________________________________
D-13  ☐ Accept   ☐ Modify: ______________________________________
D-14  ☐ Accept   ☐ Modify: ______________________________________
D-15  ☐ Accept   ☐ Modify: ______________________________________

§3 frequency response:  ☐ Widen D-05 to 40–60%   ☐ Extend sessions   ☐ Add pairs
                        ☐ Keep as-is and extend the backtest history
                        ☐ Measure first (recommended — instrument the funnel)

Signature: ______________________
```

---

## Appendix A — Parameter registry (becomes `config.yaml`)

Single source of truth once signed. Any change here bumps `strategy_version`.

```yaml
strategy:
  R1_BIAS_HTF:
    htf: D
    htf_fallback: H4
    htf_conflict_policy: d_authoritative   # revised (was: no_trade)
    swing_left: 3
    swing_right: 3
    min_leg_bars: 5
  R2_LIQUIDITY_SWEEP:
    level_sources: [swing, prior_day]      # D-03
    swing_lookback: 48
    equal_level_tolerance_pips: 0.5
    penetration_min: max(1.0, 0.05 * atr14)   # D-02, revised to ATR-relative
    penetration_max: 0.60 * atr14
    require_reclaim_close: true
    reclaim_within_bars: 2
    freshness_bars: 8
  R3a_STRUCTURE_QUALITY:
    metric: efficiency_ratio
    er_window_bars: 20
    er_timeframe: H1
    er_min: 0.30
    max_swing_density: 6
    min_range_atr: 2.0                  # added per owner (D-04, see 0c)
  R3b_STRUCTURE_SHIFT:
    mss_level_source: intervening_swing
    require_close_beyond: true
    max_bars_after_sweep: 24
    min_displacement_atr: 0.5
  R4_ENTRY_RETRACE:
    retrace_anchor: prior_impulse        # RATIFIED D-05 option C
    retrace_target: 0.50
    zone_low: 0.45          # §3 argues for 0.40
    zone_high: 0.55         # §3 argues for 0.60
    setup_ttl_bars: 96
  R5_ENGULFING_CONFIRMATION:
    require_poi: true                   # RATIFIED D-08: OB and FVG combined
    poi_source: order_block_and_fvg     # intersection, not either/or
    engulf_mode: full_range
    min_body_ratio: 0.50
    zone_overlap_required: true
    entry_timing: next_bar_open
    max_spread_multiple: 2.0
  R6_RISK_MANAGEMENT:
    risk_per_trade_pct: 0.75
    sl_anchor: sweep_extreme
    sl_buffer: max(1.5 * spread, 0.15 * atr14)
    min_sl_pips: 8
    min_rr: 3.0                         # RATIFIED D-09 (was 2.0)
  R8_MENTAL_STATE:
    require_daily_checkin: true
    force_trade_cooldown_min: 30
  R9_TRADE_LIMIT:
    daily_trade_cap: 3
    trading_day_tz: UTC
    count_scope: opened
  exits:
    take_profit: fixed_rr
    take_profit_rr: 3.0                 # RATIFIED D-09 (was 2.0)
    time_stop_bars: null
  sessions:
    entries: london_and_ny     # 07:00-16:00 UTC DST-aware
    friday_flatten_utc: "20:45"
    first_bar_after_sunday_open_min: 15
  selection:
    rank_by: rr_actual
    tie_break: instrument_ascending
    max_active_setups_per_instrument: 1
```

---

## Appendix B — What I'm least confident about

Ranked, so you know where to spend your scepticism rather than mine.

1. **§3's frequency estimate.** The individual pass rates are educated guesses built from how these patterns usually behave, not from your data. The *direction* (this conjunction is very selective) I'm confident about; the magnitude is ±2×. **Measure it.**
2. **D-08 (supply & demand).** I'm interpreting a term you used with a meaning I inferred. Highest chance this is simply not what you meant.
3. **D-09's fixed 1:2.** Defensible and testable, but if your model's edge lives in the runner (targeting the next pool rather than a fixed multiple), this choice will understate the strategy and could reject it at G2 unfairly.
4. **D-04's 0.30 threshold.** A judgement number. Set it on fixtures, not backtest P&L.
5. **D-01's H4-as-advisory.** I argued myself into this and I think it's right, but it's the kind of call where a trader with screen time would overrule me in ten seconds — and should.

Everything else I'd defend as written.

---

*[Tradie · G1 decisions v0.1.0-draft · 2026-10-25]*
*Companion to `rule-spec.md`. Confidential — internal use only.*
