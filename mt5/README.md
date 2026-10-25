# Tradie EA — MT5 implementation of the 01C checklist

A MetaTrader 5 Expert Advisor that implements the ratified rule set from `docs/rule-spec.md` and `docs/decisions.md`, so the strategy can be **backtested and forward-tested without OANDA API access**.

## ⚠️ Read this before you run it

**This is a research tool, not the production system.**

| | |
|---|---|
| **What it is** | A faithful implementation of the 9-rule checklist that you can compile, backtest in the Strategy Tester, and forward-test on demo |
| **What it is not** | The system in `docs/Tradie PRD v2.md`. It has **no** crash-safe state, **no** order reconciliation, **no** idempotency, **no** circuit-breaker persistence, **no** news blackout, and **no** portfolio-level currency-exposure cap |
| **Compile status** | **Not compiled by the author.** Written against documented MQL5 APIs and syntax-checked for balanced structure only. If MetaEditor reports an error, send me the line number and the message |
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
| 8. Mental state | **Not implemented** | Cannot be automated — see below |
| 9. Trade limit | `CountTradesToday()` | 3/day + 07:00–16:00 UTC window (D-10) |
| Exit | `InpRewardRisk` | Fixed 1:3, attached at entry (D-09) |

### Rule 8 — the one rule that isn't in the EA

Your checklist's rule 8 is *"not emotional / not forcing / not chasing losses."* **A bot cannot evaluate this, and an EA that reports it as "passing" would be lying.** In this EA rule 8 is only *partially* present:

- **Structurally satisfied** — no discretionary entries exist
- **Partly proxied** — the 3-trade cap and the session window limit "forcing" behaviour

**Not present:** the daily operator check-in and the 30-minute post-loss cooldown (`D-12`). The check-in needs a human interface; the cooldown needs persistent cross-session state. Both belong in the Python system. If you want the cooldown in the EA, it's a small addition — say so.

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

### Capital cooldown (D-19)

Pauses new entries when **this EA's own** realised + floating P&L reaches **−35%** of reference capital.

| Input | Default | Meaning |
|---|---|---|
| `InpCooldownLossPct` | 35.0 | Trigger threshold (% of reference capital) |
| `InpCooldownHours` | 168 | Pause length. `0` = halt until you set `InpCooldownReset=true` |
| `InpCooldownFlatten` | true | Close open EA positions when it triggers |
| `InpCooldownReanchor` | true | After expiry, measure the next 35% from the *new* balance |
| `InpCooldownReset` | false | Set `true` once, recompile/restart, to clear a manual halt |

Reference capital is captured **once** on first run and stored in a terminal global variable (`TRADIE_BASE_<magic>`), so a shrinking balance cannot outrun the trigger. Reset it by deleting that global variable (Tools → Global Variables, F3).

When it fires you'll see:

```
Tradie D-19 TRIGGERED: EA loss 35.12% >= 35.00% of reference capital 1000.00
  (realised -341.20 + floating -10.00). Entries paused until 2026-11-01 14:22
Tradie D-19: flattening open EA positions
```

While cooling down, entries are skipped with `D-19: cooldown until ...` in the journal. **Friday flatten and existing SL/TP keep working** — the cooldown blocks new entries, it does not stop position management.

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

1. **No persistence of setup state.** Reloading the EA or changing timeframe resets any in-progress setup. Fine for the tester; the production engine persists setups (INV-10).
2. **`D-14` (ranking two competing setups) is not implemented** — that requires a multi-symbol instance. Single-symbol-per-chart makes it moot.
3. **`D-15` sticky setup is implemented**, but "recording" a superseded sweep means a `Print` to the Journal, not a durable journal row.
4. **No news blackout.** `RSK-09` needs an external calendar; the tester can't supply one.
5. **No currency-exposure cap.** `RSK-04` is portfolio-level and needs all pairs in one process.
6. **The cooldown does not prevent losses, only repeats.** It cannot foresee a drawdown, and it is measured on this EA's trades only.
7. **Server-time offset is auto-detected** from `TimeTradeServer() - TimeGMT()`. **Verify it in the Journal on the first run** — if the session filter looks wrong, that line is why. In the tester the offset may report 0; set `InpAutoGMTOffset=false` and `InpGMTOffsetHours` to your broker's true offset (commonly +2 or +3).
8. **`input group` headers** require MetaEditor build 2650+ (2020). If your build is older, delete the `input group` lines.
9. **Spread** comes from your broker's tester settings. A backtest on raw-spread "every tick" data will look better than a demo account at 18:00 UTC. Set a realistic spread.

---

## What to send me back

After your first real run, these four numbers tell me whether the rule set is viable or needs surgery:

1. **Total trades** and the date range
2. **Win rate** and **average RR achieved**
3. The **rejection funnel** — which `R*` reason dominates the Journal
4. **Max drawdown** from the tester report

From those I can tell you whether to widen the zone, relax OB∩FVG, revisit 1:3, or whether the model simply needs more pairs.
