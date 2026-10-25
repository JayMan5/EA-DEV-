# Dry run with D-08 enforced — the full funnel (2026-10-26)

EURUSDm, M15, 2021.10.01 → 2026.09.30, deposit 500, `04-zone-entry.set`, dry run.
`evaluations=46725 rejections=46703` → **22 signals, 18 distinct setups.**

`Tradie D-20: conf0=0 conf1=18 conf2=54 conf3=10 | signals by score: 0/0/18/4 | mode=zone minConf=0`

This run closes three open questions: D-08 is verified, the dry-run and real-run frequencies now reconcile to the trade, and the funnel shows where the remaining frequency actually lives.

---

## 1. D-08 is verified working

`signals by score: 0/0/18/4` — the `conf = 1` bucket is empty. Nothing with only an order block or only a fair value gap becomes a trade.

| | RUN D (no D-08) | this run (D-08) |
|---|---|---|
| Signals from `conf = 1` | 13 | **0** |
| Signals from `conf = 2` | 22 | 18 |
| Signals from `conf = 3` | 4 | 4 |
| **Total signals** | **39** | **22** |
| D-08 rejections | — | 36 bar-evaluations |

**17 signals were removed, not 13.** I predicted "~26 or fewer" and the figure is 22, slightly below my estimate. The extra four are the important part: they scored 2 through *order block + zone overlap* while having no FVG — exactly the conflation the score was hiding. A threshold of `InpMinConfluence=2` would have let them through.

**Correction to the RUN G write-up.** It said "D-08 removed 13 of the 39, position-blocking removed 4 more". The accurate decomposition is:

- D-08 removed **17** (13 at `conf=1`, plus 4 at `conf=2` missing their FVG)
- 39 − 17 = 22 dry signals
- those 22 contain **4 re-entries** on setups that were already open, leaving **18 distinct setups**
- 18 distinct setups = **18 real trades**. Nothing extra was lost to position blocking.

The final frequency figure in that document (3.6/yr/pair) was right. The explanation of how the 18 was reached was wrong, and this run is what settles it.

---

## 2. Dry and real now agree to the trade

| | Signals | Distinct setups | per year |
|---|---|---|---|
| Dry run (this log) | 22 | **18** | 3.6 |
| Real ticks (RUN G) | 18 trades | **18** | 3.6 |

The two runs produce **the same 18 setups** — I checked every `(bias, sweep price)` pair, and every real trade appears in the dry run. The only difference between 22 and 18 is four second-and-third entries on a setup that already had a position open:

| Setup | Dry-run entries | Prices |
|---|---|---|
| `down sweep@1.08533` | 2024.03.05 12:15, 12:45, 14:45 | 1.08465, 1.08463, 1.08457 |
| `down sweep@1.08594` | 2024.02.26 15:00, 15:15 | 1.08461, 1.08410 |
| `down sweep@1.09138` | 2024.11.04 14:30, 16:00 | 1.09008, 1.08989 |

This is the measurement apparatus validating itself. A dry run can now be used to predict live trade counts, provided duplicates are collapsed. That was not true before this run.

---

## 3. The funnel — every rejection accounted for

| Rule | Rejections | Share |
|---|---|---|
| **R3a structure quality** (ER + swing density + range) | 23,503 | **50.3%** |
| **R3b no structure shift** | 10,269 | **22.0%** |
| **R2 sweep** (none found + violated) | 6,515 | **13.9%** |
| **R4 zone not reached** | 5,075 | **10.9%** |
| **R5 entry** (confirm not in zone, no engulf, D-08, chase) | 1,341 | **2.9%** |
| **signals** | **22** | |
| **total** | **46,725** | 100% |

Sums exactly: 23,503 + 10,269 + 6,515 + 5,075 + 1,341 + 22 = 46,725.

### The entry machinery is now 2.9% of the decision surface

Everything built in the last two rounds — the zone entry, the POI demotion, the confluence score, the D-08 gate, the chase guard — sits in the bottom 2.9%. **Rules 1 to 3 decide 86.2% of all outcomes.**

That is the end of the line for entry-side tuning. There is no further work above this line that can move the trade count more than a few percent.

---

