# Tradie EA — MT5 implementation of the 01C checklist

A MetaTrader 5 Expert Advisor that implements the ratified rule set from `docs/rule-spec.md` and `docs/decisions.md`, so the strategy can be **backtested and forward-tested without OANDA API access**.

## ⚠️ Read this before you run it

**This is a research tool, not the production system.**

| | |
|---|---|
| **What it is** | A faithful implementation of the 9-rule checklist that you can compile, backtest in the Strategy Tester, and forward-test on demo |
| **What it is not** | The system in `docs/Tradie PRD v2.md`. It has **no** crash-safe state, **no** order reconciliation, **no** idempotency, **no** circuit-breaker persistence, **no** news blackout, and **no** portfolio-level currency-exposure cap |
| **Compile status** | **Builds as of 2026-10-25.** First compile raised 2 errors + 1 warning in MetaEditor, all fixed (see "Build history"). Subsequent errors, if any, are new — send the line number |
| **Live use** | Don't. Demo only until G2–G4 in the PRD are satisfied |

**Why this exists:** `G0` (OANDA v20 API available for your jurisdiction) is unresolved and blocks the whole Python live path. An MT5 EA sidesteps it entirely — any broker's MT5 demo gives you a backtester and a forward-test environment today. That is a genuine unblock, not a workaround.

---

## Install

1. In MT5: **File → Open Data Folder** → `MQL5/Experts/`
2. Copy `Tradie.mq5` there
3. Open MetaEditor (**F4**), open the file, press **F7** (Compile)
4. Back in MT5, refresh the Navigator (right-click → Refresh)

The preset is in `presets/Tradie-default.set` — copy it to `MQL5/Presets/` if you want to load it directly.

---

## Test it

### Strategy Tester

| Setting | Value |
|---|---|
| Expert | `Tradie` |
| Symbol | One pair at a time (see below) |
| Period | **M15** — this is the EA's decision timeframe; it pulls D1 and H1 itself |
| Modelling | **Every tick based on real ticks** for final runs; "1 minute OHLC" for fast iteration |
| Deposit | Match your intended account size (sizing is % of balance) |
| Inputs | Load `Tradie-default.set` |

Then set the date range. **Use at least 3 years** — see "Sample size" below.

### The 12-pair plan (D-16)

The EA is **one symbol per chart/run**. Run it separately per pair and keep the reports apart — per-pair statistics are far more informative than a pooled number, and pooling hides a single pair carrying the results.

| Group | Pairs |
|---|---|
| Original majors | EURUSD, GBPUSD, AUDUSD, USDJPY, USDCAD |
| USD crosses | USDCHF, NZDUSD |
| JPY crosses | EURJPY, GBPJPY, AUDJPY |
| EUR/GBP crosses | EURGBP, GBDAUD |

Symbol names differ by broker (`EURUSD`, `EURUSD.raw`, `EURUSDm`…). The EA uses the chart symbol, so naming doesn't matter — but your broker's history quality does.

### Dry run first

Set `InpDryRun = true` for one pass. It logs every signal with full diagnostics to the **Journal** tab and sends nothing:

```
Tradie DRY RUN: BUY EURUSD lots=0.24 entry=1.08421 sl=1.08105 tp=1.09368 | bias=up sweep@1.08042 mss@1.08290 zone=1.08190-1.08266 poi=1.08210-1.08255 sl=31.6p rr=3.0
```

Rejections log their reason, which is the whole point of the funnel:

```
Tradie: no trade - R3a: range 1.62xATR < 2.00 (ranging)
Tradie: no trade - R5: OB and FVG do not overlap
Tradie: no trade - R4: zone [1.08190-1.08266] not reached
```

---

## Build history

| Date | Issue | Fix |
|---|---|---|
| 2026-10-25 | `wrong parameters count` ×2 — `built-in: int iATR(const string, ENUM_TIMEFRAMES, int)` | **MQL5's `iATR()` takes 3 arguments and returns an indicator *handle*, not a value.** This is the MQL4→MQL5 trap: MQL4's `iATR(sym, tf, period, shift)` does not exist. Now `GetATRHandle()` caches handles per (timeframe, period) and `ATRValue()` reads the value with `CopyBuffer()`. Handles are released in `OnDeinit()` |
| 2026-10-25 | `version '0.10' is incompatible with MQL5 Market, must be xxx.yyy` | `#property version "1.000"` |

