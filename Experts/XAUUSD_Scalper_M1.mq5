//+------------------------------------------------------------------+
//|                                          XAUUSD_Scalper_M1.mq5    |
//|                                   EA Scalping Trend-Following M1  |
//|                                                                  |
//|  Strategi (versi ini MA saja, tanpa oscillator, berbasis KEADAAN |
//|  bukan transisi/cross):                                          |
//|    - Dua Moving Average pada TF M1: fast (default EMA 8) dan      |
//|      slow (default EMA 21).                                       |
//|    - BUY  bila CLOSE bar terakhir yang SUDAH TUTUP (shift 1)      |
//|      berada DI ATAS kedua MA. Tanpa syarat candle sebelumnya.     |
//|    - SELL bila CLOSE bar terakhir yang sudah tutup DI BAWAH       |
//|      kedua MA.                                                    |
//|    - Evaluasi sekali per bar M1 baru, memakai bar shift 1.        |
//|    - Maksimal 1 posisi (satu-satunya penahan agar tidak buka      |
//|      berulang). Re-entry diizinkan pada bar berikutnya setelah    |
//|      posisi tutup bila kondisi masih terpenuhi.                   |
//|    - Opsi UseFullCandle: bila true, syaratnya SELURUH candle      |
//|      (low di atas kedua MA untuk buy / high di bawah kedua MA     |
//|      untuk sell), bukan hanya close.                              |
//|                                                                  |
//|  Proteksi: Hard SL saat entry, TANPA TP. Profit dikunci lewat    |
//|  manajemen stop dua tahap (dicek tiap tick):                     |
//|    Tahap 1 Breakeven -> geser SL ke entry +/- buffer.            |
//|    Tahap 2 Trailing  -> HANYA setelah breakeven tercapai.        |
//|                                                                  |
//|  ================ CATATAN PENTING tentang "POINTS" =============  |
//|  Semua input ber-satuan POINTS. Arti 1 point bergantung jumlah   |
//|  digit harga broker untuk XAUUSD:                                |
//|     - Broker 2 digit -> 1 point = 0.01  (300 pt = 3.00 USD)      |
//|     - Broker 3 digit -> 1 point = 0.001 (300 pt = 0.30 USD)      |
//|  Jadi bila broker Anda 3 digit, kalikan kira-kira 10x nilai      |
//|  points dibanding broker 2 digit untuk jarak harga yang sama.    |
//|  Cek "Digits" pada simbol lalu sesuaikan StopLossPoints,         |
//|  BreakevenTrigger, BreakevenBuffer, TrailingDistance,            |
//|  TrailingStep, dan MaxSpreadPoints sesuai broker Anda.           |
//+------------------------------------------------------------------+
#property copyright "30blekok-stack"
#property version   "1.00"
#property description "Scalping trend-following XAUUSD M1 berbasis dua MA (state-based)."
#property description "Hard SL + breakeven + trailing. Semua input ber-satuan points (lihat catatan header)."

#include <Trade/Trade.mqh>

//--- Objek trading dari library standar
CTrade trade;

//======================= INPUT (bisa diubah dari panel EA) =========
input group "=== Moving Average (M1) ==="
input int                InpFastMA        = 8;            // Periode Fast MA
input int                InpSlowMA        = 21;           // Periode Slow MA
input ENUM_MA_METHOD     InpMAMethod      = MODE_EMA;     // Metode MA
input ENUM_APPLIED_PRICE InpAppliedPrice  = PRICE_CLOSE;  // Applied price
input bool               InpUseFullCandle = false;        // Pakai SELURUH candle (low/high), bukan close saja

input group "=== Lot ==="
input double             InpLotSize       = 0.01;         // Ukuran lot

input group "=== Stop Loss & Trailing (satuan: POINTS) ==="
input int                InpStopLossPoints   = 300;       // Hard Stop Loss (points)
input int                InpBreakevenTrigger = 150;       // Trigger breakeven (profit dalam points)
input int                InpBreakevenBuffer  = 20;        // Buffer SL dari entry saat breakeven (points)
input int                InpTrailingDistance = 150;       // Jarak trailing SL dari harga (points)
input int                InpTrailingStep     = 30;        // Langkah minimal geser trailing (points)

input group "=== Filter ==="
input int                InpMaxSpreadPoints  = 50;        // Spread maksimum diizinkan untuk entry (points)

input group "=== Identitas ==="
input long               InpMagicNumber      = 20250727;  // Magic number (identitas posisi EA ini)

//======================= VARIABEL GLOBAL ==========================
int      g_maFastHandle = INVALID_HANDLE;  // handle indikator Fast MA
int      g_maSlowHandle = INVALID_HANDLE;  // handle indikator Slow MA
datetime g_lastBarTime  = 0;               // waktu open bar M1 terakhir yang sudah dievaluasi

