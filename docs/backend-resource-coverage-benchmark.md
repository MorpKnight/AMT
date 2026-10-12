# Cache, resource lifecycle, input lengkap, dan evaluasi backend

Baseline mapping disimpan pada commit `b5af42002052226ff6b42e0ef63bea1e85d0190a`
(`Optimize incremental editor result mapping`), branch `gi/flow-fix`. Implementasi
berikutnya belum di-commit atau di-push. Tidak mengubah UI, dependency, format
dokumen, signing, entitlement, atau deployment target.

Hasil utama: kebijakan cache dan pelepasan idle dapat dibuktikan berjalan, tetapi
**tidak ada peningkatan kecepatan atau RSS yang merata**. Workload lokal berubah
sekitar −4,9% sampai +4,5%; workload panjang bertambah waktu bersama pemeriksaan
segmen yang dahulu skipped. Semua sembilan pasangan incremental/fresh per versi
setara. Enam typo di luar rule pack masih terlewat; gate kualitas tetap
`insufficientEvidence`.

## Kebijakan implementasi

| Pemilik cache | Entry | Estimasi payload |
|---|---:|---:|
| Hasil lengkap processor | 512 | 16 MiB |
| Hasil segmen | 256 | 16 MiB |
| Analisis definisi | 256 | 16 MiB |
| Masing-masing cache konteks/risiko/resolution ViewModel | 256 | 8 MiB |
| Scoring TataKata | 2.048 | 8 MiB |

Semua memakai LRU: pembacaan memperbarui recency, insertion mengeluarkan entry
tertua sampai kedua anggaran terpenuhi. Entry yang sendirian melampaui anggaran
tidak disimpan. Ukuran menghitung payload logis key/value (termasuk string yang
berulang), bukan RSS atau batas total memori aplikasi. Cache tidak menyimpan raw
model output; key/eligibility/invalidation tetap berlaku. Snapshot cache segmen
mempertahankan bentuk dictionary dan dipulihkan dengan batas yang sama.

Qwen, TataKata, dan E5 memakai admission scheduler aplikasi. Model tetap resident
pada kondisi normal; buffer cache MLX dibatasi awal 512 MiB. Warning memangkas
cache turunan dan buffer idle; critical melepaskan runtime setelah lease aktif
selesai. Maintenance tidak membatalkan pemilik dokumen lain. Event berulang pada
level yang sama digabung sampai kondisi normal kembali. Callback cache memakai
weak ViewModel dan tidak menghapus hasil publik atau cakupan pekerjaan aktif.
Resource dimuat ulang secara lazy. Hook stress Debug mensimulasikan satu pressure
episode diikuti normal recovery, sehingga setiap pengulangan dapat menguji
release/reload; penggabungan repeated event diuji offline.

