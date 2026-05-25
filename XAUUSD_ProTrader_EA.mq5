//+------------------------------------------------------------------+
//|                                          XAUUSD_ProTrader_EA.mq5 |
//|                          Copyright 2024, XAUUSD ProTrader Team   |
//|                                     https://github.com/Anburaj   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, XAUUSD ProTrader Team"
#property link      "https://github.com/Anburaj"
#property version   "2.00"
#property description "XAUUSD ProTrader EA v2 - Simplified & Effective"
#property description "EMA 21/50 trend + RSI confirmation on M5/H1"
#property description "Designed to ACTUALLY TAKE TRADES in live conditions"

//+------------------------------------------------------------------+
//| ZERO #include statements - raw MQL5 only                          |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Trade Settings ==="
input long     InpMagicNumber    = 202401;      // Magic Number
input double   InpRiskPercent    = 1.0;         // Risk per trade (%)
input double   InpSLPoints       = 300.0;       // Stop Loss in points (300 = $3.00 for gold)
input double   InpTPPoints       = 600.0;       // Take Profit in points (600 = $6.00 for gold)
input int      InpMaxPositions   = 2;           // Max simultaneous positions

input group "=== Indicator Settings ==="
input int      InpEMAFast        = 21;          // Fast EMA period
input int      InpEMASlow        = 50;          // Slow EMA period
input int      InpRSIPeriod      = 14;          // RSI period
input double   InpRSIBuyMin      = 40.0;        // RSI min for BUY
input double   InpRSIBuyMax      = 75.0;        // RSI max for BUY
input double   InpRSISellMin     = 25.0;        // RSI min for SELL
input double   InpRSISellMax     = 60.0;        // RSI max for SELL

input group "=== Trailing Stop ==="
input bool     InpEnableTrailing = true;        // Enable trailing stop
input double   InpTrailStart     = 200.0;       // Start trailing after X points profit
input double   InpTrailDistance  = 150.0;       // Trail distance in points

input group "=== Filters (all OFF by default to maximize trades) ==="
input bool     InpNewsFilter     = false;       // Enable news filter
input bool     InpSessionFilter  = false;       // Enable session filter (London+NY only)

//+------------------------------------------------------------------+
//| Global Variables                                                   |
//+------------------------------------------------------------------+
// Indicator handles
int g_emaFastH1Handle;     // EMA fast on H1
int g_emaSlowH1Handle;     // EMA slow on H1
int g_emaFastM5Handle;     // EMA fast on M5
int g_emaSlowM5Handle;     // EMA slow on M5
int g_rsiM5Handle;         // RSI on M5

// State
datetime g_lastBarTime;    // Last M5 bar time (for new bar detection)
bool g_initialized;        // Data ready flag