Both were my errors, not logic problems. The EA now caches ATR handles rather than recomputing, which is also faster and is the correct MQL5 pattern.

**If you hit a further compile error:** the first two errors masked nothing else (MetaEditor reports all of them in one pass), so anything new is genuinely new. Send the line number and the message text.

---

## Which symbol to test — and in what order

Two different questions, two different symbols. Don't conflate them.

### Test 1 — "does the EA work?" → **EURUSD, M15**

Not because EURUSD is the best place to trade this model, but because it is the best place to find *bugs*:

| Reason | Why it matters here |
|---|---|
| **Deepest history** | Most brokers hold 10+ years of M15 EURUSD; exotics often have 1–2. You need years, not months (see §Expected trade frequency) |
| **Tightest spread** | The EA rejects on `InpMaxSpreadPoints` and buffers SL by 1.5 × spread. A wide-spread symbol adds noise to the exact thing you're debugging |
| **Simplest pip path** | 5 digits, non-JPY → exercises the common branch of `PipSize()` only |
| **Familiar behaviour** | You can eyeball a chart and tell whether the EA *should* have taken a trade. That is the fastest debugging loop there is |

**Purpose:** confirm the 9 rules fire, the rejection funnel reports sensibly, and the cooldown wiring logs correctly. A strategy verdict from EURUSD alone means little.

### Test 2 — "does the strategy have edge?" → **GBPJPY, then EURJPY**

This is the important one, and for a specific reason: **you chose 1:3 exits.** A 1:3 target needs *room to move*. A tightly-ranging pair will produce structurally-correct setups whose targets are never reached, and the results will look like a broken strategy when the model was fine.

| Pair | Why |
|---|---|
| **GBPJPY** | Highest ATR of the common pairs — the range exists for 3R to be reachable. Also exercises the **3-digit JPY pip branch**, which is a code path EURUSD never touches |
| **EURJPY** | Same argument, slightly tamer. Good cross-check |
| **GBPUSD / AUDUSD** | Mid-ATR, sensible second wave |
| **EURUSD** | Include for completeness — and expect the weakest results, because it is the most efficient, most-arbitraged price in FX |
| **EURGBP** | ⚠️ **Avoid for the first pass.** Very low ATR; a 3R target from a structural stop frequently sits outside the weekly range. Tight spread, wrong instrument for this exit model |

### The magic-number trap when testing several charts

This one will quietly ruin your data. `CountTradesToday()`, `CountOpenPositions()` and the P&L accumulator filter by **magic number only — not by symbol**. So with the default `InpMagic` on 12 charts:

| Running | Daily cap means |
|---|---|
| **1 chart** | 3 trades/day **for that pair** |
| **12 charts, same magic** | 3 trades/day **in total, across all 12 pairs** |

Same applies to `InpMaxConcurrent` (2 total, not 2 per pair) and to the cooldown ladder, which aggregates losses across every chart into one shared 15%/35% anchor.

**That aggregation is correct for production** — it is portfolio-level risk, exactly what you want. But it is wrong for *measuring* a pair:

| Goal | Use |
|---|---|
| Measure a single pair's edge | **Unique `InpMagic` per chart** (e.g. `20261025` + pair index). Each pair gets its own cap and its own cooldown anchors |
| Forward-test as production will run | **Shared magic.** Accept 3/day total and portfolio cooldowns |

For Strategy Tester work, run **one pair per run** — each tester run is isolated anyway, so the magic only matters for optimisations that reuse the terminal.

### Tester settings that matter

| Setting | Use | Why |
|---|---|---|
| Symbol | `EURUSD` | Deepest history, tightest spread (see above) |
| Period | **M15** | The EA's decision timeframe. It pulls D1 and H1 itself |
| Date | **5+ years if available**, 3 years minimum | At 1:3 with these filters, 2 years may yield too few trades to judge |
| Modelling | **Every tick based on real ticks** | "Every tick" is generated from M1 bars; real ticks capture intra-bar SL/TP order |
| Delays | **Random delay** | "Zero latency, ideal execution" is optimistic — it assumes your stop fills at the exact price |
| Deposit | **$500–$2,000** | Below ~$1,000 the 0.01-lot ladder rung is reachable; above ~$10,000 it is not |
| Leverage | 1:100 | Irrelevant at 0.01 lots, but keep it realistic |
| Optimization | Disabled | Never optimise before the funnel has been read |
| **"Profit in pips for faster calculations"** | **UNCHECK** | See warning below |

