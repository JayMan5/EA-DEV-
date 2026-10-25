//+------------------------------------------------------------------+
//|                                                     Tradie.mq5   |
//|  Tradie — "01C Trading Checklist" implemented as an MT5 EA       |
//|                                                                  |
//|  PURPOSE: research / validation only. Backtest in the Strategy   |
//|  Tester and forward-test on demo. This is NOT the production     |
//|  system described in docs/Tradie PRD v2.md (no reconciliation,   |
//|  no durable setup state, no circuit-breaker persistence).        |
//|                                                                  |
//|  RULES (ratified, see docs/decisions.md):                        |
//|   R1 Bias            D1 swing-leg, D authoritative               |
//|   R2 Liquidity sweep M15, ATR-relative penetration + reclaim     |
//|   R3a Structure      H1 efficiency ratio + swing density + range |
//|   R3b MSS            close beyond intervening swing + disp.      |
//|   R4 Retrace         50% of PRIOR IMPULSE (option C), 45-55%     |
//|   R5 Confirmation    full-range engulf inside POI (OB and FVG)   |
//|   R6 Risk            fixed risk %, SL beyond sweep, TP at 1:3    |
//|   R7 Alignment       assertion (direction == bias)               |
//|   R8 Mental state    NOT automatable - omitted (see README)      |
//|   R9 Trade limit     max 3 per day, 07:00-16:00 UTC only         |
//|                                                                  |
//|  STATUS: not compiled by the author. If MetaEditor reports an     |
//|  error, quote the line number and it will be fixed.              |
//+------------------------------------------------------------------+
#property copyright "Tradie"
#property link      ""
#property version   "0.10"
#property description "Tradie checklist EA - 9-rule forex model (research/testing)"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//==================================================================
//  INPUTS
//==================================================================
enum ENUM_RETRACE_ANCHOR
  {
   RETRACE_PRIOR_IMPULSE     = 0,  // C: most recent swing -> sweep extreme (RATIFIED)
   RETRACE_DISPLACEMENT_LEG  = 1,  // A: sweep extreme -> MSS close
  };

input group             "=== Identity ==="
input long              InpMagic              = 20261025;   // Magic number (shared across charts)
input bool              InpDryRun             = false;      // Dry run: log signals, send no orders

input group             "=== Risk (R6) ==="
input double            InpRiskPercent        = 0.75;       // Risk per trade (% of balance)
input double            InpRewardRisk         = 3.0;        // Target RR (RATIFIED D-09 = 1:3)
input double            InpMinSLPips          = 8.0;        // Minimum SL distance (pips)
input double            InpMaxSLATR           = 3.0;        // Max SL as multiple of M15 ATR
input double            InpSLBufferATR        = 0.15;       // SL buffer beyond sweep extreme (x ATR)
input double            InpSLBufferSpread     = 1.5;        // ...or this many spreads, whichever larger
input int               InpMaxConcurrent      = 2;          // Max simultaneous positions (all symbols)
input int               InpDailyTradeCap      = 3;          // R9: max trades per day

input group             "=== Sessions (R9 / D-10) ==="
input bool              InpSessionFilter      = true;       // Restrict entries to a UTC window
input int               InpSessionStartUTC    = 7;          // Entry window start (UTC hour)
input int               InpSessionEndUTC      = 16;         // Entry window end (UTC hour)
input bool              InpAutoGMTOffset      = true;       // Auto-detect server GMT offset
input int               InpGMTOffsetHours     = 2;          // Manual server offset if auto fails
input bool              InpFridayFlatten      = true;       // Close all before the weekend
input int               InpFridayFlattenUTC   = 20;         // Friday flatten hour (UTC)

input group             "=== R1 Bias ==="
input ENUM_TIMEFRAMES   InpBiasTF             = PERIOD_D1;  // Bias timeframe
input int               InpBiasSwingLeft      = 3;          // HTF swing left bars
input int               InpBiasSwingRight     = 3;          // HTF swing right bars

input group             "=== R2 Sweep ==="
input int               InpSweepLookback      = 48;         // Bars to look back for levels
input int               InpSweepFreshness     = 8;          // Sweep must be this recent (bars)
input double            InpPenetrationMinATR  = 0.05;       // Min penetration (x ATR)
input double            InpPenetrationMaxATR  = 0.60;       // Max penetration (x ATR)
input int               InpReclaimBars        = 2;          // Bars allowed to close back inside
input bool              InpUsePriorDayLevel   = true;       // Prior-day high/low count as levels

input group             "=== R3 Structure ==="
input ENUM_TIMEFRAMES   InpStructureTF        = PERIOD_H1;  // Structure timeframe
input int               InpERBars             = 20;         // Efficiency ratio window
input double            InpERMin              = 0.30;       // Min efficiency ratio
input int               InpMaxSwingDensity    = 6;          // Max swings in the ER window
input double            InpMinRangeATR        = 2.0;        // Min 20-bar range as x ATR (0 = off)
input int               InpMSSSwing            = 2;         // M15 swing strength for MSS level
input int               InpMSSMaxBars         = 24;         // Bars allowed for the MSS
input double            InpMSSDisplacementATR = 0.5;        // Min displacement (x ATR)

