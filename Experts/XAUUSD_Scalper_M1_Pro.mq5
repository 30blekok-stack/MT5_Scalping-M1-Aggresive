//+------------------------------------------------------------------+
//|                                      XAUUSD_Scalper_M1_Pro.mq5    |
//|              EA Scalping Trend-Following M1 (versi UPGRADE)       |
//|                                                                  |
//|  Entry dasar (MA, berbasis KEADAAN, bukan transisi/cross):       |
//|    - Dua MA di M1: fast (default EMA 8) & slow (default EMA 21).  |
//|    - BUY  bila CLOSE bar shift 1 DI ATAS kedua MA.               |
//|    - SELL bila CLOSE bar shift 1 DI BAWAH kedua MA.              |
//|    - Evaluasi sekali per bar M1 baru. Maksimal 1 posisi.         |
//|      Re-entry diizinkan setelah posisi tutup.                    |
//|    - UseFullCandle: pakai low/high seluruh candle, bukan close.  |
//|                                                                  |
//|  Filter penyaring noise (masing-masing bisa on/off):            |
//|    1. Tren Higher-Timeframe (EMA M15).                          |
//|    2. Kekuatan tren ADX (default M5).                          |
//|    3. Slope & jarak MA (gap minimal, fast naik/turun, tidak     |
//|       mengejar harga terlalu jauh dari fast MA).                |
//|    4. Sesi/jam (jam server).                                    |
//|    5. Guard volatilitas ATR M1 (min & max).                    |
//|                                                                  |
//|  Stop Loss: hard SL tetap (points) ATAU berbasis ATR M1.        |
//|  Manajemen profit (tiap tick): Partial TP + runner, Breakeven,  |
//|  lalu Trailing (hanya setelah breakeven). SL tak pernah mundur. |
//|                                                                  |
//|  ============= CATATAN PENTING tentang "POINTS" ==============  |
//|  Semua input jarak/ATR ber-satuan POINTS. Arti 1 point          |
//|  bergantung jumlah digit harga broker XAUUSD:                   |
//|     - Broker 2 digit -> 1 point = 0.01  (300 pt = 3.00 USD)     |
//|     - Broker 3 digit -> 1 point = 0.001 (300 pt = 0.30 USD)     |
//|  Bila broker Anda 3 digit, kalikan kira-kira 10x semua input    |
//|  points (SL, TP parsial, breakeven, trailing, gap/jarak MA,     |
//|  ATR min/max, spread). Cek "Digits" simbol lalu sesuaikan.      |
//|  Catatan jam: EndHour bersifat EKSKLUSIF (mis. 8-20 = entry     |
//|  pada jam 08:00..19:59 waktu server).                          |
//+------------------------------------------------------------------+
#property copyright "30blekok-stack"
#property version   "2.00"
#property description "Scalping trend-following XAUUSD M1 (state-based) + 5 filter + partial TP/breakeven/trailing."
#property description "Semua input jarak ber-satuan points (lihat catatan header untuk broker 2 vs 3 digit)."

#include <Trade/Trade.mqh>

//--- Objek trading dari library standar
CTrade trade;

//======================= INPUT (dikelompokkan agar rapi) ===========
input group "=== Moving Average (M1) ==="
input int                InpFastMA        = 8;            // Periode Fast MA
input int                InpSlowMA        = 21;           // Periode Slow MA
input ENUM_MA_METHOD     InpMAMethod      = MODE_EMA;     // Metode MA
input ENUM_APPLIED_PRICE InpAppliedPrice  = PRICE_CLOSE;  // Applied price
input bool               InpUseFullCandle = false;        // Pakai SELURUH candle (low/high), bukan close saja

input group "=== Filter 1: Tren Higher-Timeframe (M15) ==="
input bool   InpUseHTFTrend = true;                       // Aktifkan filter tren HTF
input int    InpHTFPeriod   = 50;                         // Periode EMA M15

input group "=== Filter 2: Kekuatan Tren ADX ==="
input bool            InpUseADX       = true;             // Aktifkan filter ADX
input int             InpADXPeriod    = 14;               // Periode ADX
input ENUM_TIMEFRAMES InpADXTimeframe = PERIOD_M5;        // Timeframe ADX
input double          InpADXThreshold = 20.0;             // ADX minimum untuk entry (turun = lebih banyak entry)

