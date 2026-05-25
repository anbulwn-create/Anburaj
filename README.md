# XAUUSD ProTrader EA v1.0

A professional-grade MetaTrader 5 Expert Advisor designed specifically for XAUUSD (Gold) trading. Combines Smart Money Concepts, EMA multi-timeframe trend following, RSI confirmation, and advanced profit protection for consistent, risk-managed trading.

---

## Features

### Signal Generation
- **EMA Dual Timeframe**: H1 trend direction (EMA 50/200) + M5 entry timing (EMA 50/200)
- **RSI Confirmation**: Overbought/oversold detection with divergence analysis
- **Smart Money Concepts (SMC)**: Order blocks, Fair Value Gaps, liquidity sweeps, Break of Structure, Change of Character
- **Confluence Scoring**: Weighted signal strength combining all factors

### Risk Management
- Automatic lot sizing based on account balance and risk percentage
- Kelly Criterion option for advanced position sizing
- Maximum drawdown protection (auto-pause trading)
- Daily loss limit enforcement
- Consecutive loss reduction (reduces lot size after N losses)
- Equity curve filter (trades only when equity is above its MA)
- Minimum balance protection (critical for small accounts)
- Position sizing tiers (micro/mini/standard)

### Trade Execution
- Spread filter prevents entry during high-spread conditions
- Slippage protection with configurable max deviation
- Partial close at first target (e.g., 50% at TP1)
- Break-even management (move SL to entry after X pips profit)
- Maximum open positions limit
- Trade cooldown timer
- Order send with retry logic on failure

### Profit Protection
- **Standard Trailing Stop**: Configurable distance and step
- **Hidden Lock-In Profit**: Tracks profit internally without exposing tight SL to broker; only updates server SL at larger intervals to avoid stop hunting
- **Jump Stop Loss**: Moves SL in discrete jumps (e.g., every 50 pips) rather than continuously
- **Progressive Trailing**: Trail distance tightens as profit grows
- **ATR-Based Trailing**: Dynamic trail distance using Average True Range
- **Structure-Based Trailing**: Trails below/above recent swing points

### News Filter
- Built-in high-impact USD news schedule (NFP, FOMC, CPI, GDP, etc.)
- Configurable blackout periods (minutes before/after)
- Day-of-week filter
- Friday evening and Monday morning filters
- Custom blackout date/time support

### Dashboard
- On-chart HUD displaying EA status, signals, account stats
- Real-time spread, positions, and filter status
- Color-coded warnings for drawdown and spread

---

## Installation

### Step 1: Download Files
Download all files from this repository.

### Step 2: Copy to MT5 Data Folder
1. Open MetaTrader 5
2. Go to **File > Open Data Folder**
3. Navigate to `MQL5/Experts/`
4. Create a folder called `XAUUSD_ProTrader/` (optional, for organization)
5. Copy `XAUUSD_ProTrader_EA.mq5` into `MQL5/Experts/` (or your subfolder)
6. Copy the entire `Include/` folder into the same directory as the .mq5 file

Your structure should look like:
```
MQL5/Experts/XAUUSD_ProTrader/
  XAUUSD_ProTrader_EA.mq5
  Include/
    Utils.mqh
    SMCAnalysis.mqh
    SignalEngine.mqh
    RiskManager.mqh
    TradeManager.mqh
    TrailingStop.mqh
    NewsFilter.mqh
```

### Step 3: Compile
1. Open MetaEditor (F4 from MT5)
2. Open `XAUUSD_ProTrader_EA.mq5`
3. Press **Compile** (F7)
4. Ensure 0 errors (warnings are acceptable)

### Step 4: Attach to Chart
1. Open an **XAUUSD M5** chart
2. Drag the EA from Navigator onto the chart
3. Enable **AutoTrading** (button on toolbar)
4. Configure input parameters as needed
5. Click **OK**

---

## Input Parameters