API memori mengikuti [revision MLX yang dikunci](https://github.com/ml-explore/mlx-swift/blob/0bb916c67f4b9e5c682cbe02a42c701c93ab5021/Source/MLX/Memory.swift).

Segmen publik, anchor, progress, dan schema keputusan tetap. Lokal memeriksa
seluruh teks. Candidate review memilih window internal maksimum 512 token dari
tokenizer Qwen, maksimum 16 per induk, dengan batas klausa/list dan kutipan utuh.
Klausa panjang dengan lingkup syarat/pengecualian yang ambigu tidak dipisahkan
berdasarkan tanda baca saja: cakupannya tidak lengkap dan keputusan yang
memerlukan konteks menjadi `needsReview`. Window bersifat konservatif, bukan
pembuktian semua klausa dapat dianalisis. Metadata membedakan window yang
direncanakan dari rentang yang benar-benar dikirim untuk kandidat.

Sebelum enam jalur generation, processor chat template yang sama menghitung
system instruction, tools, target, konteks, dan evidence; input maksimal 4.096
token. Batas output generation tidak berubah. Target/source definisi dan evidence
risiko/resolution lengkap; pemotongan 1.000/768/600 karakter dihapus. Jika tidak
muat, tidak ada klaim ekuivalen dari potongan. Konteks opsional dipilih sebagai
baris utuh; dependensi syarat/pengecualian yang tidak muat menolak input. E5
menolak input melampaui context 512 token, mengikuti fallback/coverage yang ada.
Hasil parsial tidak masuk cache lengkap/snapshot lengkap. Namespace kebijakan,
prompt, profil pipeline, dan cache segmen diperbarui; format dokumen tetap.

## Desain eksperimen

Baseline archive dan seluruh pengukuran awal selesai sebelum source produksi
berubah. Overlay hanya hook pengukuran Debug, fixture, dan test:
[resource-quality-baseline-overlay.patch](benchmarks/resource-quality-baseline-overlay.patch).
Harness pipeline dan fixture identik sebelum–sesudah; inference serial.

- Sepuluh workload × tiga warm run (cache hasil dikosongkan) dan tiga cached rerun.
- Enam workload lama × satu kontrol deterministic.
- Tiga pasangan incremental/fresh untuk local-12, definitions, dan long-clauses.
- 48 fixture × satu run hybrid per versi; 24 regression dan 24 holdout, delapan
  kelompok masing-masing enam scenario berbeda, seluruhnya synthetic/pending.
- TataKata terpisah: 12 kandidat tetap × tiga warm dan tiga cached run. Pipeline
  produksi tetap memakai spell checker OS; kedua hasil tidak disamakan.
- Stress: tiga pengulangan × 12 siklus local-60/definitions/TataKata, pergantian
  ViewModel untuk close/reopen dan pressure episode setiap empat siklus.

Qwen 4B, greedy/thinking off/seed 42, corpus dan resource revisions dikunci.
Persiapan resource terpisah; tidak mengulang cold matrix. RSS dan MLX active/cache
sample setiap 10 ms; puncak sampled dapat melewatkan lonjakan lebih singkat.
`editorMapping` tetap metrik event final; mapping lokal dan durasi event tetap
terpisah. Latensi terlihat mengukur publikasi state, bukan frame AppKit.

Corpus produksi saat pembekuan tidak memiliki source eligible >1.000 karakter
(maksimum 537). Workload long-source menambahkan satu entry sintetis yang jelas
berlabel sumber benchmark, tanpa URL hukum. Ini eksperimen kelengkapan evidence,
bukan sumber otoritatif atau klaim ketepatan hukum corpus produksi.

Fixture pending tidak dijadikan approved. Evaluator dan review-package yang ada
mempertahankan digest/revision/policy checks; gate tetap `insufficientEvidence`.
Precision/recall eksperimen hanya menggunakan expected output yang dinyatakan;
kelompok tanpa positive finding yang berlabel tidak memiliki recall terukur.
Holdout tidak digunakan untuk menyesuaikan threshold. Satu run kualitas tidak
menunjukkan kestabilan statistik.

## Hasil pengukuran final

Detik kecuali disebutkan lain. Angka tiga run adalah median [minimum–maximum].
Cached rerun memakai priming run di luar tiga record terukur. Persiapan resource
terpisah di setiap JSON; durasi xcodebuild/startup tidak dimasukkan ke total analisis.

### Warm dan cached

**warm**

| Workload | Sebelum | Sesudah | Delta detik | Delta % |
|---|---|---|---|---|
| local-12 | 4.077 [3.849–5.735] | 3.878 [3.861–3.889] | -0.199 | -4.9% |
| local-60 | 7.300 [7.053–7.982] | 7.057 [6.974–7.068] | -0.243 | -3.3% |
| local-180 | 15.821 [15.649–16.040] | 16.530 [16.077–16.713] | +0.709 | +4.5% |
| terminology | 0.686 [0.682–1.791] | 0.717 [0.704–0.728] | +0.031 | +4.5% |
| definitions | 4.750 [4.700–4.832] | 4.960 [4.952–5.212] | +0.210 | +4.4% |
| mixed | 9.395 [9.333–9.575] | 11.653 [11.427–11.765] | +2.258 | +24.0% |
| tatakata | 4.410 [4.396–4.826] | 4.493 [4.464–4.505] | +0.084 | +1.9% |
| long-clauses | 3.178 [3.166–3.284] | 7.817 [7.814–7.834] | +4.639 | +146.0% |
| long-source | 5.213 [5.185–5.368] | 5.340 [5.320–5.389] | +0.127 | +2.4% |
| hard-negative | 18.868 [18.670–18.886] | 19.021 [18.756–19.354] | +0.153 | +0.8% |

**cached**

| Workload | Sebelum | Sesudah | Delta detik | Delta % |
|---|---|---|---|---|
| local-12 | 0.024 [0.024–0.025] | 0.024 [0.024–0.025] | -0.000 | -1.5% |
| local-60 | 0.152 [0.150–0.160] | 0.161 [0.161–0.162] | +0.010 | +6.4% |
| local-180 | 0.796 [0.788–0.800] | 0.799 [0.797–0.806] | +0.003 | +0.3% |
| terminology | 0.012 [0.012–0.012] | 0.012 [0.012–0.012] | +0.000 | +0.1% |
| definitions | 0.013 [0.013–0.013] | 0.013 [0.013–0.016] | -0.000 | -0.6% |
| mixed | 0.295 [0.286–0.296] | 0.297 [0.290–0.304] | +0.002 | +0.7% |
| tatakata | 0.070 [0.067–0.075] | 0.061 [0.060–0.061] | -0.009 | -13.5% |
| long-clauses | 0.041 [0.041–0.041] | 0.805 [0.787–0.827] | +0.763 | +1851.5% |
| long-source | 0.012 [0.012–0.012] | 0.012 [0.012–0.012] | -0.000 | -0.3% |
| hard-negative | 0.015 [0.015–0.015] | 0.015 [0.015–0.015] | -0.000 | -0.3% |

### Kontrol dan incremental

| Workload / kondisi | Sebelum | Sesudah | Delta detik | Delta % |
|---|---|---|---|---|
| local-12 / control | 0.861 [0.861–0.861] | 0.872 [0.872–0.872] | +0.012 | +1.4% |
| local-60 / control | 4.094 [4.094–4.094] | 4.210 [4.210–4.210] | +0.117 | +2.8% |
| local-180 / control | 12.853 [12.853–12.853] | 13.191 [13.191–13.191] | +0.338 | +2.6% |
| terminology / control | 0.245 [0.245–0.245] | 0.259 [0.259–0.259] | +0.014 | +5.9% |
| definitions / control | 0.287 [0.287–0.287] | 0.290 [0.290–0.290] | +0.003 | +1.0% |
| mixed / control | 6.015 [6.015–6.015] | 9.121 [9.121–9.121] | +3.106 | +51.6% |
| local-12 / incremental | 4.182 [3.994–4.190] | 4.246 [4.196–4.724] | +0.064 | +1.5% |
| definitions / incremental | 0.512 [0.487–0.524] | 0.509 [0.475–0.514] | -0.003 | -0.6% |
| long-clauses / incremental | 3.257 [3.168–3.263] | 7.882 [7.839–8.027] | +4.625 | +142.0% |

Kesetaraan incremental/fresh (tiga pasangan, setiap versi): `{"after": {"definitions": [true, true, true], "local-12": [true, true, true], "long-clauses": [true, true, true]}, "before": {"definitions": [true, true, true], "local-12": [true, true, true], "long-clauses": [true, true, true]}}`. UUID dan timestamp dikeluarkan dari pembandingan.

### Temuan pertama dan memori

| Workload | Terlihat sebelum | Sesudah | Lokal actionable sebelum | Sesudah |
|---|---|---|---|---|
| local-12 | 0.014 [0.014–0.023] | 0.014 [0.014–0.015] | 0.014 [0.014–0.023] | 0.014 [0.014–0.015] |
| local-60 | 0.039 [0.038–0.040] | 0.038 [0.037–0.043] | 0.039 [0.038–0.040] | 0.038 [0.037–0.043] |
| local-180 | 0.096 [0.095–0.111] | 0.097 [0.095–0.099] | 0.096 [0.095–0.111] | 0.097 [0.095–0.099] |
| terminology | 0.264 [0.264–1.308] | 0.278 [0.268–0.304] | null | null |
| definitions | 0.054 [0.052–0.055] | 0.057 [0.055–0.059] | null | null |
| mixed | 0.052 [0.051–0.065] | 0.051 [0.051–0.054] | 0.052 [0.051–0.065] | 0.051 [0.051–0.054] |
| tatakata | null | null | null | null |
| long-clauses | 0.046 [0.046–0.080] | 0.046 [0.046–0.052] | 0.046 [0.046–0.080] | 0.046 [0.046–0.052] |
| long-source | null | null | null | null |
| hard-negative | 4.739 [4.708–4.808] | 4.695 [4.677–4.889] | null | null |

MiB; puncak per run, lalu median/rentang tiga run. RSS berbeda dari MLX active dan allocator cache.

| Workload | RSS sebelum | Sesudah | MLX active sebelum | Sesudah | MLX cache sebelum | Sesudah |
|---|---|---|---|---|---|---|
| local-12 | 938.5 [926.2–991.2] | 3718.7 [3718.2–3718.9] | 3630.3 [3630.3–3630.3] | 3588.8 [3588.8–3588.8] | 1826.1 [1826.1–1826.1] | 513.3 [512.7–514.3] |
| local-60 | 1151.2 [868.5–3047.2] | 3718.6 [3717.9–3718.7] | 3560.7 [3552.0–3560.7] | 3552.1 [3552.0–3560.7] | 1644.6 [1644.6–1644.6] | 512.7 [512.5–513.8] |
| local-180 | 661.8 [661.0–1844.4] | 3539.5 [3539.2–3714.9] | 3552.0 [3552.0–3560.7] | 3560.7 [3552.0–3560.7] | 1651.6 [1651.5–1651.6] | 517.0 [513.5–519.6] |
| terminology | 1963.3 [1962.9–1963.4] | 3700.2 [3700.1–3700.3] | 2715.4 [2715.4–2725.5] | 2715.4 [2715.4–2718.8] | 32.9 [32.8–33.1] | 33.4 [33.1–33.6] |
| definitions | 2256.5 [2153.3–3407.3] | 3479.1 [3165.7–3718.4] | 3613.7 [3613.7–3613.7] | 3613.7 [3613.7–3613.8] | 1209.1 [1208.5–1209.1] | 519.0 [518.8–519.2] |
| mixed | 864.7 [864.3–2737.2] | 2049.5 [2049.2–3704.3] | 3552.0 [3552.0–3588.1] | 3588.1 [3588.1–3588.1] | 1736.7 [1736.3–1736.7] | 515.0 [513.7–516.0] |
| tatakata | 1504.9 [1494.5–2878.7] | 4182.3 [4085.3–4185.9] | 4035.8 [4027.0–4035.8] | 4035.8 [4027.5–4035.9] | 1772.7 [1771.6–1772.8] | 519.5 [515.5–606.3] |
| long-clauses | 1520.7 [1350.7–2840.8] | 3729.1 [3727.9–3729.3] | 3731.7 [3677.9–3731.7] | 3613.7 [3587.7–3613.7] | 2036.3 [2036.3–2036.3] | 514.9 [514.2–515.4] |
| long-source | 1296.1 [1283.3–2612.3] | 3748.0 [3747.5–3748.6] | 3779.8 [3779.8–3779.8] | 3641.7 [3624.0–3641.7] | 2927.9 [2804.8–2927.9] | 516.9 [514.9–622.0] |
| hard-negative | 1337.1 [1336.6–3248.9] | 3721.9 [3721.5–3722.0] | 3795.7 [3776.1–3799.7] | 3792.0 [3792.0–3792.0] | 6611.1 [6610.5–6611.1] | 519.2 [519.1–740.4] |

### Tahap, counter, dan cakupan

| Workload | Retrieval sebelum | Sesudah | Validation sebelum | Sesudah | Mapping final sebelum | Sesudah |
|---|---|---|---|---|---|---|
| local-12 | 0.626 [0.625–0.672] | 0.654 [0.649–0.662] | 0.776 [0.775–0.837] | 0.809 [0.804–0.817] | 0.002 [0.002–0.002] | 0.002 [0.002–0.002] |
| local-60 | 3.257 [3.196–3.990] | 3.276 [3.202–3.316] | 4.041 [3.963–4.878] | 4.086 [3.970–4.099] | 0.025 [0.025–0.028] | 0.025 [0.025–0.025] |
| local-180 | 9.701 [9.550–9.744] | 10.099 [9.808–10.422] | 12.110 [11.936–12.110] | 12.551 [12.286–12.952] | 0.170 [0.169–0.176] | 0.176 [0.175–0.177] |
| terminology | 0.453 [0.443–1.516] | 0.468 [0.465–0.477] | 0.671 [0.668–1.773] | 0.702 [0.689–0.707] | 0.000 [0.000–0.001] | 0.000 [0.000–0.000] |
| definitions | 0.316 [0.298–0.394] | 0.325 [0.311–0.335] | 4.735 [4.684–4.813] | 4.943 [4.936–5.191] | 0.000 [0.000–0.001] | 0.000 [0.000–0.000] |
| mixed | 4.630 [4.580–4.656] | 4.864 [4.791–4.916] | 5.610 [5.546–5.637] | 7.591 [7.526–7.701] | 0.052 [0.051–0.053] | 0.055 [0.053–0.056] |
| tatakata | 0.209 [0.205–0.214] | 0.219 [0.218–0.222] | 1.856 [1.844–2.260] | 1.914 [1.890–1.927] | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] |
| long-clauses | 0.031 [0.031–0.034] | 0.500 [0.489–0.507] | 0.034 [0.034–0.040] | 4.739 [4.717–4.787] | 0.000 [0.000–0.000] | 0.001 [0.001–0.001] |
| long-source | 0.323 [0.314–0.334] | 0.325 [0.323–0.333] | 2.812 [2.798–2.851] | 2.894 [2.890–2.905] | 0.000 [0.000–0.001] | 0.000 [0.000–0.000] |
| hard-negative | 0.800 [0.794–0.816] | 0.822 [0.754–0.861] | 14.093 [13.962–14.210] | 14.353 [14.065–14.450] | 0.001 [0.001–0.001] | 0.001 [0.001–0.001] |