input group "=== Filter 3: Slope & Jarak MA ==="
input bool   InpUseMAFilter    = true;                    // Aktifkan filter slope/jarak MA
input int    InpMinMAGapPoints = 5;                       // Jarak minimal fast-slow MA (points) - kecil = mudah entry
input int    InpMaxDistPoints  = 300;                     // Jarak maksimal harga ke fast MA (points)

input group "=== Filter 4: Sesi / Jam (jam server) ==="
input bool   InpUseSessionFilter = false;                 // Aktifkan filter sesi (OFF default: hindari salah zona server)
input int    InpStartHour        = 8;                     // Jam mulai (inklusif) - JAM SERVER
input int    InpEndHour          = 20;                    // Jam selesai (eksklusif) - JAM SERVER

input group "=== Filter 5: Guard Volatilitas ATR (M1) ==="
input bool   InpUseATRGuard  = true;                      // Aktifkan guard volatilitas
input int    InpATRPeriod    = 14;                        // Periode ATR M1
input int    InpMinATRPoints = 5;                         // ATR minimum (points) - hindari pasar sepi
input int    InpMaxATRPoints = 500;                       // ATR maksimum (points) - hindari spike

input group "=== Filter Umum ==="
input int    InpMaxSpreadPoints = 50;                     // Spread maksimum untuk entry (points)

input group "=== Stop Loss ==="
input bool   InpUseATRStop     = false;                   // true = SL berbasis ATR; false = SL tetap
input int    InpStopLossPoints = 300;                     // Hard SL tetap (points) - dipakai bila UseATRStop=false
input double InpATRStopMult    = 1.5;                     // Pengali ATR untuk SL - dipakai bila UseATRStop=true

input group "=== Profit: Partial TP + Runner ==="
input bool   InpUsePartialTP        = true;               // Aktifkan partial take profit
input int    InpPartialTPPoints     = 120;                // Profit pemicu partial close (points)
input double InpPartialClosePercent = 50.0;               // Persentase volume yang ditutup (%)

input group "=== Profit: Breakeven ==="
input int    InpBreakevenTrigger = 150;                   // Profit pemicu breakeven (points)
input int    InpBreakevenBuffer  = 20;                    // Buffer SL dari entry saat breakeven (points)

input group "=== Profit: Trailing ==="
input int    InpTrailingDistance = 150;                   // Jarak trailing SL dari harga (points)
input int    InpTrailingStep     = 30;                    // Langkah minimal geser trailing (points)

input group "=== Lot & Identitas ==="
input double InpLotSize     = 0.01;                       // Ukuran lot
input long   InpMagicNumber = 20250727;                   // Magic number (identitas posisi EA)

input group "=== Diagnostik (debug 'tidak ada transaksi') ==="
input bool   InpDebugMode   = false;                      // Cetak alasan tiap sinyal ditolak ke Experts log

//--- Kode alasan penolakan filter (untuk diagnostik)
enum ENUM_FILTER_RESULT
{
   FILTER_OK = 0,   // semua filter lolos
   FILTER_HTF,      // ditolak filter tren HTF
   FILTER_ADX,      // ditolak filter ADX
   FILTER_MASLOPE,  // ditolak filter slope/jarak MA
   FILTER_SESSION,  // ditolak filter sesi
   FILTER_ATR,      // ditolak guard ATR
   FILTER_NODATA    // data indikator belum siap
};

//======================= VARIABEL GLOBAL ==========================
int      g_maFastHandle = INVALID_HANDLE;   // handle Fast MA (M1)
int      g_maSlowHandle = INVALID_HANDLE;   // handle Slow MA (M1)
int      g_htfHandle    = INVALID_HANDLE;   // handle EMA HTF (M15)
int      g_adxHandle    = INVALID_HANDLE;   // handle ADX
int      g_atrHandle    = INVALID_HANDLE;   // handle ATR (M1)

datetime g_lastBarTime      = 0;            // waktu open bar M1 terakhir yang dievaluasi
ulong    g_partialDoneTicket = 0;           // ticket posisi yang partial TP-nya sudah dilakukan
int      g_volDigits        = 2;            // jumlah desimal volume (dari SYMBOL_VOLUME_STEP)