//+------------------------------------------------------------------+
//| OnInit - Create indicator handles                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== XAUUSD ProTrader EA v2.0 Initializing ===");
   
   // Create EMA handles for H1 timeframe
   g_emaFastH1Handle = iMA(_Symbol, PERIOD_H1, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowH1Handle = iMA(_Symbol, PERIOD_H1, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   
   // Create EMA handle for M5 timeframe
   g_emaFastM5Handle = iMA(_Symbol, PERIOD_M5, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowM5Handle = iMA(_Symbol, PERIOD_M5, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   
   // Create RSI handle for M5 timeframe
   g_rsiM5Handle = iRSI(_Symbol, PERIOD_M5, InpRSIPeriod, PRICE_CLOSE);
   
   // Validate handles
   if(g_emaFastH1Handle == INVALID_HANDLE || g_emaSlowH1Handle == INVALID_HANDLE ||
      g_emaFastM5Handle == INVALID_HANDLE || g_emaSlowM5Handle == INVALID_HANDLE ||
      g_rsiM5Handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles!");
      Print("  EMA Fast H1: ", g_emaFastH1Handle);
      Print("  EMA Slow H1: ", g_emaSlowH1Handle);
      Print("  EMA Fast M5: ", g_emaFastM5Handle);
      Print("  EMA Slow M5: ", g_emaSlowM5Handle);
      Print("  RSI M5: ", g_rsiM5Handle);
      return(INIT_FAILED);
   }
   
   g_lastBarTime = 0;
   g_initialized = false;
   
   Print("EA initialized successfully. Magic=", InpMagicNumber);
   Print("Settings: SL=", InpSLPoints, " TP=", InpTPPoints, " Risk=", InpRiskPercent, "%");
   Print("EMA Fast=", InpEMAFast, " EMA Slow=", InpEMASlow, " RSI=", InpRSIPeriod);
   Print("Waiting for signals...");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit - Release indicator handles                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_emaFastH1Handle != INVALID_HANDLE) IndicatorRelease(g_emaFastH1Handle);
   if(g_emaSlowH1Handle != INVALID_HANDLE) IndicatorRelease(g_emaSlowH1Handle);
   if(g_emaFastM5Handle != INVALID_HANDLE) IndicatorRelease(g_emaFastM5Handle);
   if(g_emaSlowM5Handle != INVALID_HANDLE) IndicatorRelease(g_emaSlowM5Handle);
   if(g_rsiM5Handle != INVALID_HANDLE)     IndicatorRelease(g_rsiM5Handle);
   
   Print("XAUUSD ProTrader EA v2.0 removed. Reason=", reason);
}

//+------------------------------------------------------------------+
//| OnTick - Main logic                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we have enough bars for indicators
   if(!g_initialized)
   {
      if(Bars(_Symbol, PERIOD_M5) < 60 || Bars(_Symbol, PERIOD_H1) < 60)
      {
         return;  // Not enough data yet
      }
      g_initialized = true;
      Print("Data ready. Bars M5=", Bars(_Symbol, PERIOD_M5), " Bars H1=", Bars(_Symbol, PERIOD_H1));
   }
   
   // Manage trailing stop on every tick (for open positions)
   if(InpEnableTrailing)
      ManageTrailing();
   
   // Only check for new signals on new M5 bar
   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBarTime == g_lastBarTime)
      return;  // Not a new bar
   g_lastBarTime = currentBarTime;
   
   // Session filter (optional)
   if(InpSessionFilter && !IsSessionAllowed())
      return;
   
   // Check max positions
   if(CountPositions() >= InpMaxPositions)
      return;
   
   // Generate signal
   int signal = GetSignal();
   
   if(signal == 1)
      OpenBuy();
   else if(signal == -1)
      OpenSell();
}