Stage validation mencakup orchestration segmen dan overlap dengan tahap lain; jumlah stage bukan total pipeline. JSON mempertahankan mapping lokal dan durasi event terpisah.

| Workload | Qwen kandidat | Qwen definisi | Semantic request | Kandidat Tata scored | Cache hit | Repair | Fallback | Segmen stage tidak lengkap |
|---|---|---|---|---|---|---|---|---|
| local-12 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | [0, 0, 0] → [0, 0, 0] |
| local-60 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | [0, 0, 0] → [0, 0, 0] |
| local-180 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | [0, 0, 0] → [0, 0, 0] |
| terminology | 0 → 0 | 0 → 0 | 7 → 7 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | [0, 0, 0] → [0, 0, 0] |
| definitions | 0 → 0 | 2 → 2 | 4 → 4 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | [0, 0, 0] → [0, 0, 0] |
| mixed | 0 → 0 | 0 → 0 | 2 → 2 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | [1, 1, 1] → [0, 0, 0] |
| tatakata | 1 → 1 | 0 → 0 | 0 → 0 | 1 → 1 | 0 → 0 | 0 → 0 | 0 → 0 | [0, 0, 0] → [0, 0, 0] |
| long-clauses | 0 → 0 | 0 → 0 | 0 → 4 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | [6, 6, 6] → [1, 1, 1] |
| long-source | 0 → 0 | 1 → 1 | 4 → 4 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | [0, 0, 0] → [0, 0, 0] |
| hard-negative | 0 → 0 | 6 → 6 | 8 → 8 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | [0, 0, 0] → [0, 0, 0] |