### General Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| Magic Number | 202401 | Unique identifier for EA trades |
| EA Comment | XAUUSD_Pro | Comment attached to trades |
| Enable EA | true | Master on/off switch |
| Show Dashboard | true | Display HUD on chart |

### Signal Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| EMA Fast Period | 50 | Fast EMA period |
| EMA Slow Period | 200 | Slow EMA period |
| Lower Timeframe | M5 | Entry timeframe |
| Higher Timeframe | H1 | Trend timeframe |
| RSI Period | 14 | RSI calculation period |
| RSI Overbought | 70 | Overbought level |
| RSI Oversold | 30 | Oversold level |
| Enable SMC | true | Smart Money Concepts |
| SMC Lookback | 100 | Bars for SMC analysis |
| Weight EMA | 40 | EMA signal weight |
| Weight RSI | 25 | RSI signal weight |
| Weight SMC | 35 | SMC signal weight |

### Risk Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| Risk Per Trade | 1.0% | Percentage of balance risked |
| Max Drawdown | 10.0% | Pause trading threshold |
| Daily Loss Limit | 3.0% | Daily loss stop |
| Min Balance | $80 | Stop trading below this |
| Max Consecutive Losses | 3 | Trigger lot reduction |
| Lot Reduction | 0.5 | Factor after N losses |
| Min Risk:Reward | 1.5 | Minimum R:R ratio |
| Use Kelly | false | Kelly Criterion sizing |
| Use Equity Curve | false | Equity filter |
| Default SL | 50 pips | Stop loss distance |
| Default TP | 100 pips | Take profit distance |

### Trade Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| Max Spread | 50 pips | Spread threshold |
| Max Slippage | 30 pts | Maximum deviation |
| Max Positions | 3 | Position limit |
| Cooldown | 300 sec | Time between trades |
| Break-Even Trigger | 30 pips | Profit to move SL to BE |
| Break-Even Offset | 2 pips | Offset above entry for BE |
| Partial Close % | 50% | Amount to close at TP1 |
| Partial Close Trigger | 50 pips | Profit for partial close |

### Trailing Stop
| Parameter | Default | Description |
|-----------|---------|-------------|
| Trail Mode | Hidden Lock-In | Trailing method |
| Trail Distance | 30 pips | Standard trail distance |
| Trail Step | 5 pips | Minimum trail movement |
| Jump Size | 50 pips | Jump SL step size |
| Lock-In Threshold | 30 pips | Profit to activate lock |
| Lock-In Pips | 10 pips | Profit locked above entry |
| ATR Period | 14 | ATR calculation period |
| ATR Multiplier | 2.0 | ATR trail multiplier |

### News Filter
| Parameter | Default | Description |
|-----------|---------|-------------|
| Enable News Filter | true | News avoidance |
| Minutes Before | 30 | Pause before event |
| Minutes After | 15 | Pause after event |
| Filter Friday | true | Stop Friday evening |
| Friday End Hour | 20 | Friday stop time |
| Filter Monday | true | Avoid Monday open |
| Monday Start Hour | 3 | Monday trading start |

### Session Filter
| Parameter | Default | Description |
|-----------|---------|-------------|
| Trade London | true | London session |
| Trade New York | true | NY session |
| Trade Asian | false | Asian session |
| Trade Overlap | true | London/NY overlap |
| Custom Hours | false | Use custom hours |
| Start Hour | 8 | Custom start |
| End Hour | 20 | Custom end |

---

## Recommended Settings for XAUUSD

### Chart Setup
- **Symbol**: XAUUSD (or GOLD, depending on broker)
- **Chart Timeframe**: M5 (5-minute)
- **Higher Timeframe**: H1 (set in inputs)

### Conservative Settings (Recommended for $100-$500 accounts)
- Risk Per Trade: 0.5-1.0%
- Max Drawdown: 8%
- Daily Loss Limit: 2%
- Max Positions: 1-2
- Default SL: 50 pips
- Default TP: 100 pips
- Trail Mode: Hidden Lock-In

