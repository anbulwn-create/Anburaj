//+------------------------------------------------------------------+
//|                                                 TrailingStop.mqh  |
//|                    XAUUSD ProTrader EA - Trailing & Profit Lock   |
//+------------------------------------------------------------------+
#ifndef TRAILING_STOP_MQH
#define TRAILING_STOP_MQH

#include "Utils.mqh"
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Trailing stop mode selection                                      |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Hidden stop tracking per position                                 |
//+------------------------------------------------------------------+
struct HiddenStopData
{
   ulong             ticket;
   double            hiddenSL;          // Internal SL level (not on server)
   double            lastJumpLevel;     // Last jump SL level
   double            lockInThreshold;   // Profit threshold for lock-in
   bool              lockInActive;      // Lock-in has been triggered
   int               jumpCount;         // Number of jumps executed
};

//+------------------------------------------------------------------+
//| CTrailingStop - Advanced trailing stop management                |
//+------------------------------------------------------------------+
class CTrailingStop
{
private:
   //--- Configuration
   ENUM_TRAILING_MODE m_mode;
   string            m_symbol;
   long              m_magicNumber;
   double            m_trailDistance;     // Trail distance in pips
   double            m_trailStep;         // Minimum step to update trail
   double            m_jumpSize;          // Jump size in pips
   double            m_lockInPips;        // Pips to lock-in after threshold
   double            m_lockInThreshold;   // Pips profit before lock-in activates
   double            m_atrMultiplier;     // ATR multiplier for ATR mode
   int               m_atrPeriod;         // ATR period
   int               m_atrHandle;         // ATR indicator handle
   ENUM_TIMEFRAMES   m_timeframe;

   //--- Progressive trail settings
   double            m_progressiveStart;  // Start trail at this profit (pips)
   double            m_progressiveMin;    // Minimum trail distance (pips)
   double            m_progressiveRate;   // Rate of tightening (0-1)

   //--- Hidden stop tracking
   HiddenStopData    m_hiddenStops[];
   int               m_hiddenStopCount;

   //--- MQL5 objects
   CTrade            m_trade;
   CPositionInfo     m_position;

   //--- Internal methods
   int               FindHiddenStop(ulong ticket);
   void              AddHiddenStop(ulong ticket);
   void              RemoveHiddenStop(ulong ticket);
   double            GetATRValue();
   double            GetSwingLow(int bars);
   double            GetSwingHigh(int bars);
   double            CalculateProgressiveDistance(double profitPips);

   //--- Trail implementations
   void              TrailStandard(ulong ticket);
   void              TrailHiddenLockIn(ulong ticket);
   void              TrailJump(ulong ticket);
   void              TrailProgressive(ulong ticket);
   void              TrailATR(ulong ticket);
   void              TrailStructure(ulong ticket);

public:
                     CTrailingStop();
                    ~CTrailingStop();

   //--- Initialization
   bool              Init(string symbol, long magic, ENUM_TRAILING_MODE mode,
                          ENUM_TIMEFRAMES tf = PERIOD_M5);
   void              SetTrailParams(double distance, double step);
   void              SetJumpParams(double jumpSize);
   void              SetLockInParams(double threshold, double lockPips);
   void              SetATRParams(int period, double multiplier);
   void              SetProgressiveParams(double start, double minDist, double rate);

   //--- Main trail management (call on each tick/bar)
   void              ManageTrailing();

   //--- Hidden stop checks (for emergency close)
   bool              ShouldClosePosition(ulong ticket, double currentPrice);

   //--- Cleanup
   void              Deinit();
   void              RemoveAllTracking();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CTrailingStop::~CTrailingStop()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize trailing stop manager                                  |
//+------------------------------------------------------------------+
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

   // Create ATR handle if needed
   if(m_mode == TRAIL_ATR)
   {
      m_atrHandle = iATR(m_symbol, m_timeframe, m_atrPeriod);
      if(m_atrHandle == INVALID_HANDLE)
      {
         LogError("TrailingStop: Failed to create ATR handle");
         return false;
      }
   }

   LogInfo(StringFormat("TrailingStop initialized: mode=%s distance=%.1f step=%.1f",
           EnumToString(m_mode), m_trailDistance, m_trailStep));
   return true;
}

//+------------------------------------------------------------------+
//| Set standard trail parameters                                     |
//+------------------------------------------------------------------+
void CTrailingStop::SetTrailParams(double distance, double step)
{
   m_trailDistance = distance;
   m_trailStep = step;
}

