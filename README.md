# ProScalperEA (MT5 / MQL5)

This repo contains an MQL5-only scalping EA with:
- M5 entries
- London/NY session filter (server time)
- Dynamic risk between 2% and 3%
- Daily loss cap at 5% equity

## Files
- `MQL5/Experts/Earthasoft/ProScalperEA.mq5`
- `MQL5/Presets/Earthasoft/ProScalper_M5_LondonNY_Conservative.set`
- `MQL5/Presets/Earthasoft/ProScalper_M5_LondonNY_Standard.set`
- `SOURCE_OF_TRUTH.md` (authoritative scope and operating policy)

## Install
1. Open MetaEditor from MT5.
2. Copy `ProScalperEA.mq5` to your MT5 `MQL5/Experts/Earthasoft/`.
3. Compile in MetaEditor.
4. Load one of the `.set` files in Strategy Tester or chart settings.

## Multi-symbol usage
For the symbol list you shared, run one chart per symbol and attach the EA to each chart.
Use a unique `InpMagicNumber` per chart/symbol to isolate position management and reporting.

## Risk notes
- No strategy can guarantee a 100% win rate.
- The EA enforces a 5% daily equity stop and halts trading for the day once hit.
- Start on demo and validate spread/slippage behavior for each symbol before live use.
