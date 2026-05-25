//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh  |
//|                    XAUUSD ProTrader EA - Risk & Money Management  |
//+------------------------------------------------------------------+
#ifndef RISK_MANAGER_MQH
#define RISK_MANAGER_MQH

#include "Utils.mqh"

//+------------------------------------------------------------------+
//| Position sizing tier                                              |
//+------------------------------------------------------------------+
enum ENUM_ACCOUNT_TIER
{
   TIER_MICRO    = 0,   // $100-$999
   TIER_MINI     = 1,   // $1000-$9999
   TIER_STANDARD = 2    // $10000+
};

//+------------------------------------------------------------------+
//| CRiskManager - Comprehensive risk and money management           |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   //--- Configuration
   double            m_riskPercent;         // Risk per trade (%)
   double            m_maxDrawdownPercent;  // Max allowed drawdown (%)
   double            m_dailyLossLimit;      // Daily loss limit (%)
   double            m_minBalance;          // Minimum balance to trade
   int               m_maxConsecLosses;     // Max consecutive losses before reduction
   double            m_lotReductionFactor;  // Lot reduction after N losses (e.g., 0.5 = half size)
   double            m_minRiskReward;       // Minimum required R:R ratio
   bool              m_useKellyCriterion;   // Use Kelly for lot sizing
   bool              m_useEquityCurve;      // Trade only above equity MA

   //--- State tracking
   double            m_startingBalance;     // Balance at start of day
   double            m_peakBalance;         // Highest recorded balance
   int               m_consecutiveLosses;   // Current consecutive loss count
   double            m_dailyPnL;            // Today's profit/loss
   datetime          m_lastDayReset;        // Last daily reset time
   double            m_equityHistory[];     // Equity curve tracking (circular buffer)
   int               m_equityHistorySize;   // Size of equity history
   int               m_equityHistoryIdx;    // Current write index for circular buffer
   int               m_equityHistoryFill;   // Number of entries filled so far
   int               m_equityMAPeriod;      // Period for equity MA
   bool              m_tradingPaused;       // Trading paused flag
   string            m_pauseReason;         // Reason trading is paused

   //--- Kelly Criterion state
   int               m_totalTrades;
   int               m_winningTrades;
   double            m_avgWin;
   double            m_avgLoss;

   //--- Internal methods
   ENUM_ACCOUNT_TIER GetAccountTier();
   double            GetTierMaxLot(ENUM_ACCOUNT_TIER tier);
   double            CalculateKellyFraction();
   double            GetEquityMA();
   void              UpdateEquityHistory();
   void              CheckDailyReset();

public:
                     CRiskManager();
                    ~CRiskManager();

   //--- Initialization
   bool              Init(double riskPercent, double maxDD, double dailyLimit,
                          double minBal, int maxConsecLoss = 3, double lotReduction = 0.5);
   void              SetKellyCriterion(bool enable) { m_useKellyCriterion = enable; }
   void              SetEquityCurveTrading(bool enable, int maPeriod = 20);
   void              SetMinRiskReward(double rr) { m_minRiskReward = rr; }

   //--- Lot sizing
   double            CalculateLotSize(double slPips);
   double            CalculateLotSizeFixed(double lots);

   //--- Risk checks (call before opening trade)
   bool              CanTrade();
   bool              CheckDrawdown();
   bool              CheckDailyLoss();
   bool              CheckConsecutiveLosses();
   bool              CheckMinBalance();
   bool              CheckEquityCurve();
   bool              ValidateRiskReward(double slPips, double tpPips);

   //--- Trade result tracking
   void              RecordWin(double profit);
   void              RecordLoss(double loss);
   void              ResetDailyCounters();

   //--- Getters
   double            GetCurrentDrawdown();
   double            GetDailyPnL() { return m_dailyPnL; }
   int               GetConsecutiveLosses() { return m_consecutiveLosses; }
   bool              IsTradingPaused() { return m_tradingPaused; }
   string            GetPauseReason() { return m_pauseReason; }
   double            GetRiskPercent() { return m_riskPercent; }
   ENUM_ACCOUNT_TIER GetTier() { return GetAccountTier(); }

   //--- Update (call periodically)
   void              Update();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CRiskManager::~CRiskManager()
{
   ArrayFree(m_equityHistory);
}

//+------------------------------------------------------------------+
//| Initialize risk manager                                           |
//+------------------------------------------------------------------+
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

   LogInfo(StringFormat("RiskManager initialized: Risk=%.1f%% MaxDD=%.1f%% DailyLimit=%.1f%% MinBal=%.0f",
           m_riskPercent, m_maxDrawdownPercent, m_dailyLossLimit, m_minBalance));
   return true;
}

