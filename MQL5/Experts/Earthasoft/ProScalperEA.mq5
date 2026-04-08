#property strict
#property version   "1.00"
#property description "Earthasoft Pro Scalper EA (MQL5-only)"

#include <Trade/Trade.mqh>

input group "General"
input bool   InpEnableTrading            = true;
input ENUM_TIMEFRAMES InpEntryTimeframe  = PERIOD_M5;
input ENUM_TIMEFRAMES InpTrendTimeframe  = PERIOD_H1;
input long   InpMagicNumber              = 26032701;

input group "Sessions (Server Time)"
input bool   InpUseSessionFilter         = true;
input int    InpSessionStartHour         = 12; // London/NY overlap style default
input int    InpSessionEndHour           = 21;

input group "Risk Model"
input bool   InpUseDynamicRisk           = true;
input double InpFixedRiskPercent         = 2.0;
input double InpMinRiskPercent           = 2.0;
input double InpMaxRiskPercent           = 3.0;
input double InpDailyLossCapPercent      = 5.0;
input int    InpMaxConsecutiveLosses     = 3;

input group "Execution Guards"
input int    InpMaxSpreadPoints          = 35;
input int    InpDeviationPoints          = 10;
input int    InpMinBarsRequired          = 250;

input group "Signal Settings"
input int    InpFastEmaPeriod            = 21;
input int    InpSlowEmaPeriod            = 55;
input int    InpTrendFastEmaPeriod       = 50;
input int    InpTrendSlowEmaPeriod       = 200;
input int    InpRsiPeriod                = 14;
input int    InpAtrPeriod                = 14;
input double InpAtrSLMultiplier          = 1.5;
input double InpAtrTPMultiplier          = 2.0;
input int    InpRsiBuyLevel              = 55;
input int    InpRsiSellLevel             = 45;
input bool   InpUseBreakEven             = true;
input double InpBreakEvenAtrTrigger      = 1.0;
input bool   InpUseTrailingStop          = true;
input double InpTrailingAtrMultiplier    = 1.2;

input group "Flag Pattern (optional confirmation)"
input bool   InpUseFlagPattern           = false;
input int    InpFlagPoleBars             = 6;
input int    InpFlagConsolidationBars    = 5;
input double InpFlagMinPoleAtrMultiple   = 1.2;
input double InpFlagMaxRangeRatio        = 0.72;

CTrade trade;

int gFastEmaHandle = INVALID_HANDLE;
int gSlowEmaHandle = INVALID_HANDLE;
int gTrendFastHandle = INVALID_HANDLE;
int gTrendSlowHandle = INVALID_HANDLE;
int gRsiHandle = INVALID_HANDLE;
int gAtrHandle = INVALID_HANDLE;

datetime gLastBarTime = 0;
datetime gCurrentDay = 0;
double gDayStartEquity = 0.0;
bool gDailyCapHit = false;
int gConsecutiveLosses = 0;

int DigitsForSymbol()
{
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
}

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, DigitsForSymbol());
}

bool IsTradingSession()
{
   if(!InpUseSessionFilter)
      return true;

   MqlDateTime tm;
   TimeToStruct(TimeTradeServer(), tm);

   if(InpSessionStartHour == InpSessionEndHour)
      return true;

   if(InpSessionStartHour < InpSessionEndHour)
      return (tm.hour >= InpSessionStartHour && tm.hour < InpSessionEndHour);

   return (tm.hour >= InpSessionStartHour || tm.hour < InpSessionEndHour);
}

bool IsSpreadOk()
{
   const double spreadPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spreadPoints <= InpMaxSpreadPoints);
}

void ResetDailyStateIfNeeded()
{
   MqlDateTime tmNow;
   TimeToStruct(TimeTradeServer(), tmNow);
   tmNow.hour = 0;
   tmNow.min = 0;
   tmNow.sec = 0;
   datetime serverDay = StructToTime(tmNow);

   if(gCurrentDay != serverDay)
   {
      gCurrentDay = serverDay;
      gDayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      gDailyCapHit = false;
      gConsecutiveLosses = 0;
   }
}

bool IsDailyLossCapRespected()
{
   if(gDailyCapHit)
      return false;

   const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   const double minEq = gDayStartEquity * (1.0 - InpDailyLossCapPercent / 100.0);
   if(eq <= minEq)
   {
      gDailyCapHit = true;
      Print("Daily loss cap reached. Equity: ", DoubleToString(eq, 2), " | Min allowed: ", DoubleToString(minEq, 2));
      return false;
   }
   return true;
}

bool HasOpenPositionForSymbol()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (long)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         return true;
      }
   }
   return false;
}

