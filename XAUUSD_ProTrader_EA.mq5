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
//| Standard Library Includes (MT5 built-in)                          |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Constants                                                         |
//+------------------------------------------------------------------+
#define XAUUSD_PIP_SIZE       0.01
#define XAUUSD_POINT_PER_PIP  10
#define EA_NAME               "XAUUSD ProTrader EA"
#define EA_VERSION            "1.0"
#define MAX_RETRIES           3
#define RETRY_DELAY_MS        500

#define ASIAN_START_HOUR      0
#define ASIAN_END_HOUR        8
#define LONDON_START_HOUR     8
#define LONDON_END_HOUR       16
#define NEWYORK_START_HOUR    13
#define NEWYORK_END_HOUR      21
#define OVERLAP_START_HOUR    13
#define OVERLAP_END_HOUR      16

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_TYPE
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
};

enum ENUM_TRADE_DIRECTION
{
   DIRECTION_LONG  = 1,
   DIRECTION_SHORT = -1,
   DIRECTION_FLAT  = 0
};

enum ENUM_SESSION_TYPE
{
   SESSION_ASIAN   = 0,
   SESSION_LONDON  = 1,
   SESSION_NEWYORK = 2,
   SESSION_OVERLAP = 3,
   SESSION_OFFHOURS = 4
};

enum ENUM_LOG_LEVEL
{
   LOG_DEBUG   = 0,
   LOG_INFO    = 1,
   LOG_WARNING = 2,
   LOG_ERROR   = 3,
   LOG_CRITICAL = 4
};

enum ENUM_TRAILING_MODE
{
   TRAIL_NONE          = 0,   // No trailing (fixed SL)
   TRAIL_STANDARD      = 1,   // Standard trailing stop
   TRAIL_HIDDEN_LOCKIN = 2,   // Hidden lock-in profit
   TRAIL_JUMP          = 3,   // Jump stop loss (discrete steps)
   TRAIL_PROGRESSIVE   = 4,   // Progressive (tightens as profit grows)
   TRAIL_ATR           = 5,   // ATR-based trailing
   TRAIL_STRUCTURE     = 6    // Structure-based (swing points)
};

enum ENUM_ACCOUNT_TIER
{
   TIER_MICRO    = 0,
   TIER_MINI     = 1,
   TIER_STANDARD = 2
};

//+------------------------------------------------------------------+
//| Utility Functions (must be declared before classes that use them) |
//+------------------------------------------------------------------+
void XAU_LogMessage(ENUM_LOG_LEVEL level, string message)
{
   string prefix = "";
   switch(level)
   {
      case LOG_DEBUG:    prefix = "[DEBUG] ";    break;
      case LOG_INFO:     prefix = "[INFO] ";     break;
      case LOG_WARNING:  prefix = "[WARN] ";     break;
      case LOG_ERROR:    prefix = "[ERROR] ";    break;
      case LOG_CRITICAL: prefix = "[CRITICAL] "; break;
   }
   Print(EA_NAME, " ", prefix, message);
}

void XAU_LogDebug(string msg)    { XAU_LogMessage(LOG_DEBUG, msg); }
void XAU_LogInfo(string msg)     { XAU_LogMessage(LOG_INFO, msg); }
void XAU_LogWarning(string msg)  { XAU_LogMessage(LOG_WARNING, msg); }
void XAU_LogError(string msg)    { XAU_LogMessage(LOG_ERROR, msg); }
void XAU_LogCritical(string msg) { XAU_LogMessage(LOG_CRITICAL, msg); }

double XAU_PipsToPrice(double pips)
{
   return pips * XAUUSD_PIP_SIZE;
}

double XAU_PriceToPips(double priceDistance)
{
   if(XAUUSD_PIP_SIZE == 0) return 0;
   return priceDistance / XAUUSD_PIP_SIZE;
}

double XAU_GetPipValue(double lotSize)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0) return 0;
   return (XAUUSD_PIP_SIZE / tickSize) * tickValue * lotSize;
}

ENUM_SESSION_TYPE GetCurrentSession()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int hour = timeStruct.hour;

   if(hour >= OVERLAP_START_HOUR && hour < OVERLAP_END_HOUR)
      return SESSION_OVERLAP;
   if(hour >= LONDON_START_HOUR && hour < LONDON_END_HOUR)
      return SESSION_LONDON;
   if(hour >= NEWYORK_START_HOUR && hour < NEWYORK_END_HOUR)
      return SESSION_NEWYORK;
   if(hour >= ASIAN_START_HOUR && hour < ASIAN_END_HOUR)
      return SESSION_ASIAN;

   return SESSION_OFFHOURS;
}

bool IsInSession(ENUM_SESSION_TYPE session)
{
   return (GetCurrentSession() == session);
}

bool IsWithinHours(int startHour, int endHour)
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int hour = timeStruct.hour;

   if(startHour <= endHour)
      return (hour >= startHour && hour < endHour);
   else
      return (hour >= startHour || hour < endHour);
}

int GetDayOfWeek()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   return timeStruct.day_of_week;
}

bool IsNewBar(ENUM_TIMEFRAMES timeframe)
{
   static datetime lastBarTimes[25];
   static bool initialized = false;

   if(!initialized)
   {
      ArrayInitialize(lastBarTimes, 0);
      initialized = true;
   }

   int idx = 0;
   switch(timeframe)
   {
      case PERIOD_M1:  idx = 0;  break;
      case PERIOD_M2:  idx = 1;  break;
      case PERIOD_M3:  idx = 2;  break;
      case PERIOD_M4:  idx = 3;  break;
      case PERIOD_M5:  idx = 4;  break;
      case PERIOD_M6:  idx = 5;  break;
      case PERIOD_M10: idx = 6;  break;
      case PERIOD_M12: idx = 7;  break;
      case PERIOD_M15: idx = 8;  break;
      case PERIOD_M20: idx = 9;  break;
      case PERIOD_M30: idx = 10; break;
      case PERIOD_H1:  idx = 11; break;
      case PERIOD_H2:  idx = 12; break;
      case PERIOD_H3:  idx = 13; break;
      case PERIOD_H4:  idx = 14; break;
      case PERIOD_H6:  idx = 15; break;
      case PERIOD_H8:  idx = 16; break;
      case PERIOD_H12: idx = 17; break;
      case PERIOD_D1:  idx = 18; break;
      case PERIOD_W1:  idx = 19; break;
      case PERIOD_MN1: idx = 20; break;
      default:         idx = 21; break;
   }

   datetime currentBarTime = iTime(_Symbol, timeframe, 0);

   if(currentBarTime != lastBarTimes[idx])
   {
      lastBarTimes[idx] = currentBarTime;
      return true;
   }
   return false;
}

double XAU_NormalizeLot(double lots)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lotStep == 0) lotStep = 0.01;

   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = NormalizeDouble(lots, 2);

   return lots;
}

double XAU_GetSpreadPips()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return XAU_PriceToPips(ask - bid);
}

double ArrayMaxCustom(const double &arr[], int count = -1)
{
   int size = (count > 0) ? MathMin(count, ArraySize(arr)) : ArraySize(arr);
   if(size == 0) return 0;
   double maxVal = arr[0];
   for(int i = 1; i < size; i++)
      if(arr[i] > maxVal) maxVal = arr[i];
   return maxVal;
}

double ArrayMinCustom(const double &arr[], int count = -1)
{
   int size = (count > 0) ? MathMin(count, ArraySize(arr)) : ArraySize(arr);
   if(size == 0) return 0;
   double minVal = arr[0];
   for(int i = 1; i < size; i++)
      if(arr[i] < minVal) minVal = arr[i];
   return minVal;
}

string FormatDuration(int seconds)
{
   int hours   = seconds / 3600;
   int minutes = (seconds % 3600) / 60;
   int secs    = seconds % 60;
   return StringFormat("%02d:%02d:%02d", hours, minutes, secs);
}

string SignalToString(ENUM_SIGNAL_TYPE signal)
{
   switch(signal)
   {
      case SIGNAL_BUY:  return "BUY";
      case SIGNAL_SELL: return "SELL";
      default:          return "NONE";
   }
}

string SessionToString(ENUM_SESSION_TYPE session)
{
   switch(session)
   {
      case SESSION_ASIAN:    return "Asian";
      case SESSION_LONDON:   return "London";
      case SESSION_NEWYORK:  return "New York";
      case SESSION_OVERLAP:  return "London/NY Overlap";
      default:               return "Off-Hours";
   }
}


//+------------------------------------------------------------------+
//| Structures                                                        |
//+------------------------------------------------------------------+
struct SMCZone
{
   double            priceHigh;
   double            priceLow;
   datetime          timeCreated;
   int               touchCount;
   bool              isValid;
   bool              isBullish;
   int               strength;
};

struct StructurePoint
{
   double            price;
   datetime          time;
   bool              isHigh;
   int               barIndex;
};

struct SignalResult
{
   ENUM_SIGNAL_TYPE  signal;
   int               strength;
   bool              emaConfirmed;
   bool              rsiConfirmed;
   bool              smcConfirmed;
   string            reason;
   double            suggestedSL;
   double            suggestedTP;
};

struct NewsEvent
{
   string            name;
   int               dayOfWeek;
   int               weekOfMonth;
   int               hour;
   int               minute;
   int               impact;
};

struct BlackoutPeriod
{
   datetime          startTime;
   datetime          endTime;
   string            reason;
};

struct HiddenStopData
{
   ulong             ticket;
   double            hiddenSL;
   double            lastJumpLevel;
   double            lockInThreshold;
   bool              lockInActive;
   int               jumpCount;
};


//+------------------------------------------------------------------+
//| CSMCAnalysis - Smart Money Concepts Analysis Engine               |
//+------------------------------------------------------------------+
class CSMCAnalysis
{
private:
   int               m_lookbackBars;
   int               m_swingStrength;
   int               m_maxZones;
   int               m_zoneExpiryBars;
   ENUM_TIMEFRAMES   m_timeframe;
   string            m_symbol;

   SMCZone           m_orderBlocks[];
   SMCZone           m_fvgZones[];
   SMCZone           m_liquidityPools[];
   StructurePoint    m_swingPoints[];

   double            m_lastSwingHigh;
   double            m_lastSwingLow;
   bool              m_isBullishStructure;
   bool              m_bosDetected;
   bool              m_chochDetected;

   bool              IsSwingHigh(int index, int strength);
   bool              IsSwingLow(int index, int strength);
   void              DetectSwingPoints();
   void              InvalidateExpiredZones();
   double            GetRangeHigh(int bars);
   double            GetRangeLow(int bars);

public:
                     CSMCAnalysis();
                    ~CSMCAnalysis();

   bool              Init(string symbol, ENUM_TIMEFRAMES tf, int lookback = 100,
                          int swingStr = 3, int maxZones = 20, int expiryBars = 500);
   void              Update();
   void              DetectOrderBlocks();
   bool              IsPriceAtOrderBlock(double price, bool &isBullish);
   void              ConsumeOrderBlock(double price);
   int               GetOrderBlockCount() { return ArraySize(m_orderBlocks); }
   bool              GetNearestOrderBlock(double price, bool isBuy, double &zoneHigh, double &zoneLow);
   void              DetectFairValueGaps();
   bool              IsPriceInFVG(double price, bool &isBullish);
   void              ConsumeFVG(double price);
   int               GetFVGCount() { return ArraySize(m_fvgZones); }
   void              DetectLiquidityPools();
   bool              IsLiquiditySweep(double price);
   void              ConsumeLiquiditySweep(double price);
   int               GetLiquidityPoolCount() { return ArraySize(m_liquidityPools); }
   bool              DetectBOS();
   bool              DetectCHoCH();
   bool              IsBullishStructure() { return m_isBullishStructure; }
   bool              HasBOS() { return m_bosDetected; }
   bool              HasCHoCH() { return m_chochDetected; }
   bool              IsInPremiumZone(double price);
   bool              IsInDiscountZone(double price);
   double            GetEquilibriumPrice();
   double            GetLastSwingHigh() { return m_lastSwingHigh; }
   double            GetLastSwingLow() { return m_lastSwingLow; }
};

CSMCAnalysis::CSMCAnalysis()
{
   m_lookbackBars = 100;
   m_swingStrength = 3;
   m_maxZones = 20;
   m_zoneExpiryBars = 500;
   m_timeframe = PERIOD_M5;
   m_symbol = "";
   m_lastSwingHigh = 0;
   m_lastSwingLow = 0;
   m_isBullishStructure = false;
   m_bosDetected = false;
   m_chochDetected = false;
}

CSMCAnalysis::~CSMCAnalysis()
{
   ArrayFree(m_orderBlocks);
   ArrayFree(m_fvgZones);
   ArrayFree(m_liquidityPools);
   ArrayFree(m_swingPoints);
}

bool CSMCAnalysis::Init(string symbol, ENUM_TIMEFRAMES tf, int lookback,
                        int swingStr, int maxZones, int expiryBars)
{
   m_symbol = symbol;
   m_timeframe = tf;
   m_lookbackBars = lookback;
   m_swingStrength = swingStr;
   m_maxZones = maxZones;
   m_zoneExpiryBars = expiryBars;

   ArrayResize(m_orderBlocks, 0);
   ArrayResize(m_fvgZones, 0);
   ArrayResize(m_liquidityPools, 0);
   ArrayResize(m_swingPoints, 0);

   XAU_LogInfo("SMC Analysis initialized: " + symbol + " " + EnumToString(tf));
   return true;
}

bool CSMCAnalysis::IsSwingHigh(int index, int strength)
{
   double high = iHigh(m_symbol, m_timeframe, index);
   for(int i = 1; i <= strength; i++)
   {
      if(iHigh(m_symbol, m_timeframe, index + i) >= high) return false;
      if(iHigh(m_symbol, m_timeframe, index - i) >= high) return false;
   }
   return true;
}

