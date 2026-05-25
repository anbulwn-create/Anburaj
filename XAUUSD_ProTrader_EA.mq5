//+------------------------------------------------------------------+
//|                                          XAUUSD_ProTrader_EA.mq5 |
//|                          Copyright 2024, XAUUSD ProTrader Team   |
//|                                     https://github.com/Anburaj   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, XAUUSD ProTrader Team"
#property link      "https://github.com/Anburaj"
#property version   "1.00"
#property description "Professional XAUUSD Expert Advisor with Smart Money Concepts,"
#property description "EMA Multi-Timeframe Trend, RSI Confirmation, Hidden Profit Lock,"
#property description "Advanced Trailing Stops, News Filter, and Risk Management."
#property description "Designed for M5 chart with H1 trend confirmation."

//+------------------------------------------------------------------+
//| Includes                                                          |
//+------------------------------------------------------------------+
#include "Include/Utils.mqh"
#include "Include/SMCAnalysis.mqh"
#include "Include/SignalEngine.mqh"
#include "Include/RiskManager.mqh"
#include "Include/TradeManager.mqh"
#include "Include/TrailingStop.mqh"
#include "Include/NewsFilter.mqh"

//+------------------------------------------------------------------+
//| Input Parameters - General Settings                               |
//+------------------------------------------------------------------+
input group "=== General Settings ==="
input long     InpMagicNumber     = 202401;     // Magic Number (unique ID for this EA)
input string   InpEAComment       = "XAUUSD_Pro"; // Trade Comment
input bool     InpEnableEA        = true;        // Enable EA Trading
input bool     InpEnableDashboard = true;        // Show Dashboard on Chart

//+------------------------------------------------------------------+
//| Input Parameters - Signal Settings                                |
//+------------------------------------------------------------------+
input group "=== Signal Settings ==="
input int      InpEMAFastPeriod   = 50;          // EMA Fast Period
input int      InpEMASlowPeriod   = 200;         // EMA Slow Period
input ENUM_TIMEFRAMES InpLowerTF  = PERIOD_M5;   // Lower Timeframe (Entry)
input ENUM_TIMEFRAMES InpHigherTF = PERIOD_H1;   // Higher Timeframe (Trend)
input int      InpRSIPeriod       = 14;          // RSI Period
input double   InpRSIOverbought   = 70.0;        // RSI Overbought Level
input double   InpRSIOversold     = 30.0;        // RSI Oversold Level
input bool     InpUseSMC          = true;        // Enable Smart Money Concepts
input int      InpSMCLookback     = 100;         // SMC Lookback Bars
input int      InpSignalWeightEMA = 40;          // Signal Weight: EMA (0-100)
input int      InpSignalWeightRSI = 25;          // Signal Weight: RSI (0-100)
input int      InpSignalWeightSMC = 35;          // Signal Weight: SMC (0-100)

//+------------------------------------------------------------------+
//| Input Parameters - Risk Management                                |
//+------------------------------------------------------------------+
input group "=== Risk Management ==="
input double   InpRiskPercent     = 1.0;         // Risk Per Trade (%)
input double   InpMaxDrawdown     = 10.0;        // Max Drawdown Before Pause (%)
input double   InpDailyLossLimit  = 3.0;         // Daily Loss Limit (%)
input double   InpMinBalance      = 80.0;        // Minimum Balance to Trade ($)
input int      InpMaxConsecLoss   = 3;           // Max Consecutive Losses Before Reduction
input double   InpLotReduction    = 0.5;         // Lot Reduction Factor After Losses
input double   InpMinRiskReward   = 1.5;         // Minimum Risk:Reward Ratio
input bool     InpUseKelly        = false;       // Use Kelly Criterion Lot Sizing
input bool     InpUseEquityCurve  = false;       // Use Equity Curve Filter
input double   InpDefaultSLPips   = 50.0;        // Default Stop Loss (pips)
input double   InpDefaultTPPips   = 100.0;       // Default Take Profit (pips)

