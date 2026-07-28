# XAUUSD Scalper M1 — Expert Advisor MetaTrader 5

EA scalping **trend-following** untuk **XAUUSD** di timeframe **M1**, berbasis dua
Moving Average (MA) dengan logika **berbasis keadaan** (bukan transisi/cross).

Tersedia dua versi:

| File | Deskripsi |
|------|-----------|
| [`Experts/XAUUSD_Scalper_M1.mq5`](Experts/XAUUSD_Scalper_M1.mq5) | **Dasar** — entry MA + hard SL + breakeven + trailing. |
| [`Experts/XAUUSD_Scalper_M1_Pro.mq5`](Experts/XAUUSD_Scalper_M1_Pro.mq5) | **Upgrade** — semua fitur dasar + 5 filter penyaring noise + SL berbasis ATR + partial take profit. |

---

## Ringkasan Entry (kedua versi)

- **Dua MA di M1**: fast (default EMA 8) dan slow (default EMA 21).
- **BUY** jika **close** candle terakhir yang sudah tutup (shift 1) **di atas kedua MA**.
- **SELL** jika **close** candle terakhir yang sudah tutup **di bawah kedua MA**.
- Murni keadaan, bukan cross. Evaluasi **sekali per bar M1 baru**.
- **Maksimal 1 posisi**; **re-entry** diizinkan setelah posisi tutup.
- Opsi **`UseFullCandle`**: syarat seluruh candle (low/high), bukan hanya close.

---

## Fitur Tambahan Versi Pro

**5 filter penyaring noise** (masing-masing punya input on/off):

1. **Tren Higher-Timeframe** (`UseHTFTrend`) — hanya BUY bila harga di atas EMA M15 (`HTFPeriod`), hanya SELL bila di bawah.
2. **Kekuatan tren ADX** (`UseADX`) — entry hanya bila ADX ≥ `ADXThreshold` (default M5) → hindari sideways.
3. **Slope & jarak MA** (`UseMAFilter`) — fast harus di atas/bawah slow dengan gap ≥ `MinMAGapPoints`, fast sedang naik/turun, dan harga tidak lebih jauh dari `MaxDistPoints` dari fast MA (anti mengejar harga).
4. **Sesi/jam** (`UseSessionFilter`) — entry hanya antara `StartHour`–`EndHour` (jam server; EndHour eksklusif).
5. **Guard volatilitas ATR M1** (`UseATRGuard`) — tolak entry bila ATR < `MinATRPoints` (sepi) atau > `MaxATRPoints` (spike).

**Stop loss fleksibel:** `UseATRStop=false` → SL tetap `StopLossPoints`; `UseATRStop=true` → SL = `ATRStopMult` × ATR M1.

**Manajemen profit (tiap tick):**
- **Partial TP + runner** (`UsePartialTP`) — saat profit ≥ `PartialTPPoints`, tutup `PartialClosePercent`% volume **sekali** per posisi (hormati `VOLUME_MIN`/`VOLUME_STEP`), sekaligus pindah SL ke breakeven.
- **Breakeven** — saat profit ≥ `BreakevenTrigger`, SL ke entry ± `BreakevenBuffer` (tidak dobel dengan partial).
- **Trailing** — hanya setelah breakeven; jarak `TrailingDistance`, geser bila gerak ≥ `TrailingStep`. SL tak pernah mundur.

Semua indikator memakai **handle** (`iMA`, `iADX`, `iATR`) yang dibuat di `OnInit` dan
di-`release` di `OnDeinit`. SL selalu menghormati `SYMBOL_TRADE_STOPS_LEVEL`.

---

## ⚠️ Catatan Penting: satuan "POINTS"

Semua input jarak (SL, TP parsial, breakeven, trailing, gap/jarak MA, ATR min/max, spread)
ber-satuan **points**. Arti 1 point bergantung jumlah **digit** harga broker XAUUSD:

| Digit broker | 1 point | Contoh: 300 points |
|--------------|---------|--------------------|
| 2 digit      | 0.01    | 3.00 USD           |
| 3 digit      | 0.001   | 0.30 USD           |

> Jika broker Anda **3 digit**, kalikan kira-kira **10×** semua input points untuk jarak
> harga yang sama. Cek kolom **Digits** di Market Watch → Specification. Nilai default
> diset untuk broker **2 digit**. EA juga mencetak `Digits` & `Point` ke log saat init.

