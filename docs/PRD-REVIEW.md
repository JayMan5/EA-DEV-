# Tradie — PRD Review: Limitations, Tradeoffs & Feasibility

> **Reviewing:** `Tradie PRD.md` v1.0.0-draft and `Tradie PRD_APPENDIX.md`
> **Review date:** 2026-10-25
> **Reviewer stance:** pre-implementation technical review. No code exists yet, so this is a *buildability* review, not a code review.

---

## 0. Verdict first

Feasibility has to be split into three separate questions, because they have very different answers.

| Question | Verdict | Why |
|---|---|---|
| **Can this be built as described?** | **Yes — high confidence** | Every component is a well-trodden pattern: REST polling, a candle-close loop, rule predicates, Telegram, systemd. Roughly 2,500–5,000 LOC of Python. No research risk in the *engineering*. |
| **Can it be built and operated without losing money to bugs?** | **Medium** | The spec omits crash-safety, order idempotency, reconciliation, and a kill switch. These are the failure modes that actually cost money, and none of them are in F-01…F-10. |
| **Will it prove an edge?** | **Unknown — and the PRD's own acceptance criteria cannot establish one** | The 9 rules are never defined. The gates (3 months, win rate ≥60%, Sharpe ≥1.2) are statistically too weak to mean anything. |
| **Can you even connect it to a broker from Nigeria?** | ⚠️ **Probably not on OANDA — verify before writing any code** | The OANDA v20 REST API is documented as **not available on OANDA Global Markets**, and Global Markets is the entity that serves Nigerian residents. This is the #1 project-level risk and the PRD doesn't mention it. |

**One-line summary:** the *engineering* is a 4–6 week project. The *specification risk* is bigger than the engineering. The *broker-access risk* is bigger than both, and it is unaddressed.

---

## 1. The five things that decide whether this project works

Ordered by how much they should affect your plan.

### 🔴 BLOCKER 1 — Broker/API access for your jurisdiction

The PRD assumes "OANDA REST API v20, practice → live" as a given. That assumption has three failure points stacked on each other.

**(a) OANDA's v20 REST API is not offered on the entity that serves Nigeria.**
From OANDA's own v20 introduction: *"To use this API you must have a v20 trading account, which is available to all divisions **except OANDA Global Markets** and OANDA TMS BROKERS S.A."* ([developer.oanda.com](https://developer.oanda.com/rest-live-v20/introduction/), reinforced in the [API comparison table](https://developer.oanda.com/rest-live-v20/api-comparison/): *"Availability restrictions by division — Not yet available in Global Markets"*).