### Moderate Settings (For $1000+ accounts)
- Risk Per Trade: 1.0-2.0%
- Max Drawdown: 12%
- Daily Loss Limit: 4%
- Max Positions: 2-3
- Default SL: 40 pips
- Default TP: 80 pips
- Trail Mode: Progressive or ATR

### Best Trading Times
- London/NY Overlap (13:00-16:00 server time) provides the highest volatility and best signals for Gold
- Avoid Asian session for Gold unless specifically configured

---

## Risk Disclaimer

**WARNING: Trading involves substantial risk of loss.**

- Past performance does not guarantee future results
- Only trade with money you can afford to lose
- This EA does not guarantee profits
- Backtest thoroughly before live trading
- Start with a demo account
- Use the minimum lot size initially

**Minimum Deposit**: $100 (with conservative settings at 0.5% risk)

---

## Broker Compatibility

### Requirements
- MetaTrader 5 platform
- XAUUSD/Gold symbol available
- ECN or Raw Spread account recommended
- Hedging account type preferred
- Maximum spread under 50 pips during active sessions

### Recommended Brokers
- Any MT5 broker offering XAUUSD with:
  - Low spreads (under 30 pips typical)
  - Fast execution (under 100ms)
  - No dealing desk (NDD/STP/ECN)
  - Supports partial close
  - Allows Expert Advisors

### Order Filling
The EA uses ORDER_FILLING_FOK by default. If your broker requires different filling mode, the EA will attempt to adapt. Some brokers may need ORDER_FILLING_IOC.

---

## Troubleshooting

### EA Not Trading
1. Check AutoTrading is enabled (green button on toolbar)
2. Verify the EA is attached to an XAUUSD chart
3. Check the Experts tab for error messages
4. Ensure spread is below the max spread setting
5. Verify you are within allowed trading hours
6. Check if news filter is blocking (view dashboard)
7. Confirm account balance is above minimum threshold

### Compilation Errors
1. Ensure all Include/ files are in the correct location
2. Verify file paths match the #include statements
3. Check you are using MetaTrader 5 (not MT4)
4. Update MetaTrader to the latest version

### High Spread Issues
- Gold spreads widen during news events and low-liquidity periods
- Increase max spread setting, or accept fewer trades
- Best spreads available during London/NY overlap

### Order Failed
- Check the Journal tab for detailed error messages
- Common issues: insufficient margin, invalid stops, market closed
- The EA has retry logic built in (3 attempts)

### Dashboard Not Showing
- Right-click chart > Properties > Common > ensure "Show object descriptions" is checked
- Try removing and re-attaching the EA

---

## File Structure

```
XAUUSD_ProTrader_EA.mq5      - Main EA file (entry point)
Include/
  Utils.mqh                   - Shared utilities, enums, constants
  SMCAnalysis.mqh             - Smart Money Concepts engine
  SignalEngine.mqh            - Signal generation (EMA + RSI + SMC)
  RiskManager.mqh             - Risk and money management
  TradeManager.mqh            - Order execution and protection
  TrailingStop.mqh            - Trailing stop modes
  NewsFilter.mqh              - News event filter
README.md                     - This documentation
```

---

## Changelog

### v1.0 (2024)
- Initial release
- EMA dual-timeframe trend following (H1 + M5)
- RSI overbought/oversold with divergence detection
- Smart Money Concepts (order blocks, FVG, liquidity, BOS, CHoCH)
- Hidden lock-in profit protection
- Jump stop loss (discrete step trailing)
- Progressive and ATR-based trailing
- Structure-based trailing
- Comprehensive news filter with built-in USD schedule
- Automatic lot sizing with Kelly Criterion option
- Maximum drawdown and daily loss protection
- Equity curve trading filter
- Spread and slippage protection
- Partial close and break-even management
- On-chart dashboard/HUD
- Trade cooldown and session filters
- Consecutive loss handling with lot reduction
- Position sizing tiers for different account sizes