Counter Qwen konteks/risiko/resolution, kandidat diproses, stage lengkap, dan diagnostik LRU berada dalam `comparison.json` dan JSON per-run. Semantic request dan scored candidate merupakan counter pipeline, bukan pembuktian jumlah kernel/forward MLX; input yang ditolak sebelum forward tetap dapat menjadi retrieval request. Rentang prompt yang dilaporkan memakai `rangeScope=prompt`; range window memakai koordinat UTF-16 segmen induk.

### TataKata dengan kandidat tetap

| Kondisi | Sebelum | Sesudah | Delta detik | Delta % |
|---|---|---|---|---|
| warm | 1.845758 [1.821828–1.895385] | 1.902954 [1.889042–1.939160] | +0.057197 | +3.1% |
| cached | 0.001928 [0.001816–1.883459] | 0.002203 [0.002082–1.922994] | +0.000275 | +14.3% |

before: deltaSum [8.498275593323768, 8.498275593323768, 8.498275593323768]; jumlah kandidat [12, 12, 12]. after: deltaSum [8.498275593323768, 8.498275593323768, 8.498275593323768]; jumlah kandidat [12, 12, 12]. Fixed scoring mencatat MLX end-state; sampler RSS 10 ms berlaku pada harness pipeline/stress.

### Kualitas synthetic pending

