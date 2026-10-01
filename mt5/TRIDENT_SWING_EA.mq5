//+------------------------------------------------------------------+
//|                                           TRIDENT_SWING_EA.mq5   |
//|  Trident Swing EA — MetaTrader 5                                 |
//|                                                                  |
//|  EA MQL5 & nâng cấp: © 2026 Hồ Ngọc Khánh (LiinIT)                |
//|  https://github.com/LiinIT/Bot-EA-Trading-XAUUSD-TRIDENT-SWING     |
//|  Donate coffee: 1907.5049.8560.17 / 68814062001 (Techcombank)     |
//|                                                                  |
//|  Logic gốc: "Trident Swing Projector" © MarkitTick                |
//|  License: CC BY-NC-SA 4.0 — chỉ dùng phi thương mại, giữ ghi      |
//|  nguồn MarkitTick + LiinIT, bản phái sinh giữ cùng license.       |
//|                                                                  |
//|  Luồng: pivot A-B-C hợp lệ → đặt 3 lệnh chờ Stop tại Entry        |
//|  (cùng SL, TP1/TP2/TP3 riêng) → huỷ nếu phá C hoặc quá hạn.        |
//|  Yêu cầu tài khoản HEDGING.                                        |
//+------------------------------------------------------------------+
#property copyright "EA (c) 2026 Ho Ngoc Khanh (LiinIT) | Logic: Trident Swing Projector (c) MarkitTick - CC BY-NC-SA 4.0"
#property link      "https://github.com/LiinIT/Bot-EA-Trading-XAUUSD-TRIDENT-SWING"
#property version   "1.00"
#property description "A-B-C swing pattern -> 3 pending Stop orders (TP1/TP2/TP3), SL beyond C."
#property description "Requires a HEDGING account. Non-commercial use only (CC BY-NC-SA 4.0)."
#property description "Donate coffee: 1907.5049.8560.17 / 68814062001 (Techcombank)"

#include <Trade/Trade.mqh>

#define TP_ORDER_COUNT 3

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ENUMS
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum ENUM_SWING_UNIT
{
   SWING_POINTS  = 0, // Points
   SWING_PERCENT = 1  // Percent
};

enum ENUM_STOP_BUFFER
{
   BUFFER_NONE   = 0, // None
   BUFFER_POINTS = 1, // Points
   BUFFER_ATR    = 2  // ATR Fraction
};

enum ENUM_SETUP_STATE
{
   STATE_NONE   = 0,
   STATE_ARMED  = 1,
   STATE_ACTIVE = 2
};

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// INPUTS
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

input group "1. CORE"
input int             InpPivotLeft  = 5;             // Pivot Left
input int             InpPivotRight = 5;             // Pivot Right
input ENUM_SWING_UNIT InpSwingUnit  = SWING_POINTS;  // Swing Unit

input group "2. FILTERS"
input bool            InpUseTrend     = true;       // Trend Filter (B phá swing trước)
input double          InpMinPullback  = 23.6;       // Min Pullback %
input double          InpMaxPullback  = 78.6;       // Max Pullback %
input bool            InpUseHtf       = false;      // HTF Confirmation
input ENUM_TIMEFRAMES InpHtfTimeframe = PERIOD_H4;  // HTF Timeframe
input bool            InpUseAdx       = false;      // ADX Filter
input int             InpAdxLength    = 14;         // ADX Length (Wilder)
input double          InpAdxThreshold = 20.0;       // ADX Threshold

input group "3. ENTRY / EXIT"
input ENUM_STOP_BUFFER InpStopBufferMode    = BUFFER_NONE; // Stop Buffer
input int              InpBufferPoints      = 0;           // Buffer Points
input double           InpBufferAtrFraction = 0.0;         // Buffer ATR Fraction
input int              InpAtrLength         = 14;          // ATR Length
input int              InpExpiryBars        = 20;          // Huỷ lệnh chờ sau N nến
input bool             InpUseBreakeven      = false;       // Dời SL về giá vào sau khi chạm TP1

input group "4. RISK"
input double InpRiskPercent    = 1.0;  // Rủi ro mỗi setup (% balance, tổng 3 lệnh)
input double InpMaxRiskPercent = 3.0;  // Rủi ro tối đa khi phải làm tròn lên lot min
input double InpMaxStopAtr     = 0.0;  // Khoảng SL tối đa (bội số ATR, 0 = tắt)

input group "5. PROTECTION"
input int    InpMaxSpreadPoints   = 0;        // Max Spread (points, 0 = tắt)
input bool   InpUseRolloverFilter = true;     // Không đặt lệnh trong giờ rollover
input string InpRolloverStart     = "23:50";  // Rollover bắt đầu (giờ server, HH:MM)
input string InpRolloverEnd       = "01:10";  // Rollover kết thúc (giờ server, HH:MM)