## 4. No single threshold is the answer — the arithmetic

Sensitivity, if one gate were removed entirely:

| Gate removed | Extra signals | Result | Multiple |
|---|---|---|---|
| R3a ER | +22.3 | ~44 | ×2.0 |
| R3b MSS | +9.7 | ~32 | ×1.4 |
| R2 sweep | +6.2 | ~28 | ×1.3 |
| R4 zone | +4.8 | ~27 | ×1.2 |

**Removing the biggest filter completely — setting `InpERMin` to zero — only doubles the trade count.** And these are upper bounds: bars that fail a quality gate survive the later gates *less* often than average, so the real gain would be smaller.

The reason is visible in the conditional rates:

```
bars passing R3a:                          23,222
of those, reaching the R5 stage:            1,363   (5.87%)
of those, becoming a signal:                   22   (1.61%)
```

A signal needs to pass six independent conditions. At a 5.9% × 1.6% conversion, no amount of adjustment to any one of them produces an order of magnitude. **This is a structural property of a six-way confluence model, not a tuning problem.**

---

## 5. Sample concentration is a second, separate problem

Trade count is not the only weakness. The 18 setups are badly clustered:

| Year | Setups |
|---|---|
| 2021 | 2 |
| 2022 | 1 |
| 2023 | 2 |
| 2024 | **7** |
| 2025 | 4 |
| 2026 | 2 |

**39% of all setups came from 2024**, and the single largest winner came from 2022 — the year with only one setup. Pooling 12 pairs helps with the total but not necessarily with the clustering, because correlated FX pairs share regime shifts.

Any verdict will therefore be dominated by whichever years happen to produce setups. This raises the bar for the number of trades needed well beyond the 34 implied by the R-multiple spread.

---

## 6. A cross-pair inconsistency to decide before scaling to 11 pairs

`InpMinSLPips = 12` is an **absolute** distance, but the stop it competes with is **ATR-relative** (`InpMaxSLATR = 6.0`). On EURUSD:

| | Value |
|---|---|
| M15 ATR | ~5–8 pips |
| `InpMinSLPips = 12` | ≈ **1.5–2.0 × ATR** |
| `InpMaxSLATR = 6.0` | ≈ 36–48 pips |

So on EURUSD the floor is a *binding, relatively wide* constraint — the stop sat exactly at 12.0 pips in a third of the trades. On GBPJPY, where M15 ATR is roughly 20–30 pips, 12 pips is about **0.5 ATR** and will almost never bind. **The same preset is a different strategy on each pair.**

Two ways forward:

**(a) Run the 11 pairs as-is.** Comparable to everything measured so far, and it is what you would actually trade. The floor's influence varies by pair, which you can see directly in each run's SL distribution.

**(b) Add an ATR-relative floor first** (`InpMinSLATR`, e.g. 1.5× ATR) so the rule set means the same thing on every symbol, then run all 12.

**Recommendation: (a) first.** Running as-is costs 11 short backtests, keeps the 18-trade EURUSD baseline comparable, and the per-pair SL distributions will show immediately whether the floor is distorting a pair. If it is, (b) becomes a one-line addition and the pairs can be re-run — but we would then know *why* it changed rather than assuming.

I am not changing the input unilaterally. This is flagged as **D-21 (open)**.

---

## 7. Next action

Run the remaining 11 pairs of the D-16 universe with `06-realrun-zone.set`, real ticks, one run per symbol, shared magic. Priority: **GBPJPY, EURJPY, GBPUSD, AUDUSD**.

Expected yield at the measured rate: 11 pairs × 3.6/yr ≈ **40 trades/year**, reaching 200 in roughly **4.6 years**. If the JPY crosses convert better through R3a — likely, since their efficiency ratio is structurally higher than EURUSD's 0.14 median — it will be faster.

What to report back per pair, and what I will be looking for:

1. `Tradie stop:` and `Tradie D-20:` lines — trade count and score distribution.
2. The SL distribution from the `Tradie sizing:` lines — this is how we see whether `InpMinSLPips = 12` is binding on that pair.
3. Any pair producing **zero** trades over five years — that is a signal the preset does not transfer, not that the pair has no opportunities.
