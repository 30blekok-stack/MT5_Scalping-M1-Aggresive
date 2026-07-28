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

## Preset `.set` — pilih sesuai digit broker

Preset ini adalah **baseline yang PASTI menghasilkan transaksi** (Sesi & ATR-guard
dimatikan dulu, gap MA kecil), lalu Anda perketat filter bertahap sambil membaca log
diagnostik. Semua menyertakan **range optimasi** (`||start||step||stop||N`).

| File | Pakai bila |
|------|-----------|
| [`Presets/XAUUSD_Scalper_M1_Pro_Exness_3digit.set`](Presets/XAUUSD_Scalper_M1_Pro_Exness_3digit.set) | Broker **3 digit** (1 pt = 0.001 USD), mis. Exness dgn XAUUSD 3 desimal. |
| [`Presets/XAUUSD_Scalper_M1_Pro_2digit.set`](Presets/XAUUSD_Scalper_M1_Pro_2digit.set) | Broker **2 digit** (1 pt = 0.01 USD), XAUUSD 2 desimal. |

> **Cek digit dulu:** saat EA start, ia mencetak `Digits=...` dan `SKALA: 100 pt = ...`
> di tab **Experts/Journal**. Kalau `Digits=2` → pakai preset 2 digit; `Digits=3` → 3 digit.

**Cara load:** copy `.set` ke `<Data Folder>/MQL5/Presets/` → attach EA ke chart
XAUUSD M1 → tab **Inputs** → tombol **Load** → pilih file `.set`.

Nilai baseline (versi 3 digit; bagi 10 untuk 2 digit):

| Parameter | Points (3 digit) | ≈ USD |
|-----------|------------------|-------|
| `StopLossPoints` | 2000 | 2.00 |
| `PartialTPPoints` | 1000 | 1.00 |
| `BreakevenTrigger` / `Buffer` | 1200 / 150 | 1.20 / 0.15 |
| `TrailingDistance` / `Step` | 1200 / 250 | 1.20 / 0.25 |
| `MinMAGapPoints` | 20 | 0.02 |
| `MaxDistPoints` | 2000 | 2.00 |
| `MaxSpreadPoints` | 500 | 0.50 |
| `ADXThreshold` | 20 | — |
| `UseSessionFilter` / `UseATRGuard` | **false** / **false** | — |
| `LotSize` | 0.02 | — |

> **Perhatikan:**
> - **`LotSize=0.02`** agar Partial TP 50% bisa jalan (50% × 0.02 = 0.01 = lot minimum). Untuk 0.01 lot, set `UsePartialTP=false`. **Lot = risiko** (SL 2.00 USD @0.02 lot = −4.00 USD/trade).
> - Setelah ADA transaksi, nyalakan filter satu per satu: **Sesi** (setel `StartHour`/`EndHour` ke JAM SERVER dulu) → **ATR guard** → naikkan `ADXThreshold`/`MinMAGapPoints`.

---

## Backtest otomatis lewat file `.ini`

File: [`Tester/backtest_XAUUSD_M1_Pro.ini`](Tester/backtest_XAUUSD_M1_Pro.ini) — konfigurasi
Strategy Tester agar backtest jalan otomatis dari command line.

**Jalankan (Windows):**
```
"C:\Program Files\MetaTrader 5\terminal64.exe" /config:"C:\path\backtest_XAUUSD_M1_Pro.ini"
```

**Prasyarat (penting):**
1. Compile `XAUUSD_Scalper_M1_Pro.mq5` → `.ex5` berada di `<Data Folder>/MQL5/Experts/`.
2. Untuk mode `/config`, taruh `.set` di **`<Data Folder>/MQL5/Profiles/Tester/`**
   (berbeda dari load manual via tab Inputs yang memakai folder `Presets/`).
3. Samakan `Symbol=` dengan nama emas di broker Anda (Exness bisa `XAUUSD`, `XAUUSDm`, …).

Setelan utama di dalam ini: `Model=4` (every tick based on real ticks — paling akurat;
turunkan ke `0` bila real ticks tak tersedia), `Deposit=1000`, `Currency=USD`,
`Leverage=500`, rentang `FromDate`/`ToDate` (sesuaikan ketersediaan data). Untuk beralih
ke **optimasi**, set `Optimization=2` dan ubah flag `N`→`Y` pada parameter di `.set`
(petunjuk lengkap ada sebagai komentar di dalam file `.ini`).

---

## 🔧 Troubleshooting: backtest TIDAK ADA transaksi

Penyebab paling umum "no trades" pada EA berfilter seperti ini:

1. **Salah skala points (2 vs 3 digit)** — nilai points yang 10× terlalu besar membuat
   filter `MinMAGapPoints` / ATR guard **tak pernah** terpenuhi → nol transaksi.
   *Solusi:* cek `Digits=` di log, pakai preset yang sesuai.
2. **Filter sesi salah zona server** — jam `8–22` di zona server yang salah bisa memblokir
   semua entry. *Solusi:* preset baru sudah **mematikan** filter sesi secara default.
3. **ATR guard terlalu ketat** — `MinATRPoints` terlalu tinggi menolak semua bar. Default
   preset kini **OFF**.
4. **Kombinasi semua filter** terlalu selektif untuk periode data itu.

**EA sekarang punya diagnostik bawaan** untuk menunjuk penyebabnya:

- Saat init, EA mencetak `Digits`, `Point`, dan `SKALA: 100 pt = ...` — langsung ketahuan
  kalau skala points Anda salah.
- Di **akhir backtest** (tab Journal), EA mencetak **RINGKASAN DIAGNOSTIK**:

  ```
  ===== RINGKASAN DIAGNOSTIK EA =====
  Sinyal dasar MA (saat flat) : 1234
    ditolak spread            : 0
    ditolak filter HTF        : 210
    ditolak filter ADX        : 980     <- filter ini paling banyak menolak
    ditolak filter slope/MA   : 40
    ...
  ENTRY DIEKSEKUSI            : 4
  ===================================
  ```

  Lihat baris dengan angka penolakan terbesar → itulah filter yang perlu dilonggarkan/dimatikan.

- Set **`InpDebugMode=true`** untuk melihat alasan penolakan **setiap** sinyal (hati-hati:
  log jadi banyak pada test panjang).

**Langkah cepat:** load preset baseline yang sesuai digit → jalankan → pastikan ada
transaksi → baca ringkasan → nyalakan filter satu per satu.

> Catatan: EA juga sudah dibuat **tester-safe** (mengabaikan `TERMINAL_TRADE_ALLOWED`
> saat di Strategy Tester) sehingga guard AutoTrading tidak lagi memblokir backtest.

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