//+------------------------------------------------------------------+
//| Input Parameters - Trade Management                               |
//+------------------------------------------------------------------+
input group "=== Trade Management ==="
input double   InpMaxSpread       = 50.0;        // Max Spread Allowed (pips)
input int      InpMaxSlippage     = 30;          // Max Slippage (points)
input int      InpMaxPositions    = 3;           // Max Open Positions
input int      InpCooldownSec     = 300;         // Cooldown Between Trades (seconds)
input double   InpBreakEvenPips   = 30.0;        // Break-Even Trigger (pips profit)
input double   InpBreakEvenOffset = 2.0;         // Break-Even Offset (pips above entry)
input double   InpPartialPercent  = 50.0;        // Partial Close (% of position)
input double   InpPartialTrigger  = 50.0;        // Partial Close Trigger (pips profit)

//+------------------------------------------------------------------+
//| Input Parameters - Trailing Stop                                  |
//+------------------------------------------------------------------+
input group "=== Trailing Stop ==="
input ENUM_TRAILING_MODE InpTrailMode = TRAIL_HIDDEN_LOCKIN; // Trailing Mode
input double   InpTrailDistance   = 30.0;        // Trail Distance (pips)
input double   InpTrailStep       = 5.0;         // Trail Step (min pips to move)
input double   InpJumpSize        = 50.0;        // Jump Size (pips, for Jump mode)
input double   InpLockInThreshold = 30.0;        // Lock-In Threshold (pips profit to activate)
input double   InpLockInPips      = 10.0;        // Lock-In Pips (profit to lock above entry)
input int      InpATRPeriod       = 14;          // ATR Period (for ATR mode)
input double   InpATRMultiplier   = 2.0;         // ATR Multiplier (for ATR mode)

//+------------------------------------------------------------------+
//| Input Parameters - News Filter                                    |
//+------------------------------------------------------------------+
input group "=== News Filter ==="
input bool     InpNewsFilter      = true;        // Enable News Filter
input int      InpNewsBefore      = 30;          // Minutes Before News to Pause
input int      InpNewsAfter       = 15;          // Minutes After News to Resume
input bool     InpFilterFriday    = true;        // Avoid Trading Friday Evening
input int      InpFridayEndHour   = 20;          // Friday Stop Hour
input bool     InpFilterMonday    = true;        // Avoid Monday Early Hours
input int      InpMondayStartHour = 3;           // Monday Start Hour

//+------------------------------------------------------------------+
//| Input Parameters - Session Filter                                 |
//+------------------------------------------------------------------+
input group "=== Session Filter ==="
input bool     InpTradeLondon     = true;        // Trade During London Session
input bool     InpTradeNewYork    = true;        // Trade During New York Session
input bool     InpTradeAsian      = false;       // Trade During Asian Session
input bool     InpTradeOverlap    = true;        // Trade During London/NY Overlap
input bool     InpUseCustomHours  = false;       // Use Custom Trading Hours
input int      InpCustomStartHour = 8;           // Custom Start Hour
input int      InpCustomEndHour   = 20;          // Custom End Hour

//+------------------------------------------------------------------+
//| Global Module Instances                                           |
//+------------------------------------------------------------------+
CSMCAnalysis   g_smcAnalysis;
CSignalEngine  g_signalEngine;
CRiskManager   g_riskManager;
CTradeManager  g_tradeManager;
CTrailingStop  g_trailingStop;
CNewsFilter    g_newsFilter;