//+------------------------------------------------------------------+
//| OnInit — inisialisasi handle indikator & konfigurasi trading     |
//+------------------------------------------------------------------+
int OnInit()
{
   // --- Buat handle iMA fast & slow, dipaksa pada TF M1 agar tetap
   //     benar walau EA dipasang di chart timeframe lain.
   g_maFastHandle = iMA(_Symbol, PERIOD_M1, InpFastMA, 0, InpMAMethod, InpAppliedPrice);
   g_maSlowHandle = iMA(_Symbol, PERIOD_M1, InpSlowMA, 0, InpMAMethod, InpAppliedPrice);

   if(g_maFastHandle == INVALID_HANDLE || g_maSlowHandle == INVALID_HANDLE)
   {
      Print("ERROR: gagal membuat handle iMA. Periksa parameter MA.");
      return(INIT_FAILED);
   }

   // --- Konfigurasi objek CTrade
   trade.SetExpertMagicNumber((ulong)InpMagicNumber); // tandai order dengan magic number
   trade.SetDeviationInPoints(20);               // toleransi slippage saat market order
   trade.SetTypeFillingBySymbol(_Symbol);        // pilih filling mode sesuai simbol
   trade.SetAsyncMode(false);                     // eksekusi sinkron (tunggu hasil)

   // --- Simpan waktu bar M1 saat ini supaya evaluasi sinyal baru
   //     dimulai pada bar M1 BERIKUTNYA (menghindari entry saat attach).
   g_lastBarTime = iTime(_Symbol, PERIOD_M1, 0);

   // --- Peringatan konfigurasi ringan (tidak menghentikan EA)
   if(InpFastMA >= InpSlowMA)
      Print("PERINGATAN: FastMA >= SlowMA, hasil strategi mungkin tidak sesuai harapan.");

   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(InpStopLossPoints < stopsLevel)
      Print("PERINGATAN: StopLossPoints (", InpStopLossPoints,
            ") lebih kecil dari stops level broker (", stopsLevel,
            "). Jarak SL akan disesuaikan otomatis ke minimum broker.");

   Print("EA XAUUSD Scalper M1 aktif. Simbol=", _Symbol,
         " Digits=", _Digits, " Point=", DoubleToString(_Point, _Digits),
         " StopsLevel=", stopsLevel, " pt.");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit — lepas handle indikator saat EA dihentikan             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Bebaskan resource handle indikator
   if(g_maFastHandle != INVALID_HANDLE) IndicatorRelease(g_maFastHandle);
   if(g_maSlowHandle != INVALID_HANDLE) IndicatorRelease(g_maSlowHandle);
}

