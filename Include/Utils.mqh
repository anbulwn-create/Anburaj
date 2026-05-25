//+------------------------------------------------------------------+
//|                                                        Utils.mqh |
//|                         XAUUSD ProTrader EA - Utility Functions   |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef UTILS_MQH
#define UTILS_MQH

//+------------------------------------------------------------------+
//| Enumerations shared across all modules                           |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_TYPE
{
   SIGNAL_NONE = 0,    // No signal
   SIGNAL_BUY  = 1,    // Buy signal
   SIGNAL_SELL = -1    // Sell signal
};

enum ENUM_TRADE_DIRECTION
{
   DIRECTION_LONG  = 1,   // Long (Buy)
   DIRECTION_SHORT = -1,  // Short (Sell)
   DIRECTION_FLAT  = 0    // No direction
};

enum ENUM_SESSION_TYPE
{
   SESSION_ASIAN   = 0,   // Asian session (Tokyo)
   SESSION_LONDON  = 1,   // London session
   SESSION_NEWYORK = 2,   // New York session
   SESSION_OVERLAP = 3,   // London/NY overlap
   SESSION_OFFHOURS = 4   // Off-market hours
};

enum ENUM_LOG_LEVEL
{
   LOG_DEBUG   = 0,   // Debug (verbose)
   LOG_INFO    = 1,   // Information
   LOG_WARNING = 2,   // Warning
   LOG_ERROR   = 3,   // Error
   LOG_CRITICAL = 4   // Critical
};

//+------------------------------------------------------------------+
//| Constants                                                         |
//+------------------------------------------------------------------+
#define XAUUSD_PIP_SIZE       0.01     // Gold pip size (1 cent)
#define XAUUSD_POINT_PER_PIP  10       // Points per pip for gold
#define EA_NAME               "XAUUSD ProTrader EA"
#define EA_VERSION            "1.0"
#define MAX_RETRIES           3        // Max order send retries
#define RETRY_DELAY_MS        500      // Delay between retries

//--- Session times in server hours (adjust for broker offset)
#define ASIAN_START_HOUR      0    // 00:00
#define ASIAN_END_HOUR        8    // 08:00
#define LONDON_START_HOUR     8    // 08:00
#define LONDON_END_HOUR       16   // 16:00
#define NEWYORK_START_HOUR    13   // 13:00
#define NEWYORK_END_HOUR      21   // 21:00
#define OVERLAP_START_HOUR    13   // 13:00 (London + NY)
#define OVERLAP_END_HOUR      16   // 16:00

//+------------------------------------------------------------------+
//| Logging helper - prints with severity prefix and EA name         |
//+------------------------------------------------------------------+
void LogMessage(ENUM_LOG_LEVEL level, string message)
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

//+------------------------------------------------------------------+
//| Shorthand logging functions                                      |
//+------------------------------------------------------------------+
void LogDebug(string msg)    { LogMessage(LOG_DEBUG, msg); }
void LogInfo(string msg)     { LogMessage(LOG_INFO, msg); }
void LogWarning(string msg)  { LogMessage(LOG_WARNING, msg); }
void LogError(string msg)    { LogMessage(LOG_ERROR, msg); }
void LogCritical(string msg) { LogMessage(LOG_CRITICAL, msg); }

//+------------------------------------------------------------------+
//| Convert pips to price distance for XAUUSD                        |
//+------------------------------------------------------------------+
double PipsToPrice(double pips)
{
   return pips * XAUUSD_PIP_SIZE;
}

//+------------------------------------------------------------------+
//| Convert price distance to pips for XAUUSD                        |
//+------------------------------------------------------------------+
double PriceToPips(double priceDistance)
{
   if(XAUUSD_PIP_SIZE == 0) return 0;
   return priceDistance / XAUUSD_PIP_SIZE;
}

//+------------------------------------------------------------------+
//| Get pip value for lot size on XAUUSD                              |
//+------------------------------------------------------------------+
double GetPipValue(double lotSize)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0) return 0;
   return (XAUUSD_PIP_SIZE / tickSize) * tickValue * lotSize;
}

//+------------------------------------------------------------------+
//| Detect current trading session based on server time               |
//+------------------------------------------------------------------+
ENUM_SESSION_TYPE GetCurrentSession()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int hour = timeStruct.hour;

   // Check London/NY overlap first (most desirable)
   if(hour >= OVERLAP_START_HOUR && hour < OVERLAP_END_HOUR)
      return SESSION_OVERLAP;

   // London session
   if(hour >= LONDON_START_HOUR && hour < LONDON_END_HOUR)
      return SESSION_LONDON;

   // New York session (non-overlap portion)
   if(hour >= NEWYORK_START_HOUR && hour < NEWYORK_END_HOUR)
      return SESSION_NEWYORK;

   // Asian session
   if(hour >= ASIAN_START_HOUR && hour < ASIAN_END_HOUR)
      return SESSION_ASIAN;

   return SESSION_OFFHOURS;
}

