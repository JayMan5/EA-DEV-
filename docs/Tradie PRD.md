# Tradie — Product Requirements Document (PRD)

> **Version:** 1.0.0-draft
> **Date:** 2026-05-29
> **Author:** Va_d3R
> **Classification:** CONFIDENTIAL — Internal Use Only
> **Status:** Draft — Pending Approval

---

## 1. Executive Summary

**Tradie** is a CLI-driven, checklist-enforced, automated forex trading bot. It trades **forex pairs** on the OANDA platform, autonomously enforcing **9 pre-trade rules** before placing any order. It runs 24/7 as a headless daemon on a Linux VPS.

The project has two distinct modes:
- **Tradie BT** — Backtesting engine with vectorized replay of OANDA historical data, proving the strategy before live exposure.
- **Tradie Live** — Live paper trading → seamless switch to live money, with Telegram alerts and daily P&L reports.

All trades are driven by the **9-rule checklist**; no discretion, no intuition — **one failure = no trade.**

---

## 2. Product Vision

**For:** Va_d3R (solo trader)
**Who:** Wants a disciplined, rules-driven forex bot that trades only when the market structure aligns with the strategy.
**Tradie is:** A CLI forex trading bot
**That:** Enforces a 9-step checklist before placing any trade, runs backtests to prove the strategy, and delivers Telegram alerts for live trades.
**Unlike:** Generic EAs or discretionary traders, Tradie **only trades when all 9 rules are TRUE**, eliminating emotional slop.
**Our product:** Provides **provable, verifiable edge** before any capital is risked.

---

## 3. Target User & RBAC Model

| Role | Access Level | Description |
|------|-------------|-------------|
| Va_d3R | Full control | Sole user — manages all bot settings, keys, modes |

No multi-user support. Single-user system.

---

## 4. Feature Specifications

> Features are numbered **F-01** thru **F-10** for cross-referencing in task lists and commit messages.

### 4.1 Backtesting & Validation (Tradie BT)

#### F-01: Backtesting Engine
- Vectorized replay of OANDA historical OHLCV data (H4, Daily, M15, H1)
- Replays price action, applies the **9-rule checklist** at each candle close
- Outputs trade journal CSV (entry, exit, P&L, rules_passed)
- Generates a summary report: total trades, win rate, avg win/loss, Sharpe ratio, max drawdown
- Minimum 3 months replay mandated before allowing switch to live/paper
- Backtest reports auto-saved to `Tradie/backtests/<timestamp>.csv` & `.json`

#### F-02: Historical Data Ingestion
- Download OHLCV candles from OANDA REST API (`/instruments/<pair>/candles`)
- Supports multi-pair: EUR/USD, GBP/USD, AUD/USD, USD/JPY, USD/CAD
- Data resolution: M5, M15, H1, H4, Daily
- Local caching to `.hdf5` or `.parquet` (VectorBT format)

### 4.2 Live Trading Engine (Tradie Live)

#### F-03: Checklist Enforcement Engine
- Evaluates the **9 pre-trade rules** atomically on every **M15 candle close**
- One rule failure = **hard reject**; no trade placed
- Full trade journal log: which rules passed/failed

#### F-04: Telegram Alerts & Reporting
- Sends **trade alerts** in real time:
  - Trade opened: pair, direction, entry price, SL, TP
  - Trade closed: P&L, duration
  - Circuit breaker activated: news blackout, streak hit, daily cap
- Sends **daily P&L report** (hydro summary):
  - UTC timezone
  - Total trades, winners, losers, gross P&L, net P&L
  - Drawdown summary
  - Screenshot of `session.log` available on request

#### F-05: Circuit Breakers
- **Account drawdown ≥3% in current session** → pause 4 hrs
- **≥2 consecutive losing trades** → pause 2 hrs, force session review
- **High-impact news within ±30 min** → block trades on impacted pairs
- **Daily trade cap = 3** → hard stop at midnight UTC; counter resets

#### F-06: Risk & Lot Sizing
- Risk-per-trade: 1–2% of account balance (configurable)
- Lot size auto-calculated from SL distance
- Minimum 1:2 risk-to-reward enforced
- Static SL/TP: SL set before order, TP calculated from risk-reward

#### F-07: Trade Execution & Management
- Order routing via OANDA REST API (`/v3/accounts/<account>/orders`)
- Market entry only — no pending orders
- Stop-loss **guaranteed** (OANDA supports GSL for forex pairs with restrictions)
- Take-profit set at order time — **no trailing**