//+------------------------------------------------------------------+
//| OnTick — alur utama tiap tick                                    |
//+------------------------------------------------------------------+
void OnTick()
{
   // Jika AutoTrading dimatikan, jangan lakukan apa pun.
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return;

   // 1) Kelola posisi terbuka (breakeven & trailing) SETIAP tick.
   ManagePosition();

   // 2) Evaluasi sinyal HANYA sekali per bar M1 baru.
   if(!IsNewBar())
      return;

   // 3) Maksimal 1 posisi — penahan agar tidak buka berulang.
   if(HasOpenPosition())
      return;

   // 4) Filter spread sebelum entry.
   if(SpreadTooHigh())
      return;

   // 5) Cek sinyal berbasis keadaan close vs kedua MA (bar shift 1).
   int signal = CheckSignal();
   if(signal > 0)
      OpenTrade(ORDER_TYPE_BUY);
   else if(signal < 0)
      OpenTrade(ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| IsNewBar — deteksi bar M1 baru (true sekali per bar)             |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   // Bandingkan waktu open bar berjalan dengan yang tersimpan.
   datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| CheckSignal — kembalikan +1 (buy), -1 (sell), 0 (tidak ada)      |
//|   Berbasis KEADAAN close/candle bar shift 1 vs kedua MA.         |
//+------------------------------------------------------------------+
int CheckSignal()
{
   // Ambil nilai MA pada bar yang SUDAH tutup (shift 1).
   double fastBuf[], slowBuf[];
   if(CopyBuffer(g_maFastHandle, 0, 1, 1, fastBuf) < 1) return(0);
   if(CopyBuffer(g_maSlowHandle, 0, 1, 1, slowBuf) < 1) return(0);

   double maFast = fastBuf[0];
   double maSlow = slowBuf[0];

   // Harga candle bar shift 1.
   double close1 = iClose(_Symbol, PERIOD_M1, 1);
   if(close1 <= 0.0) return(0); // data belum siap

   if(InpUseFullCandle)
   {
      // Mode candle penuh: pakai low & high seluruh candle.
      double low1  = iLow(_Symbol, PERIOD_M1, 1);
      double high1 = iHigh(_Symbol, PERIOD_M1, 1);

      // BUY: seluruh candle DI ATAS kedua MA (low > kedua MA).
      if(low1 > maFast && low1 > maSlow)
         return(1);
      // SELL: seluruh candle DI BAWAH kedua MA (high < kedua MA).
      if(high1 < maFast && high1 < maSlow)
         return(-1);
   }
   else
   {
      // Mode close: cukup harga close yang dibandingkan.
      // BUY: close DI ATAS kedua MA.
      if(close1 > maFast && close1 > maSlow)
         return(1);
      // SELL: close DI BAWAH kedua MA.
      if(close1 < maFast && close1 < maSlow)
         return(-1);
   }

   return(0);
}

//+------------------------------------------------------------------+
//| OpenTrade — buka posisi baru dengan hard SL, tanpa TP            |
//+------------------------------------------------------------------+
void OpenTrade(const ENUM_ORDER_TYPE type)
{
   double point      = _Point;
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopsLevel * point;                 // jarak minimum broker (harga)
   double slDist     = InpStopLossPoints * point;          // jarak SL yang diminta (harga)

   // Hormati level stop minimum broker: jangan lebih dekat dari minDist.
   if(slDist < minDist)
      slDist = minDist;

   if(type == ORDER_TYPE_BUY)
   {
      double price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
      double sl    = NormalizeDouble(price - slDist, _Digits);   // SL di bawah entry

      if(!trade.Buy(InpLotSize, _Symbol, price, sl, 0.0, "M1 Scalper BUY"))
         Print("Gagal buka BUY. Retcode=", trade.ResultRetcode(),
               " (", trade.ResultRetcodeDescription(), ")");
   }
   else if(type == ORDER_TYPE_SELL)
   {
      double price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
      double sl    = NormalizeDouble(price + slDist, _Digits);   // SL di atas entry

      if(!trade.Sell(InpLotSize, _Symbol, price, sl, 0.0, "M1 Scalper SELL"))
         Print("Gagal buka SELL. Retcode=", trade.ResultRetcode(),
               " (", trade.ResultRetcodeDescription(), ")");
   }
}

//+------------------------------------------------------------------+
//| ManagePosition — breakeven lalu trailing (dicek tiap tick)       |
//|   Status breakeven disimpulkan dari posisi SL relatif entry,     |
//|   sehingga tahan restart EA & otomatis reset saat re-entry.      |
//+------------------------------------------------------------------+
void ManagePosition()
{
   // Cari & pilih posisi milik EA ini (magic + symbol).
   ulong ticket = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);   // memilih posisi index i
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

   long   type       = PositionGetInteger(POSITION_TYPE);
   double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL  = PositionGetDouble(POSITION_SL);

   double point      = _Point;
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopsLevel * point;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(type == POSITION_TYPE_BUY)
   {
      // Profit berjalan (points) diukur dari harga tutup buy = Bid.
      double profitPoints = (bid - openPrice) / point;

      // Breakeven dianggap sudah tercapai bila SL berada di entry atau di atasnya.
      bool breakevenDone = (currentSL >= openPrice);

      double newSL = currentSL;

      if(!breakevenDone)
      {
         // --- Tahap 1: Breakeven ---
         if(profitPoints >= InpBreakevenTrigger)
            newSL = NormalizeDouble(openPrice + InpBreakevenBuffer * point, _Digits);
      }
      else
      {
         // --- Tahap 2: Trailing (hanya setelah breakeven) ---
         double trail = NormalizeDouble(bid - InpTrailingDistance * point, _Digits);
         // Geser hanya bila pergerakan >= TrailingStep.
         if(trail - currentSL >= InpTrailingStep * point)
            newSL = trail;
      }

      // Terapkan: SL untuk BUY hanya boleh NAIK (tidak boleh mundur) &
      // harus menghormati jarak minimum broker terhadap Bid.
      if(newSL > currentSL && (bid - newSL) >= minDist)
         ModifySL(ticket, newSL);
   }
   else if(type == POSITION_TYPE_SELL)
   {
      // Profit berjalan (points) diukur dari harga tutup sell = Ask.
      double profitPoints = (openPrice - ask) / point;

      // Breakeven dianggap tercapai bila SL berada di entry atau di bawahnya.
      bool breakevenDone = (currentSL != 0.0 && currentSL <= openPrice);

      double newSL = currentSL;

      if(!breakevenDone)
      {
         // --- Tahap 1: Breakeven ---
         if(profitPoints >= InpBreakevenTrigger)
            newSL = NormalizeDouble(openPrice - InpBreakevenBuffer * point, _Digits);
      }
      else
      {
         // --- Tahap 2: Trailing (hanya setelah breakeven) ---
         double trail = NormalizeDouble(ask + InpTrailingDistance * point, _Digits);
         // Geser hanya bila pergerakan >= TrailingStep.
         if(currentSL - trail >= InpTrailingStep * point)
            newSL = trail;
      }

      // Terapkan: SL untuk SELL hanya boleh TURUN (tidak boleh mundur) &
      // harus menghormati jarak minimum broker terhadap Ask.
      if(newSL < currentSL && (newSL - ask) >= minDist)
         ModifySL(ticket, newSL);
   }
}

//+------------------------------------------------------------------+
//| ModifySL — ubah SL posisi (TP tetap 0/tanpa TP)                  |
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
      ulong ticket = PositionGetTicket(i);   // memilih posisi index i
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
   // Hitung spread langsung dari Ask-Bid agar akurat (dalam points).
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spreadPoints = (ask - bid) / _Point;

   return(spreadPoints > (double)InpMaxSpreadPoints);
}
//+------------------------------------------------------------------+