**(b) OANDA Global Markets is exactly the division a Nigeria-resident client gets.** Third-party broker reviews consistently describe Nigerian clients being onboarded under *OANDA Global Markets Ltd* (BVI). OANDA Global Markets publishes an explicit eligible-country list (Chile, Colombia, Hong Kong, Indonesia, Macao, Malaysia, Mexico, Philippines, Taiwan, Thailand, UAE, Vietnam) — [help.oanda.com](https://help.oanda.com/bvi/en/faqs/eligible-ogm-countries-bvi.htm) — on which Nigeria does not appear; and several independent trackers list Nigeria among OANDA's restricted jurisdictions. OANDA's own region selector *does* list Nigeria, so the public information is genuinely contradictory.

**(c) Therefore: you may be able to open an account and trade manually from the web platform, while the API your entire product depends on is unavailable to you.**

**Why this is a blocker and not a footnote:** F-01, F-02, F-03, F-06 and F-07 all depend on programmatic OANDA access. If v20 is unavailable, "Tradie Live" is not buildable as specified, and the fallback is MT4/MT5 — which Section 5 explicitly forbids.

**Verify this before anything else. It's a 15-minute test:**

1. Create an OANDA demo/practice account, selecting Nigeria as country of residence.
2. In the account portal → *Manage API Access* → generate a token. **If the option isn't there, that's your answer.**
3. `curl -H "Authorization: Bearer $TOKEN" https://api-fxpractice.oanda.com/v3/accounts` → expect `200`. A `403`/`401` with a "not available for your account/division" style message is the kill signal.
4. `GET /v3/accounts/{id}` and read `guaranteedStopLossOrderMode` and `marginRate` — this tells you what F-07 actually has to work with.
5. Only if 3 and 4 pass, run `POST /v3/accounts/{id}/orders` on the practice account with a 1-unit market order and a `stopLossOnFill`.

**If it fails, your realistic options** (each is a real tradeoff, pick deliberately and write it into the PRD):

| Option | Cost |
|---|---|
| Build **Tradie BT only** (v0.1) against free candle data, defer live indefinitely | Zero downside — and it's the correct order of work anyway |
| Another broker with a REST/WebSocket API (e.g. cTrader Open API via a broker that supports it, FXCM's REST API, Darwinex, IG's API) | Rewrites `execution.py`, re-validates order semantics, new jurisdiction question |
| OANDA under a different division (requires genuine residency elsewhere) | Not a software problem; do not paper over it with a VPN — that's a ToS/KYC problem, not a networking problem |
| MT5 + a hosted bridge (e.g. MetaApi) | Contradicts Section 5; adds a paid third-party vendor in the execution path; MT5's own "fragile headless" concerns return |

**And whatever the answer: F-07's "stop-loss guaranteed" is also jurisdiction-dependent.** OANDA exposes `guaranteedStopLossOrderMode` as `DISABLED | ALLOWED | REQUIRED` per account. GSLO is advertised in Singapore/Australia, unavailable to US and UK clients, and carries a premium charged only when triggered. So "guaranteed" must be a *runtime capability check*, not a design assumption — with a documented degrade path (plain SL + an explicit slippage assumption in the backtest).

---

### 🔴 BLOCKER 2 — The 9 rules don't exist yet. That's the whole product.

This is the most important line in the entire document set: `RULES_IDS = ["BIAS_HTF", "LIQUIDITY_SWEEP", "MARKET_STRUCTURE", "ENTRY_MODEL_RETRACE", "ENGULFING_CONFIRMATION", "RISK_MANAGEMENT", "BIAS_ALIGNMENT_GATE", "CIRCUIT_BREAKERS", "TRADE_LIMIT"]`.

Those are **names**, not specifications. There is no definition anywhere of:

- What "liquidity sweep" means numerically — sweep of *which* prior high/low? How many bars back? By how many pips? Wick-only or close-through? Does it have to be followed by a displacement candle?
- What "market structure" is — BOS? CHoCH? Which swing detection algorithm, with what lookback/fractal sensitivity? This single choice changes results more than most of the other rules combined.
- What "bias" is on H4/D — an EMA slope? A higher-high/higher-low count? A weekly open relationship? How do two timeframes disagreeing get resolved?
- "ENGULFING_CONFIRMATION" — classic body-engulf of the previous candle? At what body-to-range ratio? Does it have to close beyond the swept level?
- What "ENTRY_MODEL_RETRACE" retraces to — the 50% of the displacement leg? The order block? The FVG? Within how many candles does the retrace have to happen before the setup expires?

**Consequences if you start coding first:**

1. **You will build a backtester that discovers a different strategy every time you tweak a "rule" you never pinned down.** Every parameter you leave implicit becomes a free variable you can accidentally fit to the data. That's how a 3-month backtest produces a 78% win rate and the live version produces 41%.
2. **F-01's "≥90% rule logic coverage" is untestable.** You cannot measure coverage of an undefined predicate.
3. **Only 6 of the 9 "rules" are signal rules.** `RISK_MANAGEMENT`, `CIRCUIT_BREAKERS` and `TRADE_LIMIT` are *gates*, evaluated from account/state data, not from price. Three of them can never "fail" for the reason a trader would expect, and one implies two rules are redundant with each other (`BIAS_HTF` and `BIAS_ALIGNMENT_GATE` look like the same check). The "9 rules = 9 independent conditions" framing is really **~6 signal conditions + 3 portfolio gates**, and the PRD should say so — it changes how you order the code and report rule attribution.

**What to do instead:** write `docs/rule-spec.md` **before** `checklist.py`, one page per rule, each with: inputs (pairs/timeframes/lookbacks), the exact predicate in pseudocode, parameters with defaults and allowed ranges, a worked example from real candles, and 2–3 **fixture tests** (a bar sequence that must pass, and one that must fail for the right reason). That document is 2–4 days of work and it de-risks the next 4 weeks. It also gives you something you can hand to another trader for critique, which is the only quality control available to a solo builder.

Also worth deciding now: **`BIAS_ALIGNMENT_GATE` implies the 6 signal rules could be evaluated on both timeframes**, but F-01 asks for M15/H1/H4/D/M5 data with no statement of which timeframe each rule reads from. Define the mapping explicitly per rule (`rule → granularity`), because in the backtester it determines the resampling and look-ahead logic.

---

### 🟠 BLOCKER 3 — The validation gates cannot prove an edge

The PRD sets three acceptance gates: 3 months of replay, win rate ≥60%, Sharpe ≥1.2. Each is individually too weak, and together they are close to noise.

**"Minimum 3 months replay" is a sample-size problem.** At M15, ~96 bars/day × ~65 trading days ≈ **6,240 bars per pair** — that part is fine. But trades are the sample, and you cap at **3/day**. If the 9-rule conjunction fires ~2x/day across 5 pairs, 3 months ≈ 60–180 trades. On 60 trades, a 60% win rate has a 95% confidence interval of roughly **47%–72%**. You cannot tell 60% from 48%, and the gate lives entirely inside that uncertainty band.

**Sharpe ≥1.2 on 3 months is meaningless.** With T = 0.25 years, the standard error of an annualized Sharpe ratio is ≈ `sqrt(1/T)` ≈ **2.0**. You have a signal-to-noise ratio well below 1. A "Sharpe 1.2" from 3 months is statistically indistinguishable from zero.

**Win rate ≥60% is a *bad* objective.** It's easy to hit and says nothing about profitability. With a 1:2 minimum RR you'd be profitable at 40%. Prioritising win rate pushes you toward bad risk-reward, and worse: the PRD's own sample daily report shows **"Avg RR: 1:1.8"** — which **violates F-06's "minimum 1:2 enforced"**. That contradiction is already live in the spec, in the example output.

**Compounding sanity check.** If the strategy genuinely hit the acceptance criteria — 60% win rate at 1:2 → **+0.8R per trade** — at 3 trades/day × 250 days × 1% risk, that's **+600% per year**. No retail forex strategy sustains that. The gates, if passed, would more likely indicate a **backtest bug** (look-ahead, or costs not modelled) than an edge. Treat a too-good result as a *defect signal*, and encode that expectation now.

**Replace the gates with:**

- **Costs modelled from day one**: spread (per pair, time-of-day aware — spread widens 3–5x at rollover and around news), commission (if the account is commission-based), overnight swap for multi-day holds, and a **slippage assumption** on market entries. Without these, a 1:2 setup on EUR/USD where the round-trip cost is ~1 pip on a 20-pip stop is a **~5% expectancy headwind per trade** — enough to turn a positive edge negative.
- **Walk-forward, not a fixed window**: e.g. 18–24 months of data, 6-month in-sample optimization, 3-month out-of-sample, rolled forward. Report OOS only. Report **per-pair** and **pooled**, because 5 pairs is not one market.
- **Minimum *trade-count* gates, not calendar gates**: e.g. ≥100 OOS trades before any conclusion, and a bootstrap/jackknife confidence interval on expectancy reported alongside every point estimate.
- **Report expectancy in R and in money, with costs broken out** (gross vs net). If the strategy only works gross, it doesn't work.
- **Explicit holdout**: reserve the most recent 3–6 months and *don't look at it* until you've frozen parameters. This is the only real defence against parameter fitting.

---

### 🟠 BLOCKER 4 — No crash safety, no reconciliation, no kill switch

This is the class of omission that turns a working strategy into a blown account. The PRD's Appendix C state machine is entirely **in-memory and happy-path**:

```
MonitorState --> TradeClosed: SL/TP hit
```

What actually happens at 02:47 when the VPS reboots, or Oracle reclaims the instance, mid-position?

- On restart, `state.json` says "AwaitFill" or "MonitorState". **The order may or may not exist on OANDA.** The PRD has no reconciliation step. You do not know if you're flat, long, or long *twice* (if the daemon re-derives the signal and re-fires).
- **No order idempotency.** OANDA's `clientExtensions.id` / `tag` field is the standard mechanism for safe retry; it's not mentioned. Retrying a `POST /orders` after a timeout without an idempotency key is a duplicate-position bug waiting to happen.
- **No kill switch / panic path.** Section 5 says "manual trade override: do NOT build — violates discipline". That conflates two different things: *overriding a trade decision* (correctly forbidden) and *stopping the bot and closing out* (mandatory). **Any live-trading system needs a hard stop that is not "the strategy".** I'd add `tradie panic` (cancel everything, close all, disable the timer) as a first-class CLI command and say explicitly that it is *not* an override.
- **A late or missed candle is not handled.** F-03 says "evaluate on every M15 candle close". What if the process was down for 4 candles, or the API call took 90 seconds? Does it evaluate the missed bars (and then what — trade a setup 40 minutes stale?), or skip to the current one? Specify: **evaluate only the most recently *completed* candle, and only if the decision is made within N seconds of its close.** OANDA's candle response has a `complete` flag — filter on it, or you will evaluate a **partially formed candle and see the future** in backtest.
- **No clock discipline.** "Heartbeat every minute" and "counter resets at 00:00 UTC" both assume a trustworthy clock. Enable NTP, and assert clock skew at startup.
- **No position-netting semantics.** OANDA nets positions by default unless the account has hedging enabled. If the strategy goes long EUR/USD while a short is open, you may silently *reduce* rather than open. Read `hedgingEnabled` at startup; if false, enforce "one direction per instrument" in code.
- **No JPY/quote-currency pip-value handling.** F-06 says "lot size auto-calculated from SL distance", and target pairs include **USD/JPY**. P&L on USD/JPY is denominated in JPY and must be converted to account currency before "1–2% of balance" means anything. This is the single most common silent bug in retail forex bots: it sizes JPY-cross positions wrongly by ~the FX rate. Specify the pip-value formula and unit-test it against all 5 pairs.
- **OANDA uses *units*, not lots.** `trade_size: 0.015 # lot size` must become an integer unit count, rounded to the instrument's trade-size precision, and checked against `minimumTradeSize` / `maximumOrderUnits`. Also missing: a **margin check** before submission (otherwise you get order rejections rather than graceful skips, and rejections after a streak breaker reset can cascade).

**Minimum additions to F-07/F-08:** order idempotency key; startup reconciliation (fetch open trades + orders, diff against persisted state, adopt or flatten); atomic state writes (`write temp → fsync → rename`) or just SQLite via stdlib `sqlite3` (ACID, one file, no dependency, queryable — strictly better than JSON here); an append-only `events` log written *before* the API call and updated *after* it (intent-then-confirm), so a crash between the two is recoverable.

---

### 🟠 BLOCKER 5 — No cost model, and the news breaker has no historical archive

**Costs are absent from the entire PRD.** No spread, no swap, no commission, no slippage anywhere — including the NFRs and the backtest output spec. For a strategy whose average risk is presumably ~20–40 pips, this is not a detail: EUR/USD spread is ~0.8–1.5 pips in normal hours and **4–8+ pips at rollover (21:00–22:00 UTC) and around high-impact news**. An M15 system that trades through those windows on market orders can surrender 10–25% of its theoretical edge to friction. Every backtest report from F-01 must print **gross P&L, total costs, net P&L**, and per-pair average cost in pips.

**The news breaker can be backtested only in one direction.** F-05 needs "high-impact news within ±30 min". F-10 and Appendix A name ForexFactory as the source. The practical reality:

- The free weekly export (`ff_calendar_thisweek.json` / `.xml` / `.csv`) is **current-week only** — no reliable next-week feed (the `nextweek` variant 404s), **no actual values**, and it is **rate-limited to roughly 2 requests per 5 minutes across all formats**, returning an HTML "Request Denied" page when exceeded. It also sits behind Cloudflare and blocks some VPS IPs.
- Therefore **you cannot retroactively build the news-blackout history a backtest of Rule 8 needs.** You would be backtesting a rule you can only evaluate going forward — which means the breaker's effect is *unmeasured* at go-live, and it silently changes the strategy's trade count versus the backtest.
- Options: (i) accept it and state explicitly that R8 is evaluated live-only, **backtest with the breaker disabled**, and treat the difference as a known gap; (ii) buy a calendar with historical actuals (Trading Economics / FMP / Finnhub-class APIs) for backtesting; (iii) archive the free feed daily from day one into your own parquet store, which is cheap to build and starts paying off in 4–8 weeks.
- **Legal note:** ForexFactory's terms restrict automated use of the site. A low-frequency pull of the *published export* is the usual accommodation; scraping `forexfactory.com/calendar` HTML is where the ToS exposure lives. Prefer the export endpoint, and make the source swappable (the PRD half-does this via `NEWS_SOURCE` — good instinct, follow through with an interface).

Also note **Appendix A contradicts F-05**: `NEWS_BLACKOUT_HOURS` defaults to **±1 hour** in the appendix, ±30 minutes in F-05. Pick one and make the env var authoritative.

---

## 2. Limitations, grouped

### 2.1 Internal contradictions (fix before coding — each one is a future bug report)

| # | Where | Contradiction |
|---|---|---|
| C-01 | F-05 vs Appendix A | News blackout **±30 min** vs `NEWS_BLACKOUT_HOURS` default **±1 hr** |
| C-02 | F-06 vs §8 sample report | "Minimum 1:2 RR enforced" vs sample shows **"Avg RR: 1:1.8"** |
| C-03 | F-01 vs Appendix F | Backtests saved to `Tradie/backtests/*.csv` vs `reports/trades-*.csv` |
| C-04 | Appendix D vs E vs F | Entry point is `backtest.py` vs `tradie.py --backtest` vs `scripts/backtest.py` |
| C-05 | F-05 vs F-06 | 3% session DD breaker vs 2-loss breaker: at **1%** risk, 2 clean losses (−2%) never trigger a 3% DD pause; at **2%** risk, 2 losses (−4%) blow through both and the two breakers collide (4 hr vs 2 hr — which wins?) |
| C-06 | F-08 vs F-01 | "Counter resets at 00:00 UTC" but HTF bias uses OANDA **Daily** candles, which are not UTC-midnight aligned in most divisions. Two different "days" in one system — specify both explicitly |
| C-07 | F-03 vs Appendix B | "Evaluates rules atomically **on every M15 close**" vs `Order` carrying `max_drawdown` and `news_blackout` — gate data is *state*, not a per-candle signal. Rules 7–9 are portfolio gates; the data model should separate `signal_rules[]` from `gates[]` |
| C-08 | Appendix B | `Order = TypedDict("Order", {...})` / `rule_results: Dict[str, bool]` is **not valid Python** (bare identifiers in an argument list). Also the schema has no `order_id`, `instrument`, `timestamp`, `units`, `time_in_force`, or `client_order_id` — i.e. no idempotency and no instrument |
| C-09 | F-07 vs §5 | "Trade **Execution & Management**" — there is no management. SL/TP only, no trailing, no partial close, no time-based exit. An M15 setup with no time stop can sit open for days collecting swap |
| C-10 | F-06 vs Appendix B | `trade_size: 0.015 # lot size` vs OANDA's integer **units** |

### 2.2 Missing requirements

| # | Gap | Why it matters |
|---|---|---|
| M-01 | **The rule definitions** (see Blocker 2) | The product *is* the rules |
| M-02 | **Correlation / net-currency exposure cap** | 5 pairs is really ~2 independent bets: EUR/USD, GBP/USD, AUD/USD and USD/CAD are **one USD trade in four costumes**. Without a cap, "1% per trade" becomes a 3–4% USD position on a bad USD day — and the 3% DD breaker fires on a single correlated event |
| M-03 | **Execution idempotency + startup reconciliation** | Duplicate/orphan positions after any crash |
| M-04 | **Kill switch** (distinct from "override") | No safe way to stop the system at 3am |
| M-05 | **Cost model** (spread/swap/slippage/commission) | Invalidates every backtest number |
| M-06 | **Candle completeness + staleness guard** | Look-ahead in backtest, stale entries in live |
| M-07 | **Margin / order-rejection handling** | Rejections are normal; the spec has no path for them |
| M-08 | **Weekend / market-closed / holiday handling** | Forex closes Fri ~21:00 UTC, reopens Sun ~21:00. Trades held over the weekend collect swap and gap risk past the SL — which directly undermines "stop-loss guaranteed" |
| M-09 | **Defined statistics** | "Sharpe ratio" and "max drawdown" are undefined: annualization basis, R-based or %-based, peak-to-trough trade-close or intra-trade equity? Two correct implementations give different numbers |
| M-10 | **Backtest ≠ live parity harness** | Nothing asserts that live rule evaluation and backtest rule evaluation are the *same code path*. If they're two implementations, they will diverge — silently. This is the most important architectural rule in the whole project: **one `evaluate(candles, state) -> Decision` used by both** |
| M-11 | **Timezone/DST in the news feed** | The FF export emits New York local time with an offset; "±30 min" requires correct offset parsing |
| M-12 | **Deployment: no `systemd` unit, no log-out retention, no secrets-redaction filter** | F-09 says "alert on failure" but nothing *supervises* the daemon. Also `loguru`/`requests` at DEBUG will print the `Authorization` header — F-09's "mask keys in logs" needs an actual sink filter, not an intention |
| M-13 | **Alert-channel redundancy** | Telegram is the only channel for *and* the subject of alerts. If the token is revoked or Telegram is unreachable, failure is silent — the worst possible property for a monitoring system |
| M-14 | **"Screenshot of session.log on request"** | Implies the bot polls `getUpdates` and runs a command handler — a new inbound attack surface (anyone who finds the bot can ask it things, and can map your account) plus a lost-update problem if two processes poll the same token. Restrict to a single `chat_id` allowlist, or make it opt-in and off by default |

### 2.3 Architecture / technology risks

| # | Risk | Assessment |
|---|---|---|
| A-01 | **VectorBT is the wrong tool for this strategy** | F-01 says "vectorized replay". But the 9 rules are *path-dependent and stateful* — position lifetime, consecutive-loss counters, "session drawdown", "already swept in the last N bars", "trades today". VectorBT is built for entry/exit-matrix sweeps, not for a state machine with circuit breakers. Using it will push you toward (a) reimplementing the rules in a second, vectorized form — which breaks M-10 — or (b) leaking future information. **Recommendation: write a simple event loop over candles; it will do 5 pairs × 2 years in seconds-to-a-minute and it is trivially correct.** Keep VectorBT, if at all, as an optional parameter-sweep tool over the *same* `evaluate()` function. Also, `.hdf5` is not a "VectorBT format" — use **parquet** (columnar, typed, compressed, concurrent-read-safe; HDF5 has no safe concurrent-writer story) |
| A-02 | **Bare metal, no container** | Fine for a solo VPS, and it reduces moving parts. The cost is **environment drift between backtest and live**. Mitigate cheaply: pinned lockfile (`requirements.txt` with hashes or `uv.lock`), and embed the resolved dependency versions + git SHA + data hash into every backtest JSON. Containers are *not* required; reproducibility is |
| A-03 | **JSON state file** | Use `sqlite3` from stdlib instead: transactional, crash-safe, one file, and you get free queryability for the journal. JSON + `os.replace` is acceptable, but you'll outgrow it by the time you have a trade journal |
| A-04 | **Polling REST vs streaming** | Rate limits are not the issue — the documented limit is **120 req/s per IP**, and M15 on 5 pairs needs ~5 requests per 15 minutes. But polling means your entry price is up to one poll-interval stale, and your fill confirmation has latency. A streaming pricing connection (20 concurrent streams allowed) is the better live design and *also* gives you an accurate fill timestamp for the "≤2s latency" NFR. Backtest can stay on candles — but then state clearly that the backtest assumes fills at candle close |
| A-05 | **Oracle Cloud Ampere free tier as production host** | Attractive (4 OCPU/24GB free), but: A1 capacity is frequently unavailable, and Oracle has announced reclaiming idle Always-Free instances. For a bot holding live positions, either pay for a small always-on instance or diversify the ops story. Also: 2 OCPU/4GB in §6.1 is overspecified for this workload by a wide margin — the bot will use <200MB, so optimize for *reliability*, not size |

### 2.4 Operational & process limitations

- **The paper-trading soak is calendar time, not engineering time.** You cannot compress it. If you want 4 weeks of paper results before live, that's 4 weeks *after* code-complete. Plan for it or accept going live on less evidence (and say so explicitly rather than pretending the 3-month backtest covers it).
- **98% monthly uptime is a claim you can't currently observe.** There's no monitoring off the box. A heartbeat that reports to the same host cannot report that host's death. Use an external dead-man's switch (healthchecks.io free tier, Uptime Kuma on another host) plus a Telegram check-in; that converts "is it up?" from a feeling into a fact.
- **§10 has exactly one release row for F-01…F-10.** Ten features, including a new backtesting engine, a rule framework, live execution, and ops, in a single "v1.0". For one person this is a *5–7 month* estimate as written, and every one of those months is exposed to the unvalidated rule definitions. Split it (see §5).
- **PRD hygiene:** still `draft — pending approval`, dated 2026-05-29, five months stale, and the document has no version-control story for the *strategy* itself. Add a `strategy_version` to every trade record and backtest report — when you change a rule parameter, you need to know which trades came from which version, or your journal becomes unanalyzable.

### 2.5 Security

The PRD's §9 is directionally right but thin in one specific way that matters: **an OANDA token is account-wide, unscoped, and (as far as is documented) not IP-restrictable.** Anyone with the token can trade, withdraw nothing — but *trade*, which is also a way to lose everything. So the VPS becomes a full-trust credential store.

Minimum bar:

- Separate **practice token for development**, never `OANDA_ENVIRONMENT=live` in a shell where experiments run. Make the config failsafe: require an explicit `--i-understand-this-is-live` flag *in addition* to the env var.
- SSH keys only, `PermitRootLogin no`, `ufw default deny incoming`, `fail2ban`, `unattended-upgrades`.
- `.env` at `0600`, owned by the service user; pass via `systemd EnvironmentFile=` rather than shell exports (which leak into `history` and `/proc`).
- **A real redaction filter** on the log sink (regex for `Bearer`, `access_token`, the Telegram bot-token path segment). Outbound HTTP at DEBUG level will otherwise write your token to disk in plaintext, and `logs/` is one `git add .` away from a leak. Add `.gitignore` entries for `.env`, `logs/`, `*.parquet`, `*.json` state **before** the first commit.
- Telegram: allowlist the `chat_id`, use a private chat, and treat the bot token as a secret (it's a URL path segment — it will appear in proxy logs and in any HTTP error traceback).
- Document a **token rotation runbook** (revoke → issue → deploy → verify). You will need it at least once.

### 2.6 Legal / compliance (not legal advice, just flags)

- Jurisdiction eligibility for the broker account (§1, Blocker 1) is a ToS/KYC question, not a technical one. Resolve it honestly; a VPN does not change what division you're entitled to, and an account closed for misrepresentation mid-position is a very bad day.
- ForexFactory automated-access terms (§Blocker 5).
- Whether automated trading is permitted on your specific account type, and whether your jurisdiction requires any registration to trade your own capital (in most, not — but confirm).
- OANDA's API licence agreement constrains redistributing their market data. Fine for personal use; a hard stop on any future "sell signals" or dashboard-for-others idea (which §5 already parks as Phase 2 GUI — worth noting the constraint now).

---

## 3. Tradeoffs — each design decision, what it buys, what it costs

| Decision in PRD | You gain | You pay | My recommendation |
|---|---|---|---|
| **CLI-only** | Fast to build, no auth surface, no UI maintenance | Live exposure is invisible except in logs; you'll SSH at 2am | Keep. Add `tradie status` (positions, breakers, counters, last eval) and `tradie panic` as first-class commands — they're the two you'll actually need live |
| **Static SL/TP, no trailing** | **The strongest decision in the PRD.** The daemon is not in the exit path: if it dies, the trade still exits. Massively simpler to test and reason about | Gives up trend capture; larger average loss in trends | Keep for v1. Buys you the right to have bugs in the *entry* path while exits stay safe. Revisit only after you have 6 months of live data |
| **Market entry only** | Guaranteed fill, no stale-order management, simple state machine | Slippage exactly when you don't want it (post-news, rollover) | Keep, but log `fill_price − signal_price` on every trade and alert if it exceeds a threshold. This is your cheapest early-warning signal that costs are worse than modelled |
| **No pending orders** | Simpler state | The `ENTRY_MODEL_RETRACE` rule is *literally describing* a limit entry. You evaluate the retrace on candle close and then market-in, which is a worse version of the same idea | Keep for v1 (fill certainty > optimisation), but note the tension. A `limitOnFill` at the retrace level is the natural v2 |
| **"Seamless" paper → live switch** | One flag, easy mental model | Practice pricing/leverage/liquidity differ from live; a single typo in `.env` risks capital; nothing reconciles the two | Make live **deliberately hard**: separate token, separate config file, explicit `--live` flag *plus* confirmation, and a startup banner that says `LIVE` in red for 10 seconds. And require a flat book before switching |
| **Circuit-breaker state in JSON on disk** | Transparent, debuggable, greppable | Crash/corruption; concurrent writes if cron `report.py` touches it too | SQLite, single writer process. Make the daemon the *only* writer; cron jobs read-only |
| **3% session DD / 2-loss / 3-trade-cap** | Cheap, mechanical, emotionally effective | The three overlap and can contradict (C-05); "session" is undefined; and at 1% risk the DD breaker is nearly unreachable while the streak breaker does all the work | Define "session" = UTC trading day, explicitly. Set the DD limit *below* the arithmetic of the other two, or drop it. The 3-trade cap is the one that actually protects you — keep it |
| **News blackout ±30 min** | Cheap, protects against the worst slippage | Live-only (no backtest history), brittle data source, false positives on low-relevance events | Keep, fail **closed** (if the feed is stale beyond N hours, block new entries and alert — never silently disable), and *widen* to ±60 min around the top-tier events only |
| **ForexFactory scraper** | Free, familiar | Rate-limited (2/5min), Cloudflare, ToS-sensitive, no history, no next-week | Use the published export endpoint at low frequency, cache aggressively, archive daily to parquet, keep the source behind a swappable interface |
| **5 pairs, no correlation cap** | More setups | The 4 USD-major pairs are **one trade**. Real risk per "1% trade" can be 3–4% | **Fix this.** Cap total USD-directional exposure (e.g. ≤2% of equity across all USD-correlated pairs) |
| **No MT4/MT5** | Avoids Wine/headless fragility — correct | Removes your fallback if OANDA v20 access fails | Keep the reasoning, but *pre-plan* the fallback rather than being forced into it under pressure |
| **Single user, no RBAC** | Far less work | None | Correct. Multi-user later if ever |
| **Telegram as the only channel** | Free, mobile, excellent DX | Single point of failure for both *reporting* and *being told that reporting is broken* | Add one dumb fallback (email/SMS/ntfy) and an off-host heartbeat |
| **No container** | Fewer moving parts | Env drift between backtest and live | Keep bare metal; buy reproducibility with a lockfile + recorded hashes |
| **2 OCPU / 4 GB** | Comfortable headroom | Nothing | Fine; note that reliability (not CPU) is the binding constraint, so spend the effort on supervision, not specs |

---

## 4. Feasibility: what's easy, what's hard, what's unknown

**Genuinely easy (days, high confidence):**
Telegram alerts and the daily report (F-04, F-08) — `python-telegram-bot` + a cron job. Config/secrets (F-10). Log rotation (F-08). Lot sizing math (F-06) once you write the pip-value function — it's ~40 lines and 20 unit tests. Historical download + local cache (F-02) — paginate 5,000-candle pages; 3 months of M15 for 5 pairs is ~1–2 requests per pair.

**Moderate (weeks, medium confidence):**
The checklist engine (F-03) — moderate *because* the rules aren't defined, not because the code is hard. Once `rule-spec.md` exists, `checklist.py` is a list of pure functions over a candle window, and it's the most testable part of the system. Trade execution (F-07) — moderate due to OANDA's order/error surface (rejections, netting, precision, margin), not due to complexity. Persistence + restart safety (F-08) — moderate because it must be designed, not bolted on.

**Hard (and where the real risk sits):**
The **backtester** (F-01) — hard not because a loop is hard, but because *correctness* is hard: avoiding look-ahead in HTF resampling, modelling candle-close fills honestly, applying costs, and proving parity with live. Expect 2–3x your initial estimate here. **This is the component where a bug is invisible and expensive.**

**Unknown / blocking:**
Broker API availability in your jurisdiction (Blocker 1). Rule definitions (Blocker 2). Whether the strategy has *any* edge (unknowable until 1 and 2 are resolved, and the honest answer today is "no evidence either way").

**Bottom line on effort (one developer, part-time-ish):**

| Milestone | Scope | Estimate |
|---|---|---|
| **v0.1 — Tradie BT** | `rule-spec.md`, data cache, event-loop backtester with costs, walk-forward, report JSON/CSV | **3–4 weeks** |
| **v0.2 — Tradie Live(paper)** | Checklist as one shared `evaluate()`, execution adapter, SQLite state, reconciliation, breakers, Telegram, systemd, off-host watchdog | **3–4 weeks** |
| **v0.3 — paper soak** | Run it. Do not code. Watch for divergence between paper results and backtest distribution | **4+ weeks, calendar-bound** |
| **v1.0 — live (small size)** | Deliberate-live safeguards, panic path, runbook, monitoring | **1 week + ongoing** |

That's **~8 weeks of engineering and ~3 months to first responsible live trade** — versus the PRD's implicit "one release". The gap is not laziness; it's that v1.0 bundles research, engine, execution and ops into one bucket with no milestone exit criteria.

---

## 5. What I'd change in the PRD (prioritised)

**P0 — before one line of trading code:**
1. Run the broker/API smoke test (§Blocker 1) and write the result into the PRD as a resolved decision, including the chosen entity and whether GSLO is `ALLOWED`.
2. Write `docs/rule-spec.md`. Until each rule has pseudocode and pass/fail fixtures, the project has no definition of done.
3. Replace §7's validation targets: walk-forward, OOS-only, ≥100 trades, expectancy with confidence intervals, costs always netted out. Delete "win rate ≥60%" and "Sharpe ≥1.2 on 3 months" — replace with "does net OOS expectancy remain positive across rolling windows and across pairs?"
4. Add a **Costs** subsection to F-01/F-06: spread model per pair and session, swap for multi-day holds, slippage assumption, commission if applicable. Add "gross vs net" to every report.
5. Add **idempotency + startup reconciliation + kill switch** to F-07/F-08.

**P1 — before paper trading:**
6. Resolve C-01…C-10 (the contradictions table). Cheap now, expensive later.
7. Add the **correlation/net-exposure cap** (M-02) — this is the missing risk control that matters most.
8. Add the **backtest↔live parity rule** (M-10) as a hard architectural constraint, and state that the backtester is event-driven.
9. Define the statistics (M-09) precisely enough that two implementations agree.
10. Add the **off-host watchdog** and one non-Telegram alert path (M-13).

**P2 — before live:**
11. Split §10 into v0.1 (BT) / v0.2 (paper) / v1.0 (live) with explicit exit criteria per milestone.
12. Add a `strategy_version` to every record; add a runbook for token rotation and for "bot is misbehaving at 3am".
13. Reconcile `NEWS_SOURCE` behaviour and ToS posture; archive the feed daily.

**Spec-quality nit worth fixing:** the Appendix B `Order` schema is not valid Python and is missing the fields that make it safe. Suggested shape:

```python
@dataclass(frozen=True)
class Decision:
    instrument: str            # "EUR_USD"
    ts: datetime               # UTC, candle close being evaluated
    direction: Literal["long", "short"] | None
    signal_rules: dict[str, bool]   # the 6 signal rules
    gates: dict[str, bool]          # RISK_MANAGEMENT, CIRCUIT_BREAKERS, TRADE_LIMIT
    units: int                      # OANDA units, not lots
    entry_ref: float                # price at decision time
    sl: float
    tp: float
    strategy_version: str
```

A `Decision` with `direction=None` is the normal case, and it is still worth logging: **the rejected-signal journal is your most valuable research asset** (it's how you learn which rule is over-filtering). The PRD's journal only records taken trades.

---

## 6. Open questions I'd need answered

1. **Do you currently have, or can you get, an OANDA v20 API token?** Under which division/entity, and does `GET /v3/accounts` return 200? (Everything else is conditional on this.)
2. **Does your account allow GSLO** (`guaranteedStopLossOrderMode`)? What's the margin rate and account currency, and is hedging enabled?
3. **What are the 9 rules, concretely?** Ideally in the trader's own words first — the code can wait.
4. **What's the account size and the intended per-trade risk?** (This determines whether spread/swap is noise or decisive — at $1k with 1% risk, a 1.5-pip spread on a 25-pip stop is a ~3% expectancy tax.)
5. **Is 3 trades/day a ceiling you expect to hit, or a safety rail?** If the rules realistically produce ~0.5 trades/day, the cap is redundant and the sample-size problem gets worse.
6. **Are you willing to run this as practice-only for 3 months if API access is unavailable?** If yes, the project is feasible *today*; if no, Blocker 1 decides the project.

---

## 7. Sources checked for the external claims

- OANDA v20 API not available on OANDA Global Markets — [developer.oanda.com/rest-live-v20/introduction](https://developer.oanda.com/rest-live-v20/introduction/), [API comparison](https://developer.oanda.com/rest-live-v20/api-comparison/)
- OANDA Global Markets eligible countries — [help.oanda.com/bvi](https://help.oanda.com/bvi/en/faqs/eligible-ogm-countries-bvi.htm)
- Rate limits: 120 req/s per IP, 429 on excess, 20 streams, 2 new connections/s — [development guide](https://developer.oanda.com/rest-live-v20/development-guide/)
- Candle cap: 5,000 per request, paginate with `from`/`to` — [pricing/instrument endpoints](https://developer.oanda.com/rest-live-v20/pricing-ep/)
- GSLO availability varies by division and is per-account (`guaranteedStopLossOrderMode`: `DISABLED`/`ALLOWED`/`REQUIRED`); premium charged on trigger only — [account definitions](https://developer.oanda.com/rest-live-v20/account-df/), [OANDA GSLO pages](https://www.oanda.com/uk-en/trading/guaranteed-stop-loss-order/)
- ForexFactory weekly export is current-week only, rate-limited (~2 req/5 min), returns an HTML "Request Denied" page past the limit, no reliable next-week feed — community reports on [forexfactory.com](https://www.forexfactory.com/thread/1311021-mql45-programmers-this-weekly-news-download-code-solves) and multiple MQL5 threads

*Numbers in §Blocker 3 are order-of-magnitude arithmetic meant to size the problem, not precise estimates. The independence assumption behind the rule-conjunction figures overstates selectivity (real rules correlate), but the direction — a 9-rule AND is very selective — holds.*
