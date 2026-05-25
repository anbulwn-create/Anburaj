//+------------------------------------------------------------------+
//|                                                 TradeManager.mqh  |
//|                    XAUUSD ProTrader EA - Trade Execution Manager  |
//+------------------------------------------------------------------+
#ifndef TRADE_MANAGER_MQH
#define TRADE_MANAGER_MQH

#include "Utils.mqh"
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| CTradeManager - Handles all order execution and position mgmt    |
//+------------------------------------------------------------------+
class CTradeManager
{
private:
   //--- MQL5 Standard Library objects
   CTrade            m_trade;
   CPositionInfo     m_position;
   CSymbolInfo       m_symbolInfo;

   //--- Configuration
   string            m_symbol;
   long              m_magicNumber;
   string            m_comment;
   double            m_maxSpreadPips;       // Max allowed spread
   int               m_maxSlippage;         // Max deviation in points
   int               m_maxPositions;        // Maximum open positions
   int               m_cooldownSeconds;     // Min time between trades
   double            m_breakEvenPips;       // Pips profit to trigger BE
   double            m_breakEvenOffset;     // Offset from entry for BE SL
   double            m_partialClosePercent; // Percent to close at TP1
   double            m_partialClosePips;    // Pips profit for partial close

   //--- Session trading windows
   bool              m_tradeLondon;
   bool              m_tradeNewYork;
   bool              m_tradeAsian;
   bool              m_tradeOverlap;
   int               m_customStartHour;
   int               m_customEndHour;
   bool              m_useCustomHours;

   //--- State
   datetime          m_lastTradeTime;            // Time of last trade
   ulong             m_partialClosedTickets[];   // Tickets already partially closed
   int               m_partialClosedCount;       // Count of partially closed tickets

public:
                     CTradeManager();
                    ~CTradeManager();

   //--- Initialization
   bool              Init(string symbol, long magic, string comment,
                          double maxSpread = 50.0, int maxSlip = 30, int maxPos = 3);
   void              SetBreakEven(double triggerPips, double offsetPips);
   void              SetPartialClose(double percent, double triggerPips);
   void              SetCooldown(int seconds) { m_cooldownSeconds = seconds; }
   void              SetSessionFilter(bool london, bool ny, bool asian, bool overlap);
   void              SetCustomHours(int startHour, int endHour);

   //--- Pre-trade checks
   bool              IsSpreadOK();
   bool              IsWithinMaxPositions();
   bool              IsCooldownExpired();
   bool              IsSessionAllowed();

   //--- Order execution
   bool              OpenBuy(double lots, double sl, double tp, string comment = "");
   bool              OpenSell(double lots, double sl, double tp, string comment = "");
   bool              ModifyPosition(ulong ticket, double sl, double tp);
   bool              ClosePosition(ulong ticket);
   bool              CloseAllPositions();
   bool              PartialClose(ulong ticket, double percent);

   //--- Position management (call on each tick/bar)
   void              ManageBreakEven();
   void              ManagePartialClose();
   int               CountOpenPositions();
   double            GetTotalProfit();
   double            GetPositionProfit(ulong ticket);

   //--- Utility
   double            GetCurrentSpreadPips();
   ulong             GetLastTicket();
   bool              HasOpenPosition();
   void              GetOpenTickets(ulong &tickets[], int &count);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CTradeManager::~CTradeManager()
{
   ArrayFree(m_partialClosedTickets);
}

//+------------------------------------------------------------------+
//| Initialize trade manager                                          |
//+------------------------------------------------------------------+
bool CTradeManager::Init(string symbol, long magic, string comment,
                          double maxSpread, int maxSlip, int maxPos)
{
   m_symbol = symbol;
   m_magicNumber = magic;
   m_comment = comment;
   m_maxSpreadPips = maxSpread;
   m_maxSlippage = maxSlip;
   m_maxPositions = maxPos;

   // Configure CTrade object
   m_trade.SetExpertMagicNumber(magic);
   m_trade.SetDeviationInPoints(maxSlip);
   m_trade.SetMarginMode();

   // Detect and set supported filling mode
   long fillingMode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((fillingMode & SYMBOL_FILLING_FOK) != 0)
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillingMode & SYMBOL_FILLING_IOC) != 0)
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      m_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   // Initialize symbol info
   if(!m_symbolInfo.Name(symbol))
   {
      LogError("TradeManager: Failed to set symbol info for " + symbol);
      return false;
   }

   LogInfo(StringFormat("TradeManager initialized: %s Magic=%d MaxSpread=%.1f MaxSlip=%d MaxPos=%d",
           symbol, magic, maxSpread, maxSlip, maxPos));
   return true;
}

