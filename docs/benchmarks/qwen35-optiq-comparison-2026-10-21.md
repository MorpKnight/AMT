# Qwen3.5 4B: model saat ini vs OptiQ

Benchmark pada backend aplikasi yang sama. Label sintetis masih pending; recall deteksi span dan ketepatan operasi bukan pembuktian akurasi hukum.

Status lengkap: True. Model default aplikasi tidak diubah.

| Kondisi | Model | Request | Median request (s) | p95 (s) | Total (s) | Recall deteksi | Recall koreksi actionable | Partial |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| warm | stock | 288 | 2.3717 | 4.9796 | 542.952 | 1.0 | 0.9375 | 6 |
| warm | optiq | 288 | 2.8471 | 6.2005 | 649.166 | 1.0 | 0.9375 | 9 |
| cached | stock | 288 | 0.0129 | 0.0132 | 6.306 | 1.0 | 0.9375 | 6 |
| cached | optiq | 288 | 0.0129 | 0.0133 | 20.256 | 1.0 | 0.9375 | 9 |

Per-iteration median/rentang dan per-kategori ada di summary.json. Repetisi bukan dokumen independen. Cached mempunyai priming terpisah; fullFresh tetap melewati cache hasil.

| Model warm | RSS peak MiB | MLX active peak MiB | Context model attempts | Native model calls dilaporkan | Anchor invalid | Source invalid |
|---|---:|---:|---:|---:|---:|---:|
| stock | 3309.72 | 4238.57 | 99 | 6 | 0 | 0 |
| optiq | 1790.19 | 5073.40 | 96 | 6 | 0 | 0 |

RSS dan MLX bukan dua angka untuk dijumlahkan. Peak model resident dapat mencakup allocator/runtime lainnya. Input dengan routing lokal dibahas terpisah dari input yang memanggil model.

| Ejaan historis | Input | Target ejaan | Terdeteksi | Dikoreksi actionable | TP/FP local gold |
|---|---:|---:|---:|---:|---:|
| stock | 181 | 43 | 39 | 32 | 49/0 |
| optiq | 181 | 43 | 38 | 33 | 50/0 |

## Reproduksi dan batas

Lihat protocol.json, source-checksums.json masing-masing arm, download-manifest.json, campaign.py, evaluate.py, log dan xcresult. Snapshot stock/optiq berasal dari working tree termasuk source drafting lokal yang sama. Satu-satunya perbedaan source antar-arm adalah model ID dan revision. Runtime native MLX Swift, konfigurasi generation dan fixture identik. Bobot OptiQ diunduh sebelum pengukuran dan diverifikasi SHA256 LFS.

Inference serial, model resident untuk warm; cache hasil/scoring dihapus tiap warm. RSS/MLX disampling melalui harness yang sama setiap 10ms. Urutan stock lalu OptiQ tidak diinterleave; kondisi host bisa mempengaruhi latency. Persiapan resource, download dan build tidak masuk waktu request. Tidak ada klaim kecepatan MTP; backend memakai generator Swift yang sama.

Temuan read-only tidak dianggap koreksi actionable. Kegagalan inference, coverage partial dan unexpected actionable harus dibaca bersama recall. Rubrik span belum membuktikan alasan/evidence hukum benar. Fixture pernah dipakai pada eksperimen sebelumnya, bukan blind holdout baru.

Delta total warm OptiQ vs stock: 106.214s (+19.56%).
Fixture dengan perubahan output/status pada run pertama: 2; lihat summary.json untuk audit manual.


## Audit tambahan

Identical local-directory measurement hook diterapkan pada kedua salinan. Model MTP dan vision sidecar OptiQ diunduh utuh tetapi tidak dimuat pada text-only runtime. Loader Swift membaca safetensors secara rekursif; MTP dapat mengaktifkan jalur sanitasi norm yang bukan tujuan benchmark. Lihat loader-preflight.json dan protocol.json. Ini pengukuran OptiQ dengan staging resource yang eksplisit, bukan klaim mengganti model ID saja aman di produksi.

Subset 32 input dengan panggilan review pasangan Qwen pada salah satu model, masing-masing tiga ulang:

| Model | Median dari median per-input, s | Total tahap review pasangan, s | Attempts | Token output tahap pasangan |
|---|---:|---:|---:|---:|
| stock | 2.4883 | 221.883 | 99 | 6504 |
| optiq | 2.9662 | 264.020 | 96 | 6387 |

Waktu tahap review meliputi persiapan/validasi dan generation, bukan pengukuran decode tokens/s murni. Counter native yang tersedia tidak mencakup seluruh classifier calls; jangan menjumlahkannya sebagai total inference lengkap. First-actionable memakai pengamatan array suggestion dari harness lama; diagnostik read-only berpotensi ikut teramati. Ketepatan actionable diukur terpisah dari output final.

Perubahan source aplikasi asli: 0. Perbedaan source antar-arm: ['AMT/Features/AIConnector/Models/AIConnectorModels.swift']. Fixture/checksum dan konsistensi tiga ulang/cached ada di integrity-audit.json.