bool ReadIndicatorSnapshot(double &fastEma, double &slowEma, double &trendFast, double &trendSlow, double &rsi, double &atr)
{
   double b1[1];
   ArraySetAsSeries(b1, true);

   if(CopyBuffer(gFastEmaHandle, 0, 0, 1, b1) < 1) return false;
   fastEma = b1[0];
   if(CopyBuffer(gSlowEmaHandle, 0, 0, 1, b1) < 1) return false;
   slowEma = b1[0];
   if(CopyBuffer(gTrendFastHandle, 0, 0, 1, b1) < 1) return false;
   trendFast = b1[0];
   if(CopyBuffer(gTrendSlowHandle, 0, 0, 1, b1) < 1) return false;
   trendSlow = b1[0];
   if(CopyBuffer(gRsiHandle, 0, 0, 1, b1) < 1) return false;
   rsi = b1[0];
   if(CopyBuffer(gAtrHandle, 0, 0, 1, b1) < 1) return false;
   atr = b1[0];

   return true;
}

double ComputeRiskPercent(const double trendFast, const double trendSlow, const double atr)
{
   if(!InpUseDynamicRisk)
      return InpFixedRiskPercent;

   double bid = 0.0;
   SymbolInfoDouble(_Symbol, SYMBOL_BID, bid);
   if(bid <= 0.0 || atr <= 0.0)
      return InpMinRiskPercent;

   const double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   const double trendStrength = MathMin(MathAbs(trendFast - trendSlow) / bid, 0.01);
   const double spreadPenalty = MathMin(spread / atr, 1.0);

   double quality = 0.5;
   quality += (trendStrength * 40.0); // pushes score toward max for stronger trend
   quality -= (spreadPenalty * 0.6);
   quality = MathMax(0.0, MathMin(1.0, quality));

   return InpMinRiskPercent + (InpMaxRiskPercent - InpMinRiskPercent) * quality;
}

double CalculateVolumeByRisk(const double entryPrice, const double stopPrice, const double riskPercent)
{
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double riskMoney = equity * (riskPercent / 100.0);
   const double stopDistance = MathAbs(entryPrice - stopPrice);
   if(stopDistance <= 0.0)
      return 0.0;

   const double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   const double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(tickSize <= 0.0 || tickValue <= 0.0 || stepLot <= 0.0)
      return 0.0;

   const double moneyPerLot = (stopDistance / tickSize) * tickValue;
   if(moneyPerLot <= 0.0)
      return 0.0;

   double volume = riskMoney / moneyPerLot;
   volume = MathFloor(volume / stepLot) * stepLot;
   volume = MathMax(minLot, MathMin(maxLot, volume));
   return volume;
}

int BuildSignal(double fastEma, double slowEma, double trendFast, double trendSlow, double rsi)
{
   const bool trendUp = trendFast > trendSlow;
   const bool trendDown = trendFast < trendSlow;
   const bool momentumUp = fastEma > slowEma && rsi >= InpRsiBuyLevel;
   const bool momentumDown = fastEma < slowEma && rsi <= InpRsiSellLevel;

   if(trendUp && momentumUp)
      return 1;
   if(trendDown && momentumDown)
      return -1;
   return 0;
}

double BarHighAt(const int shift)
{
   return iHigh(_Symbol, InpEntryTimeframe, shift);
}

double BarLowAt(const int shift)
{
   return iLow(_Symbol, InpEntryTimeframe, shift);
}

double BarCloseAt(const int shift)
{
   return iClose(_Symbol, InpEntryTimeframe, shift);
}

bool PoleSegmentRange(const int poleFromShift, const int poleToShift, double &outLow, double &outHigh, double &outRange)
{
   outLow = DBL_MAX;
   outHigh = -DBL_MAX;
   for(int i = poleFromShift; i <= poleToShift; ++i)
   {
      outLow = MathMin(outLow, BarLowAt(i));
      outHigh = MathMax(outHigh, BarHighAt(i));
   }
   outRange = outHigh - outLow;
   return (outRange > 0.0);
}

bool FlagSegmentRange(const int flagFromShift, const int flagToShift, double &outHigh, double &outLow, double &outRange)
{
   outHigh = -DBL_MAX;
   outLow = DBL_MAX;
   for(int i = flagFromShift; i <= flagToShift; ++i)
   {
      outHigh = MathMax(outHigh, BarHighAt(i));
      outLow = MathMin(outLow, BarLowAt(i));
   }
   outRange = outHigh - outLow;
   return (outRange > 0.0);
}

