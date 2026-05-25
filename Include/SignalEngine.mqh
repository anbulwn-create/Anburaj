//+------------------------------------------------------------------+
//|                                                 SignalEngine.mqh  |
//|                    XAUUSD ProTrader EA - Signal Generation Engine |
//+------------------------------------------------------------------+
#ifndef SIGNAL_ENGINE_MQH
#define SIGNAL_ENGINE_MQH

#include "Utils.mqh"
#include "SMCAnalysis.mqh"

//+------------------------------------------------------------------+
//| Signal result structure                                           |
//+------------------------------------------------------------------+
struct SignalResult
{
   ENUM_SIGNAL_TYPE  signal;           // Final signal direction
   int               strength;         // Signal strength 0-100
   bool              emaConfirmed;     // EMA trend confirmed
   bool              rsiConfirmed;     // RSI condition met
   bool              smcConfirmed;     // SMC confluence present
   string            reason;           // Human-readable reason
};

//+------------------------------------------------------------------+
//| CSignalEngine - Multi-factor signal generation                   |
//+------------------------------------------------------------------+
class CSignalEngine
{
private:
   //--- Configuration
   string            m_symbol;
   ENUM_TIMEFRAMES   m_lowerTF;        // M5 for entry timing
   ENUM_TIMEFRAMES   m_higherTF;       // H1 for trend direction

   //--- EMA settings
   int               m_emaFastPeriod;   // EMA 50
   int               m_emaSlowPeriod;   // EMA 200

   //--- RSI settings
   int               m_rsiPeriod;
   double            m_rsiOverbought;
   double            m_rsiOversold;

   //--- Indicator handles
   int               m_hEmaFastLower;   // EMA 50 on M5
   int               m_hEmaSlowLower;   // EMA 200 on M5
   int               m_hEmaFastHigher;  // EMA 50 on H1
   int               m_hEmaSlowHigher;  // EMA 200 on H1
   int               m_hRsi;            // RSI on M5

   //--- SMC reference
   CSMCAnalysis*     m_smcAnalysis;

   //--- Scoring weights
   int               m_weightEMA;       // EMA weight in total score
   int               m_weightRSI;       // RSI weight in total score
   int               m_weightSMC;       // SMC weight in total score

   //--- State
   bool              m_initialized;

   //--- Internal methods
   int               GetEMAScore();
   int               GetRSIScore();
   int               GetSMCScore();
   bool              CheckEMACrossover(ENUM_TIMEFRAMES tf, int handleFast, int handleSlow);
   bool              DetectRSIDivergence(bool bullish);

public:
                     CSignalEngine();
                    ~CSignalEngine();

   //--- Initialization
   bool              Init(string symbol, ENUM_TIMEFRAMES lowerTF, ENUM_TIMEFRAMES higherTF,
                          int emaFast = 50, int emaSlow = 200,
                          int rsiPeriod = 14, double rsiOB = 70.0, double rsiOS = 30.0);
   void              SetSMCAnalysis(CSMCAnalysis *smc) { m_smcAnalysis = smc; }
   void              SetWeights(int emaW, int rsiW, int smcW);

   //--- Signal generation
   SignalResult      GenerateSignal();

   //--- Individual checks
   ENUM_SIGNAL_TYPE  GetEMATrend();
   bool              IsRSIOverbought();
   bool              IsRSIOversold();
   double            GetRSIValue();
   bool              HasEMACrossoverUp();
   bool              HasEMACrossoverDown();

   //--- Cleanup
   void              Deinit();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CSignalEngine::~CSignalEngine()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize indicator handles                                      |
//+------------------------------------------------------------------+
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