//+------------------------------------------------------------------+
//| Set break-even parameters                                         |
//+------------------------------------------------------------------+
void CTradeManager::SetBreakEven(double triggerPips, double offsetPips)
{
   m_breakEvenPips = triggerPips;
   m_breakEvenOffset = offsetPips;
}

//+------------------------------------------------------------------+
//| Set partial close parameters                                      |
//+------------------------------------------------------------------+
void CTradeManager::SetPartialClose(double percent, double triggerPips)
{
   m_partialClosePercent = percent;
   m_partialClosePips = triggerPips;
}

//+------------------------------------------------------------------+
//| Configure session filter                                          |
//+------------------------------------------------------------------+
void CTradeManager::SetSessionFilter(bool london, bool ny, bool asian, bool overlap)
{
   m_tradeLondon = london;
   m_tradeNewYork = ny;
   m_tradeAsian = asian;
   m_tradeOverlap = overlap;
}

//+------------------------------------------------------------------+
//| Set custom trading hours                                          |
//+------------------------------------------------------------------+
void CTradeManager::SetCustomHours(int startHour, int endHour)
{
   m_customStartHour = startHour;
   m_customEndHour = endHour;
   m_useCustomHours = true;
}

//+------------------------------------------------------------------+
//| Check if current spread is within allowed limits                  |
//+------------------------------------------------------------------+
bool CTradeManager::IsSpreadOK()
{
   double spreadPips = GetCurrentSpreadPips();
   if(spreadPips > m_maxSpreadPips)
   {
      LogDebug(StringFormat("Spread too high: %.1f pips (max: %.1f)", spreadPips, m_maxSpreadPips));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check if number of open positions is within limit                 |
//+------------------------------------------------------------------+
bool CTradeManager::IsWithinMaxPositions()
{
   return (CountOpenPositions() < m_maxPositions);
}

//+------------------------------------------------------------------+
//| Check if cooldown timer has expired                               |
//+------------------------------------------------------------------+
bool CTradeManager::IsCooldownExpired()
{
   if(m_lastTradeTime == 0) return true;
   return ((TimeCurrent() - m_lastTradeTime) >= m_cooldownSeconds);
}

//+------------------------------------------------------------------+
//| Check if current session allows trading                           |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Open a buy position with retry logic                              |
//+------------------------------------------------------------------+
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
         LogInfo(StringFormat("BUY opened: %.2f lots @ %.2f SL=%.2f TP=%.2f",
                 lots, ask, sl, tp));
         return true;
      }

      int error = (int)m_trade.ResultRetcode();
      LogWarning(StringFormat("BUY attempt %d failed: %d - %s",
                 attempt + 1, error, m_trade.ResultRetcodeDescription()));

      if(error == TRADE_RETCODE_NO_MONEY || error == TRADE_RETCODE_MARKET_CLOSED)
         break; // Don't retry on fatal errors

      Sleep(RETRY_DELAY_MS);
      m_symbolInfo.RefreshRates();
      ask = m_symbolInfo.Ask();
   }

   LogError("BUY order failed after all retries");
   return false;
}

//+------------------------------------------------------------------+
//| Open a sell position with retry logic                             |
//+------------------------------------------------------------------+
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
         LogInfo(StringFormat("SELL opened: %.2f lots @ %.2f SL=%.2f TP=%.2f",
                 lots, bid, sl, tp));
         return true;
      }

      int error = (int)m_trade.ResultRetcode();
      LogWarning(StringFormat("SELL attempt %d failed: %d - %s",
                 attempt + 1, error, m_trade.ResultRetcodeDescription()));

      if(error == TRADE_RETCODE_NO_MONEY || error == TRADE_RETCODE_MARKET_CLOSED)
         break;

      Sleep(RETRY_DELAY_MS);
      m_symbolInfo.RefreshRates();
      bid = m_symbolInfo.Bid();
   }

   LogError("SELL order failed after all retries");
   return false;
}