input group "6. SYSTEM"
input ulong  InpMagicNumber    = 20261002;   // Magic Number
input string InpTradeComment   = "TRIDENT";  // Order Comment
input int    InpSlippagePoints = 30;         // Max Slippage (points)
input int    InpWarmupBars     = 1000;       // Số nến lịch sử để dựng lại pivot
input bool   InpDrawLevels     = true;       // Vẽ A/B/C + Entry/SL/TP lên chart
input bool   InpShowPanel      = true;       // Hiển thị panel

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TYPES / STATE
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct PivotState
{
   double   lastHigh;
   datetime lastHighTime;
   double   prevHigh;
   double   lastLow;
   datetime lastLowTime;
   double   prevLow;
};

struct Setup
{
   int      dir;
   double   a;
   double   b;
   double   c;
   datetime aTime;
   datetime bTime;
   datetime cTime;
   double   leg;
   double   pullback;
   double   entry;
   double   stop;
   double   tp1;
   double   tp2;
   double   tp3;
};

const double ENTRY_RATIO = 0.25;
const double TP1_RATIO   = 0.50;
const double TP2_RATIO   = 0.75;
const double TP3_RATIO   = 1.00;
const string OBJ_PREFIX  = "TRIDENT_";
const string LOG_TAG     = "[TRIDENT]";

CTrade           g_trade;
PivotState       g_pivots;
Setup            g_setup;
ENUM_SETUP_STATE g_state         = STATE_NONE;
datetime         g_armTime       = 0;
datetime         g_lastBarTime   = 0;
bool             g_isWarmedUp    = false;
int              g_atrHandle     = INVALID_HANDLE;
int              g_adxHandle     = INVALID_HANDLE;
int              g_rolloverStart = 0;
int              g_rolloverEnd   = 0;
double           g_lastRiskMoney = 0.0;
string           g_lastNote      = "-";

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// LIFECYCLE
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

int OnInit()
{
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      PrintFormat("%s This EA needs a HEDGING account (3 separate positions per setup)", LOG_TAG);
      return INIT_FAILED;
   }

   g_atrHandle = iATR(_Symbol, _Period, InpAtrLength);
   g_adxHandle = iADXWilder(_Symbol, _Period, InpAdxLength);
   if(g_atrHandle == INVALID_HANDLE || g_adxHandle == INVALID_HANDLE)
   {
      PrintFormat("%s Cannot create indicator handles, error=%d", LOG_TAG, GetLastError());
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   ZeroMemory(g_pivots);
   ZeroMemory(g_setup);
   g_state       = STATE_NONE;
   g_armTime     = 0;
   g_lastBarTime = 0;
   g_isWarmedUp  = false;

   PrintFormat("%s Init %s %s risk=%.2f%% magic=%I64u", LOG_TAG, _Symbol, EnumToString(_Period), InpRiskPercent, InpMagicNumber);
   return INIT_SUCCEEDED;
}

// Lệnh chờ / vị thế KHÔNG bị xoá khi gỡ EA — gắn lại EA sẽ tự nhận lại và quản lý tiếp.
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   ObjectsDeleteAll(0, OBJ_PREFIX);
   Comment("");
   PrintFormat("%s Deinit reason=%d", LOG_TAG, reason);
}

void OnTick()
{
   if(!g_isWarmedUp && !WarmUp())
      return;

   ManageBreakeven();

   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime != 0 && currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      OnNewBar();
   }

   UpdatePanel();
}

void OnNewBar()
{
   Setup candidate;
   bool hasCandidate = ProcessPivotBar(0, candidate);

   SyncState();

   if(g_state == STATE_ARMED)
      CheckArmedCancel();

   if(!hasCandidate)
      return;

   if(g_state != STATE_NONE)
   {
      Note(StringFormat("New %s pattern ignored: a setup is already %s", DirectionText(candidate.dir), StateText()));
      return;
   }

   TryArmSetup(candidate);
}

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// INPUT VALIDATION
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

bool ValidateInputs()
{
   g_rolloverStart = ParseMinuteOfDay(InpRolloverStart);
   g_rolloverEnd   = ParseMinuteOfDay(InpRolloverEnd);

   bool isValid = InpPivotLeft >= 1 && InpPivotRight >= 1 &&
                  InpMinPullback >= 0 && InpMaxPullback <= 100 && InpMinPullback <= InpMaxPullback &&
                  InpExpiryBars >= 1 && InpAtrLength >= 1 && InpAdxLength >= 1 &&
                  InpRiskPercent > 0 && InpMaxRiskPercent >= InpRiskPercent &&
                  InpWarmupBars >= 50 && g_rolloverStart >= 0 && g_rolloverEnd >= 0;

   if(!isValid)
      PrintFormat("%s Invalid input parameters", LOG_TAG);
   return isValid;
}