### ⚠️ Do not leave "profit in pips" checked

That option makes the tester compute P&L in pips instead of account currency. Two problems:

1. The **D-19 cooldown ladder reads `AccountInfoDouble(ACCOUNT_BALANCE)` and position profit in money**. Percent-of-capital thresholds are meaningless if the tester is not moving the balance normally.
2. Every risk number in these docs — 15% = ~25 losing trades at $500, etc. — assumes currency P&L.

Uncheck it. If the run is too slow, shorten the date range instead of degrading the accounting.

### Two runs, in this order

| Run | `InpDryRun` | What you get |
|---|---|---|
| **A — plumbing** | `true` | Every rejection logged with its rule. This is the only mode that prints the funnel, because rejections are only `Print`ed when dry-run is on |
| **B — behaviour** | `false` | Real trades, equity curve, cooldown triggers, slippage |

**Run A first.** It tells you whether the rules fire at all and which one is the binding constraint — before you interpret a single P&L number. Run B with dry-run off will not print the funnel; you would only get the summary line at deinit.

---

## Rule mapping

| Checklist rule | Where in the EA | Notes |
|---|---|---|
| 1. Bias (HTF) | `GetBias()` | D1 swing-leg; D authoritative (D-01) |
| 2. Liquidity sweep | sweep search in `Evaluate()` | ATR-relative penetration + reclaim close (D-02) |
| 3a. Structure clean | `StructureClean()` | Efficiency ratio + swing density + **range test** (D-04) |
| 3b. Structure shift | MSS block in `Evaluate()` | Intervening swing, close beyond, displacement (D-13) |
| 4. Entry model | `BuildZone()` | **Prior impulse** 45–55% (D-05 option C) |
| 5. Confirmation | `BuildPOI()` + `IsBullEngulf()` | OB ∩ FVG, full-range engulf (D-06, D-08) |
| 6. Risk management | `CalcLots()`, SL block | SL set on the order before entry (D-07); **fixed 0.01 lots** (D-18), so risk % is an outcome, not a control |
| 7. Bias alignment | `OnTick()` assertion | Raises on mismatch; never trades (D-01/R7) |
| 8. Mental state | `LossCooldownActive()` | **Partial** — 30-min post-loss cooldown; daily check-in still absent |
| 9. Trade limit | `CountTradesToday()` | 3/day + 07:00–16:00 UTC window (D-10) |
| Exit | `InpRewardRisk` | Fixed 1:3, attached at entry (D-09) |

### Rule 8 — partially implemented

Your checklist's rule 8 is *"not emotional / not forcing / not chasing losses."* **A bot cannot evaluate this, and an EA that reports it as "passing" would be lying.**

| Clause | How it is handled |
|---|---|
| "not emotional" | Structurally satisfied — no discretionary entries exist |
| "not forcing trades" | Proxied — 3/day cap, session window, setup TTL |
| "not chasing losses" | **Proxied — 30-min post-loss cooldown (`InpLossCooldownMin`)** |
| Daily check-in (`RSK-11`) | **Absent** — needs a human interface; belongs to the Python system |

So the EA implements **part** of rule 8. It should not be described as running all 9 rules until the check-in exists.

---

## Sizing and the capital cooldown (D-18 / D-19)

### Fixed 0.01 lots (D-18)

`InpSizingMode = SIZING_FIXED_LOT`, `InpFixedLots = 0.01`. Every trade is 0.01 lots.

Because the lot is fixed, **risk per trade is no longer a percentage you control** — it falls out of the stop distance and your balance. The EA logs the real number on every trade:

```
Tradie sizing: 0.01 lots | SL 32.4 p | risk 3.24 (0.32% of balance)
```

At 30-pip stops ≈ **$3 risk per trade**, so:

| Balance | Risk/trade | 35% loss requires |
|---|---|---|
| $500 | ~0.6% | ~55 losing trades |
| $2,000 | ~0.15% | ~230 losing trades |
| $10,000 | ~0.03% | ~1,100 losing trades |

