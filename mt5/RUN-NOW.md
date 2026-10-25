> **Status: RUN D and RUN E are done.** Results: [`results/2026-10-25-run-d-vs-e.md`](results/2026-10-25-run-d-vs-e.md).
> Option B gave **39 signals vs 14** (×2.8). Next action is **RUN G** — `06-realrun-zone.set`, see the README.
> Compile first: the EA gained `InpZoneRequireOBFVG`, which enforces D-08 in zone mode.

# RUN NOW — D-20 A/B test (EURUSDm M15) — COMPLETED

Two dry runs, ~4 seconds each. One command to look at afterwards. Nothing here sends an order.

**Do them in this order: E first, then D.** E is the control — it proves the build still produces the same 14 signals as before. If E doesn't, D's number means nothing.

---

## Step 0 — compile first, or this is all wasted

`Tradie.mq5` is now **v1.100** and has three inputs that did not exist in v1.000. If you load a preset into the old `.ex5`, MetaTrader silently ignores the unknown keys and you would be running option A while believing you were running option B.

Open `Tradie.mq5` in MetaEditor → **F7**. Expect `0 errors, 0 warnings`.

Then confirm with the line the EA prints at startup:

```
Tradie D-20: entry=AT_ZONE (option B) | OB/FVG = confluence score 0-3, minConf=0 | max chase 0.50xATR
```

If you never see a `Tradie D-20:` line, the old `.ex5` is still loaded.

---

## Step 1 — put the two preset files where the tester can see them

The tester's **Load** button only browses one folder:

```
<your terminal data folder>\MQL5\Profiles\Tester\
```

Copy both files from `mt5/presets/` into it:

- `04-zone-entry.set`
- `05-poi-control.set`

**Finding that folder when you don't know where it is:** in MetaTrader, **File → Open Data Folder**, then go into `MQL5` → `Profiles` → `Tester`. Create `Tester` if it is not there — that is normal on a fresh install and is why the Load button sometimes shows nothing.

---

## Step 2 — Settings tab (both runs)

Set Symbol and Period **before** loading the preset. Changing the symbol in the Settings tab can reset the Inputs tab back to defaults, and then you would be running stock parameters.

| Field | Value |
|---|---|
| Expert | `Advisors\Tradie.ex5` |
| Symbol | `EURUSDm` |
| **Period** | **M15** ← the single most common mistake. Not H1 |
| Date | Custom period, `2021.10.01` → `2026.10.24` |
| Forward | No |
| Delays | Zero latency, ideal execution |
| Modelling | `1 minute OHLC` |
| Deposit | `500` USD |
| Leverage | `1:100` |
| Optimization | Disabled |
| Visual mode | off |
| Profit in pips | off |

Identical for both runs. **Nothing on the Settings tab changes between E and D** — that is the point.

---

## Step 3 — Inputs tab

### RUN E — control (load `05-poi-control.set`)

Five cells differ from the stock defaults. Everything else stays at default.

| Input | Stock | **RUN E** |
|---|---|---|
| `InpDryRun` | false | **true** |
| `InpERMin` | 0.30 | **0.20** |
| `InpMinSLPips` | 8.0 | **12.0** |
| `InpEntryMode` | `B: confirmation bar must trade into the 50% zone` | **`A: legacy - engulf must overlap the OB/FVG POI`** |
| `InpMaxSLATR` | 6.0 | **3.0** |

### RUN D — option B (load `04-zone-entry.set`)

Three cells differ from the stock defaults.

| Input | Stock | **RUN D** |
|---|---|---|
| `InpDryRun` | false | **true** |
| `InpERMin` | 0.30 | **0.20** |
| `InpMinSLPips` | 8.0 | **12.0** |

`InpEntryMode` stays at its stock value `B: confirmation bar must trade into the 50% zone`, and `InpMaxSLATR` stays at `6.0`.

### If the Load button is missing or shows an empty list