bool DetectBullFlag(const double atr)
{
   if(atr <= 0.0)
      return false;
   if(InpFlagPoleBars < 3 || InpFlagConsolidationBars < 2)
      return false;

   const int poleNew = InpFlagConsolidationBars + 1;
   const int poleOld = InpFlagConsolidationBars + InpFlagPoleBars;
   const int need = poleOld + 2;
   if(Bars(_Symbol, InpEntryTimeframe) < need)
      return false;

   double poleLow = 0.0, poleHigh = 0.0, poleRange = 0.0;
   if(!PoleSegmentRange(poleNew, poleOld, poleLow, poleHigh, poleRange))
      return false;
   if(poleRange < InpFlagMinPoleAtrMultiple * atr)
      return false;

   const double poleOpenCloseOld = BarCloseAt(poleOld);
   const double poleOpenCloseNew = BarCloseAt(poleNew);
   if(poleOpenCloseNew <= poleOpenCloseOld)
      return false;

   double flagHigh = 0.0, flagLow = 0.0, flagRange = 0.0;
   if(!FlagSegmentRange(1, InpFlagConsolidationBars, flagHigh, flagLow, flagRange))
      return false;
   if(flagRange >= poleRange * InpFlagMaxRangeRatio)
      return false;

   if(flagLow <= poleLow)
      return false;

   const double close0 = BarCloseAt(0);
   if(close0 <= flagHigh)
      return false;

   return true;
}

bool DetectBearFlag(const double atr)
{
   if(atr <= 0.0)
      return false;
   if(InpFlagPoleBars < 3 || InpFlagConsolidationBars < 2)
      return false;

   const int poleNew = InpFlagConsolidationBars + 1;
   const int poleOld = InpFlagConsolidationBars + InpFlagPoleBars;
   const int need = poleOld + 2;
   if(Bars(_Symbol, InpEntryTimeframe) < need)
      return false;

   double poleLow = 0.0, poleHigh = 0.0, poleRange = 0.0;
   if(!PoleSegmentRange(poleNew, poleOld, poleLow, poleHigh, poleRange))
      return false;
   if(poleRange < InpFlagMinPoleAtrMultiple * atr)
      return false;

   const double poleOpenCloseOld = BarCloseAt(poleOld);
   const double poleOpenCloseNew = BarCloseAt(poleNew);
   if(poleOpenCloseNew >= poleOpenCloseOld)
      return false;

   double flagHigh = 0.0, flagLow = 0.0, flagRange = 0.0;
   if(!FlagSegmentRange(1, InpFlagConsolidationBars, flagHigh, flagLow, flagRange))
      return false;
   if(flagRange >= poleRange * InpFlagMaxRangeRatio)
      return false;

   if(flagHigh >= poleHigh)
      return false;

   const double close0 = BarCloseAt(0);
   if(close0 >= flagLow)
      return false;

   return true;
}

int AnalyzeFlagPattern(const double atr)
{
   const bool bull = DetectBullFlag(atr);
   const bool bear = DetectBearFlag(atr);
   if(bull && !bear)
      return 1;
   if(bear && !bull)
      return -1;
   return 0;
}