bool CSMCAnalysis::IsSwingLow(int index, int strength)
{
   double low = iLow(m_symbol, m_timeframe, index);
   for(int i = 1; i <= strength; i++)
   {
      if(iLow(m_symbol, m_timeframe, index + i) <= low) return false;
      if(iLow(m_symbol, m_timeframe, index - i) <= low) return false;
   }
   return true;
}

void CSMCAnalysis::DetectSwingPoints()
{
   ArrayResize(m_swingPoints, 0);
   int count = 0;

   for(int i = m_swingStrength; i < m_lookbackBars - m_swingStrength; i++)
   {
      StructurePoint sp;
      if(IsSwingHigh(i, m_swingStrength))
      {
         sp.price = iHigh(m_symbol, m_timeframe, i);
         sp.time = iTime(m_symbol, m_timeframe, i);
         sp.isHigh = true;
         sp.barIndex = i;
         ArrayResize(m_swingPoints, count + 1);
         m_swingPoints[count] = sp;
         count++;
      }
      if(IsSwingLow(i, m_swingStrength))
      {
         sp.price = iLow(m_symbol, m_timeframe, i);
         sp.time = iTime(m_symbol, m_timeframe, i);
         sp.isHigh = false;
         sp.barIndex = i;
         ArrayResize(m_swingPoints, count + 1);
         m_swingPoints[count] = sp;
         count++;
      }
   }

   for(int i = 0; i < count; i++)
   {
      if(m_swingPoints[i].isHigh && (m_lastSwingHigh == 0 || m_swingPoints[i].barIndex < 10))
         m_lastSwingHigh = m_swingPoints[i].price;
      if(!m_swingPoints[i].isHigh && (m_lastSwingLow == 0 || m_swingPoints[i].barIndex < 10))
         m_lastSwingLow = m_swingPoints[i].price;
   }
}

void CSMCAnalysis::InvalidateExpiredZones()
{
   datetime expiryTime = iTime(m_symbol, m_timeframe, m_zoneExpiryBars);

   for(int i = ArraySize(m_orderBlocks) - 1; i >= 0; i--)
      if(m_orderBlocks[i].timeCreated < expiryTime)
         m_orderBlocks[i].isValid = false;
   for(int i = ArraySize(m_fvgZones) - 1; i >= 0; i--)
      if(m_fvgZones[i].timeCreated < expiryTime)
         m_fvgZones[i].isValid = false;
}

double CSMCAnalysis::GetRangeHigh(int bars)
{
   double highest = 0;
   for(int i = 0; i < bars; i++)
   {
      double h = iHigh(m_symbol, m_timeframe, i);
      if(h > highest) highest = h;
   }
   return highest;
}

double CSMCAnalysis::GetRangeLow(int bars)
{
   double lowest = DBL_MAX;
   for(int i = 0; i < bars; i++)
   {
      double l = iLow(m_symbol, m_timeframe, i);
      if(l < lowest) lowest = l;
   }
   return lowest;
}

void CSMCAnalysis::Update()
{
   m_bosDetected = false;
   m_chochDetected = false;

   DetectSwingPoints();
   DetectOrderBlocks();
   DetectFairValueGaps();
   DetectLiquidityPools();

   if(!DetectCHoCH())
      DetectBOS();

   InvalidateExpiredZones();
}


void CSMCAnalysis::DetectOrderBlocks()
{
   ArrayResize(m_orderBlocks, 0);
   int count = 0;

   for(int i = 2; i < m_lookbackBars - 2; i++)
   {
      double open_i  = iOpen(m_symbol, m_timeframe, i);
      double close_i = iClose(m_symbol, m_timeframe, i);
      double high_i  = iHigh(m_symbol, m_timeframe, i);
      double low_i   = iLow(m_symbol, m_timeframe, i);

      double open_next  = iOpen(m_symbol, m_timeframe, i - 1);
      double close_next = iClose(m_symbol, m_timeframe, i - 1);
      double high_next  = iHigh(m_symbol, m_timeframe, i - 1);

      double bodySize_i = MathAbs(close_i - open_i);
      double bodySize_next = MathAbs(close_next - open_next);

      if(close_i < open_i && close_next > open_next)
      {
         if(bodySize_next > bodySize_i * 2.0 && high_next > high_i)
         {
            SMCZone ob;
            ob.priceHigh = high_i;
            ob.priceLow = low_i;
            ob.timeCreated = iTime(m_symbol, m_timeframe, i);
            ob.touchCount = 0;
            ob.isValid = true;
            ob.isBullish = true;
            ob.strength = (int)MathMin(10, (bodySize_next / bodySize_i) * 2);

            if(count < m_maxZones)
            {
               ArrayResize(m_orderBlocks, count + 1);
               m_orderBlocks[count] = ob;
               count++;
            }
         }
      }

      if(close_i > open_i && close_next < open_next)
      {
         double low_next = iLow(m_symbol, m_timeframe, i - 1);
         if(bodySize_next > bodySize_i * 2.0 && low_next < low_i)
         {
            SMCZone ob;
            ob.priceHigh = high_i;
            ob.priceLow = low_i;
            ob.timeCreated = iTime(m_symbol, m_timeframe, i);
            ob.touchCount = 0;
            ob.isValid = true;
            ob.isBullish = false;
            ob.strength = (int)MathMin(10, (bodySize_next / bodySize_i) * 2);

            if(count < m_maxZones)
            {
               ArrayResize(m_orderBlocks, count + 1);
               m_orderBlocks[count] = ob;
               count++;
            }
         }
      }
   }
}

bool CSMCAnalysis::IsPriceAtOrderBlock(double price, bool &isBullish)
{
   for(int i = 0; i < ArraySize(m_orderBlocks); i++)
   {
      if(!m_orderBlocks[i].isValid) continue;
      if(price >= m_orderBlocks[i].priceLow && price <= m_orderBlocks[i].priceHigh)
      {
         isBullish = m_orderBlocks[i].isBullish;
         return true;
      }
   }
   return false;
}

void CSMCAnalysis::ConsumeOrderBlock(double price)
{
   for(int i = 0; i < ArraySize(m_orderBlocks); i++)
   {
      if(!m_orderBlocks[i].isValid) continue;
      if(price >= m_orderBlocks[i].priceLow && price <= m_orderBlocks[i].priceHigh)
      {
         m_orderBlocks[i].touchCount++;
         if(m_orderBlocks[i].touchCount >= 3)
            m_orderBlocks[i].isValid = false;
         return;
      }
   }
}

bool CSMCAnalysis::GetNearestOrderBlock(double price, bool isBuy, double &zoneHigh, double &zoneLow)
{
   double bestDist = DBL_MAX;
   bool found = false;

   for(int i = 0; i < ArraySize(m_orderBlocks); i++)
   {
      if(!m_orderBlocks[i].isValid) continue;

      if(isBuy && !m_orderBlocks[i].isBullish && m_orderBlocks[i].priceHigh < price)
      {
         double dist = price - m_orderBlocks[i].priceHigh;
         if(dist < bestDist)
         {
            bestDist = dist;
            zoneHigh = m_orderBlocks[i].priceHigh;
            zoneLow = m_orderBlocks[i].priceLow;
            found = true;
         }
      }
      else if(!isBuy && m_orderBlocks[i].isBullish && m_orderBlocks[i].priceLow > price)
      {
         double dist = m_orderBlocks[i].priceLow - price;
         if(dist < bestDist)
         {
            bestDist = dist;
            zoneHigh = m_orderBlocks[i].priceHigh;
            zoneLow = m_orderBlocks[i].priceLow;
            found = true;
         }
      }
   }
   return found;
}

void CSMCAnalysis::DetectFairValueGaps()
{
   ArrayResize(m_fvgZones, 0);
   int count = 0;

   for(int i = 1; i < m_lookbackBars - 2; i++)
   {
      double high1 = iHigh(m_symbol, m_timeframe, i + 1);
      double low1  = iLow(m_symbol, m_timeframe, i + 1);
      double high3 = iHigh(m_symbol, m_timeframe, i - 1);
      double low3  = iLow(m_symbol, m_timeframe, i - 1);
      double close2 = iClose(m_symbol, m_timeframe, i);
      double open2  = iOpen(m_symbol, m_timeframe, i);

      if(low3 > high1 && close2 > open2)
      {
         SMCZone fvg;
         fvg.priceLow = high1;
         fvg.priceHigh = low3;
         fvg.timeCreated = iTime(m_symbol, m_timeframe, i);
         fvg.touchCount = 0;
         fvg.isValid = true;
         fvg.isBullish = true;
         fvg.strength = (int)MathMin(10, XAU_PriceToPips(low3 - high1));

         if(count < m_maxZones)
         {
            ArrayResize(m_fvgZones, count + 1);
            m_fvgZones[count] = fvg;
            count++;
         }
      }

      if(high3 < low1 && close2 < open2)
      {
         SMCZone fvg;
         fvg.priceLow = high3;
         fvg.priceHigh = low1;
         fvg.timeCreated = iTime(m_symbol, m_timeframe, i);
         fvg.touchCount = 0;
         fvg.isValid = true;
         fvg.isBullish = false;
         fvg.strength = (int)MathMin(10, XAU_PriceToPips(low1 - high3));

         if(count < m_maxZones)
         {
            ArrayResize(m_fvgZones, count + 1);
            m_fvgZones[count] = fvg;
            count++;
         }
      }
   }
}

bool CSMCAnalysis::IsPriceInFVG(double price, bool &isBullish)
{
   for(int i = 0; i < ArraySize(m_fvgZones); i++)
   {
      if(!m_fvgZones[i].isValid) continue;
      if(price >= m_fvgZones[i].priceLow && price <= m_fvgZones[i].priceHigh)
      {
         isBullish = m_fvgZones[i].isBullish;
         return true;
      }
   }
   return false;
}

void CSMCAnalysis::ConsumeFVG(double price)
{
   for(int i = 0; i < ArraySize(m_fvgZones); i++)
   {
      if(!m_fvgZones[i].isValid) continue;
      if(price >= m_fvgZones[i].priceLow && price <= m_fvgZones[i].priceHigh)
      {
         m_fvgZones[i].isValid = false;
         return;
      }
   }
}


void CSMCAnalysis::DetectLiquidityPools()
{
   ArrayResize(m_liquidityPools, 0);
   int count = 0;
   double tolerance = XAU_PipsToPrice(5.0);

   for(int i = 0; i < ArraySize(m_swingPoints) - 1; i++)
   {
      if(!m_swingPoints[i].isHigh) continue;
      for(int j = i + 1; j < ArraySize(m_swingPoints); j++)
      {
         if(!m_swingPoints[j].isHigh) continue;
         if(MathAbs(m_swingPoints[i].price - m_swingPoints[j].price) <= tolerance)
         {
            SMCZone lp;
            lp.priceHigh = MathMax(m_swingPoints[i].price, m_swingPoints[j].price) + tolerance;
            lp.priceLow = MathMin(m_swingPoints[i].price, m_swingPoints[j].price) - tolerance;
            lp.timeCreated = m_swingPoints[j].time;
            lp.touchCount = 2;
            lp.isValid = true;
            lp.isBullish = false;
            lp.strength = 5;
            if(count < m_maxZones)
            {
               ArrayResize(m_liquidityPools, count + 1);
               m_liquidityPools[count] = lp;
               count++;
            }
            break;
         }
      }
   }

   for(int i = 0; i < ArraySize(m_swingPoints) - 1; i++)
   {
      if(m_swingPoints[i].isHigh) continue;
      for(int j = i + 1; j < ArraySize(m_swingPoints); j++)
      {
         if(m_swingPoints[j].isHigh) continue;
         if(MathAbs(m_swingPoints[i].price - m_swingPoints[j].price) <= tolerance)
         {
            SMCZone lp;
            lp.priceHigh = MathMax(m_swingPoints[i].price, m_swingPoints[j].price) + tolerance;
            lp.priceLow = MathMin(m_swingPoints[i].price, m_swingPoints[j].price) - tolerance;
            lp.timeCreated = m_swingPoints[j].time;
            lp.touchCount = 2;
            lp.isValid = true;
            lp.isBullish = true;
            lp.strength = 5;
            if(count < m_maxZones)
            {
               ArrayResize(m_liquidityPools, count + 1);
               m_liquidityPools[count] = lp;
               count++;
            }
            break;
         }
      }
   }
}

bool CSMCAnalysis::IsLiquiditySweep(double price)
{
   double currentHigh = iHigh(m_symbol, m_timeframe, 0);
   double currentLow  = iLow(m_symbol, m_timeframe, 0);

   for(int i = 0; i < ArraySize(m_liquidityPools); i++)
   {
      if(!m_liquidityPools[i].isValid) continue;
      if(!m_liquidityPools[i].isBullish)
      {
         if(currentHigh > m_liquidityPools[i].priceHigh && price < m_liquidityPools[i].priceLow)
            return true;
      }
      else
      {
         if(currentLow < m_liquidityPools[i].priceLow && price > m_liquidityPools[i].priceHigh)
            return true;
      }
   }
   return false;
}

void CSMCAnalysis::ConsumeLiquiditySweep(double price)
{
   double currentHigh = iHigh(m_symbol, m_timeframe, 0);
   double currentLow  = iLow(m_symbol, m_timeframe, 0);

   for(int i = 0; i < ArraySize(m_liquidityPools); i++)
   {
      if(!m_liquidityPools[i].isValid) continue;
      if(!m_liquidityPools[i].isBullish)
      {
         if(currentHigh > m_liquidityPools[i].priceHigh && price < m_liquidityPools[i].priceLow)
         {
            m_liquidityPools[i].isValid = false;
            return;
         }
      }
      else
      {
         if(currentLow < m_liquidityPools[i].priceLow && price > m_liquidityPools[i].priceHigh)
         {
            m_liquidityPools[i].isValid = false;
            return;
         }
      }
   }
}

