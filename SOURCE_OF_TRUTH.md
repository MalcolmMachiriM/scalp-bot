# ProScalperEA Source of Truth

This document is the authoritative reference for the current ProScalperEA scope, constraints, and operating rules.

## 1) Mission and Reality Constraints

- Build a professional MT5 scalping bot in native MQL5.
- Target robust, risk-adjusted performance and survivability.
- A 100% win rate is not a valid or achievable live-market target.
- Performance is judged by expectancy, drawdown control, and execution quality.

## 2) Project Scope (Locked)

- Stack: MQL5-only (no Python bridge).
- Strategy style: scalping.
- Entry timeframe: M5.
- Session model: London + New York overlap (server time gate).
- Risk per trade: dynamic 2% to 3% (based on setup quality scoring).
- Daily account loss cap: 5% equity hard stop.
- Universe: Deriv synthetic symbols from the approved MT5 watchlist shared by user.

## 3) Folder and File Authority

Base folder:
- `C:\Users\User\Documents\GitHub\scalp-bot`

Authoritative files:
- `MQL5/Experts/Earthasoft/ProScalperEA.mq5`
- `MQL5/Presets/Earthasoft/ProScalper_M5_LondonNY_Conservative.set`
- `MQL5/Presets/Earthasoft/ProScalper_M5_LondonNY_Standard.set`
- `README.md`
- `SOURCE_OF_TRUTH.md` (this file)

## 4) Risk and Safety Policy (Non-Negotiable)

- Every position must have stop loss and take profit.
- New entries are blocked when:
  - daily equity loss reaches 5% from day-start equity,
  - max consecutive losses threshold is reached,
  - spread is above configured max,
  - current time is outside allowed session window.
- Position size must be calculated from risk %, SL distance, and symbol trade specs.
- No martingale and no grid escalation in baseline profile.

## 5) Current Trading Logic Baseline

- Trend filter:
  - Higher timeframe EMA alignment for directional bias.
- Entry trigger:
  - Entry timeframe EMA momentum + RSI threshold confirmation.
- Volatility-aware exits:
  - ATR-based SL/TP.
  - optional break-even rule.
  - optional ATR trailing stop.
- Position policy:
  - one open EA-managed position per symbol/magic at a time.

## 6) Current Parameter Baseline

- Session hours (server time): start 12, end 21.
- Dynamic risk range: min 2.0%, max 3.0%.
- Daily loss cap: 5.0%.
- Entry timeframe: M5.
- Trend timeframe: H1.
- Signal defaults:
  - EMA fast/slow (entry): 21/55
  - EMA fast/slow (trend): 50/200
  - RSI period: 14
  - ATR period: 14
- Protection defaults:
  - ATR SL multiplier: 1.5
  - ATR TP multiplier: 1.8 (conservative) / 2.0 (standard)
  - break-even enabled
  - trailing enabled

## 7) Operating Procedure

1. Compile `ProScalperEA.mq5` in MetaEditor.
2. Start with Strategy Tester on each approved symbol using real ticks where available.
3. Load conservative preset first.
4. Verify:
   - spread and slippage assumptions,
   - drawdown behavior,
   - daily loss cap trigger behavior.
5. Move to demo forward test before any live deployment.
6. Use unique `InpMagicNumber` per symbol/chart.

## 8) Validation Gates Before Live Trading

- Minimum acceptable trade sample size established per symbol.
- Out-of-sample behavior does not materially degrade vs in-sample.
- Drawdown remains within defined tolerance.
- Daily cap behavior observed and confirmed in test logs.
- No unresolved execution errors in terminal journal.

## 9) Change Control

- Any strategy or risk change must be documented here before use.
- Any changed preset must be versioned and tracked by date.
- Production parameter changes require retest and demo verification.

## 10) Open Items / To Be Finalized

- Final curated symbol list in plain text for reproducible batch testing.
- Per-symbol spread thresholds (some symbols may require tighter max spread points).
- Exact promotion criteria from conservative to standard profile.

## 11) Decision Log (What Was Agreed)

- MQL5-only implementation selected.
- Build location changed to `C:\Users\User\Documents\GitHub\scalp-bot`.
- MT5-style folder layout selected (`MQL5/Experts`, `MQL5/Include`, `MQL5/Presets`).
- Trading style confirmed as scalping with M5 sessions.
- Risk model confirmed as dynamic 2-3%.
- Daily loss cap confirmed as 5%.
- Session window confirmed as London + New York overlap.