bool OpenTrade(const int signal, const double atr, const double riskPct)
{
   double ask = 0.0, bid = 0.0;
   SymbolInfoDouble(_Symbol, SYMBOL_ASK, ask);
   SymbolInfoDouble(_Symbol, SYMBOL_BID, bid);
   if(ask <= 0.0 || bid <= 0.0 || atr <= 0.0)
      return false;

   double entry = (signal > 0 ? ask : bid);
   double sl = 0.0;
   double tp = 0.0;

   if(signal > 0)
   {
      sl = entry - (InpAtrSLMultiplier * atr);
      tp = entry + (InpAtrTPMultiplier * atr);
   }
   else
   {
      sl = entry + (InpAtrSLMultiplier * atr);
      tp = entry - (InpAtrTPMultiplier * atr);
   }

   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
   entry = NormalizePrice(entry);

   const double volume = CalculateVolumeByRisk(entry, sl, riskPct);
   if(volume <= 0.0)
      return false;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   bool ok = false;
   if(signal > 0)
      ok = trade.Buy(volume, _Symbol, entry, sl, tp, "ProScalper BUY");
   else
      ok = trade.Sell(volume, _Symbol, entry, sl, tp, "ProScalper SELL");

   if(!ok)
      Print("Order failed: ", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
   else
      Print("Order placed. Dir=", signal, " Vol=", DoubleToString(volume, 2), " Risk%=", DoubleToString(riskPct, 2));

   return ok;
}

void ManageOpenPositions(const double atr)
{
   if(atr <= 0.0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         (long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
      {
         continue;
      }

      const long type = (long)PositionGetInteger(POSITION_TYPE);
      const double open = PositionGetDouble(POSITION_PRICE_OPEN);
      const double sl = PositionGetDouble(POSITION_SL);
      const double tp = PositionGetDouble(POSITION_TP);
      const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double newSl = sl;
      const double price = (type == POSITION_TYPE_BUY ? bid : ask);
      const double move = (type == POSITION_TYPE_BUY ? price - open : open - price);

      if(InpUseBreakEven && move >= (InpBreakEvenAtrTrigger * atr))
      {
         if(type == POSITION_TYPE_BUY && (newSl < open || newSl == 0.0))
            newSl = open;
         if(type == POSITION_TYPE_SELL && (newSl > open || newSl == 0.0))
            newSl = open;
      }

      if(InpUseTrailingStop)
      {
         const double tsDistance = InpTrailingAtrMultiplier * atr;
         if(type == POSITION_TYPE_BUY)
         {
            const double candidate = NormalizePrice(price - tsDistance);
            if(candidate > newSl && candidate < price)
               newSl = candidate;
         }
         else
         {
            const double candidate = NormalizePrice(price + tsDistance);
            if((newSl == 0.0 || candidate < newSl) && candidate > price)
               newSl = candidate;
         }
      }

      if(newSl != sl && newSl > 0.0)
         trade.PositionModify(ticket, NormalizePrice(newSl), tp);
   }
}

bool IsNewBar()
{
   datetime t[1];
   ArraySetAsSeries(t, true);
   if(CopyTime(_Symbol, InpEntryTimeframe, 0, 1, t) < 1)
      return false;
   if(t[0] == gLastBarTime)
      return false;
   gLastBarTime = t[0];
   return true;
}

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   ResetDailyStateIfNeeded();

   if(Bars(_Symbol, InpEntryTimeframe) < InpMinBarsRequired)
      return INIT_FAILED;

   gFastEmaHandle = iMA(_Symbol, InpEntryTimeframe, InpFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   gSlowEmaHandle = iMA(_Symbol, InpEntryTimeframe, InpSlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   gTrendFastHandle = iMA(_Symbol, InpTrendTimeframe, InpTrendFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   gTrendSlowHandle = iMA(_Symbol, InpTrendTimeframe, InpTrendSlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   gRsiHandle = iRSI(_Symbol, InpEntryTimeframe, InpRsiPeriod, PRICE_CLOSE);
   gAtrHandle = iATR(_Symbol, InpEntryTimeframe, InpAtrPeriod);

   if(gFastEmaHandle == INVALID_HANDLE || gSlowEmaHandle == INVALID_HANDLE ||
      gTrendFastHandle == INVALID_HANDLE || gTrendSlowHandle == INVALID_HANDLE ||
      gRsiHandle == INVALID_HANDLE || gAtrHandle == INVALID_HANDLE)
   {
      return INIT_FAILED;
   }

   Print("ProScalperEA initialized. Symbol=", _Symbol);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(gFastEmaHandle != INVALID_HANDLE) IndicatorRelease(gFastEmaHandle);
   if(gSlowEmaHandle != INVALID_HANDLE) IndicatorRelease(gSlowEmaHandle);
   if(gTrendFastHandle != INVALID_HANDLE) IndicatorRelease(gTrendFastHandle);
   if(gTrendSlowHandle != INVALID_HANDLE) IndicatorRelease(gTrendSlowHandle);
   if(gRsiHandle != INVALID_HANDLE) IndicatorRelease(gRsiHandle);
   if(gAtrHandle != INVALID_HANDLE) IndicatorRelease(gAtrHandle);
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   const ulong deal = trans.deal;
   if(deal == 0)
      return;

   if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber)
      return;

   const long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT)
      return;

   const double profit = HistoryDealGetDouble(deal, DEAL_PROFIT) +
                         HistoryDealGetDouble(deal, DEAL_SWAP) +
                         HistoryDealGetDouble(deal, DEAL_COMMISSION);

   if(profit < 0.0)
      gConsecutiveLosses++;
   else if(profit > 0.0)
      gConsecutiveLosses = 0;
}

void OnTick()
{
   if(!InpEnableTrading)
      return;

   ResetDailyStateIfNeeded();
   if(!IsDailyLossCapRespected())
      return;

   if(gConsecutiveLosses >= InpMaxConsecutiveLosses)
      return;

   if(!IsTradingSession())
      return;

   if(!IsSpreadOk())
      return;

   double fastEma, slowEma, trendFast, trendSlow, rsi, atr;
   if(!ReadIndicatorSnapshot(fastEma, slowEma, trendFast, trendSlow, rsi, atr))
      return;

   ManageOpenPositions(atr);

   if(HasOpenPositionForSymbol())
      return;

   if(!IsNewBar())
      return;

   const int signal = BuildSignal(fastEma, slowEma, trendFast, trendSlow, rsi);
   if(signal == 0)
      return;

   if(InpUseFlagPattern)
   {
      const int flagSig = AnalyzeFlagPattern(atr);
      if(flagSig != signal)
         return;
   }

   const double riskPct = ComputeRiskPercent(trendFast, trendSlow, atr);
   OpenTrade(signal, atr, riskPct);
}