//--- Penghitung diagnostik (dicetak ringkasannya di OnDeinit)
long     g_cntSignal  = 0;   // jumlah sinyal dasar MA saat flat
long     g_cntSpread  = 0;   // ditolak spread
long     g_cntHTF     = 0;   // ditolak filter HTF
long     g_cntADX     = 0;   // ditolak filter ADX
long     g_cntMA      = 0;   // ditolak filter slope/jarak MA
long     g_cntSession = 0;   // ditolak filter sesi
long     g_cntATR     = 0;   // ditolak guard ATR
long     g_cntNoData  = 0;   // ditolak karena data belum siap
long     g_cntOpened  = 0;   // entry dieksekusi

//+------------------------------------------------------------------+
//| OnInit — buat semua handle indikator & konfigurasi trading       |
//+------------------------------------------------------------------+
int OnInit()
{
   // --- MA fast & slow di M1 (dipaksa M1 walau chart TF lain)
   g_maFastHandle = iMA(_Symbol, PERIOD_M1, InpFastMA, 0, InpMAMethod, InpAppliedPrice);
   g_maSlowHandle = iMA(_Symbol, PERIOD_M1, InpSlowMA, 0, InpMAMethod, InpAppliedPrice);
   // --- EMA HTF di M15 untuk filter tren
   g_htfHandle    = iMA(_Symbol, PERIOD_M15, InpHTFPeriod, 0, MODE_EMA, PRICE_CLOSE);
   // --- ADX di timeframe pilihan
   g_adxHandle    = iADX(_Symbol, InpADXTimeframe, InpADXPeriod);
   // --- ATR di M1 (dipakai guard volatilitas & SL berbasis ATR)
   g_atrHandle    = iATR(_Symbol, PERIOD_M1, InpATRPeriod);

   if(g_maFastHandle == INVALID_HANDLE || g_maSlowHandle == INVALID_HANDLE ||
      g_htfHandle == INVALID_HANDLE || g_adxHandle == INVALID_HANDLE ||
      g_atrHandle == INVALID_HANDLE)
   {
      Print("ERROR: gagal membuat salah satu handle indikator.");
      return(INIT_FAILED);
   }

   // --- Konfigurasi CTrade
   trade.SetExpertMagicNumber((ulong)InpMagicNumber);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   // --- Hitung jumlah desimal volume dari step (untuk normalisasi lot)
   g_volDigits = CalcVolumeDigits();

   // --- Mulai evaluasi pada bar M1 berikutnya (hindari entry saat attach)
   g_lastBarTime = iTime(_Symbol, PERIOD_M1, 0);

   // --- Peringatan konfigurasi ringan
   if(InpFastMA >= InpSlowMA)
      Print("PERINGATAN: FastMA >= SlowMA, hasil strategi mungkin tidak sesuai harapan.");
   if(InpUsePartialTP && InpPartialTPPoints > InpBreakevenTrigger)
      Print("INFO: PartialTPPoints > BreakevenTrigger — breakeven bisa terjadi sebelum partial TP.");

   Print("EA XAUUSD Scalper M1 Pro aktif. Simbol=", _Symbol,
         " Digits=", _Digits, " Point=", DoubleToString(_Point, _Digits),
         " StopsLevel=", SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL), " pt.");

   // --- Info skala points supaya mudah cek 2 vs 3 digit ---
   Print("SKALA: 100 pt = ", DoubleToString(100 * _Point, _Digits),
         " | 1000 pt = ", DoubleToString(1000 * _Point, _Digits), " (harga).",
         " Jika ini tidak sesuai harapan, nilai points Anda salah skala (2 vs 3 digit).");
   if(_Digits <= 2 && InpStopLossPoints >= 1000)
      Print("PERINGATAN: broker tampak 2 digit tapi StopLossPoints=", InpStopLossPoints,
            " (=", DoubleToString(InpStopLossPoints * _Point, _Digits),
            " harga). Nilai points mungkin 10x terlalu besar. Bagi 10.");
   if(_Digits >= 3 && InpStopLossPoints > 0 && InpStopLossPoints < 500)
      Print("PERINGATAN: broker tampak 3 digit tapi StopLossPoints=", InpStopLossPoints,
            " (=", DoubleToString(InpStopLossPoints * _Point, _Digits),
            " harga). Nilai points mungkin 10x terlalu kecil. Kali 10.");

   // --- Reset penghitung diagnostik ---
   ResetCounters();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit — lepas semua handle indikator                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Cetak ringkasan diagnostik (sangat membantu saat 'tidak ada transaksi').
   PrintSummary();

   // Bebaskan resource semua handle
   if(g_maFastHandle != INVALID_HANDLE) IndicatorRelease(g_maFastHandle);
   if(g_maSlowHandle != INVALID_HANDLE) IndicatorRelease(g_maSlowHandle);
   if(g_htfHandle    != INVALID_HANDLE) IndicatorRelease(g_htfHandle);
   if(g_adxHandle    != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if(g_atrHandle    != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
}

//+------------------------------------------------------------------+
//| ResetCounters — nolkan semua penghitung diagnostik               |
//+------------------------------------------------------------------+
void ResetCounters()
{
   g_cntSignal  = 0; g_cntSpread = 0; g_cntHTF = 0; g_cntADX = 0;
   g_cntMA      = 0; g_cntSession = 0; g_cntATR = 0; g_cntNoData = 0;
   g_cntOpened  = 0;
}

//+------------------------------------------------------------------+
//| PrintSummary — ringkasan mengapa entry terjadi / tidak terjadi   |
//+------------------------------------------------------------------+
void PrintSummary()
{
   Print("===== RINGKASAN DIAGNOSTIK EA =====");
   Print("Sinyal dasar MA (saat flat) : ", g_cntSignal);
   Print("  ditolak spread            : ", g_cntSpread);
   Print("  ditolak filter HTF        : ", g_cntHTF);
   Print("  ditolak filter ADX        : ", g_cntADX);
   Print("  ditolak filter slope/MA   : ", g_cntMA);
   Print("  ditolak filter sesi       : ", g_cntSession);
   Print("  ditolak guard ATR         : ", g_cntATR);
   Print("  data indikator belum siap : ", g_cntNoData);
   Print("ENTRY DIEKSEKUSI            : ", g_cntOpened);
   if(g_cntSignal == 0)
      Print("Catatan: TIDAK ADA sinyal dasar sama sekali. Cek data M1 / periode MA / rentang tanggal.");
   else if(g_cntOpened == 0)
      Print("Catatan: ada sinyal tapi 0 entry. Lihat filter dgn angka penolakan terbesar, lalu longgarkan/matikan.");
   Print("===================================");
}

//+------------------------------------------------------------------+
//| OnTick — alur utama tiap tick                                    |
//+------------------------------------------------------------------+
void OnTick()
{
   // Jika trading tidak diizinkan, jangan lakukan apa pun (aman di tester).
   if(!IsTradingAllowed())
      return;

   // 1) Kelola posisi terbuka SETIAP tick (partial TP, breakeven, trailing).
   //    Dijalankan lebih dulu agar posisi tetap dikelola walau di luar sesi.
   ManagePosition();

   // 2) Evaluasi sinyal HANYA sekali per bar M1 baru.
   if(!IsNewBar())
      return;

   // 3) Maksimal 1 posisi.
   if(HasOpenPosition())
      return;

   // 4) Sinyal dasar MA (dihitung dulu agar diagnostik akurat).
   int signal = CheckBaseSignal();
   if(signal == 0)
      return;
   g_cntSignal++;

   // 5) Filter spread.
   if(SpreadTooHigh())
   {
      g_cntSpread++;
      if(InpDebugMode)
         Print("[TOLAK] spread ", DoubleToString(CurrentSpreadPoints(), 1),
               " pt > MaxSpreadPoints ", InpMaxSpreadPoints);
      return;
   }

   // 6) Filter penyaring noise — catat alasan penolakan untuk diagnostik.
   ENUM_FILTER_RESULT res = CheckFilters(signal);
   if(res != FILTER_OK)
   {
      CountReject(res);
      if(InpDebugMode)
         Print("[TOLAK] ", (signal > 0 ? "BUY" : "SELL"), " oleh ", FilterName(res));
      return;
   }

   // 7) Eksekusi.
   OpenTrade(signal > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   g_cntOpened++;
   if(InpDebugMode)
      Print("[ENTRY] ", (signal > 0 ? "BUY" : "SELL"), " lolos semua filter.");
}

//+------------------------------------------------------------------+
//| IsTradingAllowed — izin trading (di Strategy Tester selalu true) |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
   if(MQLInfoInteger(MQL_TESTER))
      return(true);  // di dalam tester, TERMINAL_TRADE_ALLOWED bisa false — abaikan
   return(MQLInfoInteger(MQL_TRADE_ALLOWED) && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED));
}