input group             "=== R4 Retracement ==="
input ENUM_RETRACE_ANCHOR InpRetraceAnchor    = RETRACE_PRIOR_IMPULSE; // 50% of which leg
input double            InpZoneLow            = 0.45;       // Zone start (fraction of leg)
input double            InpZoneHigh           = 0.55;       // Zone end
input int               InpSetupTTLBars       = 96;         // Setup expires after N M15 bars

input group             "=== R5 POI / Confirmation ==="
input bool              InpRequireOB          = true;       // Require an order block
input bool              InpRequireFVG         = true;       // Require a fair value gap
input bool              InpRequireZoneTouch   = true;       // Price must tap the 50% zone first
input double            InpMinBodyRatio       = 0.50;       // Minimum engulf body / range
input double            InpMaxSpreadPoints    = 0.0;        // Max spread (points, 0 = no limit)
input int               InpSlippagePoints     = 20;         // Max deviation (points)

input group             "=== Execution ==="
input int               InpBarsM15            = 250;        // M15 bars to load

//==================================================================
//  GLOBALS
//==================================================================
CTrade        g_trade;
CPositionInfo g_pos;

double        g_pip      = 0.0;      // one pip in price
double        g_point    = 0.0;
int           g_digits   = 5;
int           g_gmtSec   = 0;        // server->UTC offset in seconds
datetime      g_lastBar  = 0;
string        g_why      = "";       // last rejection reason (for logging)
string        g_tag      = "";       // last diagnostic line
int           g_evaluations = 0;
int           g_rejections  = 0;

// last-traded setup guard (prevents re-firing the same sweep)
datetime      g_lastTradeBarTime = 0;
double        g_lastSweepExtreme  = 0.0;

// D-15 (ratified): the active setup is STICKY. A new sweep does not
// replace it; the new sweep is logged and ignored until the active
// setup is invalidated, expires, or the bias flips.
bool          g_haveSetup        = false;
datetime      g_stickySweepTime  = 0;
double        g_stickyExtreme    = 0.0;
double        g_stickyLevel      = 0.0;
int           g_stickyDir        = 0;

//==================================================================
//  forward declarations (MQL5 allows later definitions, but explicit
//  prototypes avoid any dependency on compiler ordering)
//==================================================================
bool   HasPositionOnSymbol();
int    CountOpenPositions();
int    CountTradesToday();
double CalcLots(double entry, double sl, double &riskMoneyOut);
bool   InEntrySession(datetime serverBarTime);
void   MaybeFlattenFriday();
bool   SendTrade(int dir, double entry, double sl, double tp, string note);
int    Evaluate(double &entryOut, double &slOut, double &tpOut, string &whyOut, string &tagOut);
int    FindSwings(const MqlRates &r[], int bars, int left, int right,
                  int &outIdx[], int &outKind[], double &outPx[]);
int    GetBias(int &biasIdxNew, double &biasPxNew, int &biasIdxOld, double &biasPxOld);
int    FindBarIndexByTime(const MqlRates &r[], int bars, datetime t);
bool   StickyValid(const MqlRates &r[], int bars, int bias, int &outIdx,
                   double &outExtreme, double &outLevel);
void   AdoptSticky(const MqlRates &r[], int sweepIdx, int bias, double extreme, double level);
void   ClearSticky();

//==================================================================
//  small helpers
//==================================================================
double PipSize()
  {
   int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(d == 3 || d == 5)
      return(pt * 10.0);
   return(pt);
  }

double SpreadPrice()
  {
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);   // points
   return((double)sp * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
  }

double SpreadPips()
  {
   if(g_pip <= 0.0)
      return(0.0);
   return(SpreadPrice() / g_pip);
  }

double ATR(int tf, int shift)
  {
   double v = iATR(_Symbol, (ENUM_TIMEFRAMES)tf, 14, shift);
   if(v <= 0.0)
      return(0.0);
   return(v);
  }

//--- is bar[1] a bullish full-range engulf of bar[2]?
bool IsBullEngulf(const MqlRates &r[], int i, double minBody)
  {
   double body  = r[i].close - r[i].open;
   double range = r[i].high - r[i].low;
   if(range <= 0.0 || body <= 0.0)
      return(false);
   if(r[i].close <= r[i + 1].high)     // must close above the prior bar's high
      return(false);
   if(r[i].open > r[i + 1].close)      // must open at or below the prior close
      return(false);
   if(body / range < minBody)
      return(false);
   return(true);
  }

//--- is bar[1] a bearish full-range engulf of bar[2]?
bool IsBearEngulf(const MqlRates &r[], int i, double minBody)
  {
   double body  = r[i].open - r[i].close;
   double range = r[i].high - r[i].low;
   if(range <= 0.0 || body <= 0.0)
      return(false);
   if(r[i].close >= r[i + 1].low)      // must close below the prior bar's low
      return(false);
   if(r[i].open < r[i + 1].close)      // must open at or above the prior close
      return(false);
   if(body / range < minBody)
      return(false);
   return(true);
  }