int ParseMinuteOfDay(const string hhmm)
{
   string parts[];
   if(StringSplit(hhmm, ':', parts) != 2)
      return -1;

   int hour   = (int)StringToInteger(parts[0]);
   int minute = (int)StringToInteger(parts[1]);
   if(hour < 0 || hour > 23 || minute < 0 || minute > 59)
      return -1;
   return hour * 60 + minute;
}

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// WARM-UP: dựng lại pivot từ lịch sử + nhận lại lệnh đang có
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

bool WarmUp()
{
   if(BarsCalculated(g_atrHandle) <= InpAtrLength || BarsCalculated(g_adxHandle) <= InpAdxLength * 2)
      return false;

   int maxBase   = Bars(_Symbol, _Period) - (InpPivotLeft + InpPivotRight + 3);
   int startBase = MathMin(InpWarmupBars, maxBase);
   if(startBase < 1)
      return false;

   ZeroMemory(g_pivots);
   Setup ignored;
   for(int base = startBase; base >= 0; base--)
      ProcessPivotBar(base, ignored);

   g_lastBarTime = iTime(_Symbol, _Period, 0);
   g_isWarmedUp  = true;

   SyncState();
   if(g_state == STATE_NONE)
      ClearPersistedSetup();
   else
      RecoverSetup();

   PrintFormat("%s Warm-up done over %d bars, state=%s", LOG_TAG, startBase, StateText());
   return true;
}

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PIVOT + PATTERN
// base = nến đang hình thành theo góc nhìn Pine; mọi dữ liệu đọc từ base+1 trở về trước
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

bool ProcessPivotBar(const int base, Setup &candidate)
{
   int      pivotShift = base + InpPivotRight + 1;
   datetime pivotTime  = iTime(_Symbol, _Period, pivotShift);
   double   pivotHigh  = 0.0;
   double   pivotLow   = 0.0;
   bool     hasHigh    = IsPivotHigh(base, pivotHigh);
   bool     hasLow     = IsPivotLow(base, pivotLow);

   ZeroMemory(candidate);
   bool hasCandidate = hasLow && BuildBullSetup(pivotLow, pivotTime, candidate);
   if(!hasCandidate && hasHigh)
      hasCandidate = BuildBearSetup(pivotHigh, pivotTime, candidate);

   if(hasHigh)
   {
      g_pivots.prevHigh     = g_pivots.lastHigh;
      g_pivots.lastHigh     = pivotHigh;
      g_pivots.lastHighTime = pivotTime;
   }
   if(hasLow)
   {
      g_pivots.prevLow     = g_pivots.lastLow;
      g_pivots.lastLow     = pivotLow;
      g_pivots.lastLowTime = pivotTime;
   }
   return hasCandidate;
}

bool IsPivotHigh(const int base, double &value)
{
   int    candidateShift = base + InpPivotRight + 1;
   double candidate      = iHigh(_Symbol, _Period, candidateShift);
   if(candidate <= 0)
      return false;

   for(int shift = base + 1; shift <= candidateShift + InpPivotLeft; shift++)
   {
      if(shift != candidateShift && iHigh(_Symbol, _Period, shift) >= candidate)
         return false;
   }
   value = candidate;
   return true;
}

bool IsPivotLow(const int base, double &value)
{
   int    candidateShift = base + InpPivotRight + 1;
   double candidate      = iLow(_Symbol, _Period, candidateShift);
   if(candidate <= 0)
      return false;

   for(int shift = base + 1; shift <= candidateShift + InpPivotLeft; shift++)
   {
      if(shift != candidateShift && iLow(_Symbol, _Period, shift) <= candidate)
         return false;
   }
   value = candidate;
   return true;
}

