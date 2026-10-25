# RUN G — first real-tick run with D-08 enforced (2026-10-25)

EURUSDm, M15, 2021.10.01 → 2026.09.30. Deposit 500, fixed 0.01 lots, **real orders**, **real ticks**, D-20 zone entry, `InpZoneRequireOBFVG = true`.

`evaluations=46307 rejections=46289` → **18 trades. EA realised −4.39 (−0.88%).**

> **The headline is not the −4.39.** It is that 18 trades cannot distinguish a losing system from a winning one, and this run finally tells us how many trades we need and where to get them.

---

## 1. The D-08 fix worked exactly as designed

| | RUN D (before fix) | RUN G (after fix) |
|---|---|---|
| Setups with a confirmed engulf | 74 | 74 |
| `conf = 1` (only OB **or** only FVG) | 18 | 18 |
| **Signals from `conf = 1`** | **13** | **0** |
| Signals from `conf >= 2` | 26 | 18 |
| **Total signals** | **39** | **18** |

`signals by score: 0/0/15/3` — the `conf = 1` bucket is empty. D-08 is a rule again, not a scoring threshold. That was the point of the fix, and it is verified.

The 26 → 18 drop is a second, separate effect: this run placed real orders, so an open position on the symbol blocks later entries. RUN D counted those. The honest dry-run figure was 22 signals; 4 of them were re-entries on a setup already open, leaving 18 distinct setups — which is exactly the 18 trades placed.

---

## 2. All 18 trades

| # | Opened | Side | Entry | Exit | Pips | P/L | SL | Exit type |
|---|---|---|---|---|---|---|---|---|
| 1 | 2021.10.05 | sell | 1.15983 | 1.16095 | −11.2 | −1.12 | 12.0 | SL |
| 2 | 2021.10.07 | sell | 1.15614 | 1.15758 | −14.4 | −1.44 | 12.0 | SL |
| 3 | 2022.09.12 | sell | 1.01382 | 0.99557 | **+182.5** | **+18.25** | 60.9 | **TP** |
| 4 | 2023.03.23 | buy | 1.08898 | 1.08648 | −25.0 | −2.50 | 23.9 | SL |
| 5 | 2023.11.23 | sell | 1.09047 | 1.09248 | −20.1 | −2.01 | 19.8 | SL |
| 6 | 2024.02.26 | sell | 1.08464 | 1.08611 | −14.7 | −1.47 | 14.8 | SL |
| 7 | 2024.03.05 | sell | 1.08466 | 1.08595 | −12.9 | −1.29 | 12.0 | SL |
| 8 | 2024.03.22 | buy | 1.08200 | 1.08079 | −12.1 | −1.21 | 12.0 | SL |
| 9 | 2024.09.12 | buy | 1.10187 | 1.10555 | **+36.8** | **+3.68** | 12.6 | **TP** |
| 10 | 2024.11.04 | sell | 1.09012 | 1.09154 | −14.2 | −1.42 | 14.4 | SL |
| 11 | 2024.11.07 | sell | 1.07523 | 1.07823 | −30.0 | −3.00 | 30.3 | SL |
| 12 | 2024.12.03 | sell | 1.05019 | 1.05309 | −29.0 | −2.90 | 29.0 | SL |
| 13 | 2025.04.09 | buy | 1.10534 | 1.10059 | −47.5 | −4.75 | 47.8 | SL |
| 14 | 2025.06.13 | buy | 1.15238 | 1.15486 | +24.8 | +2.48 | 37.5 | Friday flatten |
| 15 | 2025.09.16 | sell | 1.18014 | 1.18190 | −17.6 | −1.76 | 17.1 | SL |
| 16 | 2025.11.13 | sell | 1.16150 | 1.16269 | −11.9 | −1.19 | 12.0 | SL |
| 17 | 2026.05.15 | buy | 1.16326 | 1.16184 | −14.2 | −1.42 | 14.2 | SL |
| 18 | 2026.06.15 | sell | 1.16071 | 1.16203 | −13.2 | −1.32 | 13.8 | SL |

15 stops, 2 targets, 1 Friday flatten. Win rate **16.7%**; break-even at 1:3 is **25%**.

### The plumbing is now beyond doubt

| Check | Result |
|---|---|
| Orders filled | **18 / 18** |
| Errors, assertions, invalid stops, margin failures | **0** |
| Average loss vs intended risk | **−1.01R** — stops honoured, ~1% slippage |
| Post-loss cooldown (D-12) | fired **15 times**, immediately after each loss |
| D-19 capital ladder | 0.88% of capital drawn down — nowhere near the 15% rung |
| Friday flatten | fired once, correctly |

An average loss of −1.01R on real ticks is the strongest evidence yet that execution is sound. Slippage or stop-placement bugs show up as −1.3R or −1.6R averages.

---

## 3. What the −4.39 actually means: nothing yet

Expressed in R, so trades with different stop sizes are comparable:

```
n = 18    sum = -8.64R    mean = -0.480R    sd = 1.313R
t = -1.55 (df 17)        two-sided p = 0.121
95% CI on expectancy: [-1.13R, +0.17R]
```