| Kelompok (6) | Precision/recall sebelum | Sesudah | FP berlabel | FN berlabel | Actionable tanpa label positif lengkap | Definisi needsReview/keputusan |
|---|---|---|---|---|---|---|
| spelling | null/0.0 | null/0.0 | 0 → 0 | 6 → 6 | 0 → 0 | 0/0 → 0/0 |
| grammar | 1.0/1.0 | 1.0/1.0 | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 |
| paraphrase | null/null | null/null | 0 → 0 | 0 → 0 | 0 → 0 | 3/3 → 3/3 |
| operators | null/null | null/null | 0 → 0 | 0 → 0 | 0 → 0 | 2/2 → 2/2 |
| quantities | null/null | null/null | 0 → 0 | 0 → 0 | 0 → 0 | 0/0 → 0/0 |
| eligibility | null/null | null/null | 0 → 0 | 0 → 0 | 0 → 0 | 1/2 → 1/2 |
| long | null/null | null/null | 0 → 0 | 0 → 0 | 3 → 3 | 0/0 → 1/1 |
| protected | null/null | null/null | 0 → 0 | 0 → 0 | 0 → 0 | 3/4 → 3/4 |

Expected spelling/grammar/no-change bersifat provisional. Empat kelompok definisi/long/eligibility belum mempunyai label semantik positif lengkap: actionables yang tidak berlabel dilaporkan terpisah, bukan otomatis false positive. Tidak ada klaim peningkatan akurasi semantik dari data ini. Proporsi needsReview untuk review kandidat dan keputusan definisi disimpan terpisah. Seluruh fixture tetap pending, tanpa reviewer palsu atau threshold holdout tuning.

before: no-change dengan suggestion 0/16; invalid anchor 0; invalid sumber 0. after: no-change dengan suggestion 0/16; invalid anchor 0; invalid sumber 0. Hard-negative angka/aktor dan protected: 0/12 fixture menghasilkan suggestion pada kedua versi. Validitas sumber berarti eligibility/anchor yang diperiksa harness, bukan pembuktian legalitas sumber.