bool RangesOverlap(double aLo, double aHi, double bLo, double bHi)
  {
   if(aLo > aHi)
      return(false);
   if(bLo > bHi)
      return(false);
   return(aLo <= bHi && bLo <= aHi);
  }

//==================================================================
//  swing detection on a series-sorted rates array
//  index 0 = current forming bar; only completed bars are scanned.
//  kind: +1 high, -1 low. Returned newest-first (index 0 = most recent)
//==================================================================
int FindSwings(const MqlRates &r[], int bars, int left, int right,
               int &outIdx[], int &outKind[], double &outPx[])
  {
   ArrayResize(outIdx, 0);
   ArrayResize(outKind, 0);
   ArrayResize(outPx, 0);

   int found = 0;
   // start at right+1 so the "right" bars needed for confirmation exist
   for(int i = right + 1; i < bars - left; i++)
     {
      bool isHigh = true;
      bool isLow  = true;
      for(int k = 1; k <= left; k++)
        {
         if(r[i].high <= r[i + k].high)
            isHigh = false;
         if(r[i].low >= r[i + k].low)
            isLow = false;
        }
      for(int k = 1; k <= right; k++)
        {
         if(r[i].high <= r[i - k].high)
            isHigh = false;
         if(r[i].low >= r[i - k].low)
            isLow = false;
        }

      if(isHigh)
        {
         ArrayResize(outIdx, found + 1);
         ArrayResize(outKind, found + 1);
         ArrayResize(outPx, found + 1);
         outIdx[found]  = i;
         outKind[found] = 1;
         outPx[found]   = r[i].high;
         found++;
        }
      else
         if(isLow)
           {
            ArrayResize(outIdx, found + 1);
            ArrayResize(outKind, found + 1);
            ArrayResize(outPx, found + 1);
            outIdx[found]  = i;
            outKind[found] = -1;
            outPx[found]   = r[i].low;
            found++;
           }
     }
   return(found);
  }

//==================================================================
//  R1 — bias from the D1 (or configured) swing leg
//  returns +1 bullish, -1 bearish, 0 none
//==================================================================
int GetBias(int &biasIdxNew, double &biasPxNew, int &biasIdxOld, double &biasPxOld)
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int copied = CopyRates(_Symbol, InpBiasTF, 0, 60, r);
   if(copied < 30)
      return(0);

   int idx[], kind[];
   double px[];
   int n = FindSwings(r, copied, InpBiasSwingLeft, InpBiasSwingRight, idx, kind, px);
   if(n < 2)
      return(0);

   // most recent swing
   int newestKind = kind[0];

   // find the next older swing of the opposite kind
   for(int j = 1; j < n; j++)
     {
      if(kind[j] != newestKind)
        {
         biasIdxNew = idx[0];
         biasPxNew  = px[0];
         biasIdxOld = idx[j];
         biasPxOld  = px[j];

         // newest high + older low  => leg went low -> high => bullish
         if(newestKind == 1)
            return(1);
         return(-1);
        }
     }
   return(0);
  }

//==================================================================
//  R3a — structure quality on the structure timeframe
//==================================================================
bool StructureClean(string &why)
  {
   why = "";
   //--- efficiency ratio
   double c1 = iClose(_Symbol, InpStructureTF, 1);
   double cN = iClose(_Symbol, InpStructureTF, 1 + InpERBars);
   if(c1 <= 0.0 || cN <= 0.0)
     {
      why = "R3a: no structure data";
      return(false);
     }

   double net = MathAbs(c1 - cN);
   double sum = 0.0;
   for(int k = 1; k <= InpERBars; k++)
     {
      double a = iClose(_Symbol, InpStructureTF, k);
      double b = iClose(_Symbol, InpStructureTF, k + 1);
      if(a > 0.0 && b > 0.0)
         sum += MathAbs(a - b);
     }
   double er = (sum > 0.0) ? net / sum : 0.0;
   if(er < InpERMin)
     {
      why = StringFormat("R3a: ER %.2f < %.2f", er, InpERMin);
      return(false);
     }

   //--- swing density
   MqlRates s[];
   ArraySetAsSeries(s, true);
   int copiedS = CopyRates(_Symbol, InpStructureTF, 0, InpERBars + 10, s);
   if(copiedS > 10)
     {
      int idx[], kind[];
      double px[];
      int nsw = FindSwings(s, copiedS, 2, 2, idx, kind, px);
      int inWindow = 0;
      for(int j = 0; j < nsw; j++)
         if(idx[j] <= InpERBars)
            inWindow++;
      if(inWindow > InpMaxSwingDensity)
        {
         why = StringFormat("R3a: swing density %d > %d", inWindow, InpMaxSwingDensity);
         return(false);
        }
     }

   //--- range expansion: the owner's "a range is also choppy" condition
   if(InpMinRangeATR > 0.0)
     {
      double hi = -DBL_MAX;
      double lo =  DBL_MAX;
      for(int k = 1; k <= InpERBars; k++)
        {
         double h = iHigh(_Symbol, InpStructureTF, k);
         double l = iLow(_Symbol, InpStructureTF, k);
         if(h > hi)
            hi = h;
         if(l < lo)
            lo = l;
        }
      double atrH1 = iATR(_Symbol, InpStructureTF, 20, 1);
      if(atrH1 > 0.0 && hi > lo)
        {
         double ratio = (hi - lo) / atrH1;
         if(ratio < InpMinRangeATR)
           {
            why = StringFormat("R3a: range %.2fxATR < %.2f (ranging)", ratio, InpMinRangeATR);
            return(false);
           }
        }
     }

   return(true);
  }