**The 95% confidence interval includes zero.** It also includes +0.17R, which would be an excellent system. The observation is consistent with break-even and cannot be distinguished from it.

From the win-rate side, if the true win rate were 25%:

```
P(X <= 3 wins in 18) = 0.31
```

A 31% chance of seeing this from a break-even system. Not evidence of failure. Not evidence of anything.

**Sample size needed:** at this spread, about **34 trades** are required to tell −0.48R from zero. We have 18 — roughly halfway to a first verdict on this pair.

### One trade carries the entire result

| | P/L |
|---|---|
| The 182.5-pip winner (trade 3, the Sept 2022 EURUSD collapse) | **+18.25** |
| All 17 other trades | **−22.64** |
| Net | **−4.39** |

Remove that one trade and the system looks far worse. Keep it and the result is near-flat. **A result that hinges on one trade out of eighteen is not a result** — which is precisely why the sample arithmetic matters more than the equity curve.

---

## 4. Live frequency is 3.6/yr/pair — half the dry-run figure

The most consequential number in the run, and a correction to my earlier estimate.

| | Signals / 5 yr | Per year | 12 pairs → 200 trades |
|---|---|---|---|
| RUN D, dry run (option B, no D-08) | 39 | 7.8 | 2.4 years |
| RUN D, distinct setups | 35 | 7.0 | 2.7 years |
| **RUN G, real orders, D-08 on** | **18** | **3.6** | **4.6 years** |

The dry run overstated live frequency by **2.2×**, for two reasons, both legitimate:

1. **D-08 removed 17 of the 39.** A ratified rule doing its job. (Corrected 2026-10-26: this document originally said 13. The other 4 scored 2 through *order block + zone overlap* while missing an FVG — see §1 of `2026-10-26-dryrun-d08-funnel.md`.)
2. **4 of the remaining 22 dry-run signals were re-entries** on setups that already had a position open. Collapsing them leaves **18 distinct setups**, which is exactly the 18 trades taken. No additional trades were lost to position blocking — the 22 → 18 gap is entirely duplicates.

**After RUN D I reported 2.4 years to a verdict. The honest figure is 4.6.** That estimate rested on a dry run that cannot know about point 2, and I should have flagged the suppression risk at the time rather than quoting the number as though it were achievable.

---

## 5. Two caveats on this run's execution modelling

**Real ticks only exist back to 2024.08.16.** The tester log states:

```
EURUSDm: real ticks begin from 2024.08.16 00:00:00
2021.10.01 - 2026.10.01: real ticks absent for 1256 minutes of 1848698 total
minute bars, every tick generation used
```

So 2021.10 → 2024.08 — which includes the 182.5-pip winner in trade 3 — was modelled on **generated** ticks. Coverage is excellent where real ticks exist (99.93% of minutes), but this run should not be described as fully real-tick.

**No commission appears in the P&L.** My independent per-pip calculation reproduces −4.39 exactly, which means the tester charged nothing. A typical EURUSD ECN commission on 0.01 lots is ~$0.07 round trip, so 18 trades ≈ **$1.30 more**, taking the result to roughly −5.7. Small at this size, but it is a systematic bias that grows with trade count and must be accounted for before any forward test.

---

## 6. One structural drag worth naming: the Friday flatten

Trade 14 was closed by `InpFridayFlatten` at **+0.66R** while its target was still 3R away.

Average win is therefore **2.19R**, not 3R. At an average win of 2.19R, the break-even win rate is **31.3%**, not 25%. Every position closed early on a Friday raises the win rate the system needs.

With one occurrence this is not evidence of a problem, but the mechanism is real — and Friday flattening is a rule I added on my own initiative, not one from the checklist. **Flagged, not changed.** If it starts truncating winners regularly it should be revisited.

---

## 7. What to do next

**Stop testing EURUSD.** Eighteen trades in five years, with a confidence interval wider than any effect we could hope to detect. More EURUSD runs will not fix that.

**Run the other 11 pairs of the D-16 universe** with `06-realrun-zone.set`, real ticks, one run per symbol. A shared magic is fine — each Strategy Tester run is independent. Pooling 12 pairs at 3.6/yr gives **~43 trades/year**, reaching 200 trades in about **4.6 years** — sooner if the other pairs are more active than EURUSD, which is likely.

**Priority order: GBPJPY, EURJPY, GBPUSD, AUDUSD.** EURUSD has the least favourable structure of the twelve: lowest ATR, highest efficiency, and an ER distribution whose median (0.14) sits well below the 0.20 floor. JPY crosses have higher ATR and far more sweep-and-reclaim behaviour, which is what this rule set actually needs.

**One cheap extra run:** a dry run of `04-zone-entry.set` (now that D-08 is on) to recover the full rejection funnel on the current build. The real run only prints the two summary lines, so we currently cannot see which gate the 56 non-signal setups died on. That matters before scaling to 12 pairs, because a pair-specific bottleneck would be missed by pooling.