//+------------------------------------------------------------------+
//| Check if current time is within a specific session                |
//+------------------------------------------------------------------+
bool IsInSession(ENUM_SESSION_TYPE session)
{
   return (GetCurrentSession() == session);
}

//+------------------------------------------------------------------+
//| Check if current time is within custom hour range                 |
//+------------------------------------------------------------------+
bool IsWithinHours(int startHour, int endHour)
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int hour = timeStruct.hour;

   if(startHour <= endHour)
      return (hour >= startHour && hour < endHour);
   else // Crosses midnight
      return (hour >= startHour || hour < endHour);
}

//+------------------------------------------------------------------+
//| Get day of week (0=Sunday, 6=Saturday)                           |
//+------------------------------------------------------------------+
int GetDayOfWeek()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   return timeStruct.day_of_week;
}

//+------------------------------------------------------------------+
//| Check if it is a new bar on the specified timeframe               |
//| Uses a static array to track bar times per timeframe safely       |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES timeframe)
{
   //--- Static array to track last bar time per timeframe index
   //--- Supports up to 25 timeframe enum values (PERIOD_M1=1 to PERIOD_MN1=49153)
   static datetime lastBarTimes[25];
   static bool initialized = false;

   if(!initialized)
   {
      ArrayInitialize(lastBarTimes, 0);
      initialized = true;
   }

   //--- Map timeframe enum to a small index
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

//+------------------------------------------------------------------+
//| Normalize lot size to broker specifications                       |
//+------------------------------------------------------------------+
double NormalizeLot(double lots)
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

//+------------------------------------------------------------------+
//| Get current spread in pips                                        |
//+------------------------------------------------------------------+
double GetSpreadPips()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return PriceToPips(ask - bid);
}

//+------------------------------------------------------------------+
//| Find highest value in a double array                              |
//+------------------------------------------------------------------+
double ArrayMax(const double &arr[], int count = -1)
{
   int size = (count > 0) ? MathMin(count, ArraySize(arr)) : ArraySize(arr);
   if(size == 0) return 0;

   double maxVal = arr[0];
   for(int i = 1; i < size; i++)
   {
      if(arr[i] > maxVal) maxVal = arr[i];
   }
   return maxVal;
}

//+------------------------------------------------------------------+
//| Find lowest value in a double array                               |
//+------------------------------------------------------------------+
double ArrayMin(const double &arr[], int count = -1)
{
   int size = (count > 0) ? MathMin(count, ArraySize(arr)) : ArraySize(arr);
   if(size == 0) return 0;

   double minVal = arr[0];
   for(int i = 1; i < size; i++)
   {
      if(arr[i] < minVal) minVal = arr[i];
   }
   return minVal;
}

//+------------------------------------------------------------------+
//| Find index of highest value in array                              |
//+------------------------------------------------------------------+
int ArrayMaxIndex(const double &arr[], int count = -1)
{
   int size = (count > 0) ? MathMin(count, ArraySize(arr)) : ArraySize(arr);
   if(size == 0) return -1;

   int maxIdx = 0;
   for(int i = 1; i < size; i++)
   {
      if(arr[i] > arr[maxIdx]) maxIdx = i;
   }
   return maxIdx;
}

//+------------------------------------------------------------------+
//| Find index of lowest value in array                               |
//+------------------------------------------------------------------+
int ArrayMinIndex(const double &arr[], int count = -1)
{
   int size = (count > 0) ? MathMin(count, ArraySize(arr)) : ArraySize(arr);
   if(size == 0) return -1;

   int minIdx = 0;
   for(int i = 1; i < size; i++)
   {
      if(arr[i] < arr[minIdx]) minIdx = i;
   }
   return minIdx;
}

//+------------------------------------------------------------------+
//| Calculate simple moving average of array values                   |
//+------------------------------------------------------------------+
double ArraySMA(const double &arr[], int period, int startIndex = 0)
{
   int size = ArraySize(arr);
   if(size == 0 || period <= 0 || startIndex + period > size) return 0;

   double sum = 0;
   for(int i = startIndex; i < startIndex + period; i++)
   {
      sum += arr[i];
   }
   return sum / period;
}

//+------------------------------------------------------------------+
//| Format time duration in human readable format                     |
//+------------------------------------------------------------------+
string FormatDuration(int seconds)
{
   int hours   = seconds / 3600;
   int minutes = (seconds % 3600) / 60;
   int secs    = seconds % 60;

   return StringFormat("%02d:%02d:%02d", hours, minutes, secs);
}

//+------------------------------------------------------------------+
//| Convert signal type to string                                     |
//+------------------------------------------------------------------+
string SignalToString(ENUM_SIGNAL_TYPE signal)
{
   switch(signal)
   {
      case SIGNAL_BUY:  return "BUY";
      case SIGNAL_SELL: return "SELL";
      default:          return "NONE";
   }
}

//+------------------------------------------------------------------+
//| Convert session type to string                                    |
//+------------------------------------------------------------------+
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

#endif // UTILS_MQH