//+------------------------------------------------------------------+
//| CurrentSpreadPoints — spread saat ini dalam points               |
//+------------------------------------------------------------------+
double CurrentSpreadPoints()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return((ask - bid) / _Point);
}

//+------------------------------------------------------------------+
//| CountReject — tambah penghitung sesuai alasan penolakan filter   |
//+------------------------------------------------------------------+
void CountReject(const ENUM_FILTER_RESULT res)
{
   switch(res)
   {
      case FILTER_HTF:     g_cntHTF++;     break;
      case FILTER_ADX:     g_cntADX++;     break;
      case FILTER_MASLOPE: g_cntMA++;      break;
      case FILTER_SESSION: g_cntSession++; break;
      case FILTER_ATR:     g_cntATR++;     break;
      case FILTER_NODATA:  g_cntNoData++;  break;
      default: break;
   }
}

//+------------------------------------------------------------------+
//| FilterName — nama alasan penolakan (untuk log)                   |
//+------------------------------------------------------------------+
string FilterName(const ENUM_FILTER_RESULT res)
{
   switch(res)
   {
      case FILTER_HTF:     return("filter Tren HTF");
      case FILTER_ADX:     return("filter ADX");
      case FILTER_MASLOPE: return("filter slope/jarak MA");
      case FILTER_SESSION: return("filter Sesi");
      case FILTER_ATR:     return("guard ATR");
      case FILTER_NODATA:  return("data indikator belum siap");
      default:             return("(tidak ada)");
   }
}