//+------------------------------------------------------------------+
//| Global State Variables                                            |
//+------------------------------------------------------------------+
bool           g_initialized = false;
datetime       g_lastBarTime = 0;
int            g_totalTrades = 0;
double         g_totalProfit = 0;
string         g_eaStatus = "Initializing";
string         g_lastSignal = "None";
int            g_lastSignalStrength = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate symbol
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
   {
      LogWarning("This EA is designed for XAUUSD/Gold. Current symbol: " + _Symbol);
      // Allow but warn - some brokers use different naming
   }

   //--- Initialize SMC Analysis
   if(InpUseSMC)
   {
      if(!g_smcAnalysis.Init(_Symbol, InpLowerTF, InpSMCLookback, 3, 20, 500))
      {
         LogError("Failed to initialize SMC Analysis");
         return INIT_FAILED;
      }
   }

   //--- Initialize Signal Engine
   if(!g_signalEngine.Init(_Symbol, InpLowerTF, InpHigherTF,
                            InpEMAFastPeriod, InpEMASlowPeriod,
                            InpRSIPeriod, InpRSIOverbought, InpRSIOversold))
   {
      LogError("Failed to initialize Signal Engine");
      return INIT_FAILED;
   }
   if(InpUseSMC)
      g_signalEngine.SetSMCAnalysis(&g_smcAnalysis);
   g_signalEngine.SetWeights(InpSignalWeightEMA, InpSignalWeightRSI, InpSignalWeightSMC);

   //--- Initialize Risk Manager
   if(!g_riskManager.Init(InpRiskPercent, InpMaxDrawdown, InpDailyLossLimit,
                           InpMinBalance, InpMaxConsecLoss, InpLotReduction))
   {
      LogError("Failed to initialize Risk Manager");
      return INIT_FAILED;
   }
   g_riskManager.SetKellyCriterion(InpUseKelly);
   g_riskManager.SetEquityCurveTrading(InpUseEquityCurve, 20);
   g_riskManager.SetMinRiskReward(InpMinRiskReward);

   //--- Initialize Trade Manager
   if(!g_tradeManager.Init(_Symbol, InpMagicNumber, InpEAComment,
                            InpMaxSpread, InpMaxSlippage, InpMaxPositions))
   {
      LogError("Failed to initialize Trade Manager");
      return INIT_FAILED;
   }
   g_tradeManager.SetBreakEven(InpBreakEvenPips, InpBreakEvenOffset);
   g_tradeManager.SetPartialClose(InpPartialPercent, InpPartialTrigger);
   g_tradeManager.SetCooldown(InpCooldownSec);
   g_tradeManager.SetSessionFilter(InpTradeLondon, InpTradeNewYork, InpTradeAsian, InpTradeOverlap);
   if(InpUseCustomHours)
      g_tradeManager.SetCustomHours(InpCustomStartHour, InpCustomEndHour);

   //--- Initialize Trailing Stop
   if(!g_trailingStop.Init(_Symbol, InpMagicNumber, InpTrailMode, InpLowerTF))
   {
      LogError("Failed to initialize Trailing Stop");
      return INIT_FAILED;
   }
   g_trailingStop.SetTrailParams(InpTrailDistance, InpTrailStep);
   g_trailingStop.SetJumpParams(InpJumpSize);
   g_trailingStop.SetLockInParams(InpLockInThreshold, InpLockInPips);
   g_trailingStop.SetATRParams(InpATRPeriod, InpATRMultiplier);
   g_trailingStop.SetProgressiveParams(20.0, 10.0, 0.5);

   //--- Initialize News Filter
   if(!g_newsFilter.Init(InpNewsFilter, InpNewsBefore, InpNewsAfter))
   {
      LogError("Failed to initialize News Filter");
      return INIT_FAILED;
   }
   g_newsFilter.SetFridayFilter(InpFilterFriday, InpFridayEndHour);
   g_newsFilter.SetMondayFilter(InpFilterMonday, InpMondayStartHour);

   //--- Set timer for dashboard updates (every 1 second)
   EventSetTimer(1);

   //--- Create dashboard
   if(InpEnableDashboard)
      CreateDashboard();

   g_initialized = true;
   g_eaStatus = "Active";
   LogInfo("=== " + EA_NAME + " v" + EA_VERSION + " initialized successfully ===");
   LogInfo(StringFormat("Account: %.2f %s | Leverage: 1:%d",
           AccountInfoDouble(ACCOUNT_BALANCE),
           AccountInfoString(ACCOUNT_CURRENCY),
           (int)AccountInfoInteger(ACCOUNT_LEVERAGE)));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Cleanup modules
   g_signalEngine.Deinit();
   g_trailingStop.Deinit();

   //--- Remove timer
   EventKillTimer();

   //--- Remove dashboard objects
   ObjectsDeleteAll(0, "EA_");

   //--- Log final statistics
   LogInfo("=== " + EA_NAME + " stopped ===");
   LogInfo(StringFormat("Reason: %d | Total trades: %d | Total P&L: %.2f",
           reason, g_totalTrades, g_totalProfit));

   g_initialized = false;
}