//+------------------------------------------------------------------+
//| Modify position SL/TP                                             |
//+------------------------------------------------------------------+
bool CTradeManager::ModifyPosition(ulong ticket, double sl, double tp)
{
   if(!m_trade.PositionModify(ticket, sl, tp))
   {
      LogWarning(StringFormat("Position modify failed: ticket=%d error=%d",
                 ticket, m_trade.ResultRetcode()));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Close position by ticket                                          |
//+------------------------------------------------------------------+
bool CTradeManager::ClosePosition(ulong ticket)
{
   if(!m_trade.PositionClose(ticket))
   {
      LogWarning(StringFormat("Position close failed: ticket=%d error=%d",
                 ticket, m_trade.ResultRetcode()));
      return false;
   }
   LogInfo(StringFormat("Position closed: ticket=%d", ticket));
   return true;
}

//+------------------------------------------------------------------+
//| Close all EA positions                                            |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Partial close a percentage of position volume                     |
//+------------------------------------------------------------------+
bool CTradeManager::PartialClose(ulong ticket, double percent)
{
   if(!m_position.SelectByTicket(ticket)) return false;

   double volume = m_position.Volume();
   double closeVolume = NormalizeLot(volume * (percent / 100.0));

   if(closeVolume < SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN))
      return false;

   if(m_trade.PositionClosePartial(ticket, closeVolume))
   {
      LogInfo(StringFormat("Partial close: ticket=%d volume=%.2f (%.0f%%)",
              ticket, closeVolume, percent));
      return true;
   }

   LogWarning(StringFormat("Partial close failed: ticket=%d error=%d",
              ticket, m_trade.ResultRetcode()));
   return false;
}

//+------------------------------------------------------------------+
//| Manage break-even for all open positions                          |
//+------------------------------------------------------------------+
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
         profitPips = PriceToPips(currentPrice - openPrice);
         double newSL = openPrice + PipsToPrice(m_breakEvenOffset);

         // Move to BE if profit exceeds trigger and SL is below entry
         if(profitPips >= m_breakEvenPips && currentSL < openPrice)
         {
            ModifyPosition(m_position.Ticket(), newSL, m_position.TakeProfit());
            LogDebug(StringFormat("Break-even set for BUY ticket %d at %.2f",
                     m_position.Ticket(), newSL));
         }
      }
      else if(m_position.PositionType() == POSITION_TYPE_SELL)
      {
         profitPips = PriceToPips(openPrice - currentPrice);
         double newSL = openPrice - PipsToPrice(m_breakEvenOffset);

         if(profitPips >= m_breakEvenPips && (currentSL > openPrice || currentSL == 0))
         {
            ModifyPosition(m_position.Ticket(), newSL, m_position.TakeProfit());
            LogDebug(StringFormat("Break-even set for SELL ticket %d at %.2f",
                     m_position.Ticket(), newSL));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage partial close for positions at TP1 level                   |
//+------------------------------------------------------------------+
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
         profitPips = PriceToPips(currentPrice - openPrice);
      else
         profitPips = PriceToPips(openPrice - currentPrice);

      // Check if partial close should trigger
      if(profitPips >= m_partialClosePips)
      {
         // Check if we already partially closed this position using ticket tracking
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
               // Record this ticket as partially closed
               ArrayResize(m_partialClosedTickets, m_partialClosedCount + 1);
               m_partialClosedTickets[m_partialClosedCount] = ticket;
               m_partialClosedCount++;
            }
         }
      }
   }

   // Prune tickets for positions that no longer exist
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
         // Remove closed position from tracking array
         for(int k = i; k < m_partialClosedCount - 1; k++)
            m_partialClosedTickets[k] = m_partialClosedTickets[k + 1];
         m_partialClosedCount--;
         ArrayResize(m_partialClosedTickets, m_partialClosedCount);
      }
   }
}

//+------------------------------------------------------------------+
//| Count open positions for this EA                                  |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Get total profit of all open positions                            |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Get profit of specific position                                   |
//+------------------------------------------------------------------+
double CTradeManager::GetPositionProfit(ulong ticket)
{
   if(m_position.SelectByTicket(ticket))
      return m_position.Profit() + m_position.Swap() + m_position.Commission();
   return 0;
}

//+------------------------------------------------------------------+
//| Get current spread in pips                                        |
//+------------------------------------------------------------------+
double CTradeManager::GetCurrentSpreadPips()
{
   m_symbolInfo.RefreshRates();
   double spread = m_symbolInfo.Ask() - m_symbolInfo.Bid();
   return PriceToPips(spread);
}

//+------------------------------------------------------------------+
//| Get ticket of last opened position                                |
//+------------------------------------------------------------------+
ulong CTradeManager::GetLastTicket()
{
   return m_trade.ResultOrder();
}

//+------------------------------------------------------------------+
//| Check if EA has any open position                                 |
//+------------------------------------------------------------------+
bool CTradeManager::HasOpenPosition()
{
   return (CountOpenPositions() > 0);
}

//+------------------------------------------------------------------+
//| Get array of open position tickets                                |
//+------------------------------------------------------------------+
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

#endif // TRADE_MANAGER_MQH