bool CSMCAnalysis::DetectBOS()
{
   double currentClose = iClose(m_symbol, m_timeframe, 0);
   if(m_lastSwingHigh == 0 || m_lastSwingLow == 0) return false;

   if(m_isBullishStructure && currentClose > m_lastSwingHigh)
   {
      m_bosDetected = true;
      XAU_LogDebug("Bullish BOS detected - price broke above " + DoubleToString(m_lastSwingHigh, 2));
      return true;
   }

   if(!m_isBullishStructure && currentClose < m_lastSwingLow)
   {
      m_bosDetected = true;
      XAU_LogDebug("Bearish BOS detected - price broke below " + DoubleToString(m_lastSwingLow, 2));
      return true;
   }

   return false;
}

bool CSMCAnalysis::DetectCHoCH()
{
   double currentClose = iClose(m_symbol, m_timeframe, 0);
   if(m_lastSwingHigh == 0 || m_lastSwingLow == 0) return false;

   if(!m_isBullishStructure && currentClose > m_lastSwingHigh)
   {
      m_chochDetected = true;
      m_isBullishStructure = true;
      XAU_LogDebug("Bullish CHoCH detected - structure shift to bullish");
      return true;
   }

   if(m_isBullishStructure && currentClose < m_lastSwingLow)
   {
      m_chochDetected = true;
      m_isBullishStructure = false;
      XAU_LogDebug("Bearish CHoCH detected - structure shift to bearish");
      return true;
   }

   return false;
}

bool CSMCAnalysis::IsInPremiumZone(double price)
{
   double equilibrium = GetEquilibriumPrice();
   return (price > equilibrium);
}

bool CSMCAnalysis::IsInDiscountZone(double price)
{
   double equilibrium = GetEquilibriumPrice();
   return (price < equilibrium);
}

double CSMCAnalysis::GetEquilibriumPrice()
{
   double rangeHigh = GetRangeHigh(m_lookbackBars);
   double rangeLow  = GetRangeLow(m_lookbackBars);
   return (rangeHigh + rangeLow) / 2.0;
}


//+------------------------------------------------------------------+
//| CSignalEngine - Multi-factor signal generation                   |
//+------------------------------------------------------------------+
class CSignalEngine
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_lowerTF;
   ENUM_TIMEFRAMES   m_higherTF;
   int               m_emaFastPeriod;
   int               m_emaSlowPeriod;
   int               m_rsiPeriod;
   double            m_rsiOverbought;
   double            m_rsiOversold;
   int               m_hEmaFastLower;
   int               m_hEmaSlowLower;
   int               m_hEmaFastHigher;
   int               m_hEmaSlowHigher;
   int               m_hRsi;
   CSMCAnalysis*     m_smcAnalysis;
   int               m_weightEMA;
   int               m_weightRSI;
   int               m_weightSMC;
   bool              m_initialized;

   int               GetEMAScore();
   int               GetRSIScore();
   int               GetSMCScore();
   bool              CheckEMACrossover(ENUM_TIMEFRAMES tf, int handleFast, int handleSlow);
   bool              DetectRSIDivergence(bool bullish);

public:
                     CSignalEngine();
                    ~CSignalEngine();

   bool              Init(string symbol, ENUM_TIMEFRAMES lowerTF, ENUM_TIMEFRAMES higherTF,
                          int emaFast = 50, int emaSlow = 200,
                          int rsiPeriod = 14, double rsiOB = 70.0, double rsiOS = 30.0);
   void              SetSMCAnalysis(CSMCAnalysis *smc) { m_smcAnalysis = smc; }
   void              SetWeights(int emaW, int rsiW, int smcW);
   SignalResult      GenerateSignal();
   ENUM_SIGNAL_TYPE  GetEMATrend();
   bool              IsRSIOverbought();
   bool              IsRSIOversold();
   double            GetRSIValue();
   bool              HasEMACrossoverUp();
   bool              HasEMACrossoverDown();
   void              Deinit();
};

CSignalEngine::CSignalEngine()
{
   m_symbol = "";
   m_lowerTF = PERIOD_M5;
   m_higherTF = PERIOD_H1;
   m_emaFastPeriod = 50;
   m_emaSlowPeriod = 200;
   m_rsiPeriod = 14;
   m_rsiOverbought = 70.0;
   m_rsiOversold = 30.0;
   m_hEmaFastLower = INVALID_HANDLE;
   m_hEmaSlowLower = INVALID_HANDLE;
   m_hEmaFastHigher = INVALID_HANDLE;
   m_hEmaSlowHigher = INVALID_HANDLE;
   m_hRsi = INVALID_HANDLE;
   m_smcAnalysis = NULL;
   m_weightEMA = 40;
   m_weightRSI = 25;
   m_weightSMC = 35;
   m_initialized = false;
}

CSignalEngine::~CSignalEngine()
{
   Deinit();
}