//+------------------------------------------------------------------+
//| IsNewBar — true sekali tiap bar M1 baru                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| GetBuf — ambil satu nilai buffer indikator pada shift tertentu   |
//+------------------------------------------------------------------+
bool GetBuf(const int handle, const int bufIndex, const int shift, double &value)
{
   double tmp[];
   if(CopyBuffer(handle, bufIndex, shift, 1, tmp) < 1)
      return(false);
   value = tmp[0];
   return(true);
}

//+------------------------------------------------------------------+
//| CheckBaseSignal — sinyal dasar MA: +1 buy, -1 sell, 0 tidak ada  |
//+------------------------------------------------------------------+
int CheckBaseSignal()
{
   // Nilai MA pada bar yang SUDAH tutup (shift 1).
   double maFast, maSlow;
   if(!GetBuf(g_maFastHandle, 0, 1, maFast)) return(0);
   if(!GetBuf(g_maSlowHandle, 0, 1, maSlow)) return(0);

   double close1 = iClose(_Symbol, PERIOD_M1, 1);
   if(close1 <= 0.0) return(0);

   if(InpUseFullCandle)
   {
      // Seluruh candle harus di atas/di bawah kedua MA.
      double low1  = iLow(_Symbol, PERIOD_M1, 1);
      double high1 = iHigh(_Symbol, PERIOD_M1, 1);
      if(low1 > maFast && low1 > maSlow)  return(1);   // BUY
      if(high1 < maFast && high1 < maSlow) return(-1);  // SELL
   }
   else
   {
      // Cukup close bar shift 1.
      if(close1 > maFast && close1 > maSlow) return(1);   // BUY
      if(close1 < maFast && close1 < maSlow) return(-1);  // SELL
   }
   return(0);
}