### Stress memori

| Siklus 12 dokumen | Analisis sebelum (s) | RSS peak (MiB) | MLX active akhir (MiB) | Analisis sesudah (s) | RSS peak (MiB) | MLX active akhir (MiB) |
|---|---|---|---|---|---|---|
| 1 | 53.270 | 4203.1 | 3181.8 | 55.640 | 4201.5 | 2732.9 |
| 2 | 52.419 | 4202.7 | 3181.8 | 55.882 | 4092.8 | 2257.9 |
| 3 | 47.404 | 4203.0 | 3181.8 | 51.851 | 4177.9 | 2706.9 |

Diagnostik maintenance setelah siklus terakhir: `{"complete": 6, "completeCost": 28344, "completeEvictions": 0, "completeHits": 0, "completeMisses": 6, "contextEvictions": 0, "contextHits": 0, "contextMisses": 1, "definition": 6, "definitionCost": 9104, "definitionEvictions": 0, "maintenance": 9, "maintenanceActiveAfter": 11996, "maintenanceActiveBefore": 3336352456, "maintenanceCacheAfter": 0, "mlxRuntimePeak": 4287570566, "qwenLoads": 4, "qwenReleases": 3, "resolutionEvictions": 0, "resolutionHits": 0, "resolutionMisses": 0, "riskEvictions": 0, "riskHits": 0, "riskMisses": 1, "segment-cost": 4140, "segment-entries": 6, "segment-evictions": 0, "segment-hits": 0, "segment-misses": 6}`.

Durasi stress adalah jumlah analisis; maintenance dan konstruksi ViewModel di antara run tidak masuk durasi tersebut. Sampler berjalan saat analisis, sedangkan MLX sebelum/sesudah pelepasan tercatat oleh lifecycle. Event OS pressure nyata belum dipaksakan; stress memakai hook, dan tekanan saat lease aktif/antrean pengguna diuji offline.

### Interpretasi regresi dan pengukuran ulang RSS

- `mixed`: median 9,395 → 11,653 s (+24,0%), skipped 1 → 0; hasil normalisasi tetap
  setara. `long-clauses`: 3,178 → 7,817 s (+146,0%), skipped 6 → 0 dan segmen dengan
  stage failed/tooLong 6 → 1. Satu assessment definisi baru menjadi needsReview.
  Ini penambahan pekerjaan/cakupan, bukan perbandingan pekerjaan identik. Stage
  skippedByPolicy tetap bukan bukti pemeriksaan semantik telah dilaksanakan.
- `local-180` memiliki hasil setara tetapi median +4,5%. Trace retrieval meningkat
  sekitar 9,701 → 10,099 s, context classification 2,823 → 2,843 s, dan mapping
  final 0,170 → 0,176 s. Validation/orchestration 12,110 → 12,551 s overlap dengan
  retrieval; jangan menjumlahkannya. Estimasi payload saat insertion dan full
  prompt preflight adalah biaya baru, tetapi eksperimen ini tidak mengisolasi
  kontribusi masing-masing. Validasi tidak dilonggarkan untuk mengejar waktu.
- Cache allocator akhir stress turun 2.767,8 → 511,2 MiB; MLX active akhir
  3.181,8 → 2.706,9 MiB. Peak RSS stress 4.203,1 → 4.201,5 MiB hampir sama.
  Sembilan maintenance episode, tiga release Qwen dan empat load Qwen tercatat.
  Critical terakhir melepaskan MLX active 3.181,8 MiB menjadi sekitar 12 KiB,
  kemudian resource yang diperlukan dimuat kembali. Buffer cache limit 512 MiB
  adalah konfigurasi allocator: API mereklamasi kelebihan pada allocation
  berikutnya, sehingga sampled peak dapat melampaui 512 MiB.

RSS warm sebelum berfluktuasi kuat antarproses. Sesudah matriks, satu pasangan
local-12 warm × tiga diulang dengan harness/revision identik dan proses baru.
Pengukuran tambahan disimpan terpisah, tidak menggantikan hasil utama:

| Metrik | Sebelum tambahan | Sesudah tambahan |
|---|---:|---:|
| Total median [min–max], s | 3,954 [3,947–4,007] | 3,956 [3,939–3,981] |
| RSS peak median [min–max], MiB | 3.262,6 [3.262,4–3.710,5] | 3.725,4 [3.724,9–3.725,6] |
| MLX cache peak median, MiB | 1.826,1 | 517,9 |
| MLX active peak median, MiB | 3.630,3 | 3.630,3 |

