//+------------------------------------------------------------------+
//|                                                   NewsFilter.mqh  |
//|                    XAUUSD ProTrader EA - News Event Filter        |
//+------------------------------------------------------------------+
#ifndef NEWS_FILTER_MQH
#define NEWS_FILTER_MQH

#include "Utils.mqh"

//+------------------------------------------------------------------+
//| News event structure                                              |
//+------------------------------------------------------------------+
struct NewsEvent
{
   string            name;           // Event name
   int               dayOfWeek;      // Day of week (1=Mon ... 5=Fri)
   int               weekOfMonth;    // Week of month (1-5, 0=every week)
   int               hour;           // Hour (server time)
   int               minute;         // Minute
   int               impact;         // Impact level 1-3 (3=highest)
};

//+------------------------------------------------------------------+
//| Custom blackout period                                            |
//+------------------------------------------------------------------+
struct BlackoutPeriod
{
   datetime          startTime;
   datetime          endTime;
   string            reason;
};

//+------------------------------------------------------------------+
//| CNewsFilter - Filters trading around high-impact news events     |
//+------------------------------------------------------------------+
class CNewsFilter
{
private:
   //--- Configuration
   bool              m_enabled;
   int               m_minutesBefore;      // Minutes before news to stop trading
   int               m_minutesAfter;       // Minutes after news to resume
   bool              m_filterFriday;       // Avoid Friday trading
   bool              m_filterMonday;       // Avoid Monday open
   int               m_mondayStartHour;    // Hour to start trading on Monday
   int               m_fridayEndHour;      // Hour to stop trading on Friday

   //--- Day of week filter
   bool              m_tradeDays[7];       // Sun=0 through Sat=6

   //--- Built-in news schedule
   NewsEvent         m_newsSchedule[];
   int               m_newsCount;

   //--- Custom blackout periods
   BlackoutPeriod    m_customBlackouts[];
   int               m_blackoutCount;

   //--- State
   bool              m_inBlackout;
   string            m_blackoutReason;
   datetime          m_blackoutEnd;

   //--- Internal methods
   void              BuildNewsSchedule();
   bool              IsNearScheduledNews();
   bool              IsInCustomBlackout();
   int               GetWeekOfMonth();

public:
                     CNewsFilter();
                    ~CNewsFilter();

   //--- Initialization
   bool              Init(bool enabled, int minBefore = 30, int minAfter = 15);
   void              SetDayFilter(bool sun, bool mon, bool tue, bool wed,
                                   bool thu, bool fri, bool sat);
   void              SetFridayFilter(bool enable, int endHour = 20);
   void              SetMondayFilter(bool enable, int startHour = 3);

   //--- Custom blackout management
   void              AddBlackout(datetime start, datetime end, string reason);
   void              ClearBlackouts();

   //--- Main filter check
   bool              IsNewsTime();
   bool              IsTradingAllowed();

   //--- Getters
   bool              IsEnabled() { return m_enabled; }
   bool              IsInBlackout() { return m_inBlackout; }
   string            GetBlackoutReason() { return m_blackoutReason; }
   void              SetEnabled(bool enable) { m_enabled = enable; }
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
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