//+------------------------------------------------------------------+
//| CheckFilters — jalankan semua filter aktif                       |
//|   Return FILTER_OK bila lolos, atau kode alasan penolakan.       |
//|   signal: +1 (buy) / -1 (sell)                                   |
//+------------------------------------------------------------------+
ENUM_FILTER_RESULT CheckFilters(const int signal)
{
   double close1 = iClose(_Symbol, PERIOD_M1, 1);
   double point  = _Point;

   //--- Filter 1: Tren Higher-Timeframe (EMA M15) ---
   if(InpUseHTFTrend)
   {
      double htfEMA;
      if(!GetBuf(g_htfHandle, 0, 0, htfEMA)) return(FILTER_NODATA);
      if(signal > 0 && !(close1 > htfEMA)) return(FILTER_HTF);   // BUY hanya bila di atas EMA HTF
      if(signal < 0 && !(close1 < htfEMA)) return(FILTER_HTF);   // SELL hanya bila di bawah EMA HTF
   }

   //--- Filter 2: Kekuatan tren ADX (hindari sideways) ---
   if(InpUseADX)
   {
      double adx;
      if(!GetBuf(g_adxHandle, 0, 1, adx)) return(FILTER_NODATA); // garis ADX utama, bar tutup
      if(adx < InpADXThreshold) return(FILTER_ADX);
   }

   //--- Filter 3: Slope & jarak MA ---
   if(InpUseMAFilter)
   {
      double fast1, fast2, slow1;
      if(!GetBuf(g_maFastHandle, 0, 1, fast1)) return(FILTER_NODATA);
      if(!GetBuf(g_maFastHandle, 0, 2, fast2)) return(FILTER_NODATA);
      if(!GetBuf(g_maSlowHandle, 0, 1, slow1)) return(FILTER_NODATA);

      double gap     = MathAbs(fast1 - slow1);
      double minGap  = InpMinMAGapPoints * point;
      double maxDist = InpMaxDistPoints  * point;

      if(signal > 0)
      {
         if(!(fast1 > slow1))            return(FILTER_MASLOPE);  // fast di atas slow
         if(gap < minGap)                return(FILTER_MASLOPE);  // jarak fast-slow cukup lebar
         if(!(fast1 > fast2))            return(FILTER_MASLOPE);  // fast sedang naik
         if((close1 - fast1) > maxDist)  return(FILTER_MASLOPE);  // harga tidak terlalu jauh di atas fast
      }
      else
      {
         if(!(fast1 < slow1))            return(FILTER_MASLOPE);  // fast di bawah slow
         if(gap < minGap)                return(FILTER_MASLOPE);
         if(!(fast1 < fast2))            return(FILTER_MASLOPE);  // fast sedang turun
         if((fast1 - close1) > maxDist)  return(FILTER_MASLOPE);  // harga tidak terlalu jauh di bawah fast
      }
   }

   //--- Filter 4: Sesi / jam ---
   if(InpUseSessionFilter && !InSession())
      return(FILTER_SESSION);

   //--- Filter 5: Guard volatilitas ATR M1 ---
   if(InpUseATRGuard)
   {
      double atr;
      if(!GetBuf(g_atrHandle, 0, 1, atr)) return(FILTER_NODATA);
      double atrPoints = atr / point;
      if(atrPoints < InpMinATRPoints) return(FILTER_ATR);   // pasar terlalu sepi
      if(atrPoints > InpMaxATRPoints) return(FILTER_ATR);   // spike volatilitas
   }

   return(FILTER_OK);
}

//+------------------------------------------------------------------+
//| InSession — true bila jam server berada dalam sesi trading       |
//+------------------------------------------------------------------+
bool InSession()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);   // waktu server
   int h = t.hour;

   if(InpStartHour == InpEndHour) return(true);              // 24 jam
   if(InpStartHour < InpEndHour)  return(h >= InpStartHour && h < InpEndHour);
   // Sesi melewati tengah malam (mis. 20 - 6)
   return(h >= InpStartHour || h < InpEndHour);
}

//+------------------------------------------------------------------+
//| GetHardStopDistance — jarak hard SL (harga), tetap atau ATR      |
//+------------------------------------------------------------------+
double GetHardStopDistance()
{
   if(InpUseATRStop)
   {
      double atr;
      if(GetBuf(g_atrHandle, 0, 1, atr) && atr > 0.0)
         return(InpATRStopMult * atr);          // SL = pengali x ATR (harga)
      // Fallback bila ATR gagal terbaca
   }
   return(InpStopLossPoints * _Point);          // SL tetap (points -> harga)
}

