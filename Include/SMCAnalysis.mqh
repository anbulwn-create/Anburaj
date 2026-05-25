//+------------------------------------------------------------------+
//|                                                  SMCAnalysis.mqh  |
//|                    XAUUSD ProTrader EA - Smart Money Concepts     |
//+------------------------------------------------------------------+
#ifndef SMC_ANALYSIS_MQH
#define SMC_ANALYSIS_MQH

#include "Utils.mqh"

//+------------------------------------------------------------------+
//| SMC Zone structure for storing detected zones                     |
//+------------------------------------------------------------------+
struct SMCZone
{
   double            priceHigh;      // Zone upper boundary
   double            priceLow;       // Zone lower boundary
   datetime          timeCreated;    // When zone was identified
   int               touchCount;     // Times price revisited
   bool              isValid;        // Zone still active
   bool              isBullish;      // Zone direction
   int               strength;       // Zone strength 1-10
};

//+------------------------------------------------------------------+
//| Structure for Break of Structure / CHoCH detection               |
//+------------------------------------------------------------------+
struct StructurePoint
{
   double            price;
   datetime          time;
   bool              isHigh;         // true = swing high, false = swing low
   int               barIndex;
};

//+------------------------------------------------------------------+
//| CSMCAnalysis - Smart Money Concepts Analysis Engine               |
//+------------------------------------------------------------------+
class CSMCAnalysis
{
private:
   //--- Configuration
   int               m_lookbackBars;       // Bars to analyze
   int               m_swingStrength;      // Swing point sensitivity
   int               m_maxZones;           // Maximum stored zones
   int               m_zoneExpiryBars;     // Bars before zone expires
   ENUM_TIMEFRAMES   m_timeframe;          // Analysis timeframe
   string            m_symbol;             // Trading symbol

   //--- Zone storage
   SMCZone           m_orderBlocks[];      // Detected order blocks
   SMCZone           m_fvgZones[];         // Fair value gaps
   SMCZone           m_liquidityPools[];   // Liquidity pools
   StructurePoint    m_swingPoints[];      // Swing high/low points

   //--- Structure tracking
   double            m_lastSwingHigh;
   double            m_lastSwingLow;
   bool              m_isBullishStructure;
   bool              m_bosDetected;
   bool              m_chochDetected;

   //--- Internal methods
   bool              IsSwingHigh(int index, int strength);
   bool              IsSwingLow(int index, int strength);
   void              DetectSwingPoints();
   void              InvalidateExpiredZones();
   double            GetRangeHigh(int bars);
   double            GetRangeLow(int bars);

public:
                     CSMCAnalysis();
                    ~CSMCAnalysis();

   //--- Initialization
   bool              Init(string symbol, ENUM_TIMEFRAMES tf, int lookback = 100,
                          int swingStr = 3, int maxZones = 20, int expiryBars = 500);

   //--- Main analysis update (call on new bar)
   void              Update();

   //--- Order Block detection
   void              DetectOrderBlocks();
   bool              IsPriceAtOrderBlock(double price, bool &isBullish);
   int               GetOrderBlockCount() { return ArraySize(m_orderBlocks); }

   //--- Fair Value Gap detection
   void              DetectFairValueGaps();
   bool              IsPriceInFVG(double price, bool &isBullish);
   int               GetFVGCount() { return ArraySize(m_fvgZones); }

   //--- Liquidity detection
   void              DetectLiquidityPools();
   bool              IsLiquiditySweep(double price);
   int               GetLiquidityPoolCount() { return ArraySize(m_liquidityPools); }

   //--- Structure analysis
   bool              DetectBOS();
   bool              DetectCHoCH();
   bool              IsBullishStructure() { return m_isBullishStructure; }
   bool              HasBOS() { return m_bosDetected; }
   bool              HasCHoCH() { return m_chochDetected; }

   //--- Premium/Discount zones
   bool              IsInPremiumZone(double price);
   bool              IsInDiscountZone(double price);
   double            GetEquilibriumPrice();

   //--- Getters
   double            GetLastSwingHigh() { return m_lastSwingHigh; }
   double            GetLastSwingLow() { return m_lastSwingLow; }
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CSMCAnalysis::~CSMCAnalysis()
{
   ArrayFree(m_orderBlocks);
   ArrayFree(m_fvgZones);
   ArrayFree(m_liquidityPools);
   ArrayFree(m_swingPoints);
}

//+------------------------------------------------------------------+
//| Initialize the SMC analysis engine                                |
//+------------------------------------------------------------------+
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

   LogInfo("SMC Analysis initialized: " + symbol + " " + EnumToString(tf));
   return true;
}

//+------------------------------------------------------------------+
//| Check if bar at index is a swing high                             |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Check if bar at index is a swing low                              |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Detect and store swing points                                     |
//+------------------------------------------------------------------+
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

   // Update last swing high/low
   for(int i = 0; i < count; i++)
   {
      if(m_swingPoints[i].isHigh && (m_lastSwingHigh == 0 || m_swingPoints[i].barIndex < 10))
         m_lastSwingHigh = m_swingPoints[i].price;
      if(!m_swingPoints[i].isHigh && (m_lastSwingLow == 0 || m_swingPoints[i].barIndex < 10))
         m_lastSwingLow = m_swingPoints[i].price;
   }
}