// BUY: A = đáy, B = đỉnh, C = đáy mới cao hơn A
bool BuildBullSetup(const double pivotLow, const datetime pivotTime, Setup &setup)
{
   if(g_pivots.lastLow <= 0 || g_pivots.lastHigh <= 0)
      return false;
   if(g_pivots.lastLowTime >= g_pivots.lastHighTime || g_pivots.lastHighTime >= pivotTime)
      return false;
   if(pivotLow <= g_pivots.lastLow)
      return false;

   double swing = g_pivots.lastHigh - g_pivots.lastLow;
   if(swing <= 0)
      return false;

   double pullback  = (g_pivots.lastHigh - pivotLow) / swing * 100.0;
   bool   isTrendOk = !InpUseTrend || (g_pivots.prevHigh > 0 && g_pivots.lastHigh > g_pivots.prevHigh);
   if(pullback < InpMinPullback || pullback > InpMaxPullback || !isTrendOk)
      return false;

   setup.dir      = 1;
   setup.a        = g_pivots.lastLow;
   setup.aTime    = g_pivots.lastLowTime;
   setup.b        = g_pivots.lastHigh;
   setup.bTime    = g_pivots.lastHighTime;
   setup.c        = pivotLow;
   setup.cTime    = pivotTime;
   setup.leg      = SwingLeg(swing, g_pivots.lastLow, pivotLow);
   setup.pullback = pullback;
   return setup.leg > 0;
}

// SELL: A = đỉnh, B = đáy, C = đỉnh mới thấp hơn A
bool BuildBearSetup(const double pivotHigh, const datetime pivotTime, Setup &setup)
{
   if(g_pivots.lastLow <= 0 || g_pivots.lastHigh <= 0)
      return false;
   if(g_pivots.lastHighTime >= g_pivots.lastLowTime || g_pivots.lastLowTime >= pivotTime)
      return false;
   if(pivotHigh >= g_pivots.lastHigh)
      return false;

   double swing = g_pivots.lastHigh - g_pivots.lastLow;
   if(swing <= 0)
      return false;

   double pullback  = (pivotHigh - g_pivots.lastLow) / swing * 100.0;
   bool   isTrendOk = !InpUseTrend || (g_pivots.prevLow > 0 && g_pivots.lastLow < g_pivots.prevLow);
   if(pullback < InpMinPullback || pullback > InpMaxPullback || !isTrendOk)
      return false;

   setup.dir      = -1;
   setup.a        = g_pivots.lastHigh;
   setup.aTime    = g_pivots.lastHighTime;
   setup.b        = g_pivots.lastLow;
   setup.bTime    = g_pivots.lastLowTime;
   setup.c        = pivotHigh;
   setup.cTime    = pivotTime;
   setup.leg      = SwingLeg(swing, g_pivots.lastHigh, pivotHigh);
   setup.pullback = pullback;
   return setup.leg > 0;
}

double SwingLeg(const double swing, const double aPrice, const double cPrice)
{
   if(InpSwingUnit == SWING_PERCENT && aPrice != 0)
      return cPrice * (swing / aPrice);
   return swing;
}

void ApplyLevels(Setup &setup, const double buffer)
{
   setup.entry = NormalizePrice(setup.c + setup.dir * ENTRY_RATIO * setup.leg);
   setup.tp1   = NormalizePrice(setup.c + setup.dir * TP1_RATIO * setup.leg);
   setup.tp2   = NormalizePrice(setup.c + setup.dir * TP2_RATIO * setup.leg);
   setup.tp3   = NormalizePrice(setup.c + setup.dir * TP3_RATIO * setup.leg);
   setup.stop  = NormalizePrice(setup.c - setup.dir * buffer);
}

double StopBuffer()
{
   if(InpStopBufferMode == BUFFER_POINTS)
      return InpBufferPoints * _Point;

   double atr = 0.0;
   if(InpStopBufferMode == BUFFER_ATR && ReadIndicator(g_atrHandle, 0, 1, atr))
      return atr * InpBufferAtrFraction;
   return 0.0;
}

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// FILTERS
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

bool PassFilters(const int dir)
{
   if(InpUseHtf && HtfBias() != dir)
   {
      Note(StringFormat("%s pattern blocked by HTF bias", DirectionText(dir)));
      return false;
   }

   if(InpUseAdx)
   {
      double adx = 0.0;
      if(!ReadIndicator(g_adxHandle, 0, 1, adx) || adx < InpAdxThreshold)
      {
         Note(StringFormat("%s pattern blocked by ADX %.1f < %.1f", DirectionText(dir), adx, InpAdxThreshold));
         return false;
      }
   }
   return true;
}

// So sánh 2 nến HTF đã đóng gần nhất (giống request.security close[1] lookahead_on)
int HtfBias()
{
   double lastClose = iClose(_Symbol, InpHtfTimeframe, 1);
   double prevClose = iClose(_Symbol, InpHtfTimeframe, 2);
   if(lastClose == 0 || prevClose == 0 || lastClose == prevClose)
      return 0;
   return lastClose > prevClose ? 1 : -1;
}