//+------------------------------------------------------------------+
//| Expert tick function - Main trading logic                         |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized || !InpEnableEA) return;

   //--- Step 1: Check for new bar (avoid processing every tick)
   datetime currentBarTime = iTime(_Symbol, InpLowerTF, 0);
   bool isNewBar = (currentBarTime != g_lastBarTime);

   //--- Always manage existing positions (trailing, break-even) on every tick
   ManageExistingPositions();

   //--- Only process new signals on new bar
   if(!isNewBar) return;
   g_lastBarTime = currentBarTime;

   //--- Step 2: Check news filter
   if(!g_newsFilter.IsTradingAllowed())
   {
      g_eaStatus = "Paused (News: " + g_newsFilter.GetBlackoutReason() + ")";
      return;
   }

   //--- Step 3: Check session filter
   if(!g_tradeManager.IsSessionAllowed())
   {
      g_eaStatus = "Paused (Session)";
      return;
   }

   //--- Step 4: Check spread
   if(!g_tradeManager.IsSpreadOK())
   {
      g_eaStatus = "Paused (Spread)";
      return;
   }

   //--- Step 5: Update SMC analysis on new bar
   if(InpUseSMC)
      g_smcAnalysis.Update();

   //--- Step 6: Update risk manager
   g_riskManager.Update();

   //--- Step 7: Check risk management
   if(!g_riskManager.CanTrade())
   {
      g_eaStatus = "Paused (Risk: " + g_riskManager.GetPauseReason() + ")";
      return;
   }

   //--- Step 8: Check max positions
   if(!g_tradeManager.IsWithinMaxPositions())
   {
      g_eaStatus = "Active (Max Positions)";
      return;
   }

   //--- Step 9: Check cooldown
   if(!g_tradeManager.IsCooldownExpired())
   {
      g_eaStatus = "Active (Cooldown)";
      return;
   }

   //--- Step 10: Generate signals
   SignalResult signal = g_signalEngine.GenerateSignal();
   g_lastSignal = SignalToString(signal.signal);
   g_lastSignalStrength = signal.strength;

   //--- Step 11: Execute trade if signal is valid
   if(signal.signal != SIGNAL_NONE && signal.strength >= 30)
   {
      ExecuteTrade(signal);
   }

   g_eaStatus = "Active";
}

//+------------------------------------------------------------------+
//| Timer function - Periodic updates                                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!g_initialized) return;

   //--- Update dashboard
   if(InpEnableDashboard)
      UpdateDashboard();

   //--- Update risk manager equity history
   g_riskManager.Update();
}

//+------------------------------------------------------------------+
//| Manage existing open positions                                    |
//+------------------------------------------------------------------+
void ManageExistingPositions()
{
   //--- Trailing stop management
   g_trailingStop.ManageTrailing();

   //--- Break-even management
   g_tradeManager.ManageBreakEven();

   //--- Partial close management
   g_tradeManager.ManagePartialClose();

   //--- Check hidden stop levels for emergency close
   ulong tickets[];
   int count = 0;
   g_tradeManager.GetOpenTickets(tickets, count);

   for(int i = 0; i < count; i++)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(g_trailingStop.ShouldClosePosition(tickets[i], bid))
      {
         LogInfo(StringFormat("Hidden SL hit - closing position %d", tickets[i]));
         g_tradeManager.ClosePosition(tickets[i]);
      }
   }
}