//==================================================================
//  R4 — retracement zone from the chosen anchor
//==================================================================
void BuildZone(int anchorMode, double legStart, double legEnd, double &zLo, double &zHi)
  {
   // 50% of the leg, expressed as a band
   double lo = MathMin(legStart, legEnd);
   double hi = MathMax(legStart, legEnd);
   double len = hi - lo;
   double z1 = lo + InpZoneLow  * len;
   double z2 = lo + InpZoneHigh * len;
   zLo = MathMin(z1, z2);
   zHi = MathMax(z1, z2);
  }

//==================================================================
//  R5 — POI = order block INTERSECT fair value gap
//==================================================================
bool BuildPOI(const MqlRates &r[], int sweepIdx, int mssIdx, int dir,
              double &poiLo, double &poiHi, string &why)
  {
   poiLo = 0.0;
   poiHi = 0.0;
   why = "";

   //--- order block: last opposing candle before the MSS bar
   double obLo = 0.0, obHi = 0.0;
   bool haveOB = false;
   for(int b = mssIdx + 1; b <= sweepIdx; b++)
     {
      bool opposing = (dir > 0) ? (r[b].close < r[b].open) : (r[b].close > r[b].open);
      if(opposing)
        {
         obLo = r[b].low;
         obHi = r[b].high;
         haveOB = true;
         break;
        }
     }
   if(InpRequireOB && !haveOB)
     {
      why = "R5: no order block";
      return(false);
     }

   //--- fair value gap: 3-bar imbalance inside the displacement
   double fvgLo = 0.0, fvgHi = 0.0;
   bool haveFVG = false;
   for(int i = 1; i + 2 <= sweepIdx; i++)
     {
      if(dir > 0)
        {
         // bullish: low of newest > high of oldest
         if(r[i].low > r[i + 2].high)
           {
            fvgLo = r[i + 2].high;
            fvgHi = r[i].low;
            haveFVG = true;
            break;
           }
        }
      else
        {
         // bearish: high of newest < low of oldest
         if(r[i].high < r[i + 2].low)
           {
            fvgLo = r[i].high;
            fvgHi = r[i + 2].low;
            haveFVG = true;
            break;
           }
        }
     }
   if(InpRequireFVG && !haveFVG)
     {
      why = "R5: no fair value gap";
      return(false);
     }

   //--- combine
   if(haveOB && haveFVG)
     {
      poiLo = MathMax(obLo, fvgLo);
      poiHi = MathMin(obHi, fvgHi);
      if(poiLo > poiHi)
        {
         why = "R5: OB and FVG do not overlap";
         return(false);
        }
      return(true);
     }
   if(haveOB)
     {
      poiLo = obLo;
      poiHi = obHi;
      return(true);
     }
   if(haveFVG)
     {
      poiLo = fvgLo;
      poiHi = fvgHi;
      return(true);
     }

   why = "R5: no POI";
   return(false);
  }

//==================================================================
//  position / trade counting
//==================================================================
int CountOpenPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      n++;
     }
   return(n);
  }

int CountTradesToday()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   datetime dayStart = StructToTime(dt);

   if(!HistorySelect(dayStart, TimeCurrent() + 60))
      return(0);

   int total = HistoryDealsTotal();
   int n = 0;
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      n++;
     }
   return(n);
  }

//==================================================================
//  sizing
//==================================================================
double CalcLots(double entry, double sl, double &riskMoneyOut)
  {
   riskMoneyOut = 0.0;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;
   if(riskMoney <= 0.0)
      return(0.0);

   double slDist = MathAbs(entry - sl);
   if(slDist <= 0.0)
      return(0.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0)
      return(0.0);

   double lossPerLot = (slDist / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return(0.0);

   double lots = riskMoney / lossPerLot;
   riskMoneyOut = riskMoney;

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0.0)
      lotStep = 0.01;

   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot)
      lots = minLot;
   if(lots > maxLot)
      lots = maxLot;

   return(NormalizeDouble(lots, 2));
  }

//==================================================================
//  session / time helpers
//==================================================================
datetime ToUTC(datetime serverTime)
  {
   return(serverTime - g_gmtSec);
  }