//+------------------------------------------------------------------+
//| Enable equity curve trading with MA period                        |
//+------------------------------------------------------------------+
void CRiskManager::SetEquityCurveTrading(bool enable, int maPeriod)
{
   m_useEquityCurve = enable;
   m_equityMAPeriod = maPeriod;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage and stop loss          |
//+------------------------------------------------------------------+
double CRiskManager::CalculateLotSize(double slPips)
{
   if(slPips <= 0) return 0;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (m_riskPercent / 100.0);

   // Apply Kelly Criterion if enabled
   if(m_useKellyCriterion && m_totalTrades > 20)
   {
      double kellyFraction = CalculateKellyFraction();
      if(kellyFraction > 0 && kellyFraction < m_riskPercent / 100.0)
         riskAmount = balance * kellyFraction;
   }

   // Calculate pip value for 1 lot
   double pipValue = GetPipValue(1.0);
   if(pipValue <= 0) return 0;

   // Lot size = risk amount / (SL in pips * pip value per lot)
   double lots = riskAmount / (slPips * pipValue);

   // Apply consecutive loss reduction
   if(m_consecutiveLosses >= m_maxConsecLosses)
   {
      lots *= m_lotReductionFactor;
      LogWarning(StringFormat("Lot reduced due to %d consecutive losses: %.2f -> %.2f",
                 m_consecutiveLosses, lots / m_lotReductionFactor, lots));
   }

   // Apply tier limits
   ENUM_ACCOUNT_TIER tier = GetAccountTier();
   double maxLot = GetTierMaxLot(tier);
   lots = MathMin(lots, maxLot);

   return NormalizeLot(lots);
}

//+------------------------------------------------------------------+
//| Return fixed lot size (normalized)                                |
//+------------------------------------------------------------------+
double CRiskManager::CalculateLotSizeFixed(double lots)
{
   return NormalizeLot(lots);
}

//+------------------------------------------------------------------+
//| Master check: can we trade right now?                             |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Check if drawdown is within limits                                |
//+------------------------------------------------------------------+
bool CRiskManager::CheckDrawdown()
{
   double dd = GetCurrentDrawdown();
   return (dd < m_maxDrawdownPercent);
}

//+------------------------------------------------------------------+
//| Check if daily loss is within limits                              |
//+------------------------------------------------------------------+
bool CRiskManager::CheckDailyLoss()
{
   double dailyLossPercent = 0;
   if(m_startingBalance > 0)
      dailyLossPercent = (MathAbs(m_dailyPnL) / m_startingBalance) * 100.0;

   return (m_dailyPnL >= 0 || dailyLossPercent < m_dailyLossLimit);
}

//+------------------------------------------------------------------+
//| Check consecutive losses                                          |
//+------------------------------------------------------------------+
bool CRiskManager::CheckConsecutiveLosses()
{
   // We allow trading but with reduced size (handled in lot calculation)
   return true;
}

//+------------------------------------------------------------------+
//| Check minimum balance requirement                                 |
//+------------------------------------------------------------------+
bool CRiskManager::CheckMinBalance()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   return (balance >= m_minBalance);
}

//+------------------------------------------------------------------+
//| Check equity curve filter                                          |
//+------------------------------------------------------------------+
bool CRiskManager::CheckEquityCurve()
{
   if(!m_useEquityCurve) return true;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double equityMA = GetEquityMA();

   return (equity >= equityMA);
}

//+------------------------------------------------------------------+
//| Validate risk-to-reward ratio                                     |
//+------------------------------------------------------------------+
bool CRiskManager::ValidateRiskReward(double slPips, double tpPips)
{
   if(slPips <= 0) return false;
   double rr = tpPips / slPips;
   return (rr >= m_minRiskReward);
}

//+------------------------------------------------------------------+
//| Record a winning trade                                            |
//+------------------------------------------------------------------+
void CRiskManager::RecordWin(double profit)
{
   m_consecutiveLosses = 0;
   m_dailyPnL += profit;
   m_totalTrades++;
   m_winningTrades++;

   // Update average win
   m_avgWin = ((m_avgWin * (m_winningTrades - 1)) + profit) / m_winningTrades;

   // Update peak balance
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > m_peakBalance) m_peakBalance = balance;

   LogDebug(StringFormat("Win recorded: +%.2f | Daily P&L: %.2f | Consec losses: 0", profit, m_dailyPnL));
}