//+------------------------------------------------------------------+
//| GetSignal - EMA + RSI signal generation (BUY and SELL)             |
//| BUY: H1 trend UP + M5 momentum UP + RSI healthy                   |
//| SELL: H1 trend DOWN OR M5 bearish crossover + RSI confirms        |
//+------------------------------------------------------------------+
int GetSignal()
{
   // Read EMA values from H1
   double emaFastH1[2], emaSlowH1[2];
   if(CopyBuffer(g_emaFastH1Handle, 0, 0, 2, emaFastH1) < 2) return 0;
   if(CopyBuffer(g_emaSlowH1Handle, 0, 0, 2, emaSlowH1) < 2) return 0;
   
   // Read EMA values from M5 (both fast and slow)
   double emaFastM5[3], emaSlowM5[3];
   if(CopyBuffer(g_emaFastM5Handle, 0, 0, 3, emaFastM5) < 3) return 0;
   if(CopyBuffer(g_emaSlowM5Handle, 0, 0, 3, emaSlowM5) < 3) return 0;
   
   // Read RSI from M5
   double rsi[3];
   if(CopyBuffer(g_rsiM5Handle, 0, 0, 3, rsi) < 3) return 0;
   
   // Get M5 close prices (bar 1 = last completed bar)
   double closeM5     = iClose(_Symbol, PERIOD_M5, 1);
   double closeM5prev = iClose(_Symbol, PERIOD_M5, 2);
   
   // Current indicator values (index 0 = most recent)
   double ema21H1 = emaFastH1[0];
   double ema50H1 = emaSlowH1[0];
   double ema21M5 = emaFastM5[0];
   double ema50M5 = emaSlowM5[0];
   double rsiVal  = rsi[0];
   double rsiPrev = rsi[1];
   
   // H1 trend direction
   bool h1TrendUp   = (ema21H1 > ema50H1);
   bool h1TrendDown = (ema21H1 < ema50H1);
   
   // M5 trend direction  
   bool m5TrendUp   = (ema21M5 > ema50M5);
   bool m5TrendDown = (ema21M5 < ema50M5);
   
   // M5 EMA crossover detection (bearish: fast crossed below slow)
   bool m5BearishCross = (emaFastM5[1] >= emaSlowM5[1]) && (emaFastM5[0] < emaSlowM5[0]);
   bool m5BullishCross = (emaFastM5[1] <= emaSlowM5[1]) && (emaFastM5[0] > emaSlowM5[0]);
   
   // Price momentum
   bool priceAboveEMA21 = (closeM5 > ema21M5);
   bool priceBelowEMA21 = (closeM5 < ema21M5);
   
   // RSI conditions
   bool rsiBuyOK  = (rsiVal > InpRSIBuyMin && rsiVal < InpRSIBuyMax);
   bool rsiSellOK = (rsiVal > InpRSISellMin && rsiVal < InpRSISellMax);
   
   // RSI falling (bearish momentum)
   bool rsiFalling = (rsiVal < rsiPrev);
   bool rsiRising  = (rsiVal > rsiPrev);
   
   //=================================================================
   // BUY SIGNAL CONDITIONS
   //=================================================================
   // Primary: H1 uptrend + M5 price above EMA21 + RSI healthy
   // Secondary: M5 bullish crossover + RSI rising
   //=================================================================
   bool buySignal = false;
   
   // Primary buy: H1 trend up + M5 momentum confirms
   if(h1TrendUp && priceAboveEMA21 && rsiBuyOK)
      buySignal = true;
   
   // Secondary buy: M5 bullish crossover with rising RSI (catch early entries)
   if(m5BullishCross && rsiRising && rsiVal > 45 && rsiVal < 75)
      buySignal = true;
   
   //=================================================================
   // SELL SIGNAL CONDITIONS
   //=================================================================
   // Primary: H1 downtrend + M5 price below EMA21 + RSI healthy
   // Secondary: M5 bearish crossover + RSI falling (works even in H1 uptrend)
   // Tertiary: H1 uptrend BUT M5 shows reversal (overbought pullback sell)
   //=================================================================
   bool sellSignal = false;
   
   // Primary sell: H1 trend down + M5 confirms
   if(h1TrendDown && priceBelowEMA21 && rsiSellOK)
      sellSignal = true;
   
   // Secondary sell: M5 bearish crossover + RSI falling (trend reversal on M5)
   if(m5BearishCross && rsiFalling && rsiVal < 60)
      sellSignal = true;
   
   // Tertiary sell: H1 still up BUT M5 turned bearish + price below M5 EMAs + RSI dropping
   // This catches pullbacks/corrections in an uptrend
   if(h1TrendUp && m5TrendDown && priceBelowEMA21 && rsiFalling && rsiVal < 55)
      sellSignal = true;
   
   // Overbought reversal sell: RSI was very high and is now dropping + price below EMA
   if(priceBelowEMA21 && rsiPrev > 70 && rsiVal < 65 && rsiFalling)
      sellSignal = true;
   
   //=================================================================
   // CONFLICT RESOLUTION: if both fire, use RSI direction
   //=================================================================
   if(buySignal && sellSignal)
   {
      if(rsiRising)
         sellSignal = false;
      else
         buySignal = false;
   }
   
   if(buySignal)
   {
      Print(">>> BUY SIGNAL: EMA21_H1=", DoubleToString(ema21H1, 2),
            " EMA50_H1=", DoubleToString(ema50H1, 2),
            " Close_M5=", DoubleToString(closeM5, 2),
            " EMA21_M5=", DoubleToString(ema21M5, 2),
            " EMA50_M5=", DoubleToString(ema50M5, 2),
            " RSI=", DoubleToString(rsiVal, 1));
      return 1;
   }
   
   if(sellSignal)
   {
      Print(">>> SELL SIGNAL: EMA21_H1=", DoubleToString(ema21H1, 2),
            " EMA50_H1=", DoubleToString(ema50H1, 2),
            " Close_M5=", DoubleToString(closeM5, 2),
            " EMA21_M5=", DoubleToString(ema21M5, 2),
            " EMA50_M5=", DoubleToString(ema50M5, 2),
            " RSI=", DoubleToString(rsiVal, 1));
      return -1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| CalculateLotSize - Based on risk percentage and SL                 |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   
   // Get tick value (value of 1 point move for 1 lot)
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue <= 0 || tickSize <= 0 || InpSLPoints <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   // Calculate: lot size = risk amount / (SL in ticks * tick value)
   double pointValue = tickValue / tickSize;  // Value per point per lot
   double lots = riskAmount / (InpSLPoints * pointValue);
   
   // Apply broker limits
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Round to lot step
   lots = MathFloor(lots / lotStep) * lotStep;
   
   // Clamp
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   
   return lots;
}

//+------------------------------------------------------------------+
//| OpenBuy - Execute a buy trade                                      |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = ask - InpSLPoints * point;
   double tp = ask + InpTPPoints * point;
   double lots = CalculateLotSize();
   
   // Normalize prices
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
   
   Print("Opening BUY: lots=", DoubleToString(lots, 2),
         " price=", DoubleToString(ask, digits),
         " sl=", DoubleToString(sl, digits),
         " tp=", DoubleToString(tp, digits));
   
   SendTradeRequest(ORDER_TYPE_BUY, lots, ask, sl, tp);
}