bool InEntrySession(datetime serverBarTime)
  {
   if(!InpSessionFilter)
      return(true);

   MqlDateTime dt;
   TimeToStruct(ToUTC(serverBarTime), dt);

   if(dt.day_of_week == 0 || dt.day_of_week == 6)
      return(false);

   int h = dt.hour;
   if(InpSessionStartUTC <= InpSessionEndUTC)
      return(h >= InpSessionStartUTC && h < InpSessionEndUTC);
   // window wraps midnight
   return(h >= InpSessionStartUTC || h < InpSessionEndUTC);
  }

//==================================================================
//  D-15 sticky setup helpers
//==================================================================
int FindBarIndexByTime(const MqlRates &r[], int bars, datetime t)
  {
   for(int i = 1; i < bars; i++)
      if(r[i].time == t)
         return(i);
   return(-1);
  }

bool StickyValid(const MqlRates &r[], int bars, int bias, int &outIdx,
                 double &outExtreme, double &outLevel)
  {
   if(!g_haveSetup)
      return(false);
   if(g_stickyDir != bias)          // bias flipped: setup is void
      return(false);

   int si = FindBarIndexByTime(r, bars, g_stickySweepTime);
   if(si < 1)                       // aged out of the loaded window
      return(false);
   if(si > InpSetupTTLBars)         // expired
      return(false);

   for(int i = 1; i < si; i++)      // invalidated by a close beyond the extreme
     {
      if(g_stickyDir > 0 && r[i].close < g_stickyExtreme)
         return(false);
      if(g_stickyDir < 0 && r[i].close > g_stickyExtreme)
         return(false);
     }

   outIdx     = si;
   outExtreme = g_stickyExtreme;
   outLevel   = g_stickyLevel;
   return(true);
  }

void AdoptSticky(const MqlRates &r[], int sweepIdx, int bias, double extreme, double level)
  {
   g_haveSetup       = true;
   g_stickySweepTime = r[sweepIdx].time;
   g_stickyExtreme   = extreme;
   g_stickyLevel     = level;
   g_stickyDir       = bias;
  }

void ClearSticky()
  {
   g_haveSetup = false;
  }