---

## 1) Cara Memasang di MetaTrader 5

1. Buka **MetaEditor** (`F4` dari MT5).
2. Salin file `.mq5` ke folder **MQL5/Experts** (Navigator → klik kanan Experts → *Open Folder*).
3. **Compile** (`F7`) — pastikan **0 error**.
4. Di MT5, buka chart **XAUUSD** timeframe **M1**.
5. Drag EA dari **Navigator → Expert Advisors** ke chart.
6. Tab **Common**: centang *Allow Algo Trading*. Tab **Inputs**: setel parameter.
7. Aktifkan tombol **Algo Trading** di toolbar.
8. **Uji di Strategy Tester (`Ctrl+R`)** dengan data XAUUSD M1 sebelum akun riil.

---

## 2) Urutan Tuning yang Disarankan

Mulai sederhana, aktifkan filter satu per satu sambil membandingkan hasil di Strategy Tester:

1. **Kalibrasi points dulu** sesuai digit broker (lihat catatan di atas).
2. **SL & entry dasar** — matikan semua filter, setel `StopLossPoints` realistis untuk
   volatilitas XAUUSD M1. Jadikan ini baseline.
3. **Filter tren HTF** (`UseHTFTrend`) — biasanya paling berdampak menyaring sinyal lawan-arah. Aktifkan lebih dulu.
4. **Filter ADX** (`UseADX`) — buang periode sideways; naikkan `ADXThreshold` bila masih terlalu banyak entry.
5. **Guard ATR** (`UseATRGuard`) — batasi entry hanya saat volatilitas sehat.
6. **Filter slope & jarak MA** (`UseMAFilter`) — perhalus timing entry & cegah mengejar harga.
7. **Filter sesi** (`UseSessionFilter`) — batasi ke jam likuid (sesuaikan ke jam server broker).
8. **Manajemen profit terakhir** — setel `PartialTPPoints`, lalu `BreakevenTrigger`, lalu `TrailingDistance`/`TrailingStep`.
9. Terakhir, baru sentuh periode MA (`FastMA`/`SlowMA`) bila perlu.

> Aktifkan **satu perubahan pada satu waktu** lalu bandingkan — supaya tahu filter mana yang benar-benar membantu.

---

## 3) Parameter Paling Berpengaruh

| Prioritas | Parameter | Efek |
|-----------|-----------|------|
| 🔴 Tinggi | `StopLossPoints` / `UseATRStop` + `ATRStopMult` | Risiko per trade. Terlalu kecil → kena noise M1; terlalu besar → loss membengkak. |
| 🔴 Tinggi | `UseHTFTrend` + `HTFPeriod` | Penyaring arah paling kuat; menghindari lawan tren besar. |
| 🔴 Tinggi | `UseADX` + `ADXThreshold` | Menentukan "trending vs sideways"; sangat memengaruhi jumlah & kualitas entry. |
| 🔴 Tinggi | `BreakevenTrigger` | Kapan profit diamankan. Terlalu kecil → sering breakeven lalu kena saat retrace. |
| 🟠 Sedang | `PartialTPPoints` + `PartialClosePercent` | Seberapa cepat & banyak profit dikunci vs membiarkan runner jalan. |
| 🟠 Sedang | `TrailingDistance` / `TrailingStep` | Ketat/longgarnya trailing & seberapa banyak give-back. |
| 🟠 Sedang | `MinATRPoints` / `MaxATRPoints` | Rentang volatilitas yang boleh ditradingkan. |
| 🟠 Sedang | `MaxDistPoints` / `MinMAGapPoints` | Timing entry: cegah mengejar & pastikan tren cukup kuat. |
| 🟢 Rendah | `StartHour` / `EndHour` | Batasi ke jam likuid (sangat bergantung zona waktu server broker). |
| 🟢 Rendah | `MaxSpreadPoints`, `BreakevenBuffer`, `UseFullCandle` | Penyesuaian halus kualitas entry & pengunci profit. |
| ⚙️ Wajib benar | `LotSize`, `MagicNumber` | Ukuran risiko & identitas posisi EA. |

---

> **Disclaimer:** EA ini untuk tujuan edukasi/riset. Trading mengandung risiko.
> Uji menyeluruh di akun demo sebelum digunakan pada akun riil.