//+------------------------------------------------------------------+
//| Set jump stop loss parameters                                     |
//+------------------------------------------------------------------+
void CTrailingStop::SetJumpParams(double jumpSize)
{
   m_jumpSize = jumpSize;
}

//+------------------------------------------------------------------+
//| Set hidden lock-in profit parameters                              |
//+------------------------------------------------------------------+
void CTrailingStop::SetLockInParams(double threshold, double lockPips)
{
   m_lockInThreshold = threshold;
   m_lockInPips = lockPips;
}

//+------------------------------------------------------------------+
//| Set ATR-based trailing parameters                                 |
//+------------------------------------------------------------------+
void CTrailingStop::SetATRParams(int period, double multiplier)
{
   m_atrPeriod = period;
   m_atrMultiplier = multiplier;

   // Recreate ATR handle with new period
   if(m_atrHandle != INVALID_HANDLE)
      IndicatorRelease(m_atrHandle);
   m_atrHandle = iATR(m_symbol, m_timeframe, m_atrPeriod);
}

//+------------------------------------------------------------------+
//| Set progressive trailing parameters                               |
//+------------------------------------------------------------------+
void CTrailingStop::SetProgressiveParams(double start, double minDist, double rate)
{
   m_progressiveStart = start;
   m_progressiveMin = minDist;
   m_progressiveRate = rate;
}

//+------------------------------------------------------------------+
//| Main trailing management - routes to appropriate method           |
//+------------------------------------------------------------------+
void CTrailingStop::ManageTrailing()
{
   if(m_mode == TRAIL_NONE) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Magic() != m_magicNumber || m_position.Symbol() != m_symbol) continue;

      ulong ticket = m_position.Ticket();

      // Ensure hidden stop tracking exists
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