bool IsTradeWindowOpen()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      Note("Skip: AutoTrading is disabled");
      return false;
   }

   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints)
   {
      Note(StringFormat("Skip: spread %d > %d points", spread, InpMaxSpreadPoints));
      return false;
   }

   if(InpUseRolloverFilter && IsInRolloverWindow())
   {
      Note("Skip: rollover window");
      return false;
   }
   return true;
}

bool IsInRolloverWindow()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int minute = now.hour * 60 + now.min;

   if(g_rolloverStart <= g_rolloverEnd)
      return minute >= g_rolloverStart && minute < g_rolloverEnd;
   return minute >= g_rolloverStart || minute < g_rolloverEnd;
}

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ARM SETUP: kiểm tra → tính lot → đặt 3 lệnh chờ Stop
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

void TryArmSetup(Setup &setup)
{
   if(!PassFilters(setup.dir))
      return;

   ApplyLevels(setup, StopBuffer());
   datetime armTime = iTime(_Symbol, _Period, 0);
   DrawSetup(setup, armTime);

   double atr = 0.0;
   double stopDistance = MathAbs(setup.entry - setup.stop);
   if(InpMaxStopAtr > 0 && ReadIndicator(g_atrHandle, 0, 1, atr) && stopDistance > InpMaxStopAtr * atr)
   {
      Note(StringFormat("Skip: SL distance %.2f > %.1f ATR (%.2f)", stopDistance, InpMaxStopAtr, InpMaxStopAtr * atr));
      return;
   }

   if(!IsTradeWindowOpen() || !AreLevelsPlaceable(setup))
      return;

   double lot = 0.0;
   if(!CalcLotPerOrder(setup, lot))
      return;

   if(!PlacePendingOrders(setup, lot))
   {
      DeleteOwnOrders("rollback after partial placement");
      return;
   }

   g_setup   = setup;
   g_armTime = armTime;
   g_state   = STATE_ARMED;
   PersistSetup();
   Note(StringFormat("ARMED %s entry=%s sl=%s tp3=%s lot=%.2fx%d risk=%.2f",
                     DirectionText(setup.dir), PriceText(setup.entry), PriceText(setup.stop),
                     PriceText(setup.tp3), lot, TP_ORDER_COUNT, g_lastRiskMoney));
}

bool AreLevelsPlaceable(const Setup &setup)
{
   double ask         = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid         = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   long   stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDistance = (double)MathMax(stopsLevel, freezeLevel) * _Point;
   bool   isLong      = setup.dir == 1;

   bool isEntryAhead = isLong ? setup.entry > ask + minDistance : setup.entry < bid - minDistance;
   if(!isEntryAhead)
   {
      Note(StringFormat("Skip: price already beyond Entry %s", PriceText(setup.entry)));
      return false;
   }

   if(MathAbs(setup.entry - setup.stop) < minDistance || MathAbs(setup.tp1 - setup.entry) < minDistance)
   {
      Note("Skip: SL/TP closer than broker stops level");
      return false;
   }
   return true;
}

bool CalcLotPerOrder(const Setup &setup, double &lot)
{
   ENUM_ORDER_TYPE calcType = setup.dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double profitPerLot = 0.0;
   if(!OrderCalcProfit(calcType, _Symbol, 1.0, setup.entry, setup.stop, profitPerLot) || profitPerLot >= 0)
   {
      Note(StringFormat("Skip: cannot calculate loss per lot, error=%d", GetLastError()));
      return false;
   }

   double lossPerLot = -profitPerLot;
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney  = balance * InpRiskPercent / 100.0;
   double minLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lot = FloorToLotStep(riskMoney / lossPerLot / TP_ORDER_COUNT);
   lot = MathMin(MathMax(lot, minLot), maxLot);

   double actualRisk = lot * TP_ORDER_COUNT * lossPerLot;
   double maxRisk    = balance * InpMaxRiskPercent / 100.0;
   if(actualRisk > maxRisk)
   {
      Note(StringFormat("Skip: risk %.2f > max %.2f (min lot %.2f x %d, SL %.2f)",
                        actualRisk, maxRisk, minLot, TP_ORDER_COUNT, MathAbs(setup.entry - setup.stop)));
      return false;
   }

   double margin = 0.0;
   if(OrderCalcMargin(calcType, _Symbol, lot * TP_ORDER_COUNT, setup.entry, margin) &&
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      Note(StringFormat("Skip: margin %.2f > free margin %.2f", margin, AccountInfoDouble(ACCOUNT_MARGIN_FREE)));
      return false;
   }

   g_lastRiskMoney = actualRisk;
   return true;
}