RSS tambahan +14,2%, allocator cache −71,6%, waktu hampir sama. Variasi RSS dan
arah yang berbeda dari MLX aktif/cache membuat klaim pengurangan total memori
proses tidak didukung. Penyebab RSS belum terisolasi secara kausal. Sampler sama
pada kedua versi; tidak mengganti RSS dengan metrik lain untuk menghilangkan
regresi. Artefak: `reports/memory-repeat-before/`, `reports/memory-repeat-after/`,
`memory-repeat-summary.json` dan log/result bundle pasangannya.

Counter LRU pada `cacheCounts` bersifat kumulatif selama umur owner; counter
observation seperti cacheHitCount adalah per-run. Tidak ada eviction kapasitas
pada matriks kecil ini; batas count/cost, oversize dan >capacity diuji offline.
Fixture kualitas tidak menguji seluruh kemungkinan window model: jalur window
Unicode/kalimat/kutipan/max-16 diuji offline, sedangkan model pada workload panjang
mengikuti routing produksi yang dapat menolak atau melewati review kandidat.

### Validasi dan identitas

before: source/tests `91cc5b670ad1ab984124157f8c48527517b2f39e6f425eeca0ce116e00b0f17c`, harness `0499bf70fbe62e42c816de3280d256f4d9276b57f387fb247f9477b03eee29c7`, fixture `8916ae13e4eadc9105755ca2cdb8634bae36afcec9529771b8ca2df896d3955b`.

after: source/tests `aa904982f425a5843ba083a4d00aff7d0de55cc57154090104cfb0c462c44766`, harness `0499bf70fbe62e42c816de3280d256f4d9276b57f387fb247f9477b03eee29c7`, fixture `8916ae13e4eadc9105755ca2cdb8634bae36afcec9529771b8ca2df896d3955b`.

Debug build dan 322 test offline lulus (11 opt-in skipped, 0 failure); hasil pengukuran awal `offline-after-breaker.xcresult`; validasi akhir `offline-final.xcresult`. Gate dari evaluator ada di `pending-quality-gate.json`: `insufficientEvidence`. Build Release lulus (`build-release-repair.log`); Debug build dan seluruh test final lulus setelah koreksi kompatibilitas Release (322 total: 311 pass, 11 opt-in skip, 0 failure). `git diff --check` lulus. Laporan percobaan sesudah sebelum perbaikan circuit breaker disimpan di `reports/after-pre-breaker-fix/` dan **dikeluarkan** dari perbandingan final.



## Reproduksi dan artefak

Artefak sesi ini berada di `/private/tmp/amt-resource-quality-task/`: baseline,
manifest source/harness/fixture, checksum corpus, JSON per-run, log, dan `.xcresult`.
Tidak ada download baru yang diperlukan pada sesi pengukuran ini. Folder sementara
bukan penyimpanan permanen; salin artefak sebelum pembersihan sistem jika dibutuhkan.

Buat baseline dari commit dan terapkan overlay dari checkout hasil implementasi:

```sh
experiment_dir="$(mktemp -d /private/tmp/amt-resource-quality.XXXXXX)"
mkdir "$experiment_dir/baseline"
git archive b5af42002052226ff6b42e0ef63bea1e85d0190a | tar -x -C "$experiment_dir/baseline"
git -C "$experiment_dir/baseline" apply "$PWD/docs/benchmarks/resource-quality-baseline-overlay.patch"
```

Gunakan path SourcePackages eksternal yang berisi dependency sesuai Package.resolved,
dan cache Hugging Face dengan model/revision yang sama. Pada sesi ini masing-masing
`/tmp/amt-backend-study-tests.qIx3rg/SourcePackages` dan
`/private/tmp/amt-flow-fix-task/hf-hub`. Jika resource belum tersedia, unduh sebelum
pengukuran dan laporkan waktunya terpisah.

Untuk tiap root (`baseline` lalu checkout hasil implementasi), build Debug dahulu;
contoh baseline:

```sh
xcodebuild -project "$experiment_dir/baseline/AMT.xcodeproj" \
  -scheme AMT -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$experiment_dir/derived-before" \
  -clonedSourcePackagesDirPath /tmp/amt-backend-study-tests.qIx3rg/SourcePackages \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  build-for-testing CODE_SIGNING_ALLOWED=NO

python3 docs/benchmarks/run-resource-quality.py \
  --label before --root "$experiment_dir/baseline" --artifacts "$experiment_dir" \
  --packages /tmp/amt-backend-study-tests.qIx3rg/SourcePackages \
  --hf-cache /private/tmp/amt-flow-fix-task/hf-hub \
  --baseline-revision b5af42002052226ff6b42e0ef63bea1e85d0190a
```