//==================================================================
//  THE RULE ENGINE
//  Returns +1 long, -1 short, 0 no trade.
//  Fills entry/sl/tp when a signal is produced.
//==================================================================
int Evaluate(double &entryOut, double &slOut, double &tpOut, string &whyOut, string &tagOut)
  {
   entryOut = 0.0;
   slOut    = 0.0;
   tpOut    = 0.0;
   whyOut   = "";
   tagOut   = "";

   //----------- data -----------
   MqlRates m15[];
   ArraySetAsSeries(m15, true);
   int copied = CopyRates(_Symbol, PERIOD_M15, 0, InpBarsM15, m15);
   if(copied < 120)
     {
      whyOut = "no data";
      return(0);
     }

   double atr = ATR(PERIOD_M15, 1);
   if(atr <= 0.0)
     {
      whyOut = "no ATR";
      return(0);
     }

   //----------- R1 bias -----------
   int biasIdxNew = 0, biasIdxOld = 0;
   double biasPxNew = 0.0, biasPxOld = 0.0;
   int bias = GetBias(biasIdxNew, biasPxNew, biasIdxOld, biasPxOld);
   if(bias == 0)
     {
      whyOut = "R1: no clear bias";
      return(0);
     }

   //----------- R3a structure -----------
   string structWhy = "";
   if(!StructureClean(structWhy))
     {
      whyOut = structWhy;
      return(0);
     }

   //----------- R2 sweep (counter to bias) -----------
   double penMin = MathMax(1.0 * g_pip, InpPenetrationMinATR * atr);
   double penMax = InpPenetrationMaxATR * atr;
   if(penMax <= penMin)
      penMax = penMin * 2.0;

   // collect candidate levels
   double levels[];
   int nLevels = 0;
   ArrayResize(levels, 0);

   int swIdx[], swKind[];
   double swPx[];
   int nSw = FindSwings(m15, copied, 2, 2, swIdx, swKind, swPx);
   for(int j = 0; j < nSw; j++)
     {
      if(swIdx[j] > InpSweepLookback)
         continue;
      // long setups sweep lows, short setups sweep highs
      if(bias > 0 && swKind[j] == -1)
        {
         ArrayResize(levels, nLevels + 1);
         levels[nLevels] = swPx[j];
         nLevels++;
        }
      if(bias < 0 && swKind[j] == 1)
        {
         ArrayResize(levels, nLevels + 1);
         levels[nLevels] = swPx[j];
         nLevels++;
        }
     }

   if(InpUsePriorDayLevel)
     {
      double pd = (bias > 0) ? iLow(_Symbol, PERIOD_D1, 1) : iHigh(_Symbol, PERIOD_D1, 1);
      if(pd > 0.0)
        {
         ArrayResize(levels, nLevels + 1);
         levels[nLevels] = pd;
         nLevels++;
        }
     }

   if(nLevels == 0)
     {
      whyOut = "R2: no candidate levels";
      return(0);
     }

   // search for the most recent valid sweep
   int    sweepIdx = -1;
   double sweepExtreme = 0.0;
   double sweptLevel = 0.0;
   int    sweepAge = 0;

   for(int age = 1; age <= InpSweepFreshness && sweepIdx < 0; age++)
     {
      for(int L = 0; L < nLevels; L++)
        {
         double lv = levels[L];

         if(bias > 0)
           {
            // long: bar low pierces below the level, within bounds
            if(m15[age].low >= lv - penMin)
               continue;
            if(m15[age].low <= lv - penMax)
               continue;
            // reclaim: close back above the level within N bars
            bool reclaimed = false;
            for(int rr = 0; rr <= InpReclaimBars; rr++)
              {
               int idx = age - rr;
               if(idx < 1)
                  break;
               if(m15[idx].close > lv)
                 {
                  reclaimed = true;
                  break;
                 }
              }
            if(!reclaimed)
               continue;
           }
         else
           {
            if(m15[age].high <= lv + penMin)
               continue;
            if(m15[age].high >= lv + penMax)
               continue;
            bool reclaimed = false;
            for(int rr = 0; rr <= InpReclaimBars; rr++)
              {
               int idx = age - rr;
               if(idx < 1)
                  break;
               if(m15[idx].close < lv)
                 {
                  reclaimed = true;
                  break;
                 }
              }
            if(!reclaimed)
               continue;
           }

         sweepIdx     = age;
         sweptLevel   = lv;
         sweepAge     = age;
         sweepExtreme = (bias > 0) ? m15[age].low : m15[age].high;
         // extend the extreme across the reclaim window
         for(int rr = 1; rr <= InpReclaimBars; rr++)
           {
            int idx = age - rr;
            if(idx < 1)
               break;
            if(bias > 0 && m15[idx].low < sweepExtreme)
               sweepExtreme = m15[idx].low;
            if(bias < 0 && m15[idx].high > sweepExtreme)
               sweepExtreme = m15[idx].high;
           }
         break;
        }
     }

   //----------- D-15 sticky selection -----------
   int    si  = 0;
   double se  = 0.0;
   double slv = 0.0;
   bool   sticky = StickyValid(m15, copied, bias, si, se, slv);

   if(sweepIdx < 0)
     {
      if(!sticky)
        {
         whyOut = "R2: no recent sweep";
         return(0);
        }
      sweepIdx     = si;
      sweepExtreme = se;
      sweptLevel   = slv;
     }
   else
      if(sticky)
        {
         // keep the old setup; record the new sweep but do not adopt it
         if(g_stickySweepTime != m15[sweepIdx].time)
            PrintFormat("Tradie D-15: new sweep at %s ignored; active setup is from %s",
                        TimeToString(m15[sweepIdx].time), TimeToString(g_stickySweepTime));
         sweepIdx     = si;
         sweepExtreme = se;
         sweptLevel   = slv;
        }
      else
        {
         AdoptSticky(m15, sweepIdx, bias, sweepExtreme, sweptLevel);
        }

   // expiry
   if(sweepIdx > InpSetupTTLBars)
     {
      whyOut = "R4: setup expired";
      return(0);
     }

   // sweep must not have been violated since
   for(int i = 1; i < sweepIdx; i++)
     {
      if(bias > 0 && m15[i].close < sweepExtreme)
        {
         whyOut = "R2: sweep violated (closed below)";
         return(0);
        }
      if(bias < 0 && m15[i].close > sweepExtreme)
        {
         whyOut = "R2: sweep violated (closed above)";
         return(0);
        }
     }

   //----------- R3b MSS -----------
   double mssLevel = 0.0;
   int    mssIdx   = -1;
   for(int j = 0; j < nSw; j++)
     {
      if(swIdx[j] >= sweepIdx || swIdx[j] < 3)
         continue;
      bool wanted = (bias > 0) ? (swKind[j] == 1) : (swKind[j] == -1);
      if(!wanted)
         continue;
      mssLevel = swPx[j];
      // find the first close beyond it, newer than the swing
      int limit = swIdx[j] - InpMSSSwing;
      for(int b = 1; b <= limit; b++)
        {
         bool broke = (bias > 0) ? (m15[b].close > mssLevel) : (m15[b].close < mssLevel);
         if(!broke)
            continue;
         if((sweepIdx - b) > InpMSSMaxBars)
            continue;
         double disp = (bias > 0) ? (m15[b].close - sweepExtreme) : (sweepExtreme - m15[b].close);
         if(disp < InpMSSDisplacementATR * atr)
            continue;
         mssIdx = b;
         break;
        }
      if(mssIdx > 0)
         break;
     }

   if(mssIdx < 0)
     {
      whyOut = "R3b: no structure shift";
      return(0);
     }

   //----------- R4 retracement zone -----------
   double legStart = 0.0;
   double legEnd   = sweepExtreme;

   if(InpRetraceAnchor == RETRACE_DISPLACEMENT_LEG)
     {
      legStart = m15[mssIdx].close;
     }
   else
     {
      // option C: the most recent opposing swing BEFORE the sweep
      for(int j = 0; j < nSw; j++)
        {
         if(swIdx[j] <= sweepIdx)
            continue;
         bool wanted = (bias > 0) ? (swKind[j] == 1) : (swKind[j] == -1);
         if(wanted)
           {
            legStart = swPx[j];
            break;
           }
        }
     }

   if(legStart <= 0.0)
     {
      whyOut = "R4: no impulse leg for the zone";
      return(0);
     }

   double zLo = 0.0, zHi = 0.0;
   BuildZone(0, legStart, legEnd, zLo, zHi);

   // did price tap the zone before the confirmation bar?
   bool zoneTouched = false;
   for(int i = 1; i <= mssIdx; i++)
     {
      if(RangesOverlap(m15[i].low, m15[i].high, zLo, zHi))
        {
         zoneTouched = true;
         break;
        }
     }
   if(InpRequireZoneTouch && !zoneTouched)
     {
      whyOut = StringFormat("R4: zone [%.5f-%.5f] not reached", zLo, zHi);
      return(0);
     }

   //----------- R5 POI + engulfing -----------
   double poiLo = 0.0, poiHi = 0.0;
   if(!BuildPOI(m15, sweepIdx, mssIdx, bias, poiLo, poiHi, whyOut))
      return(0);

   bool engulfBar = false;
   if(bias > 0)
      engulfBar = IsBullEngulf(m15, 1, InpMinBodyRatio);
   else
      engulfBar = IsBearEngulf(m15, 1, InpMinBodyRatio);

   if(!engulfBar)
     {
      whyOut = "R5: no engulfing confirmation on this bar";
      return(0);
     }

   if(!RangesOverlap(m15[1].low, m15[1].high, poiLo, poiHi))
     {
      whyOut = StringFormat("R5: engulf not in POI [%.5f-%.5f]", poiLo, poiHi);
      return(0);
     }

   // do not fire the same sweep twice
   if(m15[1].time <= g_lastTradeBarTime)
     {
      whyOut = "duplicate setup";
      return(0);
     }

   //----------- R6 risk -----------
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = (bias > 0) ? ask : bid;

   double buffer = MathMax(InpSLBufferATR * atr, InpSLBufferSpread * SpreadPrice());
   double sl;
   if(bias > 0)
      sl = sweepExtreme - buffer;
   else
      sl = sweepExtreme + buffer;

   double slDist = MathAbs(entry - sl);
   double minDist = InpMinSLPips * g_pip;

   if(slDist < minDist)
     {
      // push the stop out to the minimum distance
      if(bias > 0)
         sl = entry - minDist;
      else
         sl = entry + minDist;
      slDist = minDist;
     }

   if(slDist > InpMaxSLATR * atr)
     {
      whyOut = StringFormat("R6: SL %.1fp > %.1fxATR", slDist / g_pip, InpMaxSLATR);
      return(0);
     }

   double tp = (bias > 0) ? (entry + InpRewardRisk * slDist) : (entry - InpRewardRisk * slDist);

   // broker stops level
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDist = (double)stopsLevel * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(slDist < minStopDist)
     {
      whyOut = "R6: SL inside broker stops level";
      return(0);
     }

   // spread guard
   if(InpMaxSpreadPoints > 0.0)
     {
      long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if((double)sp > InpMaxSpreadPoints)
        {
         whyOut = StringFormat("R6: spread %d > %.0f", (int)sp, InpMaxSpreadPoints);
         return(0);
        }
     }

   entryOut = NormalizeDouble(entry, g_digits);
   slOut    = NormalizeDouble(sl, g_digits);
   tpOut    = NormalizeDouble(tp, g_digits);

   tagOut = StringFormat("bias=%s sweep@%.5f mss@%.5f zone=%.5f-%.5f poi=%.5f-%.5f sl=%.1fp rr=%.1f",
                         (bias > 0 ? "up" : "down"), sweepExtreme, mssLevel,
                         zLo, zHi, poiLo, poiHi, slDist / g_pip, InpRewardRisk);

   return(bias);
  }