//+------------------------------------------------------------------+
//| OpenTrade — buka posisi baru dengan hard SL, tanpa TP tetap      |
//+------------------------------------------------------------------+
void OpenTrade(const ENUM_ORDER_TYPE type)
{
   double point      = _Point;
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopsLevel * point;
   double slDist     = GetHardStopDistance();

   // Hormati level stop minimum broker.
   if(slDist < minDist)
      slDist = minDist;

   // Normalisasi & validasi volume.
   double vol  = NormalizeVolumeDown(InpLotSize);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(vol < vmin)
   {
      Print("Gagal entry: LotSize (", DoubleToString(InpLotSize, g_volDigits),
            ") di bawah volume minimum (", DoubleToString(vmin, g_volDigits), ").");
      return;
   }

   if(type == ORDER_TYPE_BUY)
   {
      double price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
      double sl    = NormalizeDouble(price - slDist, _Digits);
      if(!trade.Buy(vol, _Symbol, price, sl, 0.0, "M1 Pro BUY"))
         Print("Gagal buka BUY. Retcode=", trade.ResultRetcode(),
               " (", trade.ResultRetcodeDescription(), ")");
   }
   else if(type == ORDER_TYPE_SELL)
   {
      double price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
      double sl    = NormalizeDouble(price + slDist, _Digits);
      if(!trade.Sell(vol, _Symbol, price, sl, 0.0, "M1 Pro SELL"))
         Print("Gagal buka SELL. Retcode=", trade.ResultRetcode(),
               " (", trade.ResultRetcodeDescription(), ")");
   }
}

//+------------------------------------------------------------------+
//| ManagePosition — partial TP -> breakeven -> trailing (tiap tick) |
//+------------------------------------------------------------------+
void ManagePosition()
{
   // Cari & pilih posisi milik EA ini (magic + symbol).
   ulong ticket = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         ticket = t;
         break;
      }
   }
   if(ticket == 0)
      return; // tidak ada posisi milik EA

   long   type      = PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double volume    = PositionGetDouble(POSITION_VOLUME);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = _Point;

   // Profit berjalan dalam points (buy diukur di Bid, sell di Ask).
   double profitPoints = (type == POSITION_TYPE_BUY) ? (bid - openPrice) / point
                                                     : (openPrice - ask) / point;

   //--- A. Partial TP (sekali per posisi) + geser SL ke breakeven ---
   if(InpUsePartialTP && !PartialAlreadyDone(ticket, volume) &&
      profitPoints >= InpPartialTPPoints)
   {
      if(DoPartialClose(ticket, volume))
      {
         g_partialDoneTicket = ticket;
         MoveToBreakeven(ticket, type, openPrice, currentSL);
         return; // cukup satu aksi pada tick ini; trailing menyusul tick berikut
      }
   }

   //--- B. Breakeven ---
   bool breakevenDone = IsBreakevenDone(type, openPrice, currentSL);
   if(!breakevenDone)
   {
      if(profitPoints >= InpBreakevenTrigger)
         MoveToBreakeven(ticket, type, openPrice, currentSL);
      return; // belum breakeven -> belum trailing
   }

   //--- C. Trailing (hanya setelah breakeven) ---
   ApplyTrailing(ticket, type, currentSL);
}

//+------------------------------------------------------------------+
//| PartialAlreadyDone — penjaga agar partial TP hanya sekali        |
//|   Kombinasi flag ticket + cek volume (tahan restart EA).         |
//+------------------------------------------------------------------+
bool PartialAlreadyDone(const ulong ticket, const double currentVolume)
{
   if(g_partialDoneTicket == ticket)
      return(true);
   // Bila volume sudah lebih kecil dari lot pembukaan, partial pasti sudah terjadi.
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(currentVolume < InpLotSize - vstep * 0.5)
      return(true);
   return(false);
}

//+------------------------------------------------------------------+
//| DoPartialClose — tutup sebagian volume (hormati min/step)        |
//|   Return true bila partial close berhasil dieksekusi.            |
//+------------------------------------------------------------------+
bool DoPartialClose(const ulong ticket, const double currentVolume)
{
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   // Volume yang akan ditutup, dibulatkan ke bawah sesuai step.
   double closeVol = NormalizeVolumeDown(currentVolume * (InpPartialClosePercent / 100.0));
   double remain   = NormalizeDouble(currentVolume - closeVol, g_volDigits);

   // Lewati bila porsi tutup ATAU sisa runner di bawah volume minimum.
   if(closeVol < vmin) return(false);
   if(remain   < vmin) return(false);

   if(!trade.PositionClosePartial(ticket, closeVol))
   {
      Print("Gagal partial close ", DoubleToString(closeVol, g_volDigits),
            ". Retcode=", trade.ResultRetcode(),
            " (", trade.ResultRetcodeDescription(), ")");
      return(false);
   }

   Print("Partial close ", DoubleToString(closeVol, g_volDigits),
         " lot. Runner tersisa ", DoubleToString(remain, g_volDigits), " lot.");
   return(true);
}