bool CSignalEngine::Init(string symbol, ENUM_TIMEFRAMES lowerTF, ENUM_TIMEFRAMES higherTF,
                          int emaFast, int emaSlow, int rsiPeriod, double rsiOB, double rsiOS)
{
   m_symbol = symbol;
   m_lowerTF = lowerTF;
   m_higherTF = higherTF;
   m_emaFastPeriod = emaFast;
   m_emaSlowPeriod = emaSlow;
   m_rsiPeriod = rsiPeriod;
   m_rsiOverbought = rsiOB;
   m_rsiOversold = rsiOS;

   m_hEmaFastLower = iMA(m_symbol, m_lowerTF, m_emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_hEmaSlowLower = iMA(m_symbol, m_lowerTF, m_emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_hEmaFastHigher = iMA(m_symbol, m_higherTF, m_emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_hEmaSlowHigher = iMA(m_symbol, m_higherTF, m_emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_hRsi = iRSI(m_symbol, m_lowerTF, m_rsiPeriod, PRICE_CLOSE);

   if(m_hEmaFastLower == INVALID_HANDLE || m_hEmaSlowLower == INVALID_HANDLE ||
      m_hEmaFastHigher == INVALID_HANDLE || m_hEmaSlowHigher == INVALID_HANDLE ||
      m_hRsi == INVALID_HANDLE)
   {
      XAU_LogError("SignalEngine: Failed to create indicator handles. Error: " + IntegerToString(GetLastError()));
      return false;
   }

   m_initialized = true;
   XAU_LogInfo("SignalEngine initialized: " + symbol + " LTF=" + EnumToString(lowerTF) + " HTF=" + EnumToString(higherTF));
   return true;
}

void CSignalEngine::SetWeights(int emaW, int rsiW, int smcW)
{
   m_weightEMA = emaW;
   m_weightRSI = rsiW;
   m_weightSMC = smcW;
}

void CSignalEngine::Deinit()
{
   if(m_hEmaFastLower != INVALID_HANDLE)  { IndicatorRelease(m_hEmaFastLower);  m_hEmaFastLower = INVALID_HANDLE; }
   if(m_hEmaSlowLower != INVALID_HANDLE)  { IndicatorRelease(m_hEmaSlowLower);  m_hEmaSlowLower = INVALID_HANDLE; }
   if(m_hEmaFastHigher != INVALID_HANDLE) { IndicatorRelease(m_hEmaFastHigher); m_hEmaFastHigher = INVALID_HANDLE; }
   if(m_hEmaSlowHigher != INVALID_HANDLE) { IndicatorRelease(m_hEmaSlowHigher); m_hEmaSlowHigher = INVALID_HANDLE; }
   if(m_hRsi != INVALID_HANDLE)           { IndicatorRelease(m_hRsi);           m_hRsi = INVALID_HANDLE; }
   m_initialized = false;
}

int CSignalEngine::GetEMAScore()
{
   if(!m_initialized) return 0;

   double emaFastH[2], emaSlowH[2];
   double emaFastL[2], emaSlowL[2];

   if(CopyBuffer(m_hEmaFastHigher, 0, 0, 2, emaFastH) < 2) return 0;
   if(CopyBuffer(m_hEmaSlowHigher, 0, 0, 2, emaSlowH) < 2) return 0;
   if(CopyBuffer(m_hEmaFastLower, 0, 0, 2, emaFastL) < 2) return 0;
   if(CopyBuffer(m_hEmaSlowLower, 0, 0, 2, emaSlowL) < 2) return 0;

   double price = iClose(m_symbol, m_lowerTF, 0);
   int score = 0;

   if(emaFastH[0] > emaSlowH[0] && price > emaFastH[0])
      score += 40;
   else if(emaFastH[0] > emaSlowH[0])
      score += 20;
   else if(emaFastH[0] < emaSlowH[0] && price < emaFastH[0])
      score -= 40;
   else if(emaFastH[0] < emaSlowH[0])
      score -= 20;

   if(emaFastL[0] > emaSlowL[0] && price > emaFastL[0])
      score += 40;
   else if(emaFastL[0] > emaSlowL[0])
      score += 20;
   else if(emaFastL[0] < emaSlowL[0] && price < emaFastL[0])
      score -= 40;
   else if(emaFastL[0] < emaSlowL[0])
      score -= 20;

   if(emaFastL[1] <= emaSlowL[1] && emaFastL[0] > emaSlowL[0])
      score += 20;
   else if(emaFastL[1] >= emaSlowL[1] && emaFastL[0] < emaSlowL[0])
      score -= 20;

   return MathMax(-100, MathMin(100, score));
}

int CSignalEngine::GetRSIScore()
{
   if(!m_initialized) return 0;

   double rsi[3];
   if(CopyBuffer(m_hRsi, 0, 0, 3, rsi) < 3) return 0;

   int score = 0;

   if(rsi[0] < m_rsiOversold)
      score += 60;
   else if(rsi[0] < 40)
      score += 30;

   if(rsi[0] > m_rsiOverbought)
      score -= 60;
   else if(rsi[0] > 60)
      score -= 30;

   if(rsi[0] > rsi[1] && rsi[1] > rsi[2])
      score += 20;
   else if(rsi[0] < rsi[1] && rsi[1] < rsi[2])
      score -= 20;

   if(DetectRSIDivergence(true))
      score += 20;
   if(DetectRSIDivergence(false))
      score -= 20;

   return MathMax(-100, MathMin(100, score));
}


int CSignalEngine::GetSMCScore()
{
   if(m_smcAnalysis == NULL) return 0;

   double price = iClose(m_symbol, m_lowerTF, 0);
   int score = 0;
   bool isBullish = false;

   if(m_smcAnalysis.IsPriceAtOrderBlock(price, isBullish))
      score += isBullish ? 40 : -40;

   if(m_smcAnalysis.IsPriceInFVG(price, isBullish))
      score += isBullish ? 30 : -30;

   if(m_smcAnalysis.IsLiquiditySweep(price))
   {
      if(m_smcAnalysis.IsBullishStructure())
         score += 30;
      else
         score -= 30;
   }

   if(m_smcAnalysis.HasBOS())
      score += m_smcAnalysis.IsBullishStructure() ? 20 : -20;
   if(m_smcAnalysis.HasCHoCH())
      score += m_smcAnalysis.IsBullishStructure() ? 25 : -25;

   if(m_smcAnalysis.IsInDiscountZone(price))
      score += 10;
   else if(m_smcAnalysis.IsInPremiumZone(price))
      score -= 10;

   return MathMax(-100, MathMin(100, score));
}

bool CSignalEngine::DetectRSIDivergence(bool bullish)
{
   if(!m_initialized) return false;

   double rsi[20];
   if(CopyBuffer(m_hRsi, 0, 0, 20, rsi) < 20) return false;

   int swingStrength = 2;

   if(bullish)
   {
      double swingLow1Price = 0, swingLow2Price = 0;
      double swingLow1RSI = 0, swingLow2RSI = 0;
      int found = 0;

      for(int i = swingStrength; i < 18 - swingStrength && found < 2; i++)
      {
         double low = iLow(m_symbol, m_lowerTF, i);
         bool isSwing = true;

         for(int j = 1; j <= swingStrength; j++)
         {
            if(iLow(m_symbol, m_lowerTF, i - j) <= low) { isSwing = false; break; }
            if(iLow(m_symbol, m_lowerTF, i + j) <= low) { isSwing = false; break; }
         }

         if(isSwing)
         {
            if(found == 0)
            {
               swingLow1Price = low;
               swingLow1RSI = rsi[i];
            }
            else
            {
               swingLow2Price = low;
               swingLow2RSI = rsi[i];
            }
            found++;
         }
      }

      if(found < 2) return false;
      if(swingLow1Price < swingLow2Price && swingLow1RSI > swingLow2RSI)
         return true;
   }
   else
   {
      double swingHigh1Price = 0, swingHigh2Price = 0;
      double swingHigh1RSI = 0, swingHigh2RSI = 0;
      int found = 0;

      for(int i = swingStrength; i < 18 - swingStrength && found < 2; i++)
      {
         double high = iHigh(m_symbol, m_lowerTF, i);
         bool isSwing = true;

         for(int j = 1; j <= swingStrength; j++)
         {
            if(iHigh(m_symbol, m_lowerTF, i - j) >= high) { isSwing = false; break; }
            if(iHigh(m_symbol, m_lowerTF, i + j) >= high) { isSwing = false; break; }
         }

         if(isSwing)
         {
            if(found == 0)
            {
               swingHigh1Price = high;
               swingHigh1RSI = rsi[i];
            }
            else
            {
               swingHigh2Price = high;
               swingHigh2RSI = rsi[i];
            }
            found++;
         }
      }

      if(found < 2) return false;
      if(swingHigh1Price > swingHigh2Price && swingHigh1RSI < swingHigh2RSI)
         return true;
   }

   return false;
}

bool CSignalEngine::CheckEMACrossover(ENUM_TIMEFRAMES tf, int handleFast, int handleSlow)
{
   double fast[2], slow[2];
   if(CopyBuffer(handleFast, 0, 0, 2, fast) < 2) return false;
   if(CopyBuffer(handleSlow, 0, 0, 2, slow) < 2) return false;
   return (fast[1] <= slow[1] && fast[0] > slow[0]);
}

SignalResult CSignalEngine::GenerateSignal()
{
   SignalResult result;
   result.signal = SIGNAL_NONE;
   result.strength = 0;
   result.emaConfirmed = false;
   result.rsiConfirmed = false;
   result.smcConfirmed = false;
   result.reason = "No signal";
   result.suggestedSL = 0;
   result.suggestedTP = 0;

   if(!m_initialized) return result;

   int emaScore = GetEMAScore();
   int rsiScore = GetRSIScore();
   int smcScore = GetSMCScore();

   double totalWeight = m_weightEMA + m_weightRSI + m_weightSMC;
   if(totalWeight <= 0)
   {
      result.reason = "All signal weights are zero - cannot generate signal";
      return result;
   }
   double compositeScore = (emaScore * m_weightEMA + rsiScore * m_weightRSI + smcScore * m_weightSMC) / totalWeight;

   result.strength = (int)MathAbs(compositeScore);
   result.emaConfirmed = (MathAbs(emaScore) > 40);
   result.rsiConfirmed = (MathAbs(rsiScore) > 30);
   result.smcConfirmed = (MathAbs(smcScore) > 30);

   int minStrength = 30;

   if(compositeScore >= minStrength)
   {
      result.signal = SIGNAL_BUY;
      result.reason = StringFormat("BUY: EMA=%d RSI=%d SMC=%d Composite=%.0f",
                                    emaScore, rsiScore, smcScore, compositeScore);
   }
   else if(compositeScore <= -minStrength)
   {
      result.signal = SIGNAL_SELL;
      result.reason = StringFormat("SELL: EMA=%d RSI=%d SMC=%d Composite=%.0f",
                                    emaScore, rsiScore, smcScore, compositeScore);
   }
   else
   {
      result.reason = StringFormat("NO SIGNAL: EMA=%d RSI=%d SMC=%d Composite=%.0f (threshold=%d)",
                                    emaScore, rsiScore, smcScore, compositeScore, minStrength);
   }

   if(result.signal != SIGNAL_NONE && m_smcAnalysis != NULL)
   {
      double price = iClose(m_symbol, m_lowerTF, 0);
      bool isBuy = (result.signal == SIGNAL_BUY);

      double obHigh = 0, obLow = 0;
      if(m_smcAnalysis.GetNearestOrderBlock(price, isBuy, obHigh, obLow))
      {
         if(isBuy)
            result.suggestedSL = obLow;
         else
            result.suggestedSL = obHigh;
      }

      if(isBuy)
      {
         double swingHigh = m_smcAnalysis.GetLastSwingHigh();
         if(swingHigh > price)
            result.suggestedTP = swingHigh;
      }
      else
      {
         double swingLow = m_smcAnalysis.GetLastSwingLow();
         if(swingLow > 0 && swingLow < price)
            result.suggestedTP = swingLow;
      }
   }

   return result;
}

ENUM_SIGNAL_TYPE CSignalEngine::GetEMATrend()
{
   int score = GetEMAScore();
   if(score > 40) return SIGNAL_BUY;
   if(score < -40) return SIGNAL_SELL;
   return SIGNAL_NONE;
}

bool CSignalEngine::IsRSIOverbought()
{
   double rsi[1];
   if(CopyBuffer(m_hRsi, 0, 0, 1, rsi) < 1) return false;
   return (rsi[0] > m_rsiOverbought);
}

bool CSignalEngine::IsRSIOversold()
{
   double rsi[1];
   if(CopyBuffer(m_hRsi, 0, 0, 1, rsi) < 1) return false;
   return (rsi[0] < m_rsiOversold);
}

double CSignalEngine::GetRSIValue()
{
   double rsi[1];
   if(CopyBuffer(m_hRsi, 0, 0, 1, rsi) < 1) return 50.0;
   return rsi[0];
}

bool CSignalEngine::HasEMACrossoverUp()
{
   return CheckEMACrossover(m_lowerTF, m_hEmaFastLower, m_hEmaSlowLower);
}

bool CSignalEngine::HasEMACrossoverDown()
{
   double fast[2], slow[2];
   if(CopyBuffer(m_hEmaFastLower, 0, 0, 2, fast) < 2) return false;
   if(CopyBuffer(m_hEmaSlowLower, 0, 0, 2, slow) < 2) return false;
   return (fast[1] >= slow[1] && fast[0] < slow[0]);
}


//+------------------------------------------------------------------+
//| CRiskManager - Comprehensive risk and money management           |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   double            m_riskPercent;
   double            m_maxDrawdownPercent;
   double            m_dailyLossLimit;
   double            m_minBalance;
   int               m_maxConsecLosses;
   double            m_lotReductionFactor;
   double            m_minRiskReward;
   bool              m_useKellyCriterion;
   bool              m_useEquityCurve;

   double            m_startingBalance;
   double            m_peakBalance;
   int               m_consecutiveLosses;
   double            m_dailyPnL;
   datetime          m_lastDayReset;
   double            m_equityHistory[];
   int               m_equityHistorySize;
   int               m_equityHistoryIdx;
   int               m_equityHistoryFill;
   int               m_equityMAPeriod;
   bool              m_tradingPaused;
   string            m_pauseReason;

   int               m_totalTrades;
   int               m_winningTrades;
   double            m_avgWin;
   double            m_avgLoss;

   ENUM_ACCOUNT_TIER GetAccountTier();
   double            GetTierMaxLot(ENUM_ACCOUNT_TIER tier);
   double            CalculateKellyFraction();
   double            GetEquityMA();
   void              UpdateEquityHistory();
   void              CheckDailyReset();

public:
                     CRiskManager();
                    ~CRiskManager();

   bool              Init(double riskPercent, double maxDD, double dailyLimit,
                          double minBal, int maxConsecLoss = 3, double lotReduction = 0.5);
   void              SetKellyCriterion(bool enable) { m_useKellyCriterion = enable; }
   void              SetEquityCurveTrading(bool enable, int maPeriod = 20);
   void              SetMinRiskReward(double rr) { m_minRiskReward = rr; }

   double            CalculateLotSize(double slPips);
   double            CalculateLotSizeFixed(double lots);

   bool              CanTrade();
   bool              CheckDrawdown();
   bool              CheckDailyLoss();
   bool              CheckConsecutiveLosses();
   bool              CheckMinBalance();
   bool              CheckEquityCurve();
   bool              ValidateRiskReward(double slPips, double tpPips);

   void              RecordWin(double profit);
   void              RecordLoss(double loss);
   void              ResetDailyCounters();

   double            GetCurrentDrawdown();
   double            GetDailyPnL() { return m_dailyPnL; }
   int               GetConsecutiveLosses() { return m_consecutiveLosses; }
   bool              IsTradingPaused() { return m_tradingPaused; }
   string            GetPauseReason() { return m_pauseReason; }
   double            GetRiskPercent() { return m_riskPercent; }
   ENUM_ACCOUNT_TIER GetTier() { return GetAccountTier(); }

   void              Update();
};

CRiskManager::CRiskManager()
{
   m_riskPercent = 1.0;
   m_maxDrawdownPercent = 10.0;
   m_dailyLossLimit = 3.0;
   m_minBalance = 80.0;
   m_maxConsecLosses = 3;
   m_lotReductionFactor = 0.5;
   m_minRiskReward = 1.5;
   m_useKellyCriterion = false;
   m_useEquityCurve = false;
   m_startingBalance = 0;
   m_peakBalance = 0;
   m_consecutiveLosses = 0;
   m_dailyPnL = 0;
   m_lastDayReset = 0;
   m_equityHistorySize = 100;
   m_equityHistoryIdx = 0;
   m_equityHistoryFill = 0;
   m_equityMAPeriod = 20;
   m_tradingPaused = false;
   m_pauseReason = "";
   m_totalTrades = 0;
   m_winningTrades = 0;
   m_avgWin = 0;
   m_avgLoss = 0;
}

CRiskManager::~CRiskManager()
{
   ArrayFree(m_equityHistory);
}

bool CRiskManager::Init(double riskPercent, double maxDD, double dailyLimit,
                         double minBal, int maxConsecLoss, double lotReduction)
{
   m_riskPercent = riskPercent;
   m_maxDrawdownPercent = maxDD;
   m_dailyLossLimit = dailyLimit;
   m_minBalance = minBal;
   m_maxConsecLosses = maxConsecLoss;
   m_lotReductionFactor = lotReduction;

   m_startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   m_peakBalance = m_startingBalance;
   m_lastDayReset = TimeCurrent();

   ArrayResize(m_equityHistory, m_equityHistorySize);
   ArrayInitialize(m_equityHistory, m_startingBalance);
   m_equityHistoryIdx = 0;
   m_equityHistoryFill = 0;

   XAU_LogInfo(StringFormat("RiskManager initialized: Risk=%.1f%% MaxDD=%.1f%% DailyLimit=%.1f%% MinBal=%.0f",
           m_riskPercent, m_maxDrawdownPercent, m_dailyLossLimit, m_minBalance));
   return true;
}

void CRiskManager::SetEquityCurveTrading(bool enable, int maPeriod)
{
   m_useEquityCurve = enable;
   m_equityMAPeriod = maPeriod;
}

double CRiskManager::CalculateLotSize(double slPips)
{
   if(slPips <= 0) return 0;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (m_riskPercent / 100.0);

   if(m_useKellyCriterion && m_totalTrades > 20)
   {
      double kellyFraction = CalculateKellyFraction();
      if(kellyFraction > 0 && kellyFraction < m_riskPercent / 100.0)
         riskAmount = balance * kellyFraction;
   }

   double pipValue = XAU_GetPipValue(1.0);
   if(pipValue <= 0) return 0;

   double lots = riskAmount / (slPips * pipValue);

   if(m_consecutiveLosses >= m_maxConsecLosses)
   {
      lots *= m_lotReductionFactor;
      XAU_LogWarning(StringFormat("Lot reduced due to %d consecutive losses: %.2f -> %.2f",
                 m_consecutiveLosses, lots / m_lotReductionFactor, lots));
   }

   ENUM_ACCOUNT_TIER tier = GetAccountTier();
   double maxLot = GetTierMaxLot(tier);
   lots = MathMin(lots, maxLot);

   return XAU_NormalizeLot(lots);
}

double CRiskManager::CalculateLotSizeFixed(double lots)
{
   return XAU_NormalizeLot(lots);
}

bool CRiskManager::CanTrade()
{
   CheckDailyReset();
   m_tradingPaused = false;
   m_pauseReason = "";

   if(!CheckMinBalance())
   {
      m_tradingPaused = true;
      m_pauseReason = "Balance below minimum threshold";
      return false;
   }

   if(!CheckDrawdown())
   {
      m_tradingPaused = true;
      m_pauseReason = StringFormat("Drawdown exceeded: %.1f%%", GetCurrentDrawdown());
      return false;
   }

   if(!CheckDailyLoss())
   {
      m_tradingPaused = true;
      m_pauseReason = StringFormat("Daily loss limit reached: %.2f", m_dailyPnL);
      return false;
   }

   if(m_useEquityCurve && !CheckEquityCurve())
   {
      m_tradingPaused = true;
      m_pauseReason = "Equity below moving average";
      return false;
   }

   return true;
}

bool CRiskManager::CheckDrawdown()
{
   double dd = GetCurrentDrawdown();
   return (dd < m_maxDrawdownPercent);
}

bool CRiskManager::CheckDailyLoss()
{
   double dailyLossPercent = 0;
   if(m_startingBalance > 0)
      dailyLossPercent = (MathAbs(m_dailyPnL) / m_startingBalance) * 100.0;
   return (m_dailyPnL >= 0 || dailyLossPercent < m_dailyLossLimit);
}

bool CRiskManager::CheckConsecutiveLosses()
{
   return true;
}

bool CRiskManager::CheckMinBalance()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   return (balance >= m_minBalance);
}

bool CRiskManager::CheckEquityCurve()
{
   if(!m_useEquityCurve) return true;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double equityMA = GetEquityMA();
   return (equity >= equityMA);
}

bool CRiskManager::ValidateRiskReward(double slPips, double tpPips)
{
   if(slPips <= 0) return false;
   double rr = tpPips / slPips;
   return (rr >= m_minRiskReward);
}

void CRiskManager::RecordWin(double profit)
{
   m_consecutiveLosses = 0;
   m_dailyPnL += profit;
   m_totalTrades++;
   m_winningTrades++;
   m_avgWin = ((m_avgWin * (m_winningTrades - 1)) + profit) / m_winningTrades;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > m_peakBalance) m_peakBalance = balance;

   XAU_LogDebug(StringFormat("Win recorded: +%.2f | Daily P&L: %.2f | Consec losses: 0", profit, m_dailyPnL));
}

void CRiskManager::RecordLoss(double loss)
{
   m_consecutiveLosses++;
   m_dailyPnL += loss;
   m_totalTrades++;
   int losingTrades = m_totalTrades - m_winningTrades;
   m_avgLoss = ((m_avgLoss * (losingTrades - 1)) + MathAbs(loss)) / losingTrades;

   XAU_LogDebug(StringFormat("Loss recorded: %.2f | Daily P&L: %.2f | Consec losses: %d",
            loss, m_dailyPnL, m_consecutiveLosses));
}

double CRiskManager::GetCurrentDrawdown()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > m_peakBalance) m_peakBalance = balance;
   if(m_peakBalance == 0) return 0;
   return ((m_peakBalance - balance) / m_peakBalance) * 100.0;
}

ENUM_ACCOUNT_TIER CRiskManager::GetAccountTier()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance >= 10000) return TIER_STANDARD;
   if(balance >= 1000) return TIER_MINI;
   return TIER_MICRO;
}

double CRiskManager::GetTierMaxLot(ENUM_ACCOUNT_TIER tier)
{
   switch(tier)
   {
      case TIER_MICRO:    return 0.10;
      case TIER_MINI:     return 1.00;
      case TIER_STANDARD: return 10.00;
   }
   return 0.01;
}