Right-click inside the Inputs list → **Load** (on some builds it is only in the right-click menu, not as a visible button). If that is not there either, load `Tradie-default.set` first — it is in the same folder — and then edit the cells in the tables above by hand. Five numbers, nothing else.

Type `0.2`, **not** `0,2`. A locale that uses the comma as decimal separator will reject the value and snap back to 0.30.

### The values that must match, spelled the way the tab shows them

| Input | RUN E | RUN D |
|---|---|---|
| `InpDryRun` | `true` | `true` |
| `InpERMin` | `0.2` | `0.2` |
| `InpMinSLPips` | `12.0` | `12.0` |
| `InpMaxSLATR` | `3.0` | `6.0` |
| `InpEntryMode` | `A: legacy - engulf must overlap the OB/FVG POI` | `B: confirmation bar must trade into the 50% zone` |
| `InpMinConfluence` | `0` | `0` |
| `InpMaxEntryPastZoneATR` | `0.5` | `0.5` |
| `InpRetraceAnchor` | `C: most recent swing → sweep ext…` | same |
| `InpRequireOB` / `InpRequireFVG` | `true` / `true` | same (unused in zone mode) |

**The `Start` / `Step` / `Stop` columns are the optimiser's sweep columns.** With Optimization = Disabled they are ignored completely. Only `Value` matters. If one of them looks wrong, ignore it.

---

## Step 4 — run, then read the last three lines of the Experts tab

Each run takes a few seconds. Afterwards the Experts tab ends with:

```
Tradie stop: evaluations=.. rejections=.. | EA realised 0.00 | SOFT 0.00% of 500.00 | ...
Tradie D-20: conf0=.. conf1=.. conf2=.. conf3=.. | signals by score: ../../.. | mode=poi minConf=0
```

`mode=poi` for RUN E, `mode=zone` for RUN D. If RUN E says `mode=zone`, the preset did not apply.

### What RUN E must show

**~14 signals.** It is the archived RUN A configuration on the same build and the same five years. If it comes out materially different from 14, something other than the entry mode changed and RUN D must not be interpreted.

### What RUN D must show

The measurement. Either outcome is informative:

| RUN D result | What it means |
|---|---|
| **more than ~14** | entering in the zone finds setups that never travelled on to the POI. D-20 is working as intended |
| **~14** | the two entry locations trigger on the same setups; frequency is not the problem |
| **fewer than ~14** | price often reverses before retracing fully into the zone. Read the `R4/D-20: confirm N.Np from ...` reasons: mostly 1–3 pips means the zone is slightly too narrow (widen to 42–58); 20+ pips means those setups genuinely never retrace |

---

## Step 5 — send me back

1. The last 3 lines of the Experts tab **for each run** (the `Tradie stop:` and `Tradie D-20:` lines).
2. The top 8 rejection reasons from each — either paste the log or send the
   `MQL5\Logs\YYYYMMDD.txt` and `MQL5\Tester\...` files.

I need the rejection funnel, not just the signal count. The count alone cannot tell me *which* gate moved, and the convergence score line is what determines whether `InpMinConfluence` should be raised for the next run.

---

## What is deliberately not being tested yet

- **No orders are sent.** Both runs are `InpDryRun=true`.
- **No trailing, no partials, no break-even moves.** The EA has none.
- **The 15% / 35% cooldown ladder will not fire** at a $500 deposit. It needs ~60 losses to reach 15%. That is expected; `03-cooldown-test.set` exists to test it in isolation.
- **Profitability is not being measured.** At 14–30 trades over five years, P&L carries no information. This run decides whether there is enough of a sample to measure anything at all.

---

## Expect this to look worse before it looks better

The target is 3× the stop. The stop is now the distance from the zone down to the sweep extreme — roughly half the leg — instead of the few pips it used to be. So a 12-pip stop that meant a 36-pip target is now a ~40-pip stop that means a ~120-pip target.

**A lower hit rate at the same 1:3 is the arithmetic consequence, not a defect.** If it falls off a cliff, the thing to question is the fixed 1:3 (D-09), not this change.