Ulangi build dengan root checkout dan `derived-after`, lalu runner `--label after`
dengan `--root "$PWD"`. Runner menjalankan seluruh matriks serial, menolak reuse
laporan dengan identitas source yang berbeda, dan menyimpan log/result bundle di
luar repository. Jangan menjalankan build lain atau inference lain bersamaan
pengukuran. Identitas runtime, fixture text digest, runner digest, source digest,
revision Qwen/corpus, dan kondisi OS/memori tersedia dalam manifest/JSON.

Test reguler tidak mengaktifkan kedua flag opt-in `AMT_RUN_FLOW_BENCHMARK` dan
`AMT_RUN_RESOURCE_BENCHMARK`; runner menyuplai `TEST_RUNNER_*` yang diteruskan Xcode
ke XCTest tanpa prefix. `AMT_FLOW_PHASE` memilih warm/cached/control/incremental/
quality/stress; fixed scoring memakai target test terpisah.

### Koreksi Release setelah pengukuran

Build Release pertama menemukan method `recordInputCoverage` hanya dideklarasikan
pada Debug. Ditambahkan no-op di blok `#if !DEBUG`; tidak mengubah cabang Debug,
input model, cache policy, atau keputusan pipeline. Source mentah final berbeda
dari SHA pengukuran di atas. Perbandingan menyeluruh memastikan seluruh source
lain identik dan, setelah blok Release-only dikeluarkan, Debug source cocok
dengan SHA yang diukur. Bukti disimpan di `release-compatibility.json` dan
`release-compatibility.patch`; Debug/test final serta Release dibuild ulang.

SHA source/tests final: `954550874783101eca4d0dc604656b547e7e7dda65b019aba905418aff119c81`. Tidak mencampurkan identitas final ini dengan SHA raw pengukuran.

## Inventori perubahan akhir

- `AMT/Features/AIConnector/Models/AIConnectorDefinitionModels.swift`
- `AMT/Features/AIConnector/Models/AIConnectorModels.swift`
- `AMT/Features/AIConnector/Models/AIConnectorObservationModels.swift`
- `AMT/Features/AIConnector/Models/AIConnectorQualityModels.swift`
- `AMT/Features/AIConnector/Services/AIConnectorAnalysisLRUCache.swift`
- `AMT/Features/AIConnector/Services/AIConnectorBackendEvaluationFixtures.swift`
- `AMT/Features/AIConnector/Services/AIConnectorDefinitionAnalyzer.swift`
- `AMT/Features/AIConnector/Services/AIConnectorDefinitionResolutionService.swift`
- `AMT/Features/AIConnector/Services/AIConnectorDocumentContextCoordinator.swift`
- `AMT/Features/AIConnector/Services/AIConnectorDocumentReviewDetector.swift`
- `AMT/Features/AIConnector/Services/AIConnectorInferenceScheduler.swift`
- `AMT/Features/AIConnector/Services/AIConnectorInferenceWindowPlanner.swift`
- `AMT/Features/AIConnector/Services/AIConnectorObservationCollector.swift`
- `AMT/Features/AIConnector/Services/AIConnectorResourceLifecycle.swift`
- `AMT/Features/AIConnector/Services/AIConnectorSegmentCache.swift`
- `AMT/Features/AIConnector/Services/AIConnectorWorkQueue.swift`
- `AMT/Features/AIConnector/Services/QwenSuggestionService.swift`
- `AMT/Features/AIConnector/Services/TataKataLanguageScorer.swift`
- `AMT/Features/AIConnector/ViewModels/AIConnectorViewModel.swift`
- `AMT/Shared/LegalKnowledge/Services/LegalSemanticRetriever.swift`
- `AMTTests/AIConnectorFlowBenchmarkTests.swift`
- `AMTTests/AIConnectorResourcePolicyTests.swift`
- `AMTTests/AIConnectorResourceScoringBenchmarkTests.swift`
- `README.md`
- `docs/backend-resource-coverage-benchmark.md`
- `docs/benchmarks/resource-quality-baseline-overlay.patch`
- `docs/benchmarks/run-resource-quality.py`

Validasi akhir memakai `xcodebuild -project AMT.xcodeproj -scheme AMT
-destination platform=macOS,arch=arm64 -derivedDataPath
/private/tmp/amt-resource-quality-task/derived-after
-clonedSourcePackagesDirPath /tmp/amt-backend-study-tests.qIx3rg/SourcePackages
-disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO`: konfigurasi Debug
menjalankan `test` dengan `-parallel-testing-enabled NO`, konfigurasi Release
menjalankan `build`. Setting arsitektur Release yang sudah ada juga membangun
x86_64; tidak mengubah project setting. Ringkasan final: `validation-final.json`.

Checksum JSON/log/result bundle dicatat dalam `artifact-checksums.json`;
DerivedData dan cache model tidak disertakan. File raw tetap di luar repository.