//+------------------------------------------------------------------+
//| IsBreakevenDone — breakeven dianggap tercapai dari posisi SL     |
//+------------------------------------------------------------------+
bool IsBreakevenDone(const long type, const double openPrice, const double currentSL)
{
   if(currentSL == 0.0) return(false);
   if(type == POSITION_TYPE_BUY)  return(currentSL >= openPrice);
   return(currentSL <= openPrice);
}

//+------------------------------------------------------------------+
//| MoveToBreakeven — geser SL ke entry +/- buffer (tidak mundur)    |
//+------------------------------------------------------------------+
void MoveToBreakeven(const ulong ticket, const long type,
                     const double openPrice, const double currentSL)
{
   double point      = _Point;
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopsLevel * point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(type == POSITION_TYPE_BUY)
   {
      double newSL = NormalizeDouble(openPrice + InpBreakevenBuffer * point, _Digits);
      // Hanya maju (naik) & hormati jarak minimum broker terhadap Bid.
      if(newSL > currentSL && (bid - newSL) >= minDist)
         ModifySL(ticket, newSL);
   }
   else
   {
      double newSL = NormalizeDouble(openPrice - InpBreakevenBuffer * point, _Digits);
      // Hanya maju (turun) & hormati jarak minimum broker terhadap Ask.
      if((currentSL == 0.0 || newSL < currentSL) && (newSL - ask) >= minDist)
         ModifySL(ticket, newSL);
   }
}

//+------------------------------------------------------------------+
//| ApplyTrailing — trailing SL (hanya dipanggil setelah breakeven)  |
//+------------------------------------------------------------------+
void ApplyTrailing(const ulong ticket, const long type, const double currentSL)
{
   double point      = _Point;
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopsLevel * point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(type == POSITION_TYPE_BUY)
   {
      double trail = NormalizeDouble(bid - InpTrailingDistance * point, _Digits);
      // Geser hanya bila maju >= TrailingStep, tidak mundur, & hormati stops level.
      if(trail - currentSL >= InpTrailingStep * point && (bid - trail) >= minDist)
         ModifySL(ticket, trail);
   }
   else
   {
      double trail = NormalizeDouble(ask + InpTrailingDistance * point, _Digits);
      if(currentSL - trail >= InpTrailingStep * point && (trail - ask) >= minDist)
         ModifySL(ticket, trail);
   }
}

//+------------------------------------------------------------------+
//| ModifySL — ubah SL posisi (TP tetap 0)                           |
//+------------------------------------------------------------------+
void ModifySL(const ulong ticket, const double sl)
{
   if(!trade.PositionModify(ticket, sl, 0.0))
      Print("Gagal modify SL ke ", DoubleToString(sl, _Digits),
            ". Retcode=", trade.ResultRetcode(),
            " (", trade.ResultRetcodeDescription(), ")");
}

//+------------------------------------------------------------------+
//| HasOpenPosition — true bila ada posisi milik EA (magic+symbol)   |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| SpreadTooHigh — true bila spread saat ini > MaxSpreadPoints      |
//+------------------------------------------------------------------+
bool SpreadTooHigh()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spreadPoints = (ask - bid) / _Point;
   return(spreadPoints > (double)InpMaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| CalcVolumeDigits — jumlah desimal volume dari SYMBOL_VOLUME_STEP  |
//+------------------------------------------------------------------+
int CalcVolumeDigits()
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) return(2);
   int d = 0;
   double s = step;
   while(s < 1.0 - 1e-9 && d < 8)
   {
      s *= 10.0;
      d++;
   }
   return(d);
}

//+------------------------------------------------------------------+
//| NormalizeVolumeDown — bulatkan volume ke bawah sesuai step        |
//+------------------------------------------------------------------+
double NormalizeVolumeDown(const double vol)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = 0.01;

   double v = MathFloor(vol / step + 1e-8) * step;
   v = NormalizeDouble(v, g_volDigits);
   if(vmax > 0.0 && v > vmax) v = vmax;
   return(v);
}
//+------------------------------------------------------------------+