bool PlacePendingOrders(const Setup &setup, const double lot)
{
   double targets[TP_ORDER_COUNT];
   targets[0] = setup.tp1;
   targets[1] = setup.tp2;
   targets[2] = setup.tp3;

   for(int i = 0; i < TP_ORDER_COUNT; i++)
   {
      string comment = StringFormat("%s TP%d", InpTradeComment, i + 1);
      bool isSent = setup.dir == 1
                    ? g_trade.BuyStop(lot, setup.entry, _Symbol, setup.stop, targets[i], ORDER_TIME_GTC, 0, comment)
                    : g_trade.SellStop(lot, setup.entry, _Symbol, setup.stop, targets[i], ORDER_TIME_GTC, 0, comment);

      uint retcode = g_trade.ResultRetcode();
      if(!isSent || (retcode != TRADE_RETCODE_DONE && retcode != TRADE_RETCODE_PLACED))
      {
         PrintFormat("%s Place TP%d failed retcode=%u %s", LOG_TAG, i + 1, retcode, g_trade.ResultRetcodeDescription());
         return false;
      }
   }
   return true;
}

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// STATE MANAGEMENT
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Trạng thái luôn suy ra từ lệnh thật trên server, không tin vào biến cũ
void SyncState()
{
   int              positions = CountOwnPositions();
   int              orders    = CountOwnOrders();
   ENUM_SETUP_STATE previous  = g_state;

   if(positions > 0)
   {
      if(orders > 0)
         DeleteOwnOrders("leftover pending after entry");
      g_state = STATE_ACTIVE;
   }
   else if(orders > 0)
      g_state = STATE_ARMED;
   else
      g_state = STATE_NONE;

   if(previous == STATE_ARMED && g_state == STATE_ACTIVE)
      Note(StringFormat("ENTRY triggered %s @ %s", DirectionText(g_setup.dir), PriceText(g_setup.entry)));

   if(previous != STATE_NONE && g_state == STATE_NONE)
   {
      Note("Setup closed (SL/TP hit or orders removed)");
      ClearPersistedSetup();
   }
}

void CheckArmedCancel()
{
   bool isLong     = g_setup.dir == 1;
   bool isCBroken  = isLong ? iLow(_Symbol, _Period, 1) < g_setup.c : iHigh(_Symbol, _Period, 1) > g_setup.c;
   int  barsArmed  = iBarShift(_Symbol, _Period, g_armTime);
   bool isExpired  = barsArmed >= InpExpiryBars;

   if(!isCBroken && !isExpired)
      return;

   DeleteOwnOrders(isCBroken ? "C broken" : "expired");
   ClearPersistedSetup();
   g_state = STATE_NONE;
}

// Chạy mỗi tick: giá chạm TP1 → dời SL các lệnh còn lại về giá vào
void ManageBreakeven()
{
   if(!InpUseBreakeven || g_setup.dir == 0 || g_setup.tp1 <= 0)
      return;

   bool isLong = g_setup.dir == 1;
   bool isTp1Reached = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_BID) >= g_setup.tp1
                              : SymbolInfoDouble(_Symbol, SYMBOL_ASK) <= g_setup.tp1;
   if(!isTp1Reached)
      return;

   static datetime s_lastFailLogBar = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsOwnPosition(ticket))
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double stopLoss  = PositionGetDouble(POSITION_SL);
      double takeProfit = PositionGetDouble(POSITION_TP);
      bool   isProtected = isLong ? stopLoss >= openPrice : (stopLoss > 0 && stopLoss <= openPrice);
      if(isProtected)
         continue;

      if(g_trade.PositionModify(ticket, NormalizePrice(openPrice), takeProfit))
         PrintFormat("%s Breakeven ticket=%I64u sl=%s", LOG_TAG, ticket, PriceText(openPrice));
      else if(s_lastFailLogBar != g_lastBarTime)
      {
         s_lastFailLogBar = g_lastBarTime;
         PrintFormat("%s Breakeven failed ticket=%I64u retcode=%u %s", LOG_TAG, ticket,
                     g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      }
   }
}

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PERSISTENCE (Global Variables) — để khởi động lại vẫn quản lý được setup
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

string GvPrefix()
{
   return StringFormat("TRIDENT_%s_%I64u_", _Symbol, InpMagicNumber);
}

void PersistSetup()
{
   string prefix = GvPrefix();
   GlobalVariableSet(prefix + "dir",   g_setup.dir);
   GlobalVariableSet(prefix + "c",     g_setup.c);
   GlobalVariableSet(prefix + "entry", g_setup.entry);
   GlobalVariableSet(prefix + "stop",  g_setup.stop);
   GlobalVariableSet(prefix + "tp1",   g_setup.tp1);
   GlobalVariableSet(prefix + "tp2",   g_setup.tp2);
   GlobalVariableSet(prefix + "tp3",   g_setup.tp3);
   GlobalVariableSet(prefix + "arm",   (double)g_armTime);
}

