# XAUUSD ProTrader EA v2.0

A simplified, effective MetaTrader 5 Expert Advisor for XAUUSD (Gold) trading. Uses EMA trend following with RSI confirmation on M5/H1 timeframes. Designed to **actually take trades** in live conditions.

---

## Key Philosophy

This EA prioritizes **taking profitable trades** over complex analysis. The previous v1.0 had 4000+ lines of Smart Money Concepts, news filters, and confluence scoring that never fired in live conditions. This v2.0 is lean, simple, and proven.

---

## Strategy

### Signal Logic
- **H1 Trend**: EMA 21 vs EMA 50 determines trend direction
- **M5 Entry**: Price position relative to EMA 21 confirms momentum
- **RSI Filter**: RSI 14 in healthy zone (not overbought/oversold)

### Trade Rules
- **BUY**: EMA21 > EMA50 on H1 AND price > EMA21 on M5 AND RSI 40-70
- **SELL**: EMA21 < EMA50 on H1 AND price < EMA21 on M5 AND RSI 30-60
- Signal fires on every new M5 bar where conditions are met

### Risk Management
- 1% risk per trade (automatic lot calculation)
- Maximum 2 simultaneous positions
- Fixed SL: 300 points ($3.00 for gold)
- Fixed TP: 600 points ($6.00 for gold)
- 1:2 risk-reward ratio

### Trailing Stop
- Activates after 200 points ($2.00) profit
- Trails at 150 points distance
- Only moves SL forward, never backward

---

## Installation

1. Copy `XAUUSD_ProTrader_EA.mq5` to your MT5 Data Folder:
   `[MT5 Data Folder]/MQL5/Experts/`
2. Open MetaEditor and compile the file (F7)
3. Attach to any XAUUSD chart (recommended: M5 timeframe)
4. Enable "Allow Algo Trading" in MT5 settings

**Note:** The Include/ folder files are from v1.0 and are NOT used by v2.0. The EA has ZERO includes.

---

## Input Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| InpMagicNumber | 202401 | Unique EA identifier |
| InpRiskPercent | 1.0 | Risk per trade as % of balance |
| InpSLPoints | 300 | Stop loss in points (300 = $3.00) |
| InpTPPoints | 600 | Take profit in points (600 = $6.00) |
| InpMaxPositions | 2 | Max simultaneous positions |
| InpEMAFast | 21 | Fast EMA period |
| InpEMASlow | 50 | Slow EMA period |
| InpRSIPeriod | 14 | RSI period |
| InpRSIBuyMin | 40 | Min RSI for buy signal |
| InpRSIBuyMax | 70 | Max RSI for buy signal |
| InpRSISellMin | 30 | Min RSI for sell signal |
| InpRSISellMax | 60 | Max RSI for sell signal |
| InpEnableTrailing | true | Enable trailing stop |
| InpTrailStart | 200 | Points profit before trail starts |
| InpTrailDistance | 150 | Trail distance in points |
| InpNewsFilter | false | News filter (OFF by default) |
| InpSessionFilter | false | Session filter (OFF by default) |

---

## Gold Point Values

- 1 point = $0.01 price movement (e.g., 2650.50 to 2650.51)
- SL of 300 points = $3.00 price movement
- TP of 600 points = $6.00 price movement
- Typical spread: 20-50 points

---

## Debugging

The EA prints messages to the Experts tab:
- `"EA initialized, waiting for signals..."` - startup confirmation
- `"BUY signal: EMA21_H1=X EMA50_H1=X RSI=X"` - signal detected
- `"Opening BUY: lots=X price=X sl=X tp=X"` - order being sent
- `"Order SUCCESS: retcode=X deal=X"` - trade executed
- `"Trailing: ticket=X new SL=X"` - trailing stop moved

---

## Requirements

- MetaTrader 5 platform
- XAUUSD symbol available from broker
- Algo trading enabled
- Recommended: M5 chart with at least 60 bars of history
- Minimum deposit: $100 (will trade micro lots)

---

## Risk Disclaimer

Trading gold (XAUUSD) involves substantial risk of loss. Past performance does not guarantee future results. Only trade with money you can afford to lose. This EA is a tool - not financial advice.