## Kesimpulan eksperimen dan audit keluaran

Total analisis terukur 1.514: 96 input × (3 warm + 3 cached) × 2 model, ditambah 181 input historis × 2 model. Dua belas pilot dikeluarkan dari statistik utama. Build kedua arm dan seluruh fase benchmark selesai exit 0; tidak ada anchor/source actionable invalid. 96/96 fixture per arm konsisten antar tiga warm run dan cached rerun (proyeksi kategori/span/replacement/coverage).

Pada review utama, kedua model menghasilkan 15/16 koreksi benar per ulang, 0 actionable tidak sesuai fixture. Warning Jakarta dalam satu alamat hilang pada OptiQ. Satu kasus kutipan instruksi berubah dari compatible menjadi uncertain/abstained, sehingga jumlah input unik partial naik dari 2/96 ke 3/96 (6 vs 9 run warm dan cached). Ini abstention semantik, bukan kegagalan parser.

Historis: deteksi ejaan stock 39/43 (90,70%), OptiQ 38/43 (88,37%); koreksi actionable stock 32/43 (74,42%), OptiQ 33/43 (76,74%). OptiQ mengoreksi Datta pada satu fixture pendek dengan deklarasi istilah eksplisit. Namun, pada dummy document penuh OptiQ tidak menampilkan Datta sama sekali, sementara stock menampilkannya baca-saja. Pada dua dummy, OptiQ mengurangi warning nama Jakarta/Kurnia dan membuat resiko -> risiko actionable. Perubahan ini berarti OptiQ bukan pemenang akurasi secara menyeluruh. Pengujian historis satu run per model; selisih satu occurrence perlu konfirmasi sebelum keputusan produksi.

OptiQ lebih lambat 19,56% pada total warm (542,952 -> 649,166 s). Median request naik 2,3717 -> 2,8471 s. Peak active MLX naik 4.238,57 -> 5.073,40 MiB (+19,70%). Peak RSS teramati justru lebih rendah, 3.309,72 -> 1.790,19 MiB; RSS dipengaruhi residency/page mapping dan tidak membuktikan total unified memory lebih hemat. Kedua metrik dipertahankan terpisah.

Cached median hampir sama (~12,9 ms), tetapi total 288 rerun naik 6,306 -> 20,256 s; Sebagian rerun masih memanggil model, termasuk kasus partial tambahan pada OptiQ dan cache miss pada input lain; counter review pasangan adalah 1 attempt stock vs 4 attempt OptiQ. Jangan menafsirkan median cached saja sebagai performa identik untuk seluruh workload.

Rekomendasi: pertahankan model saat ini sebagai default. OptiQ memberi beberapa perbaikan spesifik, tetapi belum memberi kemenangan kualitas menyeluruh untuk menutup tambahan waktu, alokasi MLX dan abstention. Penggunaan MTP memerlukan eksperimen terpisah; tidak diuji di sini.

Lihat manual-difference-audit.json. Label tetap pending dan seluruh hasil merupakan eksperimen sintetis, bukan persetujuan ahli hukum. Tidak ada source aplikasi, model default, dependency, commit atau remote yang diubah.


## Keputusan produksi

Tetap gunakan `mlx-community/Qwen3.5-4B-MLX-4bit` revision `32f3e8ecf65426fc3306969496342d504bfa13f3`. OptiQ diuji pada revision `e36303cf85f1d8a5ef1aab69dd03d699c6ac4d79`; model default aplikasi tidak diganti. Ringkasan numerik dan audit perbedaan tersedia di `qwen35-optiq-comparison-2026-10-21.json`.

Untuk reproduksi: buat dua salinan working tree yang sama di direktori temporary; pertahankan semua dependency dan corpus. Gunakan harness `LegalReviewBackendBenchmarkTests` serta fixture `experiments/legal-review-integration`. Pada salinan kandidat, ubah hanya model ID dan revision untuk `qwen35Base4B`. Kedua salinan mendapat hook identik untuk mengarahkan `ModelConfiguration.id` ke folder model lokal yang dipin, tanpa mengganti loader/generation. Folder text-only memuat bobot utama dan tokenizer/template asli, mengecualikan sidecar MTP OptiQ dari pemindaian rekursif. Tokenizer dan chat template kedua model identik byte-for-byte.

Jalankan build-for-testing lalu matrix warm/cached (96 input, tiga ulang), history (181 input, sekali) secara serial dengan greedy, thinking mati dan seed42. Resource preparation terpisah; clear cache hasil/scoring setiap warm; cached memakai priming terpisah sebelum incremental tanpa perubahan. Bandingkan source/fixture checksum dan run provenance sebelum merangkum. Script persiapan/campaign/audit asli beserta record, checksum dan xcresult tersimpan di `/private/tmp/amt-optiq-comparison-20261021`; artefak temporary perlu disalin sebelum pembersihan sistem.