//+------------------------------------------------------------------+
//| Execute a trade based on the signal                               |
//+------------------------------------------------------------------+
void ExecuteTrade(SignalResult &signal)
{
   double slPips = InpDefaultSLPips;
   double tpPips = InpDefaultTPPips;

   //--- Validate risk-reward ratio
   if(!g_riskManager.ValidateRiskReward(slPips, tpPips))
   {
      LogDebug(StringFormat("Trade rejected: R:R ratio %.2f below minimum %.2f",
               tpPips / slPips, InpMinRiskReward));
      return;
   }

   //--- Calculate lot size
   double lots = g_riskManager.CalculateLotSize(slPips);
   if(lots <= 0)
   {
      LogWarning("Lot size calculation returned 0 - trade skipped");
      return;
   }

   //--- Calculate SL and TP prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPrice = 0;
   double tpPrice = 0;

   string comment = StringFormat("%s_%s_S%d", InpEAComment, SignalToString(signal.signal), signal.strength);

   if(signal.signal == SIGNAL_BUY)
   {
      slPrice = ask - PipsToPrice(slPips);
      tpPrice = ask + PipsToPrice(tpPips);

      if(g_tradeManager.OpenBuy(lots, slPrice, tpPrice, comment))
      {
         g_totalTrades++;
         LogInfo(StringFormat("BUY executed: %.2f lots | SL=%.2f | TP=%.2f | Strength=%d | %s",
                 lots, slPrice, tpPrice, signal.strength, signal.reason));
      }
   }
   else if(signal.signal == SIGNAL_SELL)
   {
      slPrice = bid + PipsToPrice(slPips);
      tpPrice = bid - PipsToPrice(tpPips);

      if(g_tradeManager.OpenSell(lots, slPrice, tpPrice, comment))
      {
         g_totalTrades++;
         LogInfo(StringFormat("SELL executed: %.2f lots | SL=%.2f | TP=%.2f | Strength=%d | %s",
                 lots, slPrice, tpPrice, signal.strength, signal.reason));
      }
   }
}

//+------------------------------------------------------------------+
//| Create dashboard overlay on chart                                 |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   int x = 10, y = 30;
   int lineHeight = 18;
   color textColor = clrWhite;
   color bgColor = C'30,30,30';

   //--- Background rectangle
   CreateLabel("EA_BG", x - 5, y - 5, 280, 280, bgColor);

   //--- Header
   CreateText("EA_Title", x, y, EA_NAME + " v" + EA_VERSION, clrGold, 10);
   y += lineHeight + 5;
   CreateText("EA_Sep1", x, y, "-----------------------------", clrGray, 8);
   y += lineHeight;

   //--- Status fields
   CreateText("EA_Status",    x, y, "Status: Initializing", textColor, 9); y += lineHeight;
   CreateText("EA_Signal",    x, y, "Signal: None (0)", textColor, 9); y += lineHeight;
   CreateText("EA_Session",   x, y, "Session: ---", textColor, 9); y += lineHeight;
   y += 5;
   CreateText("EA_Sep2", x, y, "-----------------------------", clrGray, 8);
   y += lineHeight;

   //--- Account info
   CreateText("EA_Balance",   x, y, "Balance: ---", textColor, 9); y += lineHeight;
   CreateText("EA_Equity",    x, y, "Equity: ---", textColor, 9); y += lineHeight;
   CreateText("EA_Drawdown",  x, y, "Drawdown: ---", textColor, 9); y += lineHeight;
   CreateText("EA_DailyPnL",  x, y, "Today P&L: ---", textColor, 9); y += lineHeight;
   y += 5;
   CreateText("EA_Sep3", x, y, "-----------------------------", clrGray, 8);
   y += lineHeight;

   //--- Trade info
   CreateText("EA_Positions", x, y, "Positions: 0", textColor, 9); y += lineHeight;
   CreateText("EA_Spread",    x, y, "Spread: ---", textColor, 9); y += lineHeight;
   CreateText("EA_Trades",    x, y, "Total Trades: 0", textColor, 9); y += lineHeight;
   y += 5;
   CreateText("EA_Sep4", x, y, "-----------------------------", clrGray, 8);
   y += lineHeight;

   //--- Filter status
   CreateText("EA_NewsF",     x, y, "News Filter: ---", textColor, 9); y += lineHeight;
   CreateText("EA_RiskF",     x, y, "Risk Status: ---", textColor, 9); y += lineHeight;
}