   // Default: trade Mon-Fri
   m_tradeDays[0] = false;  // Sunday
   m_tradeDays[1] = true;   // Monday
   m_tradeDays[2] = true;   // Tuesday
   m_tradeDays[3] = true;   // Wednesday
   m_tradeDays[4] = true;   // Thursday
   m_tradeDays[5] = true;   // Friday
   m_tradeDays[6] = false;  // Saturday
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CNewsFilter::~CNewsFilter()
{
   ArrayFree(m_newsSchedule);
   ArrayFree(m_customBlackouts);
}

//+------------------------------------------------------------------+
//| Initialize news filter                                            |
//+------------------------------------------------------------------+
bool CNewsFilter::Init(bool enabled, int minBefore, int minAfter)
{
   m_enabled = enabled;
   m_minutesBefore = minBefore;
   m_minutesAfter = minAfter;

   BuildNewsSchedule();

   LogInfo(StringFormat("NewsFilter initialized: enabled=%s before=%dmin after=%dmin",
           enabled ? "true" : "false", minBefore, minAfter));
   return true;
}

//+------------------------------------------------------------------+
//| Set day-of-week trading filter                                    |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Set Friday trading filter                                         |
//+------------------------------------------------------------------+
void CNewsFilter::SetFridayFilter(bool enable, int endHour)
{
   m_filterFriday = enable;
   m_fridayEndHour = endHour;
}

//+------------------------------------------------------------------+
//| Set Monday trading filter                                         |
//+------------------------------------------------------------------+
void CNewsFilter::SetMondayFilter(bool enable, int startHour)
{
   m_filterMonday = enable;
   m_mondayStartHour = startHour;
}

//+------------------------------------------------------------------+
//| Add custom blackout period                                        |
//+------------------------------------------------------------------+
void CNewsFilter::AddBlackout(datetime start, datetime end, string reason)
{
   ArrayResize(m_customBlackouts, m_blackoutCount + 1);
   m_customBlackouts[m_blackoutCount].startTime = start;
   m_customBlackouts[m_blackoutCount].endTime = end;
   m_customBlackouts[m_blackoutCount].reason = reason;
   m_blackoutCount++;
}

//+------------------------------------------------------------------+
//| Clear all custom blackout periods                                 |
//+------------------------------------------------------------------+
void CNewsFilter::ClearBlackouts()
{
   ArrayResize(m_customBlackouts, 0);
   m_blackoutCount = 0;
}

//+------------------------------------------------------------------+
//| Build the built-in high-impact USD news schedule                  |
//| Times are approximate and based on typical US EST schedule        |
//| Adjusted to server time (GMT+2/+3 typical broker)                |
//+------------------------------------------------------------------+
void CNewsFilter::BuildNewsSchedule()
{
   // Major recurring USD events (times in server hours, GMT+2)
   // Week 0 = any week, specific weeks for monthly events

   NewsEvent events[];
   int count = 0;

   // NFP - Non-Farm Payrolls (First Friday of month, 15:30 GMT+2)
   ArrayResize(events, count + 1);
   events[count].name = "NFP";
   events[count].dayOfWeek = 5;    // Friday
   events[count].weekOfMonth = 1;  // First week
   events[count].hour = 15;
   events[count].minute = 30;
   events[count].impact = 3;
   count++;

   // FOMC Rate Decision (Wednesday, varies - typically week 3-4, 21:00 GMT+2)
   ArrayResize(events, count + 1);
   events[count].name = "FOMC";
   events[count].dayOfWeek = 3;    // Wednesday
   events[count].weekOfMonth = 3;
   events[count].hour = 21;
   events[count].minute = 0;
   events[count].impact = 3;
   count++;

   // CPI - Consumer Price Index (Tuesday/Wednesday, week 2, 15:30 GMT+2)
   ArrayResize(events, count + 1);
   events[count].name = "CPI";
   events[count].dayOfWeek = 3;
   events[count].weekOfMonth = 2;
   events[count].hour = 15;
   events[count].minute = 30;
   events[count].impact = 3;
   count++;

   // PPI - Producer Price Index (Tuesday/Thursday, week 2, 15:30)
   ArrayResize(events, count + 1);
   events[count].name = "PPI";
   events[count].dayOfWeek = 4;
   events[count].weekOfMonth = 2;
   events[count].hour = 15;
   events[count].minute = 30;
   events[count].impact = 2;
   count++;

   // Retail Sales (Tuesday, week 2-3, 15:30)
   ArrayResize(events, count + 1);
   events[count].name = "Retail Sales";
   events[count].dayOfWeek = 2;
   events[count].weekOfMonth = 3;
   events[count].hour = 15;
   events[count].minute = 30;
   events[count].impact = 2;
   count++;

   // Initial Jobless Claims (Every Thursday, 15:30)
   ArrayResize(events, count + 1);
   events[count].name = "Jobless Claims";
   events[count].dayOfWeek = 4;
   events[count].weekOfMonth = 0;  // Every week
   events[count].hour = 15;
   events[count].minute = 30;
   events[count].impact = 2;
   count++;

   // ISM Manufacturing PMI (First business day of month, 17:00)
   ArrayResize(events, count + 1);
   events[count].name = "ISM Manufacturing";
   events[count].dayOfWeek = 1;
   events[count].weekOfMonth = 1;
   events[count].hour = 17;
   events[count].minute = 0;
   events[count].impact = 2;
   count++;

   // GDP (Thursday, week 4, 15:30)
   ArrayResize(events, count + 1);
   events[count].name = "GDP";
   events[count].dayOfWeek = 4;
   events[count].weekOfMonth = 4;
   events[count].hour = 15;
   events[count].minute = 30;
   events[count].impact = 3;
   count++;

   // Fed Chair Speech (various, but typically major impact)
   ArrayResize(events, count + 1);
   events[count].name = "Fed Speech";
   events[count].dayOfWeek = 3;
   events[count].weekOfMonth = 2;
   events[count].hour = 18;
   events[count].minute = 0;
   events[count].impact = 3;
   count++;

   // Core PCE Price Index (Last Friday of month, 15:30)
   ArrayResize(events, count + 1);
   events[count].name = "Core PCE";
   events[count].dayOfWeek = 5;
   events[count].weekOfMonth = 4;
   events[count].hour = 15;
   events[count].minute = 30;
   events[count].impact = 3;
   count++;

   // ADP Employment (Wednesday before NFP, 15:15)
   ArrayResize(events, count + 1);
   events[count].name = "ADP Employment";
   events[count].dayOfWeek = 3;
   events[count].weekOfMonth = 1;
   events[count].hour = 15;
   events[count].minute = 15;
   events[count].impact = 2;
   count++;

   // Copy to member array
   ArrayResize(m_newsSchedule, count);
   for(int i = 0; i < count; i++)
      m_newsSchedule[i] = events[i];
   m_newsCount = count;

   ArrayFree(events);
}

//+------------------------------------------------------------------+
//| Get current week of month (1-5)                                   |
//+------------------------------------------------------------------+
int CNewsFilter::GetWeekOfMonth()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return ((dt.day - 1) / 7) + 1;
}