double CRiskManager::CalculateKellyFraction()
{
   if(m_totalTrades < 20 || m_avgLoss == 0) return m_riskPercent / 100.0;

   double winRate = (double)m_winningTrades / m_totalTrades;
   double winLossRatio = m_avgWin / m_avgLoss;
   double kelly = (winRate * winLossRatio - (1.0 - winRate)) / winLossRatio;
   kelly *= 0.5;
   return MathMax(0, MathMin(kelly, m_riskPercent / 100.0));
}

double CRiskManager::GetEquityMA()
{
   if(m_equityHistoryFill < m_equityMAPeriod) return 0;

   double sum = 0;
   for(int i = 0; i < m_equityMAPeriod; i++)
   {
      int idx = (m_equityHistoryIdx - 1 - i + m_equityHistorySize) % m_equityHistorySize;
      sum += m_equityHistory[idx];
   }
   return sum / m_equityMAPeriod;
}

void CRiskManager::UpdateEquityHistory()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   m_equityHistory[m_equityHistoryIdx] = equity;
   m_equityHistoryIdx = (m_equityHistoryIdx + 1) % m_equityHistorySize;
   if(m_equityHistoryFill < m_equityHistorySize)
      m_equityHistoryFill++;
}

void CRiskManager::CheckDailyReset()
{
   MqlDateTime now, last;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(m_lastDayReset, last);

   if(now.day != last.day)
   {
      ResetDailyCounters();
      m_lastDayReset = TimeCurrent();
   }
}

void CRiskManager::ResetDailyCounters()
{
   m_dailyPnL = 0;
   m_startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   XAU_LogInfo("Daily counters reset. Starting balance: " + DoubleToString(m_startingBalance, 2));
}

void CRiskManager::Update()
{
   CheckDailyReset();
   UpdateEquityHistory();
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > m_peakBalance) m_peakBalance = balance;
}


//+------------------------------------------------------------------+
//| CTradeManager - Handles all order execution and position mgmt    |
//+------------------------------------------------------------------+
class CTradeManager
{
private:
   CTrade            m_trade;
   CPositionInfo     m_position;
   CSymbolInfo       m_symbolInfo;

   string            m_symbol;
   long              m_magicNumber;
   string            m_comment;
   double            m_maxSpreadPips;
   int               m_maxSlippage;
   int               m_maxPositions;
   int               m_cooldownSeconds;
   double            m_breakEvenPips;
   double            m_breakEvenOffset;
   double            m_partialClosePercent;
   double            m_partialClosePips;

   bool              m_tradeLondon;
   bool              m_tradeNewYork;
   bool              m_tradeAsian;
   bool              m_tradeOverlap;
   int               m_customStartHour;
   int               m_customEndHour;
   bool              m_useCustomHours;

   datetime          m_lastTradeTime;
   ulong             m_partialClosedTickets[];
   int               m_partialClosedCount;

public:
                     CTradeManager();
                    ~CTradeManager();

   bool              Init(string symbol, long magic, string comment,
                          double maxSpread = 50.0, int maxSlip = 30, int maxPos = 3);
   void              SetBreakEven(double triggerPips, double offsetPips);
   void              SetPartialClose(double percent, double triggerPips);
   void              SetCooldown(int seconds) { m_cooldownSeconds = seconds; }
   void              SetSessionFilter(bool london, bool ny, bool asian, bool overlap);
   void              SetCustomHours(int startHour, int endHour);

   bool              IsSpreadOK();
   bool              IsWithinMaxPositions();
   bool              IsCooldownExpired();
   bool              IsSessionAllowed();

   bool              OpenBuy(double lots, double sl, double tp, string comment = "");
   bool              OpenSell(double lots, double sl, double tp, string comment = "");
   bool              ModifyPosition(ulong ticket, double sl, double tp);
   bool              ClosePosition(ulong ticket);
   bool              CloseAllPositions();
   bool              PartialClose(ulong ticket, double percent);

   void              ManageBreakEven();
   void              ManagePartialClose();
   int               CountOpenPositions();
   double            GetTotalProfit();
   double            GetPositionProfit(ulong ticket);

   double            GetCurrentSpreadPips();
   ulong             GetLastTicket();
   bool              HasOpenPosition();
   void              GetOpenTickets(ulong &tickets[], int &count);
};

CTradeManager::CTradeManager()
{
   m_symbol = "";
   m_magicNumber = 0;
   m_comment = "";
   m_maxSpreadPips = 50.0;
   m_maxSlippage = 30;
   m_maxPositions = 3;
   m_cooldownSeconds = 300;
   m_breakEvenPips = 30.0;
   m_breakEvenOffset = 2.0;
   m_partialClosePercent = 50.0;
   m_partialClosePips = 50.0;
   m_tradeLondon = true;
   m_tradeNewYork = true;
   m_tradeAsian = false;
   m_tradeOverlap = true;
   m_customStartHour = 0;
   m_customEndHour = 24;
   m_useCustomHours = false;
   m_lastTradeTime = 0;
   m_partialClosedCount = 0;
}

CTradeManager::~CTradeManager()
{
   ArrayFree(m_partialClosedTickets);
}

bool CTradeManager::Init(string symbol, long magic, string comment,
                          double maxSpread, int maxSlip, int maxPos)
{
   m_symbol = symbol;
   m_magicNumber = magic;
   m_comment = comment;
   m_maxSpreadPips = maxSpread;
   m_maxSlippage = maxSlip;
   m_maxPositions = maxPos;

   m_trade.SetExpertMagicNumber(magic);
   m_trade.SetDeviationInPoints(maxSlip);
   m_trade.SetMarginMode();

   long fillingMode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((fillingMode & SYMBOL_FILLING_FOK) != 0)
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillingMode & SYMBOL_FILLING_IOC) != 0)
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      m_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   if(!m_symbolInfo.Name(symbol))
   {
      XAU_LogError("TradeManager: Failed to set symbol info for " + symbol);
      return false;
   }

   XAU_LogInfo(StringFormat("TradeManager initialized: %s Magic=%d MaxSpread=%.1f MaxSlip=%d MaxPos=%d",
           symbol, magic, maxSpread, maxSlip, maxPos));
   return true;
}

void CTradeManager::SetBreakEven(double triggerPips, double offsetPips)
{
   m_breakEvenPips = triggerPips;
   m_breakEvenOffset = offsetPips;
}

void CTradeManager::SetPartialClose(double percent, double triggerPips)
{
   m_partialClosePercent = percent;
   m_partialClosePips = triggerPips;
}

void CTradeManager::SetSessionFilter(bool london, bool ny, bool asian, bool overlap)
{
   m_tradeLondon = london;
   m_tradeNewYork = ny;
   m_tradeAsian = asian;
   m_tradeOverlap = overlap;
}

void CTradeManager::SetCustomHours(int startHour, int endHour)
{
   m_customStartHour = startHour;
   m_customEndHour = endHour;
   m_useCustomHours = true;
}

bool CTradeManager::IsSpreadOK()
{
   double spreadPips = GetCurrentSpreadPips();
   if(spreadPips > m_maxSpreadPips)
   {
      XAU_LogDebug(StringFormat("Spread too high: %.1f pips (max: %.1f)", spreadPips, m_maxSpreadPips));
      return false;
   }
   return true;
}

bool CTradeManager::IsWithinMaxPositions()
{
   return (CountOpenPositions() < m_maxPositions);
}

bool CTradeManager::IsCooldownExpired()
{
   if(m_lastTradeTime == 0) return true;
   return ((TimeCurrent() - m_lastTradeTime) >= m_cooldownSeconds);
}

bool CTradeManager::IsSessionAllowed()
{
   if(m_useCustomHours)
      return IsWithinHours(m_customStartHour, m_customEndHour);

   ENUM_SESSION_TYPE session = GetCurrentSession();
   switch(session)
   {
      case SESSION_LONDON:   return m_tradeLondon;
      case SESSION_NEWYORK:  return m_tradeNewYork;
      case SESSION_ASIAN:    return m_tradeAsian;
      case SESSION_OVERLAP:  return m_tradeOverlap;
      default:               return false;
   }
}

bool CTradeManager::OpenBuy(double lots, double sl, double tp, string tradeComment)
{
   if(tradeComment == "") tradeComment = m_comment;

   m_symbolInfo.RefreshRates();
   double ask = m_symbolInfo.Ask();

   for(int attempt = 0; attempt < MAX_RETRIES; attempt++)
   {
      if(m_trade.Buy(lots, m_symbol, ask, sl, tp, tradeComment))
      {
         m_lastTradeTime = TimeCurrent();
         XAU_LogInfo(StringFormat("BUY opened: %.2f lots @ %.2f SL=%.2f TP=%.2f",
                 lots, ask, sl, tp));
         return true;
      }

      int error = (int)m_trade.ResultRetcode();
      XAU_LogWarning(StringFormat("BUY attempt %d failed: %d - %s",
                 attempt + 1, error, m_trade.ResultRetcodeDescription()));

      if(error == TRADE_RETCODE_NO_MONEY || error == TRADE_RETCODE_MARKET_CLOSED)
         break;

      Sleep(RETRY_DELAY_MS);
      m_symbolInfo.RefreshRates();
      ask = m_symbolInfo.Ask();
   }

   XAU_LogError("BUY order failed after all retries");
   return false;
}

bool CTradeManager::OpenSell(double lots, double sl, double tp, string tradeComment)
{
   if(tradeComment == "") tradeComment = m_comment;

   m_symbolInfo.RefreshRates();
   double bid = m_symbolInfo.Bid();

   for(int attempt = 0; attempt < MAX_RETRIES; attempt++)
   {
      if(m_trade.Sell(lots, m_symbol, bid, sl, tp, tradeComment))
      {
         m_lastTradeTime = TimeCurrent();
         XAU_LogInfo(StringFormat("SELL opened: %.2f lots @ %.2f SL=%.2f TP=%.2f",
                 lots, bid, sl, tp));
         return true;
      }

      int error = (int)m_trade.ResultRetcode();
      XAU_LogWarning(StringFormat("SELL attempt %d failed: %d - %s",
                 attempt + 1, error, m_trade.ResultRetcodeDescription()));

      if(error == TRADE_RETCODE_NO_MONEY || error == TRADE_RETCODE_MARKET_CLOSED)
         break;

      Sleep(RETRY_DELAY_MS);
      m_symbolInfo.RefreshRates();
      bid = m_symbolInfo.Bid();
   }

   XAU_LogError("SELL order failed after all retries");
   return false;
}

bool CTradeManager::ModifyPosition(ulong ticket, double sl, double tp)
{
   if(!m_trade.PositionModify(ticket, sl, tp))
   {
      XAU_LogWarning(StringFormat("Position modify failed: ticket=%d error=%d",
                 ticket, m_trade.ResultRetcode()));
      return false;
   }
   return true;
}

bool CTradeManager::ClosePosition(ulong ticket)
{
   if(!m_trade.PositionClose(ticket))
   {
      XAU_LogWarning(StringFormat("Position close failed: ticket=%d error=%d",
                 ticket, m_trade.ResultRetcode()));
      return false;
   }
   XAU_LogInfo(StringFormat("Position closed: ticket=%d", ticket));
   return true;
}

bool CTradeManager::CloseAllPositions()
{
   bool allClosed = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Magic() == m_magicNumber && m_position.Symbol() == m_symbol)
         {
            if(!ClosePosition(m_position.Ticket()))
               allClosed = false;
         }
      }
   }
   return allClosed;
}

bool CTradeManager::PartialClose(ulong ticket, double percent)
{
   if(!m_position.SelectByTicket(ticket)) return false;

   double volume = m_position.Volume();
   double closeVolume = XAU_NormalizeLot(volume * (percent / 100.0));

   if(closeVolume < SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN))
      return false;

   if(m_trade.PositionClosePartial(ticket, closeVolume))
   {
      XAU_LogInfo(StringFormat("Partial close: ticket=%d volume=%.2f (%.0f%%)",
              ticket, closeVolume, percent));
      return true;
   }

   XAU_LogWarning(StringFormat("Partial close failed: ticket=%d error=%d",
              ticket, m_trade.ResultRetcode()));
   return false;
}


void CTradeManager::ManageBreakEven()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Magic() != m_magicNumber || m_position.Symbol() != m_symbol) continue;

      double openPrice = m_position.PriceOpen();
      double currentSL = m_position.StopLoss();
      double currentPrice = m_position.PriceCurrent();
      double profitPips = 0;

      if(m_position.PositionType() == POSITION_TYPE_BUY)
      {
         profitPips = XAU_PriceToPips(currentPrice - openPrice);
         double newSL = openPrice + XAU_PipsToPrice(m_breakEvenOffset);
         if(profitPips >= m_breakEvenPips && currentSL < openPrice)
         {
            ModifyPosition(m_position.Ticket(), newSL, m_position.TakeProfit());
            XAU_LogDebug(StringFormat("Break-even set for BUY ticket %d at %.2f",
                     m_position.Ticket(), newSL));
         }
      }
      else if(m_position.PositionType() == POSITION_TYPE_SELL)
      {
         profitPips = XAU_PriceToPips(openPrice - currentPrice);
         double newSL = openPrice - XAU_PipsToPrice(m_breakEvenOffset);
         if(profitPips >= m_breakEvenPips && (currentSL > openPrice || currentSL == 0))
         {
            ModifyPosition(m_position.Ticket(), newSL, m_position.TakeProfit());
            XAU_LogDebug(StringFormat("Break-even set for SELL ticket %d at %.2f",
                     m_position.Ticket(), newSL));
         }
      }
   }
}