//+------------------------------------------------------------------+
//| Invalidate expired zones                                          |
//+------------------------------------------------------------------+
void CSMCAnalysis::InvalidateExpiredZones()
{
   datetime expiryTime = iTime(m_symbol, m_timeframe, m_zoneExpiryBars);

   for(int i = ArraySize(m_orderBlocks) - 1; i >= 0; i--)
   {
      if(m_orderBlocks[i].timeCreated < expiryTime)
         m_orderBlocks[i].isValid = false;
   }
   for(int i = ArraySize(m_fvgZones) - 1; i >= 0; i--)
   {
      if(m_fvgZones[i].timeCreated < expiryTime)
         m_fvgZones[i].isValid = false;
   }
}

//+------------------------------------------------------------------+
//| Get range high over N bars                                        |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Get range low over N bars                                         |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Main update method - call on each new bar                         |
//+------------------------------------------------------------------+
void CSMCAnalysis::Update()
{
   DetectSwingPoints();
   DetectOrderBlocks();
   DetectFairValueGaps();
   DetectLiquidityPools();
   DetectBOS();
   DetectCHoCH();
   InvalidateExpiredZones();
}

//+------------------------------------------------------------------+
//| Detect Order Blocks                                               |
//| Bullish OB: last bearish candle before a strong bullish move      |
//| Bearish OB: last bullish candle before a strong bearish move      |
//+------------------------------------------------------------------+
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

      // Bullish Order Block: bearish candle followed by strong bullish move
      if(close_i < open_i && close_next > open_next)
      {
         // Next candle must be significantly larger (impulse move)
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

      // Bearish Order Block: bullish candle followed by strong bearish move
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

//+------------------------------------------------------------------+
//| Check if price is at an active order block                        |
//+------------------------------------------------------------------+
bool CSMCAnalysis::IsPriceAtOrderBlock(double price, bool &isBullish)
{
   for(int i = 0; i < ArraySize(m_orderBlocks); i++)
   {
      if(!m_orderBlocks[i].isValid) continue;

      if(price >= m_orderBlocks[i].priceLow && price <= m_orderBlocks[i].priceHigh)
      {
         isBullish = m_orderBlocks[i].isBullish;
         m_orderBlocks[i].touchCount++;
         // Invalidate after 3 touches
         if(m_orderBlocks[i].touchCount >= 3)
            m_orderBlocks[i].isValid = false;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Detect Fair Value Gaps (3-candle imbalance patterns)              |
//| Bullish FVG: gap between candle 1 high and candle 3 low          |
//| Bearish FVG: gap between candle 1 low and candle 3 high          |
//+------------------------------------------------------------------+
void CSMCAnalysis::DetectFairValueGaps()
{
   ArrayResize(m_fvgZones, 0);
   int count = 0;

   for(int i = 1; i < m_lookbackBars - 2; i++)
   {
      double high1 = iHigh(m_symbol, m_timeframe, i + 1);  // First candle
      double low1  = iLow(m_symbol, m_timeframe, i + 1);
      double high3 = iHigh(m_symbol, m_timeframe, i - 1);  // Third candle
      double low3  = iLow(m_symbol, m_timeframe, i - 1);

      double close2 = iClose(m_symbol, m_timeframe, i);     // Middle candle
      double open2  = iOpen(m_symbol, m_timeframe, i);

      // Bullish FVG: low of candle 3 is above high of candle 1
      if(low3 > high1 && close2 > open2)
      {
         SMCZone fvg;
         fvg.priceLow = high1;
         fvg.priceHigh = low3;
         fvg.timeCreated = iTime(m_symbol, m_timeframe, i);
         fvg.touchCount = 0;
         fvg.isValid = true;
         fvg.isBullish = true;
         fvg.strength = (int)MathMin(10, PriceToPips(low3 - high1));

         if(count < m_maxZones)
         {
            ArrayResize(m_fvgZones, count + 1);
            m_fvgZones[count] = fvg;
            count++;
         }
      }

      // Bearish FVG: high of candle 3 is below low of candle 1
      if(high3 < low1 && close2 < open2)
      {
         SMCZone fvg;
         fvg.priceLow = high3;
         fvg.priceHigh = low1;
         fvg.timeCreated = iTime(m_symbol, m_timeframe, i);
         fvg.touchCount = 0;
         fvg.isValid = true;
         fvg.isBullish = false;
         fvg.strength = (int)MathMin(10, PriceToPips(low1 - high3));

         if(count < m_maxZones)
         {
            ArrayResize(m_fvgZones, count + 1);
            m_fvgZones[count] = fvg;
            count++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if price is within a Fair Value Gap                         |
//+------------------------------------------------------------------+
bool CSMCAnalysis::IsPriceInFVG(double price, bool &isBullish)
{
   for(int i = 0; i < ArraySize(m_fvgZones); i++)
   {
      if(!m_fvgZones[i].isValid) continue;

      if(price >= m_fvgZones[i].priceLow && price <= m_fvgZones[i].priceHigh)
      {
         isBullish = m_fvgZones[i].isBullish;
         // FVG is filled once price passes through
         m_fvgZones[i].isValid = false;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Detect Liquidity Pools (equal highs/lows, swing clusters)        |
//+------------------------------------------------------------------+
void CSMCAnalysis::DetectLiquidityPools()
{
   ArrayResize(m_liquidityPools, 0);
   int count = 0;
   double tolerance = PipsToPrice(5.0); // 5 pips tolerance for "equal" levels

   // Find equal highs (buy-side liquidity)
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
            lp.isBullish = false; // Liquidity above = target for sells
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

   // Find equal lows (sell-side liquidity)
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
            lp.isBullish = true; // Liquidity below = target for buys
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

//+------------------------------------------------------------------+
//| Check if a liquidity sweep has occurred                           |
//| A sweep occurs when price briefly pierces a liquidity level       |
//| then reverses back                                                |
//+------------------------------------------------------------------+
bool CSMCAnalysis::IsLiquiditySweep(double price)
{
   double currentHigh = iHigh(m_symbol, m_timeframe, 0);
   double currentLow  = iLow(m_symbol, m_timeframe, 0);
   double prevClose   = iClose(m_symbol, m_timeframe, 1);

   for(int i = 0; i < ArraySize(m_liquidityPools); i++)
   {
      if(!m_liquidityPools[i].isValid) continue;

      // Buy-side liquidity sweep: price spiked above then reversed below
      if(!m_liquidityPools[i].isBullish)
      {
         if(currentHigh > m_liquidityPools[i].priceHigh && price < m_liquidityPools[i].priceLow)
         {
            m_liquidityPools[i].isValid = false;
            return true;
         }
      }
      // Sell-side liquidity sweep: price spiked below then reversed above
      else
      {
         if(currentLow < m_liquidityPools[i].priceLow && price > m_liquidityPools[i].priceHigh)
         {
            m_liquidityPools[i].isValid = false;
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Detect Break of Structure (BOS)                                   |
//| BOS occurs when price breaks a swing high/low in trend direction  |
//+------------------------------------------------------------------+
bool CSMCAnalysis::DetectBOS()
{
   m_bosDetected = false;
   double currentClose = iClose(m_symbol, m_timeframe, 0);

   if(m_lastSwingHigh == 0 || m_lastSwingLow == 0) return false;

   // Bullish BOS: price closes above last swing high
   if(m_isBullishStructure && currentClose > m_lastSwingHigh)
   {
      m_bosDetected = true;
      LogDebug("Bullish BOS detected - price broke above " + DoubleToString(m_lastSwingHigh, 2));
      return true;
   }

   // Bearish BOS: price closes below last swing low
   if(!m_isBullishStructure && currentClose < m_lastSwingLow)
   {
      m_bosDetected = true;
      LogDebug("Bearish BOS detected - price broke below " + DoubleToString(m_lastSwingLow, 2));
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Detect Change of Character (CHoCH)                                |
//| CHoCH is the first sign of reversal - break against current trend |
//+------------------------------------------------------------------+
bool CSMCAnalysis::DetectCHoCH()
{
   m_chochDetected = false;
   double currentClose = iClose(m_symbol, m_timeframe, 0);

   if(m_lastSwingHigh == 0 || m_lastSwingLow == 0) return false;

   // Bullish CHoCH: was bearish, now breaks above swing high
   if(!m_isBullishStructure && currentClose > m_lastSwingHigh)
   {
      m_chochDetected = true;
      m_isBullishStructure = true;
      LogDebug("Bullish CHoCH detected - structure shift to bullish");
      return true;
   }

   // Bearish CHoCH: was bullish, now breaks below swing low
   if(m_isBullishStructure && currentClose < m_lastSwingLow)
   {
      m_chochDetected = true;
      m_isBullishStructure = false;
      LogDebug("Bearish CHoCH detected - structure shift to bearish");
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check if price is in premium zone (above 50% of range)           |
//+------------------------------------------------------------------+
bool CSMCAnalysis::IsInPremiumZone(double price)
{
   double equilibrium = GetEquilibriumPrice();
   return (price > equilibrium);
}

//+------------------------------------------------------------------+
//| Check if price is in discount zone (below 50% of range)          |
//+------------------------------------------------------------------+
bool CSMCAnalysis::IsInDiscountZone(double price)
{
   double equilibrium = GetEquilibriumPrice();
   return (price < equilibrium);
}

//+------------------------------------------------------------------+
//| Get equilibrium price (50% of range)                              |
//+------------------------------------------------------------------+
double CSMCAnalysis::GetEquilibriumPrice()
{
   double rangeHigh = GetRangeHigh(m_lookbackBars);
   double rangeLow  = GetRangeLow(m_lookbackBars);
   return (rangeHigh + rangeLow) / 2.0;
}

#endif // SMC_ANALYSIS_MQH