//+------------------------------------------------------------------+
//| Update dashboard values                                           |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   //--- Status
   color statusColor = (g_eaStatus == "Active") ? clrLime : clrOrange;
   UpdateText("EA_Status", "Status: " + g_eaStatus, statusColor);

   //--- Signal
   color sigColor = clrWhite;
   if(g_lastSignal == "BUY") sigColor = clrLime;
   else if(g_lastSignal == "SELL") sigColor = clrRed;
   UpdateText("EA_Signal", StringFormat("Signal: %s (%d)", g_lastSignal, g_lastSignalStrength), sigColor);

   //--- Session
   UpdateText("EA_Session", "Session: " + SessionToString(GetCurrentSession()), clrWhite);

   //--- Account info
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = g_riskManager.GetCurrentDrawdown();
   double dailyPnL = g_riskManager.GetDailyPnL();

   UpdateText("EA_Balance", StringFormat("Balance: %.2f", balance), clrWhite);
   UpdateText("EA_Equity", StringFormat("Equity: %.2f", equity), clrWhite);

   color ddColor = (drawdown > 5.0) ? clrRed : (drawdown > 2.0) ? clrOrange : clrLime;
   UpdateText("EA_Drawdown", StringFormat("Drawdown: %.1f%%", drawdown), ddColor);

   color pnlColor = (dailyPnL >= 0) ? clrLime : clrRed;
   UpdateText("EA_DailyPnL", StringFormat("Today P&L: %.2f", dailyPnL), pnlColor);

   //--- Trade info
   int positions = g_tradeManager.CountOpenPositions();
   double spread = g_tradeManager.GetCurrentSpreadPips();

   UpdateText("EA_Positions", StringFormat("Positions: %d / %d", positions, InpMaxPositions), clrWhite);

   color spreadColor = (spread > InpMaxSpread * 0.8) ? clrRed : clrLime;
   UpdateText("EA_Spread", StringFormat("Spread: %.1f pips", spread), spreadColor);
   UpdateText("EA_Trades", StringFormat("Total Trades: %d", g_totalTrades), clrWhite);

   //--- Filters
   color newsColor = g_newsFilter.IsInBlackout() ? clrRed : clrLime;
   string newsStatus = g_newsFilter.IsInBlackout() ? "ACTIVE" : "Clear";
   UpdateText("EA_NewsF", "News Filter: " + newsStatus, newsColor);

   color riskColor = g_riskManager.IsTradingPaused() ? clrRed : clrLime;
   string riskStatus = g_riskManager.IsTradingPaused() ? "PAUSED" : "OK";
   UpdateText("EA_RiskF", "Risk Status: " + riskStatus, riskColor);
}

//+------------------------------------------------------------------+
//| Helper: Create a text label on chart                              |
//+------------------------------------------------------------------+
void CreateText(string name, int x, int y, string text, color clr, int fontSize = 9)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
}

//+------------------------------------------------------------------+
//| Helper: Create background rectangle label                         |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, int width, int height, color bgColor)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrGray);
}

//+------------------------------------------------------------------+
//| Helper: Update text of an existing label                          |
//+------------------------------------------------------------------+
void UpdateText(string name, string text, color clr)
{
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Trade transaction handler - track closed positions                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   //--- Track trade results for risk manager
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
      {
         // Check if this is a closing deal
         if(trans.deal > 0)
         {
            double profit = 0;
            if(HistoryDealSelect(trans.deal))
            {
               profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                        HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                        HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

               long dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
               long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);

               if(dealEntry == DEAL_ENTRY_OUT && dealMagic == InpMagicNumber)
               {
                  g_totalProfit += profit;
                  if(profit >= 0)
                     g_riskManager.RecordWin(profit);
                  else
                     g_riskManager.RecordLoss(profit);

                  LogInfo(StringFormat("Trade closed: P&L=%.2f | Total P&L=%.2f | Consec Losses=%d",
                          profit, g_totalProfit, g_riskManager.GetConsecutiveLosses()));
               }
            }
         }
      }
   }
}