void CTradeManager::ManagePartialClose()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Magic() != m_magicNumber || m_position.Symbol() != m_symbol) continue;

      double openPrice = m_position.PriceOpen();
      double currentPrice = m_position.PriceCurrent();
      double profitPips = 0;
      ulong ticket = m_position.Ticket();

      if(m_position.PositionType() == POSITION_TYPE_BUY)
         profitPips = XAU_PriceToPips(currentPrice - openPrice);
      else
         profitPips = XAU_PriceToPips(openPrice - currentPrice);

      if(profitPips >= m_partialClosePips)
      {
         bool alreadyClosed = false;
         for(int j = 0; j < m_partialClosedCount; j++)
         {
            if(m_partialClosedTickets[j] == ticket)
            {
               alreadyClosed = true;
               break;
            }
         }

         if(!alreadyClosed)
         {
            if(PartialClose(ticket, m_partialClosePercent))
            {
               ArrayResize(m_partialClosedTickets, m_partialClosedCount + 1);
               m_partialClosedTickets[m_partialClosedCount] = ticket;
               m_partialClosedCount++;
            }
         }
      }
   }

   for(int i = m_partialClosedCount - 1; i >= 0; i--)
   {
      bool found = false;
      for(int j = PositionsTotal() - 1; j >= 0; j--)
      {
         if(m_position.SelectByIndex(j) && m_position.Ticket() == m_partialClosedTickets[i])
         {
            found = true;
            break;
         }
      }
      if(!found)
      {
         for(int k = i; k < m_partialClosedCount - 1; k++)
            m_partialClosedTickets[k] = m_partialClosedTickets[k + 1];
         m_partialClosedCount--;
         ArrayResize(m_partialClosedTickets, m_partialClosedCount);
      }
   }
}

int CTradeManager::CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Magic() == m_magicNumber && m_position.Symbol() == m_symbol)
            count++;
      }
   }
   return count;
}

double CTradeManager::GetTotalProfit()
{
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Magic() == m_magicNumber && m_position.Symbol() == m_symbol)
            total += m_position.Profit() + m_position.Swap() + m_position.Commission();
      }
   }
   return total;
}

double CTradeManager::GetPositionProfit(ulong ticket)
{
   if(m_position.SelectByTicket(ticket))
      return m_position.Profit() + m_position.Swap() + m_position.Commission();
   return 0;
}

double CTradeManager::GetCurrentSpreadPips()
{
   m_symbolInfo.RefreshRates();
   double spread = m_symbolInfo.Ask() - m_symbolInfo.Bid();
   return XAU_PriceToPips(spread);
}

ulong CTradeManager::GetLastTicket()
{
   return m_trade.ResultOrder();
}

bool CTradeManager::HasOpenPosition()
{
   return (CountOpenPositions() > 0);
}

void CTradeManager::GetOpenTickets(ulong &tickets[], int &count)
{
   count = 0;
   ArrayResize(tickets, 0);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Magic() == m_magicNumber && m_position.Symbol() == m_symbol)
         {
            ArrayResize(tickets, count + 1);
            tickets[count] = m_position.Ticket();
            count++;
         }
      }
   }
}


//+------------------------------------------------------------------+
//| CTrailingStop - Advanced trailing stop management                |
//+------------------------------------------------------------------+
class CTrailingStop
{
private:
   ENUM_TRAILING_MODE m_mode;
   string            m_symbol;
   long              m_magicNumber;
   double            m_trailDistance;
   double            m_trailStep;
   double            m_jumpSize;
   double            m_lockInPips;
   double            m_lockInThreshold;
   double            m_atrMultiplier;
   int               m_atrPeriod;
   int               m_atrHandle;
   ENUM_TIMEFRAMES   m_timeframe;

   double            m_progressiveStart;
   double            m_progressiveMin;
   double            m_progressiveRate;

   HiddenStopData    m_hiddenStops[];
   int               m_hiddenStopCount;

   CTrade            m_trade;
   CPositionInfo     m_position;

   int               FindHiddenStop(ulong ticket);
   void              AddHiddenStop(ulong ticket);
   void              RemoveHiddenStop(ulong ticket);
   double            GetATRValue();
   double            GetSwingLow(int bars);
   double            GetSwingHigh(int bars);
   double            CalculateProgressiveDistance(double profitPips);

   void              TrailStandard(ulong ticket);
   void              TrailHiddenLockIn(ulong ticket);
   void              TrailJump(ulong ticket);
   void              TrailProgressive(ulong ticket);
   void              TrailATR(ulong ticket);
   void              TrailStructure(ulong ticket);

public:
                     CTrailingStop();
                    ~CTrailingStop();

   bool              Init(string symbol, long magic, ENUM_TRAILING_MODE mode,
                          ENUM_TIMEFRAMES tf = PERIOD_M5);
   void              SetTrailParams(double distance, double step);
   void              SetJumpParams(double jumpSize);
   void              SetLockInParams(double threshold, double lockPips);
   void              SetATRParams(int period, double multiplier);
   void              SetProgressiveParams(double start, double minDist, double rate);

   void              ManageTrailing();
   bool              ShouldClosePosition(ulong ticket, double currentPrice);
   void              Deinit();
   void              RemoveAllTracking();
};

CTrailingStop::CTrailingStop()
{
   m_mode = TRAIL_NONE;
   m_symbol = "";
   m_magicNumber = 0;
   m_trailDistance = 30.0;
   m_trailStep = 5.0;
   m_jumpSize = 50.0;
   m_lockInPips = 10.0;
   m_lockInThreshold = 30.0;
   m_atrMultiplier = 2.0;
   m_atrPeriod = 14;
   m_atrHandle = INVALID_HANDLE;
   m_timeframe = PERIOD_M5;
   m_progressiveStart = 20.0;
   m_progressiveMin = 10.0;
   m_progressiveRate = 0.5;
   m_hiddenStopCount = 0;
}

CTrailingStop::~CTrailingStop()
{
   Deinit();
}

bool CTrailingStop::Init(string symbol, long magic, ENUM_TRAILING_MODE mode,
                          ENUM_TIMEFRAMES tf)
{
   m_symbol = symbol;
   m_magicNumber = magic;
   m_mode = mode;
   m_timeframe = tf;

   m_trade.SetExpertMagicNumber(magic);
   ArrayResize(m_hiddenStops, 0);
   m_hiddenStopCount = 0;

   if(m_mode == TRAIL_ATR)
   {
      m_atrHandle = iATR(m_symbol, m_timeframe, m_atrPeriod);
      if(m_atrHandle == INVALID_HANDLE)
      {
         XAU_LogError("TrailingStop: Failed to create ATR handle");
         return false;
      }
   }

   XAU_LogInfo(StringFormat("TrailingStop initialized: mode=%s distance=%.1f step=%.1f",
           EnumToString(m_mode), m_trailDistance, m_trailStep));
   return true;
}

void CTrailingStop::SetTrailParams(double distance, double step)
{
   m_trailDistance = distance;
   m_trailStep = step;
}

void CTrailingStop::SetJumpParams(double jumpSize)
{
   m_jumpSize = jumpSize;
}

void CTrailingStop::SetLockInParams(double threshold, double lockPips)
{
   m_lockInThreshold = threshold;
   m_lockInPips = lockPips;
}

void CTrailingStop::SetATRParams(int period, double multiplier)
{
   m_atrPeriod = period;
   m_atrMultiplier = multiplier;

   if(m_atrHandle != INVALID_HANDLE)
      IndicatorRelease(m_atrHandle);
   m_atrHandle = iATR(m_symbol, m_timeframe, m_atrPeriod);
}

void CTrailingStop::SetProgressiveParams(double start, double minDist, double rate)
{
   m_progressiveStart = start;
   m_progressiveMin = minDist;
   m_progressiveRate = rate;
}

void CTrailingStop::ManageTrailing()
{
   if(m_mode == TRAIL_NONE) return;

   for(int i = m_hiddenStopCount - 1; i >= 0; i--)
   {
      bool positionExists = m_position.SelectByTicket(m_hiddenStops[i].ticket);
      if(!positionExists)
         RemoveHiddenStop(m_hiddenStops[i].ticket);
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Magic() != m_magicNumber || m_position.Symbol() != m_symbol) continue;

      ulong ticket = m_position.Ticket();

      if(FindHiddenStop(ticket) < 0)
         AddHiddenStop(ticket);

      switch(m_mode)
      {
         case TRAIL_STANDARD:      TrailStandard(ticket);      break;
         case TRAIL_HIDDEN_LOCKIN: TrailHiddenLockIn(ticket);  break;
         case TRAIL_JUMP:          TrailJump(ticket);          break;
         case TRAIL_PROGRESSIVE:   TrailProgressive(ticket);   break;
         case TRAIL_ATR:           TrailATR(ticket);           break;
         case TRAIL_STRUCTURE:     TrailStructure(ticket);     break;
         default: break;
      }
   }
}

void CTrailingStop::TrailStandard(ulong ticket)
{
   if(!m_position.SelectByTicket(ticket)) return;

   double openPrice = m_position.PriceOpen();
   double currentSL = m_position.StopLoss();
   double currentPrice = m_position.PriceCurrent();
   double trailPrice = XAU_PipsToPrice(m_trailDistance);
   double stepPrice = XAU_PipsToPrice(m_trailStep);

   if(m_position.PositionType() == POSITION_TYPE_BUY)
   {
      double newSL = currentPrice - trailPrice;
      if(newSL > openPrice && newSL > currentSL + stepPrice)
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
   }
   else if(m_position.PositionType() == POSITION_TYPE_SELL)
   {
      double newSL = currentPrice + trailPrice;
      if(newSL < openPrice && (currentSL == 0 || newSL < currentSL - stepPrice))
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
   }
}

void CTrailingStop::TrailHiddenLockIn(ulong ticket)
{
   if(!m_position.SelectByTicket(ticket)) return;

   int idx = FindHiddenStop(ticket);
   if(idx < 0) return;

   double openPrice = m_position.PriceOpen();
   double currentPrice = m_position.PriceCurrent();
   double profitPips = 0;

   if(m_position.PositionType() == POSITION_TYPE_BUY)
      profitPips = XAU_PriceToPips(currentPrice - openPrice);
   else
      profitPips = XAU_PriceToPips(openPrice - currentPrice);

   if(profitPips >= m_lockInThreshold && !m_hiddenStops[idx].lockInActive)
   {
      m_hiddenStops[idx].lockInActive = true;

      if(m_position.PositionType() == POSITION_TYPE_BUY)
         m_hiddenStops[idx].hiddenSL = openPrice + XAU_PipsToPrice(m_lockInPips);
      else
         m_hiddenStops[idx].hiddenSL = openPrice - XAU_PipsToPrice(m_lockInPips);

      XAU_LogDebug(StringFormat("Lock-in activated: ticket=%d hidden SL=%.2f",
               ticket, m_hiddenStops[idx].hiddenSL));
   }

   if(m_hiddenStops[idx].lockInActive)
   {
      double trailPrice = XAU_PipsToPrice(m_trailDistance);

      if(m_position.PositionType() == POSITION_TYPE_BUY)
      {
         double newHiddenSL = currentPrice - trailPrice;
         if(newHiddenSL > m_hiddenStops[idx].hiddenSL)
            m_hiddenStops[idx].hiddenSL = newHiddenSL;
      }
      else
      {
         double newHiddenSL = currentPrice + trailPrice;
         if(newHiddenSL < m_hiddenStops[idx].hiddenSL || m_hiddenStops[idx].hiddenSL == 0)
            m_hiddenStops[idx].hiddenSL = newHiddenSL;
      }

      double serverSL = m_position.StopLoss();
      double hiddenSL = m_hiddenStops[idx].hiddenSL;
      double bigStep = XAU_PipsToPrice(m_trailDistance * 2);

      if(m_position.PositionType() == POSITION_TYPE_BUY)
      {
         if(hiddenSL > serverSL + bigStep || serverSL < openPrice)
         {
            m_trade.PositionModify(ticket, hiddenSL, m_position.TakeProfit());
            XAU_LogDebug(StringFormat("Server SL updated (lock-in): ticket=%d SL=%.2f", ticket, hiddenSL));
         }
      }
      else
      {
         if((serverSL == 0 || hiddenSL < serverSL - bigStep) || serverSL > openPrice)
         {
            m_trade.PositionModify(ticket, hiddenSL, m_position.TakeProfit());
            XAU_LogDebug(StringFormat("Server SL updated (lock-in): ticket=%d SL=%.2f", ticket, hiddenSL));
         }
      }
   }
}


void CTrailingStop::TrailJump(ulong ticket)
{
   if(!m_position.SelectByTicket(ticket)) return;

   int idx = FindHiddenStop(ticket);
   if(idx < 0) return;

   double openPrice = m_position.PriceOpen();
   double currentPrice = m_position.PriceCurrent();
   double currentSL = m_position.StopLoss();
   double jumpPrice = XAU_PipsToPrice(m_jumpSize);
   double profitPips = 0;

   if(m_position.PositionType() == POSITION_TYPE_BUY)
   {
      profitPips = XAU_PriceToPips(currentPrice - openPrice);
      int jumpsEarned = (int)(profitPips / m_jumpSize);
      if(jumpsEarned > m_hiddenStops[idx].jumpCount && jumpsEarned > 0)
      {
         double newSL = openPrice + (jumpsEarned - 1) * jumpPrice;
         if(newSL > currentSL)
         {
            m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
            m_hiddenStops[idx].jumpCount = jumpsEarned;
            m_hiddenStops[idx].lastJumpLevel = newSL;
            XAU_LogDebug(StringFormat("Jump SL: ticket=%d jump #%d SL=%.2f",
                     ticket, jumpsEarned, newSL));
         }
      }
   }
   else if(m_position.PositionType() == POSITION_TYPE_SELL)
   {
      profitPips = XAU_PriceToPips(openPrice - currentPrice);
      int jumpsEarned = (int)(profitPips / m_jumpSize);
      if(jumpsEarned > m_hiddenStops[idx].jumpCount && jumpsEarned > 0)
      {
         double newSL = openPrice - (jumpsEarned - 1) * jumpPrice;
         if(currentSL == 0 || newSL < currentSL)
         {
            m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
            m_hiddenStops[idx].jumpCount = jumpsEarned;
            m_hiddenStops[idx].lastJumpLevel = newSL;
            XAU_LogDebug(StringFormat("Jump SL: ticket=%d jump #%d SL=%.2f",
                     ticket, jumpsEarned, newSL));
         }
      }
   }
}