   // Create EMA handles for lower timeframe (M5)
   m_hEmaFastLower = iMA(m_symbol, m_lowerTF, m_emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_hEmaSlowLower = iMA(m_symbol, m_lowerTF, m_emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);

   // Create EMA handles for higher timeframe (H1)
   m_hEmaFastHigher = iMA(m_symbol, m_higherTF, m_emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_hEmaSlowHigher = iMA(m_symbol, m_higherTF, m_emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);

   // Create RSI handle on lower timeframe
   m_hRsi = iRSI(m_symbol, m_lowerTF, m_rsiPeriod, PRICE_CLOSE);

   // Validate handles
   if(m_hEmaFastLower == INVALID_HANDLE || m_hEmaSlowLower == INVALID_HANDLE ||
      m_hEmaFastHigher == INVALID_HANDLE || m_hEmaSlowHigher == INVALID_HANDLE ||
      m_hRsi == INVALID_HANDLE)
   {
      LogError("SignalEngine: Failed to create indicator handles. Error: " + IntegerToString(GetLastError()));
      return false;
   }

   m_initialized = true;
   LogInfo("SignalEngine initialized: " + symbol + " LTF=" + EnumToString(lowerTF) + " HTF=" + EnumToString(higherTF));
   return true;
}

//+------------------------------------------------------------------+
//| Set scoring weights for signal components                         |
//+------------------------------------------------------------------+
void CSignalEngine::SetWeights(int emaW, int rsiW, int smcW)
{
   m_weightEMA = emaW;
   m_weightRSI = rsiW;
   m_weightSMC = smcW;
}

//+------------------------------------------------------------------+
//| Release indicator handles                                         |
//+------------------------------------------------------------------+
void CSignalEngine::Deinit()
{
   if(m_hEmaFastLower != INVALID_HANDLE)  { IndicatorRelease(m_hEmaFastLower);  m_hEmaFastLower = INVALID_HANDLE; }
   if(m_hEmaSlowLower != INVALID_HANDLE)  { IndicatorRelease(m_hEmaSlowLower);  m_hEmaSlowLower = INVALID_HANDLE; }
   if(m_hEmaFastHigher != INVALID_HANDLE) { IndicatorRelease(m_hEmaFastHigher); m_hEmaFastHigher = INVALID_HANDLE; }
   if(m_hEmaSlowHigher != INVALID_HANDLE) { IndicatorRelease(m_hEmaSlowHigher); m_hEmaSlowHigher = INVALID_HANDLE; }
   if(m_hRsi != INVALID_HANDLE)           { IndicatorRelease(m_hRsi);           m_hRsi = INVALID_HANDLE; }
   m_initialized = false;
}

//+------------------------------------------------------------------+
//| Get EMA trend score (-100 to +100)                                |
//+------------------------------------------------------------------+
int CSignalEngine::GetEMAScore()
{
   if(!m_initialized) return 0;

   double emaFastH[2], emaSlowH[2]; // Higher TF
   double emaFastL[2], emaSlowL[2]; // Lower TF

   if(CopyBuffer(m_hEmaFastHigher, 0, 0, 2, emaFastH) < 2) return 0;
   if(CopyBuffer(m_hEmaSlowHigher, 0, 0, 2, emaSlowH) < 2) return 0;
   if(CopyBuffer(m_hEmaFastLower, 0, 0, 2, emaFastL) < 2) return 0;
   if(CopyBuffer(m_hEmaSlowLower, 0, 0, 2, emaSlowL) < 2) return 0;

   double price = iClose(m_symbol, m_lowerTF, 0);
   int score = 0;

   // Higher timeframe trend (+/-40 points max)
   if(emaFastH[0] > emaSlowH[0] && price > emaFastH[0])
      score += 40;  // Strong bullish HTF
   else if(emaFastH[0] > emaSlowH[0])
      score += 20;  // Moderate bullish HTF
   else if(emaFastH[0] < emaSlowH[0] && price < emaFastH[0])
      score -= 40;  // Strong bearish HTF
   else if(emaFastH[0] < emaSlowH[0])
      score -= 20;  // Moderate bearish HTF

   // Lower timeframe alignment (+/-40 points max)
   if(emaFastL[0] > emaSlowL[0] && price > emaFastL[0])
      score += 40;
   else if(emaFastL[0] > emaSlowL[0])
      score += 20;
   else if(emaFastL[0] < emaSlowL[0] && price < emaFastL[0])
      score -= 40;
   else if(emaFastL[0] < emaSlowL[0])
      score -= 20;

   // EMA crossover bonus (+/-20 points)
   if(emaFastL[1] <= emaSlowL[1] && emaFastL[0] > emaSlowL[0])
      score += 20;  // Bullish crossover
   else if(emaFastL[1] >= emaSlowL[1] && emaFastL[0] < emaSlowL[0])
      score -= 20;  // Bearish crossover

   return MathMax(-100, MathMin(100, score));
}

//+------------------------------------------------------------------+
//| Get RSI score (-100 to +100)                                      |
//+------------------------------------------------------------------+
int CSignalEngine::GetRSIScore()
{
   if(!m_initialized) return 0;

   double rsi[3];
   if(CopyBuffer(m_hRsi, 0, 0, 3, rsi) < 3) return 0;

   int score = 0;

   // Oversold condition (bullish)
   if(rsi[0] < m_rsiOversold)
      score += 60;
   else if(rsi[0] < 40)
      score += 30;

   // Overbought condition (bearish)
   if(rsi[0] > m_rsiOverbought)
      score -= 60;
   else if(rsi[0] > 60)
      score -= 30;

   // RSI momentum direction
   if(rsi[0] > rsi[1] && rsi[1] > rsi[2])
      score += 20;  // Rising RSI
   else if(rsi[0] < rsi[1] && rsi[1] < rsi[2])
      score -= 20;  // Falling RSI

   // Divergence bonus
   if(DetectRSIDivergence(true))
      score += 20;
   if(DetectRSIDivergence(false))
      score -= 20;

   return MathMax(-100, MathMin(100, score));
}

//+------------------------------------------------------------------+
//| Get SMC confluence score (-100 to +100)                           |
//+------------------------------------------------------------------+
int CSignalEngine::GetSMCScore()
{
   if(m_smcAnalysis == NULL) return 0;

   double price = iClose(m_symbol, m_lowerTF, 0);
   int score = 0;
   bool isBullish = false;

   // Order Block confluence
   if(m_smcAnalysis.IsPriceAtOrderBlock(price, isBullish))
   {
      score += isBullish ? 40 : -40;
   }

   // FVG fill
   if(m_smcAnalysis.IsPriceInFVG(price, isBullish))
   {
      score += isBullish ? 30 : -30;
   }

   // Liquidity sweep
   if(m_smcAnalysis.IsLiquiditySweep(price))
   {
      // After sweep, expect reversal
      if(m_smcAnalysis.IsBullishStructure())
         score += 30;
      else
         score -= 30;
   }

   // Structure alignment
   if(m_smcAnalysis.HasBOS())
   {
      score += m_smcAnalysis.IsBullishStructure() ? 20 : -20;
   }
   if(m_smcAnalysis.HasCHoCH())
   {
      score += m_smcAnalysis.IsBullishStructure() ? 25 : -25;
   }

   // Premium/Discount zone
   if(m_smcAnalysis.IsInDiscountZone(price))
      score += 10;  // Favor buys in discount
   else if(m_smcAnalysis.IsInPremiumZone(price))
      score -= 10;  // Favor sells in premium

   return MathMax(-100, MathMin(100, score));
}

//+------------------------------------------------------------------+
//| Detect RSI divergence                                             |
//| Bullish: price makes lower low but RSI makes higher low           |
//| Bearish: price makes higher high but RSI makes lower high         |
//+------------------------------------------------------------------+
bool CSignalEngine::DetectRSIDivergence(bool bullish)
{
   if(!m_initialized) return false;

   double rsi[20];
   if(CopyBuffer(m_hRsi, 0, 0, 20, rsi) < 20) return false;

   if(bullish)
   {
      // Check last 20 bars for bullish divergence
      double priceLow1 = iLow(m_symbol, m_lowerTF, 0);
      double priceLow2 = iLow(m_symbol, m_lowerTF, 10);
      double rsiLow1 = rsi[0];
      double rsiLow2 = rsi[10];

      // Price lower low, RSI higher low = bullish divergence
      if(priceLow1 < priceLow2 && rsiLow1 > rsiLow2)
         return true;
   }
   else
   {
      // Check for bearish divergence
      double priceHigh1 = iHigh(m_symbol, m_lowerTF, 0);
      double priceHigh2 = iHigh(m_symbol, m_lowerTF, 10);
      double rsiHigh1 = rsi[0];
      double rsiHigh2 = rsi[10];

      // Price higher high, RSI lower high = bearish divergence
      if(priceHigh1 > priceHigh2 && rsiHigh1 < rsiHigh2)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check for EMA crossover on given timeframe                        |
//+------------------------------------------------------------------+
bool CSignalEngine::CheckEMACrossover(ENUM_TIMEFRAMES tf, int handleFast, int handleSlow)
{
   double fast[2], slow[2];
   if(CopyBuffer(handleFast, 0, 0, 2, fast) < 2) return false;
   if(CopyBuffer(handleSlow, 0, 0, 2, slow) < 2) return false;

   // Crossover: fast was below slow, now above
   return (fast[1] <= slow[1] && fast[0] > slow[0]);
}

//+------------------------------------------------------------------+
//| Generate composite trading signal                                 |
//+------------------------------------------------------------------+
SignalResult CSignalEngine::GenerateSignal()
{
   SignalResult result;
   result.signal = SIGNAL_NONE;
   result.strength = 0;
   result.emaConfirmed = false;
   result.rsiConfirmed = false;
   result.smcConfirmed = false;
   result.reason = "No signal";

   if(!m_initialized) return result;

   int emaScore = GetEMAScore();
   int rsiScore = GetRSIScore();
   int smcScore = GetSMCScore();

   // Weighted composite score
   double totalWeight = m_weightEMA + m_weightRSI + m_weightSMC;
   double compositeScore = (emaScore * m_weightEMA + rsiScore * m_weightRSI + smcScore * m_weightSMC) / totalWeight;

   result.strength = (int)MathAbs(compositeScore);
   result.emaConfirmed = (MathAbs(emaScore) > 40);
   result.rsiConfirmed = (MathAbs(rsiScore) > 30);
   result.smcConfirmed = (MathAbs(smcScore) > 30);

   // Minimum threshold for signal generation
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

   return result;
}

//+------------------------------------------------------------------+
//| Get overall EMA trend direction                                   |
//+------------------------------------------------------------------+
ENUM_SIGNAL_TYPE CSignalEngine::GetEMATrend()
{
   int score = GetEMAScore();
   if(score > 40) return SIGNAL_BUY;
   if(score < -40) return SIGNAL_SELL;
   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Check if RSI is in overbought territory                           |
//+------------------------------------------------------------------+
bool CSignalEngine::IsRSIOverbought()
{
   double rsi[1];
   if(CopyBuffer(m_hRsi, 0, 0, 1, rsi) < 1) return false;
   return (rsi[0] > m_rsiOverbought);
}

//+------------------------------------------------------------------+
//| Check if RSI is in oversold territory                             |
//+------------------------------------------------------------------+
bool CSignalEngine::IsRSIOversold()
{
   double rsi[1];
   if(CopyBuffer(m_hRsi, 0, 0, 1, rsi) < 1) return false;
   return (rsi[0] < m_rsiOversold);
}

//+------------------------------------------------------------------+
//| Get current RSI value                                             |
//+------------------------------------------------------------------+
double CSignalEngine::GetRSIValue()
{
   double rsi[1];
   if(CopyBuffer(m_hRsi, 0, 0, 1, rsi) < 1) return 50.0;
   return rsi[0];
}

//+------------------------------------------------------------------+
//| Check for bullish EMA crossover on lower TF                       |
//+------------------------------------------------------------------+
bool CSignalEngine::HasEMACrossoverUp()
{
   return CheckEMACrossover(m_lowerTF, m_hEmaFastLower, m_hEmaSlowLower);
}

//+------------------------------------------------------------------+
//| Check for bearish EMA crossover on lower TF                       |
//+------------------------------------------------------------------+
bool CSignalEngine::HasEMACrossoverDown()
{
   double fast[2], slow[2];
   if(CopyBuffer(m_hEmaFastLower, 0, 0, 2, fast) < 2) return false;
   if(CopyBuffer(m_hEmaSlowLower, 0, 0, 2, slow) < 2) return false;
   return (fast[1] >= slow[1] && fast[0] < slow[0]);
}

#endif // SIGNAL_ENGINE_MQH