//+------------------------------------------------------------------+
//| Check if near a scheduled news event                              |
//+------------------------------------------------------------------+
bool CNewsFilter::IsNearScheduledNews()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentWeek = GetWeekOfMonth();
   int currentMinutes = dt.hour * 60 + dt.min;

   for(int i = 0; i < m_newsCount; i++)
   {
      // Check day of week matches
      if(m_newsSchedule[i].dayOfWeek != dt.day_of_week) continue;

      // Check week of month (0 = every week)
      if(m_newsSchedule[i].weekOfMonth != 0 && m_newsSchedule[i].weekOfMonth != currentWeek)
         continue;

      // Calculate minutes until/since event
      int eventMinutes = m_newsSchedule[i].hour * 60 + m_newsSchedule[i].minute;
      int diff = currentMinutes - eventMinutes;

      // Within blackout window?
      if(diff >= -m_minutesBefore && diff <= m_minutesAfter)
      {
         m_blackoutReason = StringFormat("Near %s event (impact=%d)",
                            m_newsSchedule[i].name, m_newsSchedule[i].impact);
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check if within a custom blackout period                          |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Check if currently in a news blackout period                      |
//+------------------------------------------------------------------+
bool CNewsFilter::IsNewsTime()
{
   if(!m_enabled) return false;

   m_inBlackout = false;
   m_blackoutReason = "";

   // Check scheduled news
   if(IsNearScheduledNews())
   {
      m_inBlackout = true;
      return true;
   }

   // Check custom blackouts
   if(IsInCustomBlackout())
   {
      m_inBlackout = true;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Master check: is trading allowed right now?                       |
//| Combines news filter + day filter + time restrictions             |
//+------------------------------------------------------------------+
bool CNewsFilter::IsTradingAllowed()
{
   if(!m_enabled) return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // Day of week filter
   if(!m_tradeDays[dt.day_of_week])
   {
      m_inBlackout = true;
      m_blackoutReason = "Trading disabled for this day of week";
      return false;
   }

   // Monday morning filter
   if(m_filterMonday && dt.day_of_week == 1 && dt.hour < m_mondayStartHour)
   {
      m_inBlackout = true;
      m_blackoutReason = StringFormat("Monday filter: waiting until %d:00", m_mondayStartHour);
      return false;
   }

   // Friday evening filter
   if(m_filterFriday && dt.day_of_week == 5 && dt.hour >= m_fridayEndHour)
   {
      m_inBlackout = true;
      m_blackoutReason = StringFormat("Friday filter: trading stopped at %d:00", m_fridayEndHour);
      return false;
   }

   // News event check
   if(IsNewsTime())
      return false;

   m_inBlackout = false;
   m_blackoutReason = "";
   return true;
}

#endif // NEWS_FILTER_MQH