void CTrailingStop::TrailProgressive(ulong ticket)
{
   if(!m_position.SelectByTicket(ticket)) return;

   double openPrice = m_position.PriceOpen();
   double currentPrice = m_position.PriceCurrent();
   double currentSL = m_position.StopLoss();
   double profitPips = 0;

   if(m_position.PositionType() == POSITION_TYPE_BUY)
      profitPips = XAU_PriceToPips(currentPrice - openPrice);
   else
      profitPips = XAU_PriceToPips(openPrice - currentPrice);

   if(profitPips < m_progressiveStart) return;

   double dynamicDistance = CalculateProgressiveDistance(profitPips);
   double trailPrice = XAU_PipsToPrice(dynamicDistance);
   double stepPrice = XAU_PipsToPrice(m_trailStep);

   if(m_position.PositionType() == POSITION_TYPE_BUY)
   {
      double newSL = currentPrice - trailPrice;
      if(newSL > openPrice && newSL > currentSL + stepPrice)
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
   }
   else
   {
      double newSL = currentPrice + trailPrice;
      if(newSL < openPrice && (currentSL == 0 || newSL < currentSL - stepPrice))
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
   }
}

void CTrailingStop::TrailATR(ulong ticket)
{
   if(!m_position.SelectByTicket(ticket)) return;

   double atrValue = GetATRValue();
   if(atrValue == 0) return;

   double trailPrice = atrValue * m_atrMultiplier;
   double openPrice = m_position.PriceOpen();
   double currentPrice = m_position.PriceCurrent();
   double currentSL = m_position.StopLoss();
   double stepPrice = XAU_PipsToPrice(m_trailStep);

   if(m_position.PositionType() == POSITION_TYPE_BUY)
   {
      double newSL = currentPrice - trailPrice;
      if(newSL > openPrice && newSL > currentSL + stepPrice)
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
   }
   else
   {
      double newSL = currentPrice + trailPrice;
      if(newSL < openPrice && (currentSL == 0 || newSL < currentSL - stepPrice))
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
   }
}

void CTrailingStop::TrailStructure(ulong ticket)
{
   if(!m_position.SelectByTicket(ticket)) return;

   double openPrice = m_position.PriceOpen();
   double currentSL = m_position.StopLoss();
   double buffer = XAU_PipsToPrice(5.0);

   if(m_position.PositionType() == POSITION_TYPE_BUY)
   {
      double swingLow = GetSwingLow(20);
      double newSL = swingLow - buffer;
      if(newSL > openPrice && newSL > currentSL + XAU_PipsToPrice(m_trailStep))
      {
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
         XAU_LogDebug(StringFormat("Structure trail BUY: SL moved to %.2f (swing low)", newSL));
      }
   }
   else
   {
      double swingHigh = GetSwingHigh(20);
      double newSL = swingHigh + buffer;
      if(newSL < openPrice && (currentSL == 0 || newSL < currentSL - XAU_PipsToPrice(m_trailStep)))
      {
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
         XAU_LogDebug(StringFormat("Structure trail SELL: SL moved to %.2f (swing high)", newSL));
      }
   }
}

bool CTrailingStop::ShouldClosePosition(ulong ticket, double currentPrice)
{
   int idx = FindHiddenStop(ticket);
   if(idx < 0 || !m_hiddenStops[idx].lockInActive) return false;

   if(!m_position.SelectByTicket(ticket)) return false;

   double hiddenSL = m_hiddenStops[idx].hiddenSL;
   if(hiddenSL == 0) return false;

   if(m_position.PositionType() == POSITION_TYPE_BUY)
      return (currentPrice <= hiddenSL);
   else
      return (currentPrice >= hiddenSL);
}

double CTrailingStop::CalculateProgressiveDistance(double profitPips)
{
   double ratio = (profitPips - m_progressiveStart) * m_progressiveRate / 100.0;
   double distance = m_trailDistance * (1.0 - ratio);
   return MathMax(distance, m_progressiveMin);
}

double CTrailingStop::GetATRValue()
{
   if(m_atrHandle == INVALID_HANDLE) return 0;
   double atr[1];
   if(CopyBuffer(m_atrHandle, 0, 0, 1, atr) < 1) return 0;
   return atr[0];
}

double CTrailingStop::GetSwingLow(int bars)
{
   double lowest = DBL_MAX;
   for(int i = 1; i <= bars; i++)
   {
      double low = iLow(m_symbol, m_timeframe, i);
      if(i >= 2 && i <= bars - 1)
      {
         double prevLow = iLow(m_symbol, m_timeframe, i - 1);
         double nextLow = iLow(m_symbol, m_timeframe, i + 1);
         if(low < prevLow && low < nextLow && low < lowest)
            lowest = low;
      }
   }
   if(lowest == DBL_MAX) lowest = iLow(m_symbol, m_timeframe, 1);
   return lowest;
}

double CTrailingStop::GetSwingHigh(int bars)
{
   double highest = 0;
   for(int i = 1; i <= bars; i++)
   {
      double high = iHigh(m_symbol, m_timeframe, i);
      if(i >= 2 && i <= bars - 1)
      {
         double prevHigh = iHigh(m_symbol, m_timeframe, i - 1);
         double nextHigh = iHigh(m_symbol, m_timeframe, i + 1);
         if(high > prevHigh && high > nextHigh && high > highest)
            highest = high;
      }
   }
   if(highest == 0) highest = iHigh(m_symbol, m_timeframe, 1);
   return highest;
}

int CTrailingStop::FindHiddenStop(ulong ticket)
{
   for(int i = 0; i < m_hiddenStopCount; i++)
      if(m_hiddenStops[i].ticket == ticket)
         return i;
   return -1;
}

void CTrailingStop::AddHiddenStop(ulong ticket)
{
   HiddenStopData data;
   data.ticket = ticket;
   data.hiddenSL = 0;
   data.lastJumpLevel = 0;
   data.lockInThreshold = m_lockInThreshold;
   data.lockInActive = false;
   data.jumpCount = 0;

   ArrayResize(m_hiddenStops, m_hiddenStopCount + 1);
   m_hiddenStops[m_hiddenStopCount] = data;
   m_hiddenStopCount++;
}

void CTrailingStop::RemoveHiddenStop(ulong ticket)
{
   int idx = FindHiddenStop(ticket);
   if(idx < 0) return;

   for(int i = idx; i < m_hiddenStopCount - 1; i++)
      m_hiddenStops[i] = m_hiddenStops[i + 1];

   m_hiddenStopCount--;
   ArrayResize(m_hiddenStops, m_hiddenStopCount);
}

void CTrailingStop::RemoveAllTracking()
{
   ArrayResize(m_hiddenStops, 0);
   m_hiddenStopCount = 0;
}

void CTrailingStop::Deinit()
{
   if(m_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(m_atrHandle);
      m_atrHandle = INVALID_HANDLE;
   }
   RemoveAllTracking();
}


//+------------------------------------------------------------------+
//| CNewsFilter - Filters trading around high-impact news events     |
//+------------------------------------------------------------------+
class CNewsFilter
{
private:
   bool              m_enabled;
   int               m_minutesBefore;
   int               m_minutesAfter;
   bool              m_filterFriday;
   bool              m_filterMonday;
   int               m_mondayStartHour;
   int               m_fridayEndHour;

   bool              m_tradeDays[7];

   NewsEvent         m_newsSchedule[];
   int               m_newsCount;

   BlackoutPeriod    m_customBlackouts[];
   int               m_blackoutCount;

   bool              m_inBlackout;
   string            m_blackoutReason;
   datetime          m_blackoutEnd;

   void              BuildNewsSchedule();
   bool              IsNearScheduledNews();
   bool              IsInCustomBlackout();
   int               GetWeekOfMonth();

public:
                     CNewsFilter();
                    ~CNewsFilter();

   bool              Init(bool enabled, int minBefore = 30, int minAfter = 15);
   void              SetDayFilter(bool sun, bool mon, bool tue, bool wed,
                                   bool thu, bool fri, bool sat);
   void              SetFridayFilter(bool enable, int endHour = 20);
   void              SetMondayFilter(bool enable, int startHour = 3);

   void              AddBlackout(datetime start, datetime end, string reason);
   void              ClearBlackouts();

   bool              IsNewsTime();
   bool              IsTradingAllowed();

   bool              IsEnabled() { return m_enabled; }
   bool              IsInBlackout() { return m_inBlackout; }
   string            GetBlackoutReason() { return m_blackoutReason; }
   void              SetEnabled(bool enable) { m_enabled = enable; }
};

CNewsFilter::CNewsFilter()
{
   m_enabled = true;
   m_minutesBefore = 30;
   m_minutesAfter = 15;
   m_filterFriday = true;
   m_filterMonday = true;
   m_mondayStartHour = 3;
   m_fridayEndHour = 20;
   m_inBlackout = false;
   m_blackoutReason = "";
   m_blackoutEnd = 0;
   m_newsCount = 0;
   m_blackoutCount = 0;

   m_tradeDays[0] = false;
   m_tradeDays[1] = true;
   m_tradeDays[2] = true;
   m_tradeDays[3] = true;
   m_tradeDays[4] = true;
   m_tradeDays[5] = true;
   m_tradeDays[6] = false;
}

CNewsFilter::~CNewsFilter()
{
   ArrayFree(m_newsSchedule);
   ArrayFree(m_customBlackouts);
}

bool CNewsFilter::Init(bool enabled, int minBefore, int minAfter)
{
   m_enabled = enabled;
   m_minutesBefore = minBefore;
   m_minutesAfter = minAfter;

   BuildNewsSchedule();

   XAU_LogInfo(StringFormat("NewsFilter initialized: enabled=%s before=%dmin after=%dmin",
           enabled ? "true" : "false", minBefore, minAfter));
   return true;
}

void CNewsFilter::SetDayFilter(bool sun, bool mon, bool tue, bool wed,
                                bool thu, bool fri, bool sat)
{
   m_tradeDays[0] = sun;
   m_tradeDays[1] = mon;
   m_tradeDays[2] = tue;
   m_tradeDays[3] = wed;
   m_tradeDays[4] = thu;
   m_tradeDays[5] = fri;
   m_tradeDays[6] = sat;
}

void CNewsFilter::SetFridayFilter(bool enable, int endHour)
{
   m_filterFriday = enable;
   m_fridayEndHour = endHour;
}

void CNewsFilter::SetMondayFilter(bool enable, int startHour)
{
   m_filterMonday = enable;
   m_mondayStartHour = startHour;
}

void CNewsFilter::AddBlackout(datetime start, datetime end, string reason)
{
   ArrayResize(m_customBlackouts, m_blackoutCount + 1);
   m_customBlackouts[m_blackoutCount].startTime = start;
   m_customBlackouts[m_blackoutCount].endTime = end;
   m_customBlackouts[m_blackoutCount].reason = reason;
   m_blackoutCount++;
}

void CNewsFilter::ClearBlackouts()
{
   ArrayResize(m_customBlackouts, 0);
   m_blackoutCount = 0;
}

void CNewsFilter::BuildNewsSchedule()
{
   NewsEvent events[];
   int count = 0;

   ArrayResize(events, count + 1);
   events[count].name = "NFP";
   events[count].dayOfWeek = 5;
   events[count].weekOfMonth = 1;
   events[count].hour = 15;
   events[count].minute = 30;
   events[count].impact = 3;
   count++;

   ArrayResize(events, count + 1);
   events[count].name = "FOMC";
   events[count].dayOfWeek = 3;
   events[count].weekOfMonth = 3;
   events[count].hour = 21;
   events[count].minute = 0;
   events[count].impact = 3;
   count++;

   ArrayResize(events, count + 1);
   events[count].name = "CPI";
   events[count].dayOfWeek = 3;
   events[count].weekOfMonth = 2;
   events[count].hour = 15;
   events[count].minute = 30;
   events[count].impact = 3;
   count++;

   ArrayResize(events, count + 1);
   events[count].name = "PPI";
   events[count].dayOfWeek = 4;
   events[count].weekOfMonth = 2;
   events[count].hour = 15;
   events[count].minute = 30;
   events[count].impact = 2;
   count++;

   ArrayResize(events, count + 1);
   events[count].name = "Retail Sales";
   events[count].dayOfWeek = 2;
   events[count].weekOfMonth = 3;
   events[count].hour = 15;
   events[count].minute = 30;
   events[count].impact = 2;
   count++;

   ArrayResize(events, count + 1);
   events[count].name = "Jobless Claims";
   events[count].dayOfWeek = 4;
   events[count].weekOfMonth = 0;
   events[count].hour = 15;
   events[count].minute = 30;
   events[count].impact = 2;
   count++;

   ArrayResize(events, count + 1);
   events[count].name = "ISM Manufacturing";
   events[count].dayOfWeek = 1;
   events[count].weekOfMonth = 1;
   events[count].hour = 17;
   events[count].minute = 0;
   events[count].impact = 2;
   count++;

   ArrayResize(events, count + 1);
   events[count].name = "GDP";
   events[count].dayOfWeek = 4;
   events[count].weekOfMonth = 4;
   events[count].hour = 15;
   events[count].minute = 30;
   events[count].impact = 3;
   count++;

   ArrayResize(events, count + 1);
   events[count].name = "Fed Speech";
   events[count].dayOfWeek = 3;
   events[count].weekOfMonth = 2;
   events[count].hour = 18;
   events[count].minute = 0;
   events[count].impact = 3;
   count++;

   ArrayResize(events, count + 1);
   events[count].name = "Core PCE";
   events[count].dayOfWeek = 5;
   events[count].weekOfMonth = 4;
   events[count].hour = 15;
   events[count].minute = 30;
   events[count].impact = 3;
   count++;

   ArrayResize(events, count + 1);
   events[count].name = "ADP Employment";
   events[count].dayOfWeek = 3;
   events[count].weekOfMonth = 1;
   events[count].hour = 15;
   events[count].minute = 15;
   events[count].impact = 2;
   count++;

   ArrayResize(m_newsSchedule, count);
   for(int i = 0; i < count; i++)
      m_newsSchedule[i] = events[i];
   m_newsCount = count;

   ArrayFree(events);
}