**This is the key interaction with the cooldown:** the loss rate is fixed in *currency*, but the trigger is fixed in *percentage*. On a large account the cooldown is effectively unreachable. Read §"The 35% trap" below.

### Capital cooldown — two stages (D-19)

| Stage | Input | Default | Pause | Flatten |
|---|---|---|---|---|
| **SOFT** | `InpSoftLossPct` / `InpSoftHours` | **15%** / **24 h** | pause entries | no |
| **HARD** | `InpCooldownLossPct` / `InpCooldownHours` | **35%** / **168 h** | halt entries | **yes** |

SOFT is the "stop and think" rung — it stops new entries while your open trades keep their broker-side SL/TP. HARD flattens and stops the EA for a week.

Both measure **this EA's own** P&L (magic-filtered), realised + floating:

```
stageLoss% = -((realised_since_anchor + floating) / refCapital) * 100
```

Each stage keeps its own **anchor** (reference capital + cumulative realised P&L at that moment), persisted in terminal global variables. On expiry the anchor moves to the then-current balance, so the next threshold is measured from there. Without that, a still-unrecovered loss would re-arm the stage instantly and forever.

```
Tradie D-19[SOFT] TRIGGERED: loss 15.31% >= 15.0% of ref capital 2000.00
  (realised since anchor -306.20, floating 0.00). Paused for 24h until 2026-10-26 14:22
```

### Post-loss cooldown — rule 8 (D-12)

`InpLossCooldownMin = 30`. After **any** realised loss, no new entry for 30 minutes.

```
Tradie: D-12/R8: post-loss cooldown, 27 min remaining - no new entries
```

This is arguably the most useful of the three: it acts on the behaviour rule 8 actually names — re-entering straight after a loss — instead of waiting for a drawdown. It counts exits only, includes swap/commission in deciding what a "loss" is, and seeds itself from history on restart so the clock doesn't reset.

### Resetting the cooldowns

| Action | How |
|---|---|
| Clear everything (soft, hard, post-loss) | Set `InpCooldownReset = true`, restart, set it back to `false` |
| Clear just the anchors | Tools → Global Variables (**F3**) → delete `TRADIE_SOFT_*` / `TRADIE_HARD_*` / `TRADIE_LASTLOSS_*` |
| Disable stage 1 | `InpSoftEnabled = false` |

⚠️ **Validation rule:** `InpSoftLossPct` must be **below** `InpCooldownLossPct`. The EA refuses to start otherwise — stage 1 firing after stage 2 would be meaningless.

### Still a backstop, not a risk system

The ladder improves on a single 35% trapdoor, but read the numbers:

- After **−35%** you need **+53.8%** to recover. After two: **−57.75%**, needing **+137%**.
- The PRD's emergency equity brake (`RSK-08`) is **4%**. The HARD rung is ~9× looser.
- The EA still implements **none** of the PRD's L1–L5 breaker stack — no 3% daily halt, no loss-streak pause. The 30-minute post-loss rule is a *partial* substitute for the streak breaker, not a full one.

**Where these fire depends on your lot size.** At 0.01 lots risk is ~$3/trade, fixed in currency while the thresholds are fixed in percentage:

| Balance | Risk/trade | 15% (SOFT) | 35% (HARD) |
|---|---|---|---|
| $500 | ~0.6% | ~25 losing trades | ~55 |
| $2,000 | ~0.15% | ~100 | ~230 |
| $10,000 | ~0.03% | ~500 | ~1,100 |

On a large test account the ladder is effectively unreachable. **The 30-minute post-loss rule is the one that will actually fire** — which is the right outcome, but worth knowing before you conclude the ladder is working.

### ⚠️ The 35% trap

**Do not mistake this for a risk control. It is a kill switch that fires after severe damage.**

- After **−35%** you need **+53.8%** to recover. Two of them = **−57.75%**, needing **+137%**.
- The PRD's emergency equity brake (`RSK-08`) is **4%**. This threshold is ~9× looser. The EA implements **none** of the PRD's L1–L5 breaker stack (daily 3% halt, loss-streak pause, 4% equity brake). D-19 is not a substitute for them.
- With 1:3 and ~30% winners, **8–10 consecutive losers is routine** (roughly once per 30–60 trades). At 0.01 lots on $500 that's ~−6%, so you are safe *at that lot size*. If you raise lots, the same streak costs more **while the 35% trigger stays put** — the trigger does not scale with position size.