bool LoadPersistedSetup()
{
   string prefix = GvPrefix();
   if(!GlobalVariableCheck(prefix + "dir"))
      return false;

   ZeroMemory(g_setup);
   g_setup.dir   = (int)GlobalVariableGet(prefix + "dir");
   g_setup.c     = GlobalVariableGet(prefix + "c");
   g_setup.entry = GlobalVariableGet(prefix + "entry");
   g_setup.stop  = GlobalVariableGet(prefix + "stop");
   g_setup.tp1   = GlobalVariableGet(prefix + "tp1");
   g_setup.tp2   = GlobalVariableGet(prefix + "tp2");
   g_setup.tp3   = GlobalVariableGet(prefix + "tp3");
   g_armTime     = (datetime)GlobalVariableGet(prefix + "arm");
   return true;
}

void ClearPersistedSetup()
{
   GlobalVariablesDeleteAll(GvPrefix());
}

void RecoverSetup()
{
   if(LoadPersistedSetup())
   {
      Note(StringFormat("Recovered %s setup (%s)", DirectionText(g_setup.dir), StateText()));
      DrawSetup(g_setup, g_armTime);
      return;
   }

   DeriveSetupFromTrades();
   PersistSetup();
   Note(StringFormat("Recovered %s setup from open trades (C approximated by SL)", DirectionText(g_setup.dir)));
}

// Dự phòng khi mất Global Variables: suy ra mức giá từ lệnh đang mở
void DeriveSetupFromTrades()
{
   ZeroMemory(g_setup);
   double targets[];

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsOwnPosition(ticket))
         continue;
      g_setup.dir   = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      g_setup.entry = PositionGetDouble(POSITION_PRICE_OPEN);
      g_setup.stop  = PositionGetDouble(POSITION_SL);
      AppendValue(targets, PositionGetDouble(POSITION_TP));
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!IsOwnOrder(ticket))
         continue;
      g_setup.dir   = OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP ? 1 : -1;
      g_setup.entry = OrderGetDouble(ORDER_PRICE_OPEN);
      g_setup.stop  = OrderGetDouble(ORDER_SL);
      g_armTime     = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      AppendValue(targets, OrderGetDouble(ORDER_TP));
   }

   g_setup.c = g_setup.stop;
   int count = ArraySize(targets);
   if(count == 0)
      return;

   ArraySort(targets);
   bool isLong = g_setup.dir == 1;
   g_setup.tp1 = isLong ? targets[0] : targets[count - 1];
   g_setup.tp3 = isLong ? targets[count - 1] : targets[0];
}

void AppendValue(double &values[], const double value)
{
   int size = ArraySize(values);
   ArrayResize(values, size + 1);
   values[size] = value;
}

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ORDER / POSITION HELPERS
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

bool IsOwnPosition(const ulong ticket)
{
   return PositionSelectByTicket(ticket) &&
          PositionGetString(POSITION_SYMBOL) == _Symbol &&
          (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber;
}

bool IsOwnOrder(const ulong ticket)
{
   return OrderSelect(ticket) &&
          OrderGetString(ORDER_SYMBOL) == _Symbol &&
          (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagicNumber;
}

int CountOwnPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(IsOwnPosition(PositionGetTicket(i)))
         count++;
   }
   return count;
}

int CountOwnOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(IsOwnOrder(OrderGetTicket(i)))
         count++;
   }
   return count;
}

void DeleteOwnOrders(const string reason)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!IsOwnOrder(ticket))
         continue;

      if(g_trade.OrderDelete(ticket))
         PrintFormat("%s Deleted order ticket=%I64u (%s)", LOG_TAG, ticket, reason);
      else
         PrintFormat("%s Delete failed ticket=%I64u retcode=%u %s", LOG_TAG, ticket,
                     g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   }
   Note(StringFormat("Pending orders removed: %s", reason));
}

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// UTILS
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

bool ReadIndicator(const int handle, const int bufferIndex, const int shift, double &value)
{
   double buffer[1];
   if(CopyBuffer(handle, bufferIndex, shift, 1, buffer) != 1)
      return false;
   value = buffer[0];
   return true;
}

double NormalizePrice(const double price)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0)
      return NormalizeDouble(price, _Digits);
   return NormalizeDouble(MathRound(price / tickSize) * tickSize, _Digits);
}