//==================================================================
//  order submission
//==================================================================
bool SendTrade(int dir, double entry, double sl, double tp, string note)
  {
   double riskMoney = 0.0;
   double lots = CalcLots(entry, sl, riskMoney);
   if(lots <= 0.0)
     {
      Print("Tradie: sizing failed, no lots computed");
      return(false);
     }

   // margin check
   ENUM_ORDER_TYPE ot = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double marginNeeded = 0.0;
   double price = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(OrderCalcMargin(ot, _Symbol, lots, price, marginNeeded))
     {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(marginNeeded > freeMargin)
        {
         PrintFormat("Tradie: skip, margin needed %.2f > free %.2f", marginNeeded, freeMargin);
         return(false);
        }
     }

   if(InpDryRun)
     {
      PrintFormat("Tradie DRY RUN: %s %s lots=%.2f entry=%.5f sl=%.5f tp=%.5f | %s",
                  (dir > 0 ? "BUY" : "SELL"), _Symbol, lots, entry, sl, tp, note);
      return(false);
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   bool ok = false;
   if(dir > 0)
      ok = g_trade.Buy(lots, _Symbol, 0.0, sl, tp, "Tradie");
   else
      ok = g_trade.Sell(lots, _Symbol, 0.0, sl, tp, "Tradie");

   if(ok)
     {
      PrintFormat("Tradie: %s %s %.2f lots | SL %.5f TP %.5f | %s",
                  (dir > 0 ? "BUY" : "SELL"), _Symbol, lots, sl, tp, note);
      g_lastTradeBarTime = iTime(_Symbol, PERIOD_M15, 1);
      ClearSticky();            // a traded setup is consumed
     }
   else
      PrintFormat("Tradie: order FAILED retcode=%d (%s)",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());

   return(ok);
  }

//==================================================================
//  Friday flatten
//==================================================================
void MaybeFlattenFriday()
  {
   if(!InpFridayFlatten)
      return;
   if(CountOpenPositions() == 0)
      return;

   MqlDateTime dt;
   TimeToStruct(ToUTC(TimeCurrent()), dt);
   if(dt.day_of_week != 5)
      return;
   if(dt.hour < InpFridayFlattenUTC)
      return;

   Print("Tradie: Friday flatten");
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      g_trade.SetExpertMagicNumber(InpMagic);
      g_trade.PositionClose(ticket);
     }
  }