//+------------------------------------------------------------------+
//| Standard trailing stop implementation                             |
//+------------------------------------------------------------------+
void CTrailingStop::TrailStandard(ulong ticket)
{
   if(!m_position.SelectByTicket(ticket)) return;

   double openPrice = m_position.PriceOpen();
   double currentSL = m_position.StopLoss();
   double currentPrice = m_position.PriceCurrent();
   double trailPrice = PipsToPrice(m_trailDistance);
   double stepPrice = PipsToPrice(m_trailStep);

   if(m_position.PositionType() == POSITION_TYPE_BUY)
   {
      double newSL = currentPrice - trailPrice;
      if(newSL > openPrice && newSL > currentSL + stepPrice)
      {
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
      }
   }
   else if(m_position.PositionType() == POSITION_TYPE_SELL)
   {
      double newSL = currentPrice + trailPrice;
      if(newSL < openPrice && (currentSL == 0 || newSL < currentSL - stepPrice))
      {
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
//| Hidden lock-in profit trailing                                    |
//| Tracks profit internally without modifying server SL immediately  |
//| Only places real SL when reversal is detected or threshold hit    |
//+------------------------------------------------------------------+
void CTrailingStop::TrailHiddenLockIn(ulong ticket)
{
   if(!m_position.SelectByTicket(ticket)) return;

   int idx = FindHiddenStop(ticket);
   if(idx < 0) return;

   double openPrice = m_position.PriceOpen();
   double currentPrice = m_position.PriceCurrent();
   double profitPips = 0;

   if(m_position.PositionType() == POSITION_TYPE_BUY)
      profitPips = PriceToPips(currentPrice - openPrice);
   else
      profitPips = PriceToPips(openPrice - currentPrice);

   // Check if lock-in threshold is reached
   if(profitPips >= m_lockInThreshold && !m_hiddenStops[idx].lockInActive)
   {
      m_hiddenStops[idx].lockInActive = true;

      // Set hidden SL at entry + lock-in pips (not sent to server yet)
      if(m_position.PositionType() == POSITION_TYPE_BUY)
         m_hiddenStops[idx].hiddenSL = openPrice + PipsToPrice(m_lockInPips);
      else
         m_hiddenStops[idx].hiddenSL = openPrice - PipsToPrice(m_lockInPips);

      LogDebug(StringFormat("Lock-in activated: ticket=%d hidden SL=%.2f",
               ticket, m_hiddenStops[idx].hiddenSL));
   }

   // If lock-in is active, trail the hidden SL
   if(m_hiddenStops[idx].lockInActive)
   {
      double trailPrice = PipsToPrice(m_trailDistance);

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

      // Only modify server SL when price moves significantly further
      // or when reversal is detected (protects from stop hunting)
      double serverSL = m_position.StopLoss();
      double hiddenSL = m_hiddenStops[idx].hiddenSL;
      double bigStep = PipsToPrice(m_trailDistance * 2); // Only update server at 2x distance

      if(m_position.PositionType() == POSITION_TYPE_BUY)
      {
         if(hiddenSL > serverSL + bigStep || serverSL < openPrice)
         {
            m_trade.PositionModify(ticket, hiddenSL, m_position.TakeProfit());
            LogDebug(StringFormat("Server SL updated (lock-in): ticket=%d SL=%.2f", ticket, hiddenSL));
         }
      }
      else
      {
         if((serverSL == 0 || hiddenSL < serverSL - bigStep) || serverSL > openPrice)
         {
            m_trade.PositionModify(ticket, hiddenSL, m_position.TakeProfit());
            LogDebug(StringFormat("Server SL updated (lock-in): ticket=%d SL=%.2f", ticket, hiddenSL));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Jump stop loss - moves SL in discrete jumps                       |
//| More stealthy than continuous trailing                            |
//+------------------------------------------------------------------+
void CTrailingStop::TrailJump(ulong ticket)
{
   if(!m_position.SelectByTicket(ticket)) return;

   int idx = FindHiddenStop(ticket);
   if(idx < 0) return;

   double openPrice = m_position.PriceOpen();
   double currentPrice = m_position.PriceCurrent();
   double currentSL = m_position.StopLoss();
   double jumpPrice = PipsToPrice(m_jumpSize);
   double profitPips = 0;

   if(m_position.PositionType() == POSITION_TYPE_BUY)
   {
      profitPips = PriceToPips(currentPrice - openPrice);

      // Calculate how many jumps profit covers
      int jumpsEarned = (int)(profitPips / m_jumpSize);
      if(jumpsEarned > m_hiddenStops[idx].jumpCount && jumpsEarned > 0)
      {
         // Place SL at (jumpsEarned - 1) * jumpSize above entry
         double newSL = openPrice + (jumpsEarned - 1) * jumpPrice;
         if(newSL > currentSL)
         {
            m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
            m_hiddenStops[idx].jumpCount = jumpsEarned;
            m_hiddenStops[idx].lastJumpLevel = newSL;
            LogDebug(StringFormat("Jump SL: ticket=%d jump #%d SL=%.2f",
                     ticket, jumpsEarned, newSL));
         }
      }
   }
   else if(m_position.PositionType() == POSITION_TYPE_SELL)
   {
      profitPips = PriceToPips(openPrice - currentPrice);

      int jumpsEarned = (int)(profitPips / m_jumpSize);
      if(jumpsEarned > m_hiddenStops[idx].jumpCount && jumpsEarned > 0)
      {
         double newSL = openPrice - (jumpsEarned - 1) * jumpPrice;
         if(currentSL == 0 || newSL < currentSL)
         {
            m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
            m_hiddenStops[idx].jumpCount = jumpsEarned;
            m_hiddenStops[idx].lastJumpLevel = newSL;
            LogDebug(StringFormat("Jump SL: ticket=%d jump #%d SL=%.2f",
                     ticket, jumpsEarned, newSL));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Progressive trailing - tightens distance as profit grows          |
//+------------------------------------------------------------------+
void CTrailingStop::TrailProgressive(ulong ticket)
{
   if(!m_position.SelectByTicket(ticket)) return;

   double openPrice = m_position.PriceOpen();
   double currentPrice = m_position.PriceCurrent();
   double currentSL = m_position.StopLoss();
   double profitPips = 0;

   if(m_position.PositionType() == POSITION_TYPE_BUY)
      profitPips = PriceToPips(currentPrice - openPrice);
   else
      profitPips = PriceToPips(openPrice - currentPrice);

   if(profitPips < m_progressiveStart) return;

   double dynamicDistance = CalculateProgressiveDistance(profitPips);
   double trailPrice = PipsToPrice(dynamicDistance);
   double stepPrice = PipsToPrice(m_trailStep);

   if(m_position.PositionType() == POSITION_TYPE_BUY)
   {
      double newSL = currentPrice - trailPrice;
      if(newSL > openPrice && newSL > currentSL + stepPrice)
      {
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
      }
   }
   else
   {
      double newSL = currentPrice + trailPrice;
      if(newSL < openPrice && (currentSL == 0 || newSL < currentSL - stepPrice))
      {
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
//| ATR-based trailing stop                                           |
//+------------------------------------------------------------------+
void CTrailingStop::TrailATR(ulong ticket)
{
   if(!m_position.SelectByTicket(ticket)) return;

   double atrValue = GetATRValue();
   if(atrValue == 0) return;

   double trailPrice = atrValue * m_atrMultiplier;
   double openPrice = m_position.PriceOpen();
   double currentPrice = m_position.PriceCurrent();
   double currentSL = m_position.StopLoss();
   double stepPrice = PipsToPrice(m_trailStep);

   if(m_position.PositionType() == POSITION_TYPE_BUY)
   {
      double newSL = currentPrice - trailPrice;
      if(newSL > openPrice && newSL > currentSL + stepPrice)
      {
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
      }
   }
   else
   {
      double newSL = currentPrice + trailPrice;
      if(newSL < openPrice && (currentSL == 0 || newSL < currentSL - stepPrice))
      {
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
//| Structure-based trailing (trail below/above swing points)         |
//+------------------------------------------------------------------+
void CTrailingStop::TrailStructure(ulong ticket)
{
   if(!m_position.SelectByTicket(ticket)) return;

   double openPrice = m_position.PriceOpen();
   double currentSL = m_position.StopLoss();
   double buffer = PipsToPrice(5.0); // 5 pip buffer beyond swing

   if(m_position.PositionType() == POSITION_TYPE_BUY)
   {
      double swingLow = GetSwingLow(20);
      double newSL = swingLow - buffer;
      if(newSL > openPrice && newSL > currentSL + PipsToPrice(m_trailStep))
      {
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
         LogDebug(StringFormat("Structure trail BUY: SL moved to %.2f (swing low)", newSL));
      }
   }
   else
   {
      double swingHigh = GetSwingHigh(20);
      double newSL = swingHigh + buffer;
      if(newSL < openPrice && (currentSL == 0 || newSL < currentSL - PipsToPrice(m_trailStep)))
      {
         m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
         LogDebug(StringFormat("Structure trail SELL: SL moved to %.2f (swing high)", newSL));
      }
   }
}

//+------------------------------------------------------------------+
//| Check if hidden SL has been hit (for emergency close)             |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Calculate progressive trail distance                              |
//+------------------------------------------------------------------+
double CTrailingStop::CalculateProgressiveDistance(double profitPips)
{
   // Distance decreases as profit increases
   double ratio = (profitPips - m_progressiveStart) * m_progressiveRate / 100.0;
   double distance = m_trailDistance * (1.0 - ratio);
   return MathMax(distance, m_progressiveMin);
}

//+------------------------------------------------------------------+
//| Get current ATR value in price                                    |
//+------------------------------------------------------------------+
double CTrailingStop::GetATRValue()
{
   if(m_atrHandle == INVALID_HANDLE) return 0;

   double atr[1];
   if(CopyBuffer(m_atrHandle, 0, 0, 1, atr) < 1) return 0;
   return atr[0];
}

//+------------------------------------------------------------------+
//| Get recent swing low for structure trailing                       |
//+------------------------------------------------------------------+
double CTrailingStop::GetSwingLow(int bars)
{
   double lowest = DBL_MAX;
   for(int i = 1; i <= bars; i++)
   {
      double low = iLow(m_symbol, m_timeframe, i);
      // Simple swing low: lower than neighbors
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

//+------------------------------------------------------------------+
//| Get recent swing high for structure trailing                      |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Find hidden stop tracking data by ticket                          |
//+------------------------------------------------------------------+
int CTrailingStop::FindHiddenStop(ulong ticket)
{
   for(int i = 0; i < m_hiddenStopCount; i++)
   {
      if(m_hiddenStops[i].ticket == ticket)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Add new hidden stop tracking entry                                |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Remove hidden stop tracking for closed position                   |
//+------------------------------------------------------------------+
void CTrailingStop::RemoveHiddenStop(ulong ticket)
{
   int idx = FindHiddenStop(ticket);
   if(idx < 0) return;

   // Shift remaining entries
   for(int i = idx; i < m_hiddenStopCount - 1; i++)
      m_hiddenStops[i] = m_hiddenStops[i + 1];

   m_hiddenStopCount--;
   ArrayResize(m_hiddenStops, m_hiddenStopCount);
}

//+------------------------------------------------------------------+
//| Remove all tracking data                                          |
//+------------------------------------------------------------------+
void CTrailingStop::RemoveAllTracking()
{
   ArrayResize(m_hiddenStops, 0);
   m_hiddenStopCount = 0;
}

//+------------------------------------------------------------------+
//| Cleanup and release resources                                     |
//+------------------------------------------------------------------+
void CTrailingStop::Deinit()
{
   if(m_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(m_atrHandle);
      m_atrHandle = INVALID_HANDLE;
   }
   RemoveAllTracking();
}

#endif // TRAILING_STOP_MQH