double FloorToLotStep(const double lot)
{
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   int    digits = (int)MathMax(0, MathCeil(-MathLog10(step)));
   return NormalizeDouble(MathFloor(lot / step) * step, digits);
}

void Note(const string message)
{
   g_lastNote = message;
   PrintFormat("%s %s", LOG_TAG, message);
}

string DirectionText(const int dir)
{
   if(dir == 1)
      return "LONG";
   if(dir == -1)
      return "SHORT";
   return "-";
}

string StateText()
{
   if(g_state == STATE_ARMED)
      return "ARMED";
   if(g_state == STATE_ACTIVE)
      return "ACTIVE";
   return "NONE";
}

string PriceText(const double price)
{
   if(price <= 0)
      return "-";
   return DoubleToString(price, _Digits);
}

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// DRAWING + PANEL
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

void DrawSetup(const Setup &setup, const datetime armTime)
{
   if(!InpDrawLevels)
      return;

   ObjectsDeleteAll(0, OBJ_PREFIX);
   datetime startTime = setup.cTime > 0 ? setup.cTime : armTime;
   datetime endTime   = armTime + (datetime)(PeriodSeconds(_Period) * InpExpiryBars);

   DrawLevel("SL",    startTime, endTime, setup.stop,  clrTomato,         STYLE_SOLID, 2);
   DrawLevel("ENTRY", startTime, endTime, setup.entry, clrDodgerBlue,     STYLE_DASH,  1);
   DrawLevel("TP1",   startTime, endTime, setup.tp1,   clrMediumSeaGreen, STYLE_DASH,  1);
   DrawLevel("TP2",   startTime, endTime, setup.tp2,   clrMediumSeaGreen, STYLE_DASH,  1);
   DrawLevel("TP3",   startTime, endTime, setup.tp3,   clrLimeGreen,      STYLE_DASH,  1);

   bool isLong = setup.dir == 1;
   DrawPoint("A", setup.aTime, setup.a, isLong ? ANCHOR_UPPER : ANCHOR_LOWER);
   DrawPoint("B", setup.bTime, setup.b, isLong ? ANCHOR_LOWER : ANCHOR_UPPER);
   DrawPoint("C", setup.cTime, setup.c, isLong ? ANCHOR_UPPER : ANCHOR_LOWER);
   ChartRedraw();
}

void DrawLevel(const string name, const datetime startTime, const datetime endTime,
               const double price, const color lineColor, const ENUM_LINE_STYLE style, const int width)
{
   if(price <= 0)
      return;

   string lineId = OBJ_PREFIX + name;
   ObjectCreate(0, lineId, OBJ_TREND, 0, startTime, price, endTime, price);
   ObjectSetInteger(0, lineId, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, lineId, OBJPROP_STYLE, style);
   ObjectSetInteger(0, lineId, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, lineId, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, lineId, OBJPROP_SELECTABLE, false);

   string labelId = lineId + "_LBL";
   ObjectCreate(0, labelId, OBJ_TEXT, 0, endTime, price);
   ObjectSetString(0, labelId, OBJPROP_TEXT, name + " " + PriceText(price));
   ObjectSetInteger(0, labelId, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, labelId, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, labelId, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, labelId, OBJPROP_SELECTABLE, false);
}

void DrawPoint(const string name, const datetime time, const double price, const ENUM_ANCHOR_POINT anchor)
{
   if(time <= 0 || price <= 0)
      return;

   string id = OBJ_PREFIX + "PT_" + name;
   ObjectCreate(0, id, OBJ_TEXT, 0, time, price);
   ObjectSetString(0, id, OBJPROP_TEXT, name);
   ObjectSetInteger(0, id, OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(0, id, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, id, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
}

void UpdatePanel()
{
   if(!InpShowPanel)
      return;

   Comment(StringFormat(
      "TRIDENT SWING EA\n"
      "State    : %s %s\n"
      "Entry    : %s\n"
      "SL       : %s\n"
      "TP1/2/3  : %s / %s / %s\n"
      "Risk     : %.2f %s\n"
      "Pos/Ord  : %d / %d\n"
      "Spread   : %d pts\n"
      "Last     : %s",
      StateText(), DirectionText(g_setup.dir),
      PriceText(g_setup.entry),
      PriceText(g_setup.stop),
      PriceText(g_setup.tp1), PriceText(g_setup.tp2), PriceText(g_setup.tp3),
      g_lastRiskMoney, AccountInfoString(ACCOUNT_CURRENCY),
      CountOwnPositions(), CountOwnOrders(),
      (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD),
      g_lastNote));
}
//+------------------------------------------------------------------+