//==================================================================
//  LIFECYCLE
//==================================================================
int OnInit()
  {
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_pip    = PipSize();

   if(InpAutoGMTOffset)
     {
      datetime srv = TimeTradeServer();
      datetime gmt = TimeGMT();
      g_gmtSec = (int)MathRound((double)(srv - gmt));
      // sanity clamp; brokers are within +-12h
      if(MathAbs(g_gmtSec) > 12 * 3600)
         g_gmtSec = InpGMTOffsetHours * 3600;
     }
   else
      g_gmtSec = InpGMTOffsetHours * 3600;

   PrintFormat("Tradie init: %s | pip=%.5f digits=%d | server-UTC offset=%+.1fh | tester=%d",
               _Symbol, g_pip, g_digits, g_gmtSec / 3600.0,
               (int)MQLInfoInteger(MQL_TESTER));
   PrintFormat("Tradie rules: bias=%s sweep=ATR-bound MSS=close+disp retrace=%s zone=%.2f-%.2f POI=OB%sFVG%s RR=1:%.1f",
               EnumToString(InpBiasTF),
               (InpRetraceAnchor == RETRACE_PRIOR_IMPULSE ? "prior_impulse" : "displacement"),
               InpZoneLow, InpZoneHigh,
               (InpRequireOB ? "+" : "off"), (InpRequireFVG ? "+" : "off"),
               InpRewardRisk);

   if(InpRewardRisk < 1.0)
     {
      Print("Tradie: InpRewardRisk must be >= 1.0");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpZoneLow >= InpZoneHigh || InpZoneLow < 0.0 || InpZoneHigh > 1.0)
     {
      Print("Tradie: zone bounds invalid");
      return(INIT_PARAMETERS_INCORRECT);
     }

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   PrintFormat("Tradie stop: evaluations=%d rejections=%d last=%s",
               g_evaluations, g_rejections, g_why);
   Comment("");
  }

void OnTick()
  {
   MaybeFlattenFriday();

   // act once per completed M15 bar
   datetime barTime = iTime(_Symbol, PERIOD_M15, 0);
   if(barTime == 0 || barTime == g_lastBar)
      return;
   g_lastBar = barTime;

   //--- R9 / gates -------------------------------------------------
   if(CountOpenPositions() >= InpMaxConcurrent)
     {
      g_why = "R9: max concurrent positions";
      return;
     }
   int today = CountTradesToday();
   if(today >= InpDailyTradeCap)
     {
      g_why = StringFormat("R9: daily cap %d reached", InpDailyTradeCap);
      return;
     }
   if(HasPositionOnSymbol())
     {
      g_why = "position already open on this symbol";
      return;
     }

   // the bar that just closed is index 1
   if(!InEntrySession(iTime(_Symbol, PERIOD_M15, 1)))
     {
      g_why = "outside entry session";
      return;
     }

   //--- rule engine ------------------------------------------------
   g_evaluations++;
   double entry = 0.0, sl = 0.0, tp = 0.0;
   string why = "", tag = "";
   int dir = Evaluate(entry, sl, tp, why, tag);

   g_why = why;
   g_tag = tag;

   if(dir == 0)
     {
      g_rejections++;
      if(InpDryRun)
         PrintFormat("Tradie: no trade - %s", why);
      return;
     }

   //--- R7 alignment assertion -------------------------------------
   int biasIdxNew = 0, biasIdxOld = 0;
   double biasPxNew = 0.0, biasPxOld = 0.0;
   int bias = GetBias(biasIdxNew, biasPxNew, biasIdxOld, biasPxOld);
   if(bias != dir)
     {
      Print("Tradie: ASSERTION FAILED - direction does not match bias. Refusing to trade.");
      return;
     }

   SendTrade(dir, entry, sl, tp, tag);
  }

bool HasPositionOnSymbol()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+