int CNewsFilter::GetWeekOfMonth()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return ((dt.day - 1) / 7) + 1;
}

bool CNewsFilter::IsNearScheduledNews()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentWeek = GetWeekOfMonth();
   int currentMinutes = dt.hour * 60 + dt.min;

   for(int i = 0; i < m_newsCount; i++)
   {
      if(m_newsSchedule[i].dayOfWeek != dt.day_of_week) continue;
      if(m_newsSchedule[i].weekOfMonth != 0 && m_newsSchedule[i].weekOfMonth != currentWeek)
         continue;

      int eventMinutes = m_newsSchedule[i].hour * 60 + m_newsSchedule[i].minute;
      int diff = currentMinutes - eventMinutes;

      if(diff >= -m_minutesBefore && diff <= m_minutesAfter)
      {
         m_blackoutReason = StringFormat("Near %s event (impact=%d)",
                            m_newsSchedule[i].name, m_newsSchedule[i].impact);
         return true;
      }
   }

   return false;
}

bool CNewsFilter::IsInCustomBlackout()
{
   datetime now = TimeCurrent();
   for(int i = 0; i < m_blackoutCount; i++)
   {
      if(now >= m_customBlackouts[i].startTime && now <= m_customBlackouts[i].endTime)
      {
         m_blackoutReason = "Custom blackout: " + m_customBlackouts[i].reason;
         return true;
      }
   }
   return false;
}

bool CNewsFilter::IsNewsTime()
{
   if(!m_enabled) return false;

   m_inBlackout = false;
   m_blackoutReason = "";

   if(IsNearScheduledNews())
   {
      m_inBlackout = true;
      return true;
   }

   if(IsInCustomBlackout())
   {
      m_inBlackout = true;
      return true;
   }

   return false;
}

bool CNewsFilter::IsTradingAllowed()
{
   if(!m_enabled) return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(!m_tradeDays[dt.day_of_week])
   {
      m_inBlackout = true;
      m_blackoutReason = "Trading disabled for this day of week";
      return false;
   }

   if(m_filterMonday && dt.day_of_week == 1 && dt.hour < m_mondayStartHour)
   {
      m_inBlackout = true;
      m_blackoutReason = StringFormat("Monday filter: waiting until %d:00", m_mondayStartHour);
      return false;
   }

   if(m_filterFriday && dt.day_of_week == 5 && dt.hour >= m_fridayEndHour)
   {
      m_inBlackout = true;
      m_blackoutReason = StringFormat("Friday filter: trading stopped at %d:00", m_fridayEndHour);
      return false;
   }

   if(IsNewsTime())
      return false;

   m_inBlackout = false;
   m_blackoutReason = "";
   return true;
}


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
      XAU_LogWarning("This EA is designed for XAUUSD/Gold. Current symbol: " + _Symbol);
   }

   //--- Initialize SMC Analysis
   if(InpUseSMC)
   {
      if(!g_smcAnalysis.Init(_Symbol, InpLowerTF, InpSMCLookback, 3, 20, 500))
      {
         XAU_LogError("Failed to initialize SMC Analysis");
         return INIT_FAILED;
      }
   }

   //--- Initialize Signal Engine
   if(!g_signalEngine.Init(_Symbol, InpLowerTF, InpHigherTF,
                            InpEMAFastPeriod, InpEMASlowPeriod,
                            InpRSIPeriod, InpRSIOverbought, InpRSIOversold))
   {
      XAU_LogError("Failed to initialize Signal Engine");
      return INIT_FAILED;
   }
   if(InpUseSMC)
      g_signalEngine.SetSMCAnalysis(&g_smcAnalysis);
   g_signalEngine.SetWeights(InpSignalWeightEMA, InpSignalWeightRSI, InpSignalWeightSMC);

   //--- Initialize Risk Manager
   if(!g_riskManager.Init(InpRiskPercent, InpMaxDrawdown, InpDailyLossLimit,
                           InpMinBalance, InpMaxConsecLoss, InpLotReduction))
   {
      XAU_LogError("Failed to initialize Risk Manager");
      return INIT_FAILED;
   }
   g_riskManager.SetKellyCriterion(InpUseKelly);
   g_riskManager.SetEquityCurveTrading(InpUseEquityCurve, 20);
   g_riskManager.SetMinRiskReward(InpMinRiskReward);

   //--- Initialize Trade Manager
   if(!g_tradeManager.Init(_Symbol, InpMagicNumber, InpEAComment,
                            InpMaxSpread, InpMaxSlippage, InpMaxPositions))
   {
      XAU_LogError("Failed to initialize Trade Manager");
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
      XAU_LogError("Failed to initialize Trailing Stop");
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
      XAU_LogError("Failed to initialize News Filter");
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
   XAU_LogInfo("=== " + EA_NAME + " v" + EA_VERSION + " initialized successfully ===");
   XAU_LogInfo(StringFormat("Account: %.2f %s | Leverage: 1:%d",
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
   g_signalEngine.Deinit();
   g_trailingStop.Deinit();

   EventKillTimer();

   ObjectsDeleteAll(0, "EA_");

   XAU_LogInfo("=== " + EA_NAME + " stopped ===");
   XAU_LogInfo(StringFormat("Reason: %d | Total trades: %d | Total P&L: %.2f",
           reason, g_totalTrades, g_totalProfit));

   g_initialized = false;
}

//+------------------------------------------------------------------+
//| Expert tick function - Main trading logic                         |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized || !InpEnableEA) return;

   //--- Step 1: Check for new bar
   datetime currentBarTime = iTime(_Symbol, InpLowerTF, 0);
   bool isNewBar = (currentBarTime != g_lastBarTime);

   //--- Always manage existing positions on every tick
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

   if(InpEnableDashboard)
      UpdateDashboard();

   g_riskManager.Update();
}


//+------------------------------------------------------------------+
//| Manage existing open positions                                    |
//+------------------------------------------------------------------+
void ManageExistingPositions()
{
   g_trailingStop.ManageTrailing();

   g_tradeManager.ManageBreakEven();

   g_tradeManager.ManagePartialClose();

   ulong tickets[];
   int count = 0;
   g_tradeManager.GetOpenTickets(tickets, count);

   for(int i = 0; i < count; i++)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(g_trailingStop.ShouldClosePosition(tickets[i], bid))
      {
         XAU_LogInfo(StringFormat("Hidden SL hit - closing position %d", tickets[i]));
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

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPrice = 0;
   double tpPrice = 0;

   bool usedStructureSL = false;
   bool usedStructureTP = false;

   if(signal.suggestedSL > 0)
   {
      if(signal.signal == SIGNAL_BUY)
      {
         double structureSLDist = ask - signal.suggestedSL;
         if(structureSLDist > 0)
         {
            slPips = XAU_PriceToPips(structureSLDist);
            usedStructureSL = true;
         }
      }
      else if(signal.signal == SIGNAL_SELL)
      {
         double structureSLDist = signal.suggestedSL - bid;
         if(structureSLDist > 0)
         {
            slPips = XAU_PriceToPips(structureSLDist);
            usedStructureSL = true;
         }
      }
   }

   if(signal.suggestedTP > 0)
   {
      if(signal.signal == SIGNAL_BUY)
      {
         double structureTPDist = signal.suggestedTP - ask;
         if(structureTPDist > 0)
         {
            tpPips = XAU_PriceToPips(structureTPDist);
            usedStructureTP = true;
         }
      }
      else if(signal.signal == SIGNAL_SELL)
      {
         double structureTPDist = bid - signal.suggestedTP;
         if(structureTPDist > 0)
         {
            tpPips = XAU_PriceToPips(structureTPDist);
            usedStructureTP = true;
         }
      }
   }

   //--- Validate risk-reward ratio
   if(!g_riskManager.ValidateRiskReward(slPips, tpPips))
   {
      XAU_LogDebug(StringFormat("Trade rejected: R:R ratio %.2f below minimum %.2f",
               tpPips / slPips, InpMinRiskReward));
      return;
   }

   //--- Calculate lot size
   double lots = g_riskManager.CalculateLotSize(slPips);
   if(lots <= 0)
   {
      XAU_LogWarning("Lot size calculation returned 0 - trade skipped");
      return;
   }

   //--- Calculate SL and TP prices
   string comment = StringFormat("%s_%s_S%d", InpEAComment, SignalToString(signal.signal), signal.strength);

   if(signal.signal == SIGNAL_BUY)
   {
      slPrice = ask - XAU_PipsToPrice(slPips);
      tpPrice = ask + XAU_PipsToPrice(tpPips);

      if(g_tradeManager.OpenBuy(lots, slPrice, tpPrice, comment))
      {
         g_totalTrades++;
         if(InpUseSMC)
         {
            double price = iClose(_Symbol, InpLowerTF, 0);
            g_smcAnalysis.ConsumeOrderBlock(price);
            g_smcAnalysis.ConsumeFVG(price);
            g_smcAnalysis.ConsumeLiquiditySweep(price);
         }
         XAU_LogInfo(StringFormat("BUY executed: %.2f lots | SL=%.2f%s | TP=%.2f%s | Strength=%d | %s",
                 lots, slPrice, usedStructureSL ? " (SMC)" : "",
                 tpPrice, usedStructureTP ? " (SMC)" : "",
                 signal.strength, signal.reason));
      }
   }
   else if(signal.signal == SIGNAL_SELL)
   {
      slPrice = bid + XAU_PipsToPrice(slPips);
      tpPrice = bid - XAU_PipsToPrice(tpPips);

      if(g_tradeManager.OpenSell(lots, slPrice, tpPrice, comment))
      {
         g_totalTrades++;
         if(InpUseSMC)
         {
            double price = iClose(_Symbol, InpLowerTF, 0);
            g_smcAnalysis.ConsumeOrderBlock(price);
            g_smcAnalysis.ConsumeFVG(price);
            g_smcAnalysis.ConsumeLiquiditySweep(price);
         }
         XAU_LogInfo(StringFormat("SELL executed: %.2f lots | SL=%.2f%s | TP=%.2f%s | Strength=%d | %s",
                 lots, slPrice, usedStructureSL ? " (SMC)" : "",
                 tpPrice, usedStructureTP ? " (SMC)" : "",
                 signal.strength, signal.reason));
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

   CreateLabel("EA_BG", x - 5, y - 5, 280, 280, bgColor);

   CreateText("EA_Title", x, y, EA_NAME + " v" + EA_VERSION, clrGold, 10);
   y += lineHeight + 5;
   CreateText("EA_Sep1", x, y, "-----------------------------", clrGray, 8);
   y += lineHeight;

   CreateText("EA_Status",    x, y, "Status: Initializing", textColor, 9); y += lineHeight;
   CreateText("EA_Signal",    x, y, "Signal: None (0)", textColor, 9); y += lineHeight;
   CreateText("EA_Session",   x, y, "Session: ---", textColor, 9); y += lineHeight;
   y += 5;
   CreateText("EA_Sep2", x, y, "-----------------------------", clrGray, 8);
   y += lineHeight;

   CreateText("EA_Balance",   x, y, "Balance: ---", textColor, 9); y += lineHeight;
   CreateText("EA_Equity",    x, y, "Equity: ---", textColor, 9); y += lineHeight;
   CreateText("EA_Drawdown",  x, y, "Drawdown: ---", textColor, 9); y += lineHeight;
   CreateText("EA_DailyPnL",  x, y, "Today P&L: ---", textColor, 9); y += lineHeight;
   y += 5;
   CreateText("EA_Sep3", x, y, "-----------------------------", clrGray, 8);
   y += lineHeight;

   CreateText("EA_Positions", x, y, "Positions: 0", textColor, 9); y += lineHeight;
   CreateText("EA_Spread",    x, y, "Spread: ---", textColor, 9); y += lineHeight;
   CreateText("EA_Trades",    x, y, "Total Trades: 0", textColor, 9); y += lineHeight;
   y += 5;
   CreateText("EA_Sep4", x, y, "-----------------------------", clrGray, 8);
   y += lineHeight;

   CreateText("EA_NewsF",     x, y, "News Filter: ---", textColor, 9); y += lineHeight;
   CreateText("EA_RiskF",     x, y, "Risk Status: ---", textColor, 9); y += lineHeight;
}

//+------------------------------------------------------------------+
//| Update dashboard values                                           |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   color statusColor = (g_eaStatus == "Active") ? clrLime : clrOrange;
   UpdateText("EA_Status", "Status: " + g_eaStatus, statusColor);

   color sigColor = clrWhite;
   if(g_lastSignal == "BUY") sigColor = clrLime;
   else if(g_lastSignal == "SELL") sigColor = clrRed;
   UpdateText("EA_Signal", StringFormat("Signal: %s (%d)", g_lastSignal, g_lastSignalStrength), sigColor);

   UpdateText("EA_Session", "Session: " + SessionToString(GetCurrentSession()), clrWhite);

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

   int positions = g_tradeManager.CountOpenPositions();
   double spread = g_tradeManager.GetCurrentSpreadPips();

   UpdateText("EA_Positions", StringFormat("Positions: %d / %d", positions, InpMaxPositions), clrWhite);

   color spreadColor = (spread > InpMaxSpread * 0.8) ? clrRed : clrLime;
   UpdateText("EA_Spread", StringFormat("Spread: %.1f pips", spread), spreadColor);
   UpdateText("EA_Trades", StringFormat("Total Trades: %d", g_totalTrades), clrWhite);

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
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
      {
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

                  XAU_LogInfo(StringFormat("Trade closed: P&L=%.2f | Total P&L=%.2f | Consec Losses=%d",
                          profit, g_totalProfit, g_riskManager.GetConsecutiveLosses()));
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+