//+------------------------------------------------------------------+
//| OpenSell - Execute a sell trade                                    |
//+------------------------------------------------------------------+
void OpenSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = bid + InpSLPoints * point;
   double tp = bid - InpTPPoints * point;
   double lots = CalculateLotSize();
   
   // Normalize prices
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
   
   Print("Opening SELL: lots=", DoubleToString(lots, 2),
         " price=", DoubleToString(bid, digits),
         " sl=", DoubleToString(sl, digits),
         " tp=", DoubleToString(tp, digits));
   
   SendTradeRequest(ORDER_TYPE_SELL, lots, bid, sl, tp);
}

//+------------------------------------------------------------------+
//| SendTradeRequest - Raw OrderSend with filling mode fallback        |
//+------------------------------------------------------------------+
void SendTradeRequest(ENUM_ORDER_TYPE orderType, double lots, double price, double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.volume    = lots;
   request.type      = orderType;
   request.price     = price;
   request.sl        = sl;
   request.tp        = tp;
   request.deviation = 50;
   request.magic     = InpMagicNumber;
   request.comment   = "XAUUSD_Pro_v2";
   
   // Try ORDER_FILLING_FOK first
   request.type_filling = ORDER_FILLING_FOK;
   if(OrderSend(request, result))
   {
      Print("Order SUCCESS: retcode=", result.retcode,
            " deal=", result.deal, " order=", result.order,
            " price=", result.price, " volume=", result.volume);
      return;
   }
   
   Print("FOK failed: retcode=", result.retcode, " comment=", result.comment);
   
   // Try ORDER_FILLING_IOC
   ZeroMemory(result);
   request.type_filling = ORDER_FILLING_IOC;
   if(OrderSend(request, result))
   {
      Print("Order SUCCESS (IOC): retcode=", result.retcode,
            " deal=", result.deal, " order=", result.order);
      return;
   }
   
   Print("IOC failed: retcode=", result.retcode, " comment=", result.comment);
   
   // Try ORDER_FILLING_RETURN
   ZeroMemory(result);
   request.type_filling = ORDER_FILLING_RETURN;
   if(OrderSend(request, result))
   {
      Print("Order SUCCESS (RETURN): retcode=", result.retcode,
            " deal=", result.deal, " order=", result.order);
      return;
   }
   
   Print("ALL filling modes FAILED: retcode=", result.retcode,
         " comment=", result.comment);
}

//+------------------------------------------------------------------+
//| ManageTrailing - Simple trailing stop for open positions            |
//+------------------------------------------------------------------+
void ManageTrailing()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      // Only manage our positions
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long posType = PositionGetInteger(POSITION_TYPE);
      
      if(posType == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profitPoints = (bid - openPrice) / point;
         
         if(profitPoints >= InpTrailStart)
         {
            double newSL = bid - InpTrailDistance * point;
            newSL = NormalizeDouble(newSL, digits);
            
            // Only move SL forward (up for buys)
            if(newSL > currentSL)
            {
               ModifyPosition(ticket, newSL, currentTP);
            }
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profitPoints = (openPrice - ask) / point;
         
         if(profitPoints >= InpTrailStart)
         {
            double newSL = ask + InpTrailDistance * point;
            newSL = NormalizeDouble(newSL, digits);
            
            // Only move SL forward (down for sells)
            if(newSL < currentSL || currentSL == 0)
            {
               ModifyPosition(ticket, newSL, currentTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ModifyPosition - Modify SL/TP of a position                        |
//+------------------------------------------------------------------+
void ModifyPosition(ulong ticket, double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action   = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol   = _Symbol;
   request.sl       = sl;
   request.tp       = tp;
   
   if(OrderSend(request, result))
   {
      Print("Trailing: ticket=", ticket, " new SL=", DoubleToString(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)));
   }
   else
   {
      Print("Trail modify FAILED: ticket=", ticket, " retcode=", result.retcode);
   }
}

//+------------------------------------------------------------------+
//| CountPositions - Count open positions with our magic number        |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   int total = PositionsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         count++;
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| IsSessionAllowed - Check if current time is in London or NY         |
//+------------------------------------------------------------------+
bool IsSessionAllowed()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   
   // London: 08:00-16:00 server time
   // New York: 13:00-21:00 server time
   if(hour >= 8 && hour < 21)
      return true;
   
   return false;
}
//+------------------------------------------------------------------+
