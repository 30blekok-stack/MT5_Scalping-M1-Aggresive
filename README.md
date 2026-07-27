# XAUUSD Scalper M1 — Expert Advisor MetaTrader 5

EA scalping **trend-following** untuk **XAUUSD** di timeframe **M1**, berbasis dua
Moving Average (MA) dengan logika **berbasis keadaan** (bukan transisi/cross).
Proteksi profit memakai **hard stop loss** + **breakeven** + **trailing** dua tahap.

File EA: [`Experts/XAUUSD_Scalper_M1.mq5`](Experts/XAUUSD_Scalper_M1.mq5)

---

## Ringkasan Strategi

- **Dua MA di M1**: fast (default EMA 8) dan slow (default EMA 21).
- **BUY** jika **close** candle terakhir yang sudah tutup (shift 1) berada **di atas kedua MA**.
- **SELL** jika **close** candle terakhir yang sudah tutup berada **di bawah kedua MA**.
- Tidak ada syarat candle sebelumnya — murni keadaan, bukan cross.
- Evaluasi **sekali per bar M1 baru**.
- **Maksimal 1 posisi** dalam satu waktu (penahan agar tidak buka berulang).
  Setelah posisi tutup, **re-entry** diizinkan pada bar berikutnya bila kondisi masih terpenuhi.
- Opsi **`UseFullCandle`**: bila `true`, syaratnya seluruh candle
  (low di atas kedua MA untuk buy / high di bawah kedua MA untuk sell), bukan hanya close.

**Manajemen stop (dicek tiap tick):**
1. **Breakeven** — begitu profit ≥ `BreakevenTrigger`, SL digeser ke entry ± `BreakevenBuffer`.
2. **Trailing** — **hanya setelah breakeven**, SL trail mengikuti harga dengan jarak
   `TrailingDistance`, dan hanya digeser bila pergerakan ≥ `TrailingStep`. SL tidak pernah mundur.

**Filter:** tidak entry bila spread > `MaxSpreadPoints`; SL selalu menghormati
`SYMBOL_TRADE_STOPS_LEVEL` broker. Tanpa TP — profit dikunci lewat trailing.

---

## ⚠️ Catatan Penting: satuan "POINTS"

Semua input jarak ber-satuan **points**. Arti 1 point bergantung jumlah **digit** harga
broker Anda untuk XAUUSD:

| Digit broker | 1 point | Contoh: 300 points |
|--------------|---------|--------------------|
| 2 digit      | 0.01    | 3.00 USD           |
| 3 digit      | 0.001   | 0.30 USD           |

> Jika broker Anda **3 digit**, kalikan kira-kira **10×** nilai points dibanding broker
> 2 digit untuk jarak harga yang sama. Cek kolom **Digits** pada Market Watch → Specification,
> lalu sesuaikan `StopLossPoints`, `BreakevenTrigger`, `BreakevenBuffer`,
> `TrailingDistance`, `TrailingStep`, dan `MaxSpreadPoints`.

Nilai default pada EA diset untuk broker **2 digit** (mis. SL 300 pt = 3.00 USD).

---

## Cara Memasang EA di MetaTrader 5

1. Buka **MetaEditor** (dari MT5: tombol IDE / `F4`).
2. Di **Navigator**, klik kanan folder **Experts** → *Open Folder*, lalu salin
   `XAUUSD_Scalper_M1.mq5` ke sana. (Atau: File → Open dan arahkan ke file ini.)
3. Klik **Compile** (`F7`). Pastikan **0 error**.
4. Kembali ke **MT5**, buka chart **XAUUSD** dan set timeframe **M1**.
5. Dari **Navigator → Expert Advisors**, drag **XAUUSD_Scalper_M1** ke chart.
6. Di tab **Common**, centang **Allow Algo Trading**; di tab **Inputs**, sesuaikan parameter.
7. Pastikan tombol **Algo Trading** (toolbar) menyala.

**Uji dulu di Strategy Tester** (Ctrl+R) memakai data XAUUSD M1 sebelum akun live/real.

---

## Parameter Paling Berpengaruh untuk Di-tuning

| Prioritas | Parameter | Efek |
|-----------|-----------|------|
| 🔴 Tinggi | `StopLossPoints` | Risiko per trade. Terlalu kecil → sering kena SL oleh noise M1; terlalu besar → loss per trade membengkak. |
| 🔴 Tinggi | `FastMA` / `SlowMA` | Sensitivitas sinyal. Nilai kecil → lebih agresif & banyak sinyal (banyak noise); nilai besar → lebih lambat & selektif. |
| 🔴 Tinggi | `BreakevenTrigger` | Kapan profit "diamankan". Terlalu kecil → sering breakeven lalu kena SL saat retrace; terlalu besar → profit sudah didapat tapi belum terkunci. |
| 🟠 Sedang | `TrailingDistance` | Ketat/longgarnya trailing. Ketat → cepat kena tapi profit kecil; longgar → beri ruang tren tapi give-back lebih besar. |
| 🟠 Sedang | `TrailingStep` | Frekuensi geser SL. Kecil → sering modify; besar → jarang geser. |
| 🟠 Sedang | `MaxSpreadPoints` | Kualitas entry. XAUUSD bisa spread lebar saat news; nilai ini mencegah entry mahal. |
| 🟢 Rendah | `BreakevenBuffer` | Seberapa banyak profit dikunci saat breakeven (menutup biaya spread/komisi). |
| 🟢 Rendah | `UseFullCandle` | `true` = sinyal lebih ketat/lebih sedikit; `false` = lebih banyak sinyal. |
| ⚙️ Wajib benar | `LotSize`, `MagicNumber` | Ukuran risiko & identitas posisi EA (agar tidak bentrok dengan EA/manual lain). |

**Saran alur tuning:** mulai dari `StopLossPoints` yang realistis untuk volatilitas XAUUSD M1,
lalu setel `BreakevenTrigger` (biasanya ≈ 0.5–1× SL), kemudian `TrailingDistance` /
`TrailingStep`, terakhir barulah utak-atik periode MA. Selalu validasi di Strategy Tester.

---

> **Disclaimer:** EA ini untuk tujuan edukasi/riset. Trading mengandung risiko.
> Uji menyeluruh di akun demo sebelum digunakan pada akun riil.