**Cheap improvement, if you want it:** a second, lower threshold (e.g. 15%) that pauses 24 h *without* flattening. Two-stage gives you "stop and think" before catastrophe. ~20 lines, reusing the existing machinery — ask and I'll add it.

---

## Settings that will change your results most

| Input | Default | What it does | If you get too few trades |
|---|---|---|---|
| `InpRewardRisk` | 3.0 | Target RR (D-09) | Don't lower this first — it's your ratified decision. Check the funnel before touching it |
| `InpRequireFVG` | true | Require an FVG (part of D-08) | Set `false` → order block only |
| `InpRequireOB` | true | Require an order block | Set `false` → FVG only |
| `InpRequireZoneTouch` | true | Price must tap the 50% zone | Leave on — it's rule 4 |
| `InpRetraceAnchor` | 0 (prior impulse) | 50% of which leg | Set `1` to test the displacement leg (option A) — this is the single biggest A/B test available |
| `InpMinRangeATR` | 2.0 | Range-floor filter (D-04) | Lower to 1.5 |
| `InpERMin` | 0.30 | Chop filter | Lower to 0.25 |
| `InpSessionStartUTC` / `End` | 7 / 16 | Entry window | Widen to 7–21 |

**Test one change at a time, and always compare out-of-sample.** Every knob above is a place where you can overfit 3 years of data into a beautiful equity curve that means nothing.

---

## Expected trade frequency — and why the sample size matters

From `docs/decisions.md` §0f: at **1:3**, break-even win rate is **25%** (≈27–29% after costs). You need enough trades for the observed win rate to be distinguishable from break-even — that is roughly **200+ trades**, not 50.

At an estimated 0.05–0.15 setups/pair/day *after* OB∩FVG and 1:3 filtering, on 12 pairs, expect something in the range of **100–300 trades/year pooled**. That's a guess, not a measurement — **the Strategy Tester is how you replace it with a number.** Run the longest history your broker has (5+ years if available) on 3–4 pairs first, count the trades, and *then* decide whether the rule set is too selective.

**If you get <20 trades per pair over 5 years, the problem is selectivity, not the EA.** The funnel log tells you which rule is the binding constraint — read it before changing anything.

---

## Known limitations (deliberate, documented rather than hidden)

1. **`InpCooldownReanchor` is retained but inert** — stages always re-anchor on expiry, because not doing so makes them re-arm forever.
2. **Cooldown state lives in terminal global variables**, not in the EA's own file. Deleting them resets the ladder. In the Strategy Tester these persist between runs on the same terminal.
3. **No persistence of setup state.** Reloading the EA or changing timeframe resets any in-progress setup. Fine for the tester; the production engine persists setups (INV-10).
4. **`D-14` (ranking two competing setups) is not implemented** — that requires a multi-symbol instance. Single-symbol-per-chart makes it moot.
5. **`D-15` sticky setup is implemented**, but "recording" a superseded sweep means a `Print` to the Journal, not a durable journal row.
6. **No news blackout.** `RSK-09` needs an external calendar; the tester can't supply one.
7. **No currency-exposure cap.** `RSK-04` is portfolio-level and needs all pairs in one process.
8. **The cooldown does not prevent losses, only repeats.** It cannot foresee a drawdown, and it is measured on this EA's trades only.
9. **Server-time offset is auto-detected** from `TimeTradeServer() - TimeGMT()`. **Verify it in the Journal on the first run** — if the session filter looks wrong, that line is why. In the tester the offset may report 0; set `InpAutoGMTOffset=false` and `InpGMTOffsetHours` to your broker's true offset (commonly +2 or +3).
10. **`input group` headers** require MetaEditor build 2650+ (2020). If your build is older, delete the `input group` lines.
11. **Spread** comes from your broker's tester settings. A backtest on raw-spread "every tick" data will look better than a demo account at 18:00 UTC. Set a realistic spread.

---

## What to send me back

After your first real run, these four numbers tell me whether the rule set is viable or needs surgery:

1. **Total trades** and the date range
2. **Win rate** and **average RR achieved**
3. The **rejection funnel** — which `R*` reason dominates the Journal
4. **Max drawdown** from the tester report

From those I can tell you whether to widen the zone, relax OB∩FVG, revisit 1:3, or whether the model simply needs more pairs.