### 4.3 Watchdog & Ops

#### F-08: Session State & Persistence
- Trade counter resets at **00:00 UTC** daily
- Circuit breaker state persisted to disk (JSON)
- Log rotation: retain last 7 log files

#### F-09: Health Monitor
- Daemon heartbeats every minute
- Low disk, high RAM → Telegram alert
- API call failures → Telegram alert + crash if persistent

#### F-10: Configuration
- `.env` file for secrets (API keys, Telegram token)
- `config.yaml` for strategy tweaks (risk %, target pairs, news sources switch)

---

## 5. Out of Scope — Do NOT Build

| Item | Reason |
|------|--------|
| MetaTrader (MT4/MT5) | Fragile headless; Wine/X11 adds points of failure |
| TradingView integration | Not needed — OANDA data is sufficient |
| Manual trade override | Violates discipline — bot is 100% autonomous |
| GUI / Desktop app | Phase 2 — CLI first, GUI later via Next.js dashboard |
| Skipping rules | Rules are non-negotiable — one failure = no trade |

---

## 6. Infrastructure & Deployment

### 6.1 Target Environment

| Service | Technology | Resources |
|--------|---------|-------------|
| Runtime | Ubuntu Server 22.04+ | 2 OCPU, 4 GB RAM |
| Language | Python 3.11+ | `.venv` isolated |
| Broker API | OANDA REST API v20 | Practice → Live switch |
| News Source | ForexFactory scraper | High-impact events only |
| Telegram | `python-telegram-bot` (async) | Token via BotFather |
| Logging | `loguru` *or* `logging` | Rotated logs, keep 7 |
| Backtesting | VectorBT | HDF5 local cache |
| Container | None — bare metal | `

### 6.2 Hosting

- **VPS:** Oracle Cloud (Ampere A1) or similar Linux VPS
- **TLS:** Not required — all traffic to OANDA & Telegram is already encrypted
- **Backup:** Mount a Block Volume or Object Storage (OCI- native)

---

## 7. Non-Functional Requirements

| Requirement | Target |
|--------------------------|----------------------------------|
| Backtesting coverage | ≥90% rule logic |
| Backtesting replay speed | ≤5 min for 1 year of M15 data |
| Rule evaluation latency | ≤2 sec per candle (M15 close) |
| Telegram alert latency | ≤5 sec from order fill |
| Health monitor frequency| Heartbeat ≤1 min |
| Uptime target | ≥98% monthly |
| Platform support | Ubuntu 22.04+, Debian 12 |

---

## 8. Brand & UI Guidelines

Since Tradie starts as a CLI-only system, Brand applies to **telegram alerts** and future GUI:

| Token | Hex | Usage |
|---------|---------|----------------------------------|
| LogoAccent | `#0066FF` | Telegram bot avatar border |
| BullishTrade | `#5FFF5F` | Telegram alert — long trade |
| BearishTrade | `#FF5F5F` | Telegram alert — short trade |
| DrawRestraint | `#FFBF00` | Telegram alert — circuit breaker |

Font pair: **JetBrains Mono** (monospace) for CLI / telegram monospace code blocks.

Daily report format:
```
☕ DAILY HYDRO SUMMARY
UTC: 2026-05-29 00:00 — 2026-05-30 00:00

▶️ Trades taken: 2 (cap: 3)
✅ Winners: 1 (+0.8 R)
❌ Losers: 1 (-1.0 R)
💰 Gross P&L: -0.2%
📉 Drawdown (session): -0.8%
🏦 Account Balance: $10,523

📊 Metrics:
- Win rate: 50%
- Avg RR: 1:1.8
- Max adverse excursion: -0.3%

🔋 Circuit breakers active: none
```

---

## 9. Security Requirements

| Requirement | Implementation |
|-----------------------|------------------------------------------------|
| OANDA API key | `.env` only — never committed |
| Telegram bot token | `.env` only — never logged or exposed |
| Log sanitization | Mask keys, passwords, API secrets in log files |
| Rate limiting | OANDA rate limits obeyed (500 req/min max) |

---

## 10. Product Roadmap

### Tradie 1.0 — MVP

| Release | Features | Status |
|--------|------------------------------------------------|--------|
| **v1.0** | F-01–F-10: Backtest, Live paper, 9 rules, alerts | Draft |

---

[Tradie · PRD v1.0.0-draft · 2026-05-29]
*This document is confidential and intended for internal use only.*