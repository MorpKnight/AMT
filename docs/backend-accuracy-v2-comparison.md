# Akurasi backend v2: perbandingan sebelum–sesudah

Hybrid pada fixture eksperimen: recall deteksi ejaan **44,2% → 90,7%**, koreksi actionable **44,2% → 74,4%**. `Datta` pada dummy kini terdeteksi, tetapi masih **needsReview**, belum koreksi actionable. Ada percepatan routing sumber dan regresi pada workload lain; tabel di bawah memisahkan perubahan cakupan dari pekerjaan setara. Seluruh label tetap pending.

Eksperimen ini membandingkan commit baseline
`b2759f53af56105805fe64fd5009bc3d3128eff5` dengan working tree implementasi
sesudahnya pada `gi/flow-fix`. Commit baseline dan riwayat flow-fix sudah di-push
ke GitHub; SHA remote diverifikasi sama dengan lokal. Implementasi sesudahnya
diukur sebagai working tree sebelum commit. Laporan ini merekam keadaan saat
pengukuran; README diperbarui dan hasil dipublikasikan bersama branch flow-fix
setelah validasi. Tidak ada perubahan View pada tahap akurasi ini, dependency, format dokumen,
signing, entitlement, atau deployment target.

## Yang berubah

- Kandidat ejaan memakai lookup case-normalized dengan teks asli/kapitalisasi dan
  anchor UTF-16 tetap utuh; satu operasi mencakup transposisi huruf berdekatan.
  Maksimal enam alternatif per occurrence, dengan deduplikasi dan batch tiga
  yang sudah ada.
- Frasa istilah yang didefinisikan eksplisit dalam dokumen menambah kandidat
  dengan scope. `Datta Pribadi` dapat menunjuk `Data Pribadi`; satu kata dalam
  vocabulary dokumen tidak cukup. Lookup dimiliki processor per revisi, tanpa
  cache global. Dukungan frasa tetap bertahan jika native checker mempunyai
  alternatif lain.
- API `score` dan threshold 0,25 tetap. `scoreForReview` mengembalikan kandidat
  terbaik per anchor dengan skor valid, termasuk delta rendah/negatif.
  Revision/configuration/finite score/window/anchor diperiksa sebelum routing.
  Delta rendah hanya diteruskan bila ada unique eligible native guess atau
  evidence frasa dokumen eksplisit. Ia tidak pernah menjadi persetujuan edit.
- Deterministic mode menyajikan kandidat baru sebagai review baca-saja tanpa
  memanggil TataKata/Qwen; rule lama tetap. Restorasi marker hukum seperti
  `kewajban → kewajiban` selalu menjadi `needsReview`, tanpa replacement.
  Kapital biasa hanya dapat berubah dengan proof terikat occurrence/context,
  keputusan model yang menerima, dan validator; nama/kutipan/akronim/identifier
  tetap terlindungi.
- Review definisi memisahkan document term/body dari source term/body.
  Identitas seluruh istilah deklarasi diperiksa terlebih dahulu, termasuk nama
  produk yang memuat istilah corpus. Sumber eksplisit memerlukan exact normalized
  term atau alias yang dinyatakan dokumen; kandidat E5 tetap tersedia untuk
  parafrasa tersirat. Sumber tidak terkait tidak lagi mendasari alignment.
- Definisi kuat tanpa sumber layak mempertahankan identitas definisinya dengan
  alignment `needsReview`. Prompt/parser menyepakati pasangan enum yang valid.
  Maksimal satu repair untuk format/kontrak; keputusan semantik valid yang
  bertentangan dengan pola kuat tidak di-retry.
- Mismatch lokal dibatasi pada body lengkap identik setelah normalisasi, kecuali
  satu `tidak` tepat sebelum `dapat`. Tidak mengabaikan predikat lain, aktor,
  angka, punctuation, kondisi, atau pengecualian. Resolver tidak menawarkan
  replacement maupun reverse-term proposal dari mismatch lokal ini.
- Nominal uang, desimal bersatuan, dan persentase dikecualikan sebelum pencarian
  rujukan. Angka bertitik memerlukan struktur atau konteks referral; deiktik
  `Lampiran ini/tersebut` bukan identifier hilang. `Lampiran C` tidak menyertakan
  titik penutup dalam anchor.
- Tahap wajib yang gagal/terlalu panjang/dibatalkan ditandai partial. Temuan lokal
  dipertahankan; cache/snapshot lengkap tidak dibuat. Selesai dengan cakupan
  parsial dibedakan dari cancellation. Profile/prompt/validator/routing/reference
  policy dan namespace cache diperbarui; evidence dan dependensi konteks masuk
  fingerprint. Diagnostik Debug menambah alasan filter dan repair definisi.

## Metode dan batas interpretasi

181 input per versi: 113 lama, 48 baru (24 regression/24 holdout), 18 kontrol
definisi dengan body sumber dibekukan, dummy bawaan utuh, dan satu dummy
sintetis dengan `Datta` pada penggunaan `Data Pribadi` di luar deklarasi/kutipan.
Input 113 lama tidak diganti. Expectation eksperimen v2 memperbaiki occurrence
lintas kategori, tiga typo pada teks panjang, dan rujukan Lampiran C. Saran
`wajib untuk → wajib` diukur sebagai gaya opsional.

Semua label **pending**, tanpa approval manusia. Label lama retrospektif berasal
dari review assistant sebelumnya; label baru dibekukan sebelum perubahan
algoritma. Perbaikan sidecar selama baseline tidak mengubah input/pipeline.
Holdout tidak dipakai menyetel threshold. Semantik tanpa expectation lengkap
tidak menjadi gold negative. Status bukti tetap `insufficientEvidence`; angka
ini bukan quality gate hukum atau pengukuran kemampuan umum bahasa Indonesia.

Qwen 4B, corpus, E5, TataKata dan revision sama; greedy, thinking mati, seed 42.
Inference serial pada MacBook Pro M5/RAM 24 GB. Tiap mode menjalankan tiga warm
run (cache analisis/scoring dibersihkan, `fullFresh`) dan tiga cached rerun
(priming terpisah, incremental tanpa perubahan). Model boleh tetap resident.
Hook yang membuat fullFresh menerima cache dimatikan. Download/resource
preparation terpisah dari durasi analisis. Cold matrix tidak diulang.

Baseline selesai sebelum source produksi berubah. Sesudah jeda atas permintaan
pengguna, dua edge case binding ditemukan dari inspeksi source, bukan tuning
holdout. Pemeriksaan dummy utuh kemudian menemukan deklarasi balik `selanjutnya disebut`
belum masuk lookup restorasi dan proteksi token yang tidak diubah menghalangi
seluruh frasa. Kedua jalur diperbaiki dengan test offline dummy utuh, tanpa
mengubah threshold atau label. Record build sesudah yang digantikan dipisahkan
dalam direktori `after-superseded-static-binding-fixes/` dan
`after-superseded-reverse-declaration/`; seluruh matrix final diulang dan
laporan ini hanya memakai `after/`. UUID/timestamp tidak dibandingkan.

RSS/MLX disampel setiap 10 ms dengan sampler identik. First-visible/actionable
yang tidak muncul adalah null. Precision hanya dihitung ketika gold lokal
lengkap; kebutuhan review tidak dianggap koreksi actionable. Latensi gabungan
lintas fixture hanya deskriptif; tabel pipeline membandingkan workload sama.
Kasus dengan tambahan kandidat/cakupan/perubahan perilaku ditandai terpisah.

Artefak mentah, log, manifest/checksum, source manifest, dan `.xcresult` berada
di `/private/tmp/amt-accuracy-fix-task/`. Data, evaluator, measurement overlay,
dan instruksi reproduksi tersimpan di
[benchmarks/accuracy-v2](benchmarks/accuracy-v2/README.md).


## Hasil akurasi per occurrence

Setiap sel berisi total tiga run. Repeat bukan tambahan fixture independen. Deteksi memerlukan original, occurrence, dan anchor valid; actionable juga memerlukan replacement yang benar serta status suggestion.

| Mode/fase | Deteksi ejaan sebelum → sesudah | Koreksi actionable sebelum → sesudah | Precision deteksi ejaan sebelum → sesudah | Precision koreksi ejaan sebelum → sesudah | Partial run sebelum → sesudah |
|---|---:|---:|---:|---:|---:|
| deterministic/warm | 57/129 (44.2%) → 123/129 (95.3%) | 57/129 (44.2%) → 57/129 (44.2%) | 90.5% → 95.7% | 100.0% → 100.0% | 0 → 0 |
| deterministic/cached | 57/129 (44.2%) → 123/129 (95.3%) | 57/129 (44.2%) → 57/129 (44.2%) | 90.5% → 95.7% | 100.0% → 100.0% | 0 → 0 |
| hybrid/warm | 57/129 (44.2%) → 117/129 (90.7%) | 57/129 (44.2%) → 96/129 (74.4%) | 90.5% → 95.5% | 100.0% → 100.0% | 0 → 18 |
| hybrid/cached | 57/129 (44.2%) → 117/129 (90.7%) | 57/129 (44.2%) → 96/129 (74.4%) | 90.5% → 95.5% | 100.0% → 100.0% | 0 → 18 |
| modelOnly/warm | 57/129 (44.2%) → 117/129 (90.7%) | 57/129 (44.2%) → 96/129 (74.4%) | 90.5% → 95.5% | 100.0% → 100.0% | 0 → 18 |
| modelOnly/cached | 57/129 (44.2%) → 117/129 (90.7%) | 57/129 (44.2%) → 96/129 (74.4%) | 90.5% → 95.5% | 100.0% → 100.0% | 0 → 18 |

### Pemisahan kelompok (hybrid warm)

| Kelompok | Deteksi sebelum → sesudah | Actionable sebelum → sesudah |
|---|---:|---:|
| retrospective113 | 54/72 (75.0%) → 72/72 (100.0%) | 54/72 (75.0%) → 69/72 (95.8%) |
| newRegression | 3/33 (9.1%) → 24/33 (72.7%) | 3/33 (9.1%) → 18/33 (54.5%) |
| newHoldout | 0/21 (0.0%) → 18/21 (85.7%) | 0/21 (0.0%) → 9/21 (42.9%) |
| dummy | 0/3 (0.0%) → 3/3 (100.0%) | 0/3 (0.0%) → 0/3 (0.0%) |

## Waktu pipeline

Detik: median [minimum–maksimum] tiga run. Tanda hasil setara hanya membandingkan normalisasi harness; perubahan coverage ditandai terpisah.

| Workload/fase | Sebelum | Sesudah | Δ detik | Δ % | Hasil / coverage setara |
|---|---:|---:|---:|---:|---|
| definitions-cached | 0.0133 [0.0127–0.0133] | 0.0131 [0.0131–0.0133] | -0.0001 | -1.1% | False / True |
| definitions-incremental | 0.4968 [0.4948–0.5065] | 0.3790 [0.3595–0.3806] | -0.1178 | -23.7% | False / True |
| definitions-warm | 4.7685 [4.7488–4.8562] | 0.3808 [0.3676–0.4103] | -4.3877 | -92.0% | False / True |
| fixed-scoring-cached | 0.0017 [0.0016–0.0025] | 0.0021 [0.0021–0.0022] | +0.0005 | +27.5% | True / n/a |
| fixed-scoring-warm | 1.9711 [1.9478–1.9844] | 1.9029 [1.8955–1.9238] | -0.0681 | -3.5% | True / n/a |
| hard-negative-cached | 0.0165 [0.0165–0.0168] | 0.0152 [0.0152–0.0154] | -0.0013 | -7.8% | False / True |
| hard-negative-warm | 18.5589 [18.4445–18.6801] | 5.8589 [5.7345–6.2041] | -12.6999 | -68.4% | False / True |
| local-12-cached | 0.0183 [0.0181–0.0185] | 0.0179 [0.0178–0.0184] | -0.0003 | -1.7% | True / True |
| local-12-incremental | 3.9485 [3.9322–3.9826] | 4.4154 [4.2243–4.6609] | +0.4669 | +11.8% | True / True |
| local-12-warm | 4.3260 [4.0811–4.4662] | 3.9763 [3.9624–4.2341] | -0.3497 | -8.1% | True / True |
| local-180-cached | 0.4530 [0.4526–0.4537] | 0.5178 [0.4831–0.7587] | +0.0647 | +14.3% | True / True |
| local-180-warm | 16.4167 [16.1211–17.1797] | 16.3075 [16.1438–16.3738] | -0.1092 | -0.7% | True / True |
| local-60-cached | 0.0671 [0.0669–0.0676] | 0.0609 [0.0608–0.0619] | -0.0062 | -9.2% | True / True |
| local-60-warm | 7.4175 [7.2948–8.1357] | 7.2021 [7.1387–7.4525] | -0.2154 | -2.9% | True / True |
| long-clauses-cached | 0.8845 [0.8795–0.8894] | 0.2582 [0.2564–0.2601] | -0.6263 | -70.8% | False / False |
| long-clauses-incremental | 7.7873 [7.7511–7.8977] | 8.7955 [8.7076–8.9882] | +1.0081 | +12.9% | False / False |
| long-clauses-warm | 7.8243 [7.7785–7.8467] | 9.0117 [8.8043–9.5612] | +1.1873 | +15.2% | False / False |
| long-source-cached | 0.0136 [0.0135–0.0137] | 0.0127 [0.0127–0.0133] | -0.0008 | -6.0% | True / True |
| long-source-warm | 5.3196 [5.2222–5.4904] | 5.5979 [5.4509–5.9533] | +0.2783 | +5.2% | True / True |
| mixed-cached | 0.1888 [0.1884–0.1929] | 0.1843 [0.1840–0.2009] | -0.0045 | -2.4% | False / True |
| mixed-warm | 11.2593 [11.2356–11.3905] | 12.3260 [12.2530–12.4760] | +1.0666 | +9.5% | False / True |
| tatakata-cached | 0.0128 [0.0128–0.0133] | 0.0130 [0.0128–0.0132] | +0.0002 | +1.3% | False / True |
| tatakata-warm | 4.4723 [4.4146–4.8310] | 10.8902 [10.8890–11.1407] | +6.4180 | +143.5% | False / True |
| terminology-cached | 0.0127 [0.0126–0.0128] | 0.0126 [0.0126–0.0128] | -0.0001 | -0.7% | True / True |
| terminology-warm | 0.6878 [0.6868–0.7658] | 0.5658 [0.5096–0.6411] | -0.1220 | -17.7% | True / True |

## Latensi temuan dan memori pipeline

First-visible dan field legacy `firstLocalActionable` dalam detik. RSS/MLX dalam MiB; median peak sampel [min–max]. Null berarti tidak ada temuan terkait.

| Workload warm | Visible sebelum → sesudah | Actionable sebelum → sesudah | RSS sebelum → sesudah | MLX active sebelum → sesudah | MLX cache sebelum → sesudah |
|---|---|---|---|---|---|
| definitions | 0.0538 [0.0537–0.0574] → 0.0559 [0.0554–0.0578] | null → null | 1980.5781 [1871.9531–2947.1094] → 1899.9062 [1899.8594–1899.9844] | 3613.7109 [3593.2423–3613.7274] → 2714.1061 [2710.1015–2715.1424] | 71.3438 [69.0471–512.9703] → 8.5921 [8.5803–8.5921] |
| hard-negative | 4.6395 [4.6385–4.6449] → 5.3215 [5.2331–5.6813] | null → null | 1674.3594 [1674.3438–2966.9688] → 1457.1250 [1444.5312–1497.2656] | 3783.9665 [3783.9353–3790.0603] → 3552.2550 [3552.0987–3560.7120] | 524.7029 [517.4845–750.1926] → 516.4502 [512.6973–519.6093] |
| local-12 | 0.0140 [0.0139–0.0299] → 0.0138 [0.0135–0.0264] | 0.0140 [0.0139–0.0299] → 0.0138 [0.0135–0.0264] | 1147.7500 [1141.2031–1162.0469] → 902.9531 [902.0312–951.2031] | 3630.5110 [3630.3391–3630.5110] → 3588.8094 [3588.8087–3630.3412] | 69.3127 [69.3127–72.0653] → 515.6680 [513.6158–519.7490] |
| local-180 | 0.0957 [0.0947–0.1105] → 0.0928 [0.0919–0.1477] | 0.0957 [0.0947–0.1105] → 0.0929 [0.0919–0.1478] | 277.2188 [276.7969–1417.1719] → 1135.9375 [1135.4219–2203.2656] | 3551.9893 [3551.9893–3560.7120] → 3552.2081 [3551.9893–3560.7120] | 517.2158 [512.6973–517.6157] → 513.9344 [513.2901–516.1763] |
| local-60 | 0.0408 [0.0375–0.0425] → 0.0368 [0.0367–0.0499] | 0.0408 [0.0375–0.0425] → 0.0368 [0.0367–0.0499] | 1818.1250 [333.6562–2189.3750] → 1514.2812 [1504.7188–3215.0312] | 3552.0518 [3551.7862–3560.7120] → 3552.0049 [3552.0049–3560.7120] | 71.6877 [69.3127–513.4493] → 513.6085 [513.2439–514.5170] |
| long-clauses | 0.0461 [0.0452–0.0705] → 0.0469 [0.0424–0.1146] | 0.0461 [0.0452–0.0705] → 0.0469 [0.0424–0.1146] | 1639.5781 [1623.4375–2526.8125] → 1188.5469 [1188.5000–1984.7812] | 3587.7276 [3581.2178–3613.7431] → 3613.7431 [3575.7178–3613.7900] | 515.5899 [515.3925–518.1428] → 518.2306 [515.3925–520.5746] |
| long-source | null → null | null → null | 1537.0625 [1507.5469–2559.0469] → 1563.2656 [1511.8750–1624.9375] | 3641.7284 [3624.0095–3641.7597] → 3624.0408 [3623.9939–3641.7909] | 513.8713 [513.6864–513.9450] → 516.9089 [516.3496–636.7618] |
| mixed | 0.0519 [0.0514–0.0548] → 0.0503 [0.0494–0.0688] | 0.0519 [0.0514–0.0548] → 0.0503 [0.0494–0.0688] | 1291.1094 [1290.3125–2146.8438] → 872.6562 [872.2031–1456.3594] | 3588.1398 [3560.7121–3588.1418] → 3588.1411 [3560.7121–3588.1438] | 512.6973 [69.3127–515.0313] → 517.4751 [515.3750–517.8479] |
| tatakata | null → 4.2216 [4.2181–4.3998] | null → 4.2216 [4.2181–4.3998] | 1392.9688 [1380.6250–1442.3906] → 1947.4531 [1947.0000–2372.3594] | 4035.8285 [4027.1215–4035.8754] → 4035.9108 [4035.8014–4035.9420] | 69.3127 [69.3127–70.8671] → 520.4319 [519.8137–602.2080] |
| terminology | 0.2636 [0.2633–0.3458] → 0.1971 [0.1760–0.2926] | null → null | 1355.3594 [1355.1562–1355.3594] → 1124.8281 [1121.0469–1125.2031] | 2715.3785 [2714.2379–2728.2849] → 2715.3785 [2706.7518–2728.2849] | 35.4232 [35.0364–35.4232] → 35.8890 [35.8890–35.8890] |

## Counter dan cakupan pipeline

Counter adalah jumlah tiga run, bukan median. Qwen merupakan invocation tahap menurut report, bukan token atau jaminan setiap panggilan sukses. Repair kandidat dihitung per segmen, repair definisi per retry format.

| Workload/fase | Qwen sebelum → sesudah | E5 | Tata batches | Cache hit | Repair kandidat / definisi | Gagal / terlalu panjang sebelum → sesudah |
|---|---:|---:|---:|---:|---|---|
| definitions-cached | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| definitions-incremental | 0 → 0 | 12 → 6 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| definitions-warm | 6 → 0 | 12 → 6 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| fixed-scoring-cached | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| fixed-scoring-warm | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| hard-negative-cached | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| hard-negative-warm | 21 → 3 | 24 → 12 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| local-12-cached | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| local-12-incremental | 3 → 3 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| local-12-warm | 3 → 3 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| local-180-cached | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| local-180-warm | 3 → 3 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| local-60-cached | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| local-60-warm | 3 → 3 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| long-clauses-cached | 0 → 0 | 12 → 9 | 0 → 0 | 3 → 0 | 0/0 → 0/0 | 6/0 → 3/0 |
| long-clauses-incremental | 3 → 3 | 12 → 9 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 6/0 → 3/0 |
| long-clauses-warm | 3 → 3 | 12 → 9 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 6/0 → 3/0 |
| long-source-cached | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| long-source-warm | 6 → 6 | 12 → 12 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| mixed-cached | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| mixed-warm | 3 → 3 | 6 → 3 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| tatakata-cached | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| tatakata-warm | 6 → 18 | 0 → 0 | 3 → 18 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| terminology-cached | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |
| terminology-warm | 0 → 0 | 21 → 15 | 0 → 0 | 0 → 0 | 0/0 → 0/0 | 0/0 → 0/0 |

## Durasi tahap (hybrid warm matrix)

Detik median [min–max] per record lintas 181 fixture; distribusi ini deskriptif dan tahap dapat overlap.

| Tahap | Sebelum | Sesudah |
|---|---:|---:|
| candidateBuilding | 0.0000 [0.0000–0.0052] | 0.0001 [0.0000–0.0083] |
| candidateReview | 1.4503 [1.4336–1.6943] | 1.4544 [1.4301–16.2449] |
| contextClassification | 2.1784 [2.1143–10.1706] | 2.1575 [2.1059–9.9457] |
| contextExtraction | 0.0002 [0.0002–0.0037] | 0.0002 [0.0002–0.0037] |
| contextSegmentation | 0.0003 [0.0002–0.0148] | 0.0003 [0.0002–0.0150] |
| definitionDetection | 0.0056 [0.0014–1.1786] | 0.0055 [0.0014–1.4981] |
| definitionResolution | 0.0002 [0.0001–0.0019] | 0.0001 [0.0001–0.0015] |
| definitionRetrieval | 0.0676 [0.0470–5.2926] | 0.0834 [0.0532–5.3771] |
| definitionReview | 2.1214 [2.0435–6.3597] | 2.0353 [2.0215–2.0691] |
| documentFindingDetection | 0.0002 [0.0002–0.0207] | 0.0003 [0.0002–0.0229] |
| documentStructure | 0.0001 [0.0000–0.0047] | 0.0001 [0.0000–0.0048] |
| editorMapping | 0.0000 [0.0000–0.0117] | 0.0001 [0.0000–0.0123] |
| localReview | 0.0003 [0.0002–0.0182] | 0.0003 [0.0001–0.0311] |
| protectionContext | 0.0001 [0.0001–0.0016] | 0.0000 [0.0000–0.0000] |
| resultAcknowledgement | 0.0000 [0.0000–0.0029] | 0.0000 [0.0000–0.0029] |
| spellingCandidateGeneration | 0.0006 [0.0004–0.1329] | 0.0012 [0.0009–0.3607] |
| suggestionRetrieval | 0.0471 [0.0138–7.4082] | 0.0465 [0.0137–7.5709] |
| tataKataScoring | 0.1408 [0.0964–1.7182] | 0.1089 [0.0002–8.6695] |
| validationConflictResolution | 0.0548 [0.0175–14.5440] | 0.0617 [0.0181–33.9992] |

## Detail matrix: latensi, memori, dan counter

Nilai lintas fixture bersifat deskriptif; workload memiliki ukuran berbeda. Durasi detik, RSS/MLX MiB. Median [min–max] memakai record yang mempunyai temuan untuk latensi pertama. Nilai null tidak diganti nol.

| Mode/fase | Total sebelum → sesudah | First visible | First actionable | RSS | MLX active | MLX cache |
|---|---|---|---|---|---|---|
| deterministic/warm | 0.0593 [0.0265–6.3367] → 0.0618 [0.0274–6.5297] | 0.0527 [0.0124–0.5897] → 0.0511 [0.0122–3.6561] | 0.0461 [0.0124–0.0646] → 0.0469 [0.0122–0.0770] | 1757.6250 [1750.1562–1874.2344] → 588.2812 [459.2188–594.1875] | 2706.6689 [2706.6689–2706.6689] → 2706.6689 [2706.6689–2706.6689] | 0.0012 [0.0012–0.0012] → 0.0012 [0.0000–0.0012] |
| deterministic/cached | 0.0117 [0.0108–0.0532] → 0.0128 [0.0110–0.0422] | 0.0007 [0.0005–0.0309] → 0.0007 [0.0006–0.0315] | 0.0007 [0.0006–0.0309] → 0.0007 [0.0006–0.0315] | 1757.6250 [1750.1562–1874.2188] → 588.2500 [418.6406–593.9531] | 2706.6689 [2706.6689–2706.6689] → 2706.6689 [2706.6689–2706.6689] | 0.0012 [0.0012–0.0012] → 0.0012 [0.0000–0.0012] |
| hybrid/warm | 2.2458 [0.0484–24.8967] → 2.2518 [0.0485–44.1499] | 0.1804 [0.0116–7.1555] → 0.1559 [0.0115–13.2502] | 0.0127 [0.0116–0.0734] → 0.0127 [0.0116–13.2502] | 1545.7969 [207.0938–2033.0156] → 199.5156 [165.1719–681.1562] | 4027.1221 [2706.6689–4272.8189] → 4027.0780 [2706.6689–4266.2419] | 511.2917 [63.5535–742.5868] → 514.0584 [67.0627–599.3184] |
| hybrid/cached | 0.0127 [0.0108–10.0725] → 0.0128 [0.0112–10.1133] | 0.0118 [0.0006–2.3921] → 0.0127 [0.0006–0.2201] | 0.0127 [0.0007–0.0314] → 0.0128 [0.0007–0.0336] | 1541.2188 [206.5781–2032.0938] → 199.1875 [165.1719–672.0938] | 3181.7558 [2706.6689–4272.6936] → 3181.7568 [2706.6689–4128.3319] | 506.6929 [62.0898–514.0870] → 512.2448 [63.1803–518.5704] |
| modelOnly/warm | 2.2435 [0.0465–29.0109] → 2.2959 [0.0483–44.2448] | 2.2453 [0.0400–12.1571] → 2.3256 [0.0406–13.9380] | 2.2453 [2.1732–12.7449] → 2.2658 [2.1707–15.9400] | 165.4375 [132.0781–208.0156] → 183.0938 [155.3438–233.0625] | 4027.1707 [3181.7558–4272.8033] → 4035.7993 [3181.7568–4265.3823] | 69.3127 [63.3730–520.7547] → 69.3283 [63.9949–530.7322] |
| modelOnly/cached | 0.0128 [0.0109–10.4964] → 0.0120 [0.0109–10.3122] | 0.0127 [0.0006–2.3263] → 0.0118 [0.0007–0.2147] | 0.0128 [0.0008–0.0361] → 0.0127 [0.0007–0.0318] | 164.9844 [129.7500–207.5312] → 181.9375 [155.4688–229.1875] | 3181.7558 [3181.7558–4272.8033] → 3181.7568 [3181.7568–4128.3319] | 65.2116 [43.8405–514.7594] → 65.6620 [54.5816–519.8352] |

| Mode/fase | Qwen invocations | E5 queries | TataKata batches | Cache hit | Candidate repair segments | Definition repair |
|---|---:|---:|---:|---:|---:|---:|
| deterministic/warm | 0 → 0 | 0 → 0 | 0 → 0 | 552 → 552 | 0 → 0 | 0 → 0 |
| deterministic/cached | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 |
| hybrid/warm | 597 → 618 | 810 → 702 | 33 → 135 | 552 → 552 | 0 → 0 | 0 → 0 |
| hybrid/cached | 18 → 6 | 30 → 9 | 0 → 9 | 15 → 0 | 0 → 0 | 0 → 0 |
| modelOnly/warm | 597 → 618 | 810 → 702 | 33 → 135 | 552 → 552 | 0 → 0 | 0 → 0 |
| modelOnly/cached | 18 → 6 | 30 → 9 | 0 → 9 | 15 → 0 | 0 → 0 | 0 → 0 |

Persiapan resource matrix terpisah: sebelum 2,6696 detik; sesudah 2,9114 detik. Model sudah ada di disk; ini bukan benchmark download. Tidak ada repair format definisi yang terpicu pada matrix final; bounded repair diuji offline.

### Delapan kelompok baru: hybrid warm

Total tiga pengulangan per kelompok. Setiap kelompok berisi enam fixture, tiga regression dan tiga holdout. Kelompok tanpa expected ejaan tetap menguji review, semantik, proteksi, atau rujukan; kolom ejaan kosong bukan kegagalan.

| Kelompok | Ejaan deteksi sebelum → sesudah | Ejaan actionable sebelum → sesudah | Partial runs sebelum → sesudah |
|---|---:|---:|---:|
| 1 | 0/15 → 15/15 | 0/15 → 9/15 | 0 → 0 |
| 2 | 0/15 → 15/15 | 0/15 → 12/15 | 0 → 0 |
| 3 | 0/0 → 0/0 | 0/0 → 0/0 | 0 → 0 |
| 4 | 0/0 → 0/0 | 0/0 → 0/0 | 0 → 0 |
| 5 | 0/6 → 6/6 | 0/6 → 0/6 | 0 → 0 |
| 6 | 0/0 → 0/0 | 0/0 → 0/0 | 0 → 0 |
| 7 | 0/0 → 0/0 | 0/0 → 0/0 | 0 → 0 |
| 8 | 3/18 → 6/18 | 3/18 → 6/18 | 0 → 9 |

## Interpretasi performa dan regresi

- **Hasil setara, warm:** lokal 12/60/180 segmen masing-masing -8,1%/-2,9%/-0,7%;
  terminologi -17,7%. Tidak ada klaim signifikansi statistik dari tiga run.
  Terminologi memakai 15 E5 queries dalam tiga run, turun dari 21.
- **Perubahan perilaku:** definisi 4,768 → 0,381 detik (-92,0%), hard negative
  18,559 → 5,859 detik (-68,4%). Qwen invocations definisi turun 6 → 0,
  hard negative 21 → 3 dalam tiga run; sumber tidak relevan berhenti sebelum
  review. Hasil normalized berubah, sehingga ini bukan percepatan atas
  keputusan yang identik.
- **Tambahan cakupan kandidat:** workload TataKata 4,472 → 10,890 detik
  (+143,5%); 0 → 6 normalized findings per run. Qwen termasuk classifier
  6 → 18, TataKata batches 3 → 18 dalam tiga run. Review kandidat meningkat
  dari 1 → 5 invocation per run. Biaya dominan berasal dari inference tambahan,
  bukan hanya operasi mapping. Hasil tambahan tetap perlu review kualitas;
  jumlah finding bukan sinonim akurasi.
- **Regresi sumber panjang yang hasil/coverage-nya setara:** 5,320 → 5,598 detik
  (+0,278 detik/+5,2%). Trace stage run kedua menunjukkan definitionReview
  2,432 → 2,768 detik dan contextClassification 2,411 → 2,487 detik, sementara
  definitionDetection 0,079 → 0,007 detik. Prompt sekarang memisahkan document
  term dan source term. Durasi generation/variasi proses lebih dominan daripada
  deteksi lokal, tetapi trace tiga run belum membuktikan penyebab kausal tunggal.
- **Cached lokal 180 segmen:** 0,453 → 0,518 detik (+0,065 detik/+14,3%), rentang
  sesudah 0,483–0,759 detik dibanding sebelum 0,453–0,454. Mapping/application
  lokal juga naik pada record terukur; full run mencakup lebih dari mapping.
  Perlu profiling CPU yang terarah sebelum mengaitkannya dengan satu helper.
- **Regresi lain:** mixed +9,5% dan long-clauses +15,2%; normalized result berbeda,
  long-clauses juga berbeda stage coverage. Jumlah finding mixed tetap 242,
  tetapi isi assessment berubah akibat source binding. Invocation Qwen tetap,
  E5 justru turun; tambahan waktu tidak dijelaskan hanya oleh jumlah model call.
  Audit biaya pemeriksaan phrase/protection pada dokumen besar dan profiling
  preparation/event application merupakan pekerjaan lanjutan. Tidak ada
  validasi yang dilonggarkan untuk menutupi regresi.

Resource preparation terpisah dan RSS/MLX ditampilkan dalam tabel. Peak proses
terpengaruh resource resident dan allocator; tidak menunjukkan batas memori
payload cache. Angka matrix lintas fixture tidak menggantikan perbandingan
workload yang identik. Cached rerun pada analisis partial tetap dapat
mengulang tahap yang belum lengkap dan tidak boleh dianggap cache miss yang
selalu merupakan bug performa.

## Kontrol semantik dan kelengkapan

Positive control hanya 12 definisi × tiga pengulangan; 18 mention run terpisah tidak mempunyai assessment. Abstention total mencakup semua assessment di 181 input, bukan hanya gold kontrol.

| Mode/fase | Classification benar positive control | Alignment benar positive control | Semua assessment / needsReview sebelum → sesudah | Sumber explicit-shaped berbeda istilah | Tahap failed sebelum → sesudah |
|---|---:|---:|---:|---:|---:|
| deterministic/warm | 18/36 → 36/36 | 18/36 → 36/36 | 144/126 → 144/108 | 0 → 0 | 0 → 0 |
| deterministic/cached | 18/36 → 36/36 | 18/36 → 36/36 | 144/126 → 144/108 | 0 → 0 | 0 → 0 |
| hybrid/warm | 18/36 → 36/36 | 18/36 → 36/36 | 144/114 → 144/108 | 39 → 0 | 18 → 12 |
| hybrid/cached | 18/36 → 36/36 | 18/36 → 36/36 | 144/114 → 144/108 | 39 → 0 | 18 → 12 |
| modelOnly/warm | 18/36 → 36/36 | 18/36 → 36/36 | 144/114 → 144/108 | 39 → 0 | 18 → 12 |
| modelOnly/cached | 18/36 → 36/36 | 18/36 → 36/36 | 144/114 → 144/108 | 39 → 0 | 18 → 12 |

Sembilan pasangan incremental/fresh (tiga workload × tiga pengulangan) setara pada kedua versi menurut normalisasi harness. Tidak ada invalid mapped anchor atau actionable source pada seluruh matrix dan pipeline. Raw report juga memuat alasan filter/routing, stage coverage, dan rentang input yang ditinjau.

Fixed-candidate TataKata: skor dan jumlah kandidat sama pada kedua versi; warm median turun 3,5%, sedangkan cached naik sekitar 0,000458 detik (+27,5%). Persentase cached perlu dibaca bersama besaran sub-milidetik tersebut.

## Pembacaan hasil dan pekerjaan yang masih tersisa

Hybrid warm dan cached memberi hasil occurrence yang sama pada tiga pengulangan:
39 dari 43 ejaan wajib terdeteksi, 32 dari 43 mempunyai koreksi actionable.
Baseline 19 dari 43 untuk keduanya. Kenaikan masing-masing **46,5** dan
**30,2 poin persentase**. Pada 24 occurrence retrospektif, deteksi naik dari
18/24 menjadi 24/24 dan koreksi dari 18/24 menjadi 23/24. Pada fixture baru,
regression 8/11 terdeteksi dan 6/11 terkoreksi; holdout 6/7 terdeteksi dan
3/7 terkoreksi. Angka holdout tidak dipakai menyetel threshold.

Precision koreksi ejaan 100% hanya berlaku pada subset synthetic dengan gold
lokal lengkap, bukan semua bahasa/dokumen produksi. Precision deteksi ejaan
hybrid sesudah 95,5%: dua fixture nama produk `Memasukan` masih menghasilkan
review baca-saja, diulang tiga kali. Tidak ada koreksi actionable salah pada
291 no-change run dalam subset tersebut. Noise ini tetap kekurangan proteksi,
meskipun validator mencegah replacement actionable.

**`Datta` pada dummy utuh:** baseline tidak mendeteksinya. Versi baru mendeteksi
pada ketiga warm dan ketiga cached hybrid run dengan anchor valid, tetapi
hasilnya **`needsReview`, bukan `Data` actionable**. Test offline membuktikan
provider dapat menghasilkan `Datta → Data`; hasil model tidak dipaksa mengikuti
expectation. Prompt kandidat masih meminta review konservatif bila defined term
dapat terpengaruh, sedangkan bukti restorasi belum dijelaskan khusus pada prompt.
Ini adalah hipotesis penyebab abstention yang didukung inspeksi prompt, bukan
bukti kausal dari eksperimen ablation.

Empat ejaan wajib yang belum terdeteksi pada hybrid berada pada kelompok baru
teks panjang/Unicode: `laproan` dan `dokumne` pada g8-1, `Datta` pada g8-2,
serta `perjanjain` pada g8-4. Dua fixture pertama mencatat language scoring
failed; record backend46-long-3 juga mencatat semantic retrieval failed.
Deterministic mendeteksi 41/43, lebih tinggi daripada hybrid, namun hanya
19/43 actionable karena kandidat baru memerlukan review model. Jalur model
masih dapat kehilangan cakupan yang telah dimiliki provider lokal.

Pada kontrol semantik positif (12 definisi × tiga run), pasangan classification
serta alignment benar naik dari 18/36 menjadi 36/36; enam mention control × tiga
run tidak menghasilkan assessment pada kedua versi. Absennya assessment pada
mention tidak dianggap bukti model menghasilkan `NOT_A_DEFINITION`. Hasil ini
terutama menguji exact source binding dan satu bentuk negasi sempit; tidak
membuktikan guard seluruh relasi hukum sempurna. Seluruh 181 input masih memuat
banyak assessment `needsReview`; abstention tidak dihitung sebagai jawaban
semantik lengkap.

Kontrol rujukan hybrid mempertahankan recall 9/9 occurrence berulang, sementara
false positive turun dari 15 menjadi 0; precision 37,5% menjadi 100% pada tujuh
fixture rujukan berlabel. Lima negative fixture tidak lagi memunculkan rujukan
hilang. Diagnostik explicit-shaped source comparison dengan istilah berbeda
berkurang 39 menjadi 0. Perbedaan istilah adalah diagnostik identitas, bukan
secara umum gold irrelevance karena alias eksplisit dapat sah.

## Rekomendasi berikutnya

1. **Review restorasi yang memahami evidence.** Berikan Qwen data terstruktur
   read-only tentang istilah deklarasi, scope, span target, dan satu operasi
   typo yang sudah diverifikasi. Bedakan restorasi ejaan istilah yang sama dari
   penggantian konsep. Uji ablation pada regression baru, lalu holdout baru;
   pertahankan keputusan `needsReview` bila proof/identitas/keamanan tidak cukup.
   Jangan mengubah threshold 0,25 atau menganggap skor sebagai izin edit.
2. **Kegagalan scoring tidak menghapus deteksi.** Audit budget tokenizer/window
   TataKata pada fixture panjang dan Unicode, lalu pertahankan kandidat valid
   sebagai review terjangkar bila scoring gagal. Jaga partial coverage dan
   larangan cache/snapshot lengkap. Prioritaskan ini karena hybrid masih
   mendeteksi lebih sedikit daripada deterministic pada empat occurrence.
3. **Proteksi nama berbasis deklarasi dan penggunaan.** Perluas konteks entitas
   untuk pola seperti `Memasukan adalah nama produk`, dengan scope dan evidence
   anchor. Tujuannya mengurangi false alarm baca-saja; jangan melindungi semua
   token kapital karena akan menghilangkan typo yang sah.
4. **Observabilitas tahap dokumen.** Rekam status/failure reason context classifier
   dan risk review secara eksplisit dalam envelope benchmark. Dummy berstatus
   partial tanpa failed segment; kode summary juga memasukkan fallback konteks
   atau risk. Harness saat ini belum membedakan keduanya dengan field status
   dedicated. Jangan mengasumsikan semua segmen sukses berarti dokumen lengkap.
5. **Review manusia dan holdout baru.** Minta review label occurrence, no-change,
   nama, sumber, serta semantic expectation sebelum membangun quality gate.
   Setelah perbaikan berikutnya, gunakan holdout yang belum pernah dianalisis
   untuk pengembangan. Benchmark v2 sekarang menjadi evidence eksperimen yang
   telah diamati, bukan holdout yang selamanya belum tersentuh.

## Validasi dan artefak

Build Debug melalui `xcodebuild test` dan build Release lulus pada source yang
sama dengan benchmark final. Destination macOS arm64, DerivedData eksternal,
`CODE_SIGNING_ALLOWED=NO`. Offline: **348 executed, 333 passed, 15 opt-in skipped,
0 failures**. Test mencakup restorasi, low/invalid score, proteksi, source binding,
kontrak/repair, mismatch sempit, rujukan, serta regresi pipeline/editor yang sudah
ada. Dummy utuh mendapat test restorasi tersendiri. Pengujian ini tidak berarti
interaksi editor manual atau seluruh ketepatan hukum telah diverifikasi.

Log final: `after-offline-9.log`, `after-offline-9.xcresult`,
`after-release-final.log`; baseline precommit validation ada dalam direktori
artefak yang sama. Source checksum ada pada `after-source-manifest.json` dan
`final-build-state.json`; hasil run dan checksum output pada
`before/completed-manifest.json`, `after/completed-manifest.json`.
Verifikasi final pada `final-verification.json`: 3.284 raw JSON per versi
(matrix, preparation, dan pipeline) cocok dengan checksum; source/fixture/overlay
tidak drift. Seluruh raw JSON dan `.xcresult` di luar repository. Dokumentasi repository
menyimpan fixture sintetis, evaluator, overlay pengukuran dan reproduksi.