//+------------------------------------------------------------------+
//| Record a losing trade                                             |
//+------------------------------------------------------------------+
void CRiskManager::RecordLoss(double loss)
{
   m_consecutiveLosses++;
   m_dailyPnL += loss; // loss is negative
   m_totalTrades++;
   int losingTrades = m_totalTrades - m_winningTrades;

   // Update average loss
   m_avgLoss = ((m_avgLoss * (losingTrades - 1)) + MathAbs(loss)) / losingTrades;

   LogDebug(StringFormat("Loss recorded: %.2f | Daily P&L: %.2f | Consec losses: %d",
            loss, m_dailyPnL, m_consecutiveLosses));
}

//+------------------------------------------------------------------+
//| Get current drawdown percentage from peak                         |
//+------------------------------------------------------------------+
double CRiskManager::GetCurrentDrawdown()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > m_peakBalance) m_peakBalance = balance;
   if(m_peakBalance == 0) return 0;
   return ((m_peakBalance - balance) / m_peakBalance) * 100.0;
}

//+------------------------------------------------------------------+
//| Determine account tier based on balance                           |
//+------------------------------------------------------------------+
ENUM_ACCOUNT_TIER CRiskManager::GetAccountTier()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance >= 10000) return TIER_STANDARD;
   if(balance >= 1000) return TIER_MINI;
   return TIER_MICRO;
}

//+------------------------------------------------------------------+
//| Get maximum lot size for account tier                             |
//+------------------------------------------------------------------+
double CRiskManager::GetTierMaxLot(ENUM_ACCOUNT_TIER tier)
{
   switch(tier)
   {
      case TIER_MICRO:    return 0.10;   // Max 0.10 for micro accounts
      case TIER_MINI:     return 1.00;   // Max 1.00 for mini accounts
      case TIER_STANDARD: return 10.00;  // Max 10.00 for standard accounts
   }
   return 0.01;
}

//+------------------------------------------------------------------+
//| Calculate Kelly Criterion fraction                                 |
//+------------------------------------------------------------------+
double CRiskManager::CalculateKellyFraction()
{
   if(m_totalTrades < 20 || m_avgLoss == 0) return m_riskPercent / 100.0;

   double winRate = (double)m_winningTrades / m_totalTrades;
   double winLossRatio = m_avgWin / m_avgLoss;

   // Kelly formula: f = (p * b - q) / b
   // where p = win probability, q = loss probability, b = win/loss ratio
   double kelly = (winRate * winLossRatio - (1.0 - winRate)) / winLossRatio;

   // Use half Kelly for safety
   kelly *= 0.5;

   // Cap at max risk percent
   return MathMax(0, MathMin(kelly, m_riskPercent / 100.0));
}

//+------------------------------------------------------------------+
//| Get equity moving average (reads from circular buffer)            |
//+------------------------------------------------------------------+
double CRiskManager::GetEquityMA()
{
   if(m_equityHistoryFill < m_equityMAPeriod) return 0;

   double sum = 0;
   for(int i = 0; i < m_equityMAPeriod; i++)
   {
      // Read backwards from the most recent entry
      int idx = (m_equityHistoryIdx - 1 - i + m_equityHistorySize) % m_equityHistorySize;
      sum += m_equityHistory[idx];
   }

   return sum / m_equityMAPeriod;
}

//+------------------------------------------------------------------+
//| Update equity history using circular buffer (O(1))                |
//+------------------------------------------------------------------+
void CRiskManager::UpdateEquityHistory()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   m_equityHistory[m_equityHistoryIdx] = equity;
   m_equityHistoryIdx = (m_equityHistoryIdx + 1) % m_equityHistorySize;
   if(m_equityHistoryFill < m_equityHistorySize)
      m_equityHistoryFill++;
}

//+------------------------------------------------------------------+
//| Check if new day and reset counters                               |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Reset daily tracking counters                                     |
//+------------------------------------------------------------------+
void CRiskManager::ResetDailyCounters()
{
   m_dailyPnL = 0;
   m_startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   LogInfo("Daily counters reset. Starting balance: " + DoubleToString(m_startingBalance, 2));
}

//+------------------------------------------------------------------+
//| Periodic update (call from OnTimer or OnTick)                     |
//+------------------------------------------------------------------+
void CRiskManager::Update()
{
   CheckDailyReset();
   UpdateEquityHistory();

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > m_peakBalance) m_peakBalance = balance;
}

#endif // RISK_MANAGER_MQH
