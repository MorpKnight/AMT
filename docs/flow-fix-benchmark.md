# Benchmark flow sebelum dan sesudah

Baseline commit `94aa700` dibandingkan dengan working tree `gi/flow-fix`. JSON, manifest/checksum, log, dan `.xcresult` berada di `/private/tmp/amt-flow-fix-task/`. Metode dan instruksi reproduksi: [flow-fix-methodology.md](flow-fix-methodology.md); perubahan implementasi: [flow-fix-implementation.md](flow-fix-implementation.md).

Pengunduhan bobot 4.002.937.527 byte memerlukan 2.216 detik (36 menit 56 detik), dilakukan sebelum analisis dan tidak masuk waktu benchmark. Resource preparation dipisahkan di JSON. Capture instrumentasi awal yang tidak lengkap dikeluarkan dan baseline diulang dengan harness final yang identik pada kedua versi.

## Hasil utama

Matriks final memuat 54 pengukuran per versi (108 total), ditambah preparation dan benchmark tambahan. Semua angka sesudah berasal dari source final; capture sebelum perbaikan key cache diarsipkan di `reports/after-cache-key-v1/` dan tidak masuk tabel.

| Workload warm | Median total sebelum → sesudah | Perubahan |
|---|---:|---:|
| definitions | 14.913 → 5.676 detik | -61.9% |
| local-12 | 19.401 → 6.534 detik | -66.3% |
| local-180 | 482.647 → 61.939 detik | -87.2% |
| local-60 | 164.272 → 20.769 detik | -87.4% |
| mixed | 177.540 → 25.609 detik | -85.6% |
| terminology | 4.914 → 2.611 detik | -46.9% |

Gold ejaan pada 12/60/180 segmen tetap mempunyai precision/recall 1,0 di kedua versi. Workload campuran bertambah dari 180 menjadi 240 kandidat, sehingga perbandingannya juga mencerminkan perubahan cakupan. Routing baru menghindari E5/review definisi pada workload ejaan lokal, sementara indikasi terminologi/definisi tetap menjalankan retrieval yang relevan.

Kontrol deterministic 180 segmen mengalami regresi total **56,448 → 58,993 detik (+2,545 detik; +4,5%)**. Trace tahap menunjukkan tambahan pass lokal 2,324 detik dan editorMapping 2,034 → 4,910 detik, sementara suggestionRetrieval turun 51,959 → 47,702 detik. Publikasi bertahap/upsert menambah pekerjaan pada kontrol yang sejak awal tidak memanggil Qwen. Tahap dapat overlap; angka ini melokalisasi biaya tambahan, bukan profil per fungsi. Koreksi lokal pertamanya tetap lebih cepat: 1,413 → 0,107 detik.

Temuan pertama yang terlihat pada workload terminologi juga lebih lambat: **0,806 → 1,116 detik (+0,310 detik; +38,5%)**, walaupun total warm turun 4,914 → 2,611 detik. Trace segmen pertama menunjukkan suggestionRetrieval 0,287 → 0,572 detik. Jalur baru melakukan lexical gate sebelum hybrid retrieval; workload ini tidak mempunyai koreksi lokal yang dapat dipublikasikan lebih awal. Penggunaan ulang hasil lexical gate merupakan kandidat optimasi berikutnya, tanpa menghilangkan kebijakan routing atau validasi.

Peak RSS warm meningkat pada empat workload, termasuk local-180 **0,193 → 3,042 GiB**. Nilai awal yang sangat rendah dan variasi residency membatasi interpretasi; pengukuran ini tidak membuktikan kenaikan total memori GPU, dan penyebabnya belum terdiagnosis. Semua nilai/rentang RSS tetap ditampilkan, bukan diganti metrik setelah melihat hasil.

Pada warm 60 segmen, tahap suggestionRetrieval masih memerlukan median 15.994 detik walaupun query E5 nol. Jalur lexical dan mapping editor tetap membutuhkan pekerjaan; stage agregat dapat overlap dan tidak dijumlahkan sebagai waktu total.

Peningkatan ini adalah hasil workload sintetis pada mesin dan urutan eksperimen tersebut. Model masih menilai kalimat eksplisit `"Data" adalah informasi yang tidak dapat dipublikasikan.` sebagai `notDefinition` pada kedua versi. Fixture terminologi/definisi belum mempunyai gold hukum yang ditinjau, sehingga hasil ini belum mengukur recall definisi secara menyeluruh. Tidak ditemukan keputusan matches/actionable pada hard-negative definisi yang dijalankan; pernyataan ini deskriptif untuk fixture tersebut.

Durasi editorMapping warm 180 segmen meningkat dari 2.490 ke 4.882 detik. Jalur baru melakukan publikasi lokal dan upsert hasil akhir dengan identitas occurrence yang dipertahankan; kenaikan ini selaras dengan pekerjaan mapping tambahan, tetapi belum dipisahkan melalui profiler per fungsi. Total dan latensi temuan pertama tetap lebih pendek.

## Resource cold: satu run dalam proses baru

Waktu dalam detik. Selisih absolut/persentase menggunakan waktu total; angka negatif berarti waktu lebih pendek.

| Workload | Lokal pertama sebelum → sesudah | Total sebelum | Total sesudah | Selisih | % |
|---|---:|---:|---:|---:|---:|
| definitions | null → null | 14.322 | 7.708 | -6.614 | -46.2% |
| local-12 | 6.075 → 0.028 | 21.041 | 7.844 | -13.197 | -62.7% |
| local-180 | 5.857 → 0.106 | 388.920 | 62.658 | -326.262 | -83.9% |
| local-60 | 5.712 → 0.055 | 116.009 | 21.857 | -94.152 | -81.2% |
| mixed | 7.152 → 0.062 | 173.404 | 27.693 | -145.711 | -84.0% |
| terminology | null → null | 7.343 | 3.346 | -3.997 | -54.4% |

## Model warm: median tiga run dan rentang

Waktu dalam detik. Selisih absolut/persentase menggunakan waktu total; angka negatif berarti waktu lebih pendek.

| Workload | Lokal pertama sebelum → sesudah | Total sebelum | Total sesudah | Selisih | % |
|---|---:|---:|---:|---:|---:|
| definitions | null → null | 14.913 [13.663–14.933] | 5.676 [5.600–5.681] | -9.237 | -61.9% |
| local-12 | 4.320 [4.289–4.381] → 0.014 [0.014–0.016] | 19.401 [19.272–19.415] | 6.534 [6.514–6.567] | -12.868 | -66.3% |
| local-180 | 6.579 [4.343–7.515] → 0.097 [0.095–0.100] | 482.647 [476.710–484.790] | 61.939 [61.701–62.800] | -420.708 | -87.2% |
| local-60 | 7.012 [4.155–7.173] → 0.039 [0.039–0.040] | 164.272 [127.931–187.070] | 20.769 [20.502–21.184] | -143.503 | -87.4% |
| mixed | 5.529 [5.422–6.071] → 0.055 [0.052–0.060] | 177.540 [172.347–178.455] | 25.609 [25.452–25.667] | -151.931 | -85.6% |
| terminology | null → null | 4.914 [4.649–5.065] | 2.611 [2.594–2.667] | -2.303 | -46.9% |

## Cached rerun: median tiga run dan rentang

Waktu dalam detik. Selisih absolut/persentase menggunakan waktu total; angka negatif berarti waktu lebih pendek.

| Workload | Lokal pertama sebelum → sesudah | Total sebelum | Total sesudah | Selisih | % |
|---|---:|---:|---:|---:|---:|
| definitions | null → null | 0.743 [0.743–0.745] | 0.014 [0.014–0.014] | -0.729 | -98.1% |
| local-12 | 0.530 [0.526–0.556] → 0.014 [0.014–0.014] | 3.463 [3.432–3.563] | 0.046 [0.046–0.046] | -3.417 | -98.7% |
| local-180 | 0.569 [0.562–0.605] → 0.053 [0.052–0.053] | 54.241 [53.863–54.319] | 7.365 [7.334–7.557] | -46.876 | -86.4% |
| local-60 | 0.556 [0.546–0.584] → 0.024 [0.024–0.024] | 17.560 [17.428–17.911] | 0.650 [0.650–0.653] | -16.910 | -96.3% |
| mixed | 1.155 [1.139–1.165] → 0.030 [0.030–0.030] | 58.038 [57.855–58.057] | 1.529 [1.520–1.533] | -56.509 | -97.4% |
| terminology | null → null | 1.443 [1.432–1.444] | 0.013 [0.013–0.013] | -1.430 | -99.1% |

## Kontrol deterministic: satu run

Waktu dalam detik. Selisih absolut/persentase menggunakan waktu total; angka negatif berarti waktu lebih pendek.

| Workload | Lokal pertama sebelum → sesudah | Total sebelum | Total sesudah | Selisih | % |
|---|---:|---:|---:|---:|---:|
| definitions | null → null | 1.597 | 0.680 | -0.917 | -57.4% |
| local-12 | 1.293 → 0.029 | 4.303 | 3.430 | -0.873 | -20.3% |
| local-180 | 1.413 → 0.107 | 56.448 | 58.993 | 2.545 | +4.5% |
| local-60 | 1.321 → 0.049 | 18.809 | 17.528 | -1.281 | -6.8% |
| mixed | 2.056 → 0.061 | 61.575 | 21.778 | -39.797 | -64.6% |
| terminology | null → null | 2.378 | 0.851 | -1.526 | -64.2% |

## Temuan pertama yang terlihat di state editor

Median dan rentang tiga warm run, detik. Ini mencakup annotation/review selain koreksi lokal; `null` berarti tidak ada temuan.

| Workload | Sebelum | Sesudah | Selisih | % |
|---|---:|---:|---:|---:|
| definitions | 0.234 [0.210–0.236] | 0.233 [0.226–0.238] | -0.001 | -0.5% |
| local-12 | 4.320 [4.289–4.381] | 0.014 [0.014–0.016] | -4.305 | -99.7% |
| local-180 | 6.579 [4.343–7.515] | 0.097 [0.095–0.100] | -6.482 | -98.5% |
| local-60 | 7.012 [4.155–7.173] | 0.039 [0.039–0.040] | -6.973 | -99.4% |
| mixed | 3.854 [3.796–4.211] | 0.055 [0.052–0.060] | -3.799 | -98.6% |
| terminology | 0.806 [0.805–0.842] | 1.116 [1.092–1.162] | 0.310 | +38.5% |

## Panggilan dan cakupan warm run

Median tiga run. Qwen meliputi classification, kandidat, definisi, risiko, dan resolution; TataKata menghitung invocation scorer, bukan forward pass masked-token.

| Workload | Qwen sebelum → sesudah | E5 sebelum → sesudah | TataKata sebelum → sesudah | Kandidat sebelum → sesudah | Segmen skipped sebelum → sesudah |
|---|---:|---:|---:|---:|---:|
| definitions | 5.000 → 2.000 | 12.000 → 4.000 | 0.000 → 0.000 | 0.000 → 0.000 | 0.000 → 0.000 |
| local-12 | 5.000 → 1.000 | 24.000 → 0.000 | 0.000 → 0.000 | 36.000 → 36.000 | 0.000 → 0.000 |
| local-180 | 111.000 → 1.000 | 360.000 → 0.000 | 0.000 → 0.000 | 540.000 → 540.000 | 0.000 → 0.000 |
| local-60 | 34.000 → 1.000 | 120.000 → 0.000 | 0.000 → 0.000 | 180.000 → 180.000 | 0.000 → 0.000 |
| mixed | 42.000 → 1.000 | 368.000 → 2.000 | 0.000 → 0.000 | 180.000 → 240.000 | 1.000 → 1.000 |
| terminology | 1.000 → 0.000 | 9.000 → 7.000 | 0.000 → 0.000 | 0.000 → 0.000 | 0.000 → 0.000 |

| Workload warm | Cache hit sebelum → sesudah | Repair sebelum → sesudah | Fallback sebelum → sesudah |
|---|---:|---:|---:|
| definitions | 0.000 → 0.000 | 0.000 → 0.000 | 0.000 → 0.000 |
| local-12 | 0.000 → 0.000 | 0.000 → 0.000 | 0.000 → 0.000 |
| local-180 | 0.000 → 0.000 | 0.000 → 0.000 | 0.000 → 0.000 |
| local-60 | 0.000 → 0.000 | 0.000 → 0.000 | 0.000 → 0.000 |
| mixed | 0.000 → 0.000 | 0.000 → 0.000 | 0.000 → 0.000 |
| terminology | 0.000 → 0.000 | 0.000 → 0.000 | 0.000 → 0.000 |

## Status cakupan warm run sesudah

Jumlah status per tahap dijumlahkan atas tiga run. Baseline belum mempunyai enumerasi coverage ini; nilainya tidak disamakan dengan nol tahap gagal. Status skippedByPolicy tidak berarti semantik telah diperiksa.

| Workload | Tahap/status | Jumlah (3 run) |
|---|---|---:|
| definitions | candidateReview:notApplicable | 18 |
| definitions | definitionReview:completed | 6 |
| definitions | definitionReview:notApplicable | 12 |
| definitions | languageScoring:notApplicable | 18 |
| definitions | lexicalRetrieval:completed | 18 |
| definitions | localReview:completed | 18 |
| definitions | semanticRetrieval:completed | 6 |
| definitions | semanticRetrieval:skippedByPolicy | 12 |
| local-12 | candidateReview:notApplicable | 36 |
| local-12 | definitionReview:notApplicable | 36 |
| local-12 | languageScoring:notApplicable | 36 |
| local-12 | lexicalRetrieval:completed | 36 |
| local-12 | localReview:completed | 36 |
| local-12 | semanticRetrieval:skippedByPolicy | 36 |
| local-180 | candidateReview:notApplicable | 540 |
| local-180 | definitionReview:notApplicable | 540 |
| local-180 | languageScoring:notApplicable | 540 |
| local-180 | lexicalRetrieval:completed | 540 |
| local-180 | localReview:completed | 540 |
| local-180 | semanticRetrieval:skippedByPolicy | 540 |
| local-60 | candidateReview:notApplicable | 180 |
| local-60 | definitionReview:notApplicable | 180 |
| local-60 | languageScoring:notApplicable | 180 |
| local-60 | lexicalRetrieval:completed | 180 |
| local-60 | localReview:completed | 180 |
| local-60 | semanticRetrieval:skippedByPolicy | 180 |
| mixed | candidateReview:notApplicable | 375 |
| mixed | candidateReview:tooLong | 3 |
| mixed | definitionReview:completed | 3 |
| mixed | definitionReview:notApplicable | 372 |
| mixed | definitionReview:tooLong | 3 |
| mixed | languageScoring:notApplicable | 378 |
| mixed | lexicalRetrieval:completed | 375 |
| mixed | localReview:completed | 378 |
| mixed | semanticRetrieval:completed | 3 |
| mixed | semanticRetrieval:skippedByPolicy | 372 |
| terminology | candidateReview:notApplicable | 9 |
| terminology | definitionReview:completed | 6 |
| terminology | definitionReview:notApplicable | 3 |
| terminology | languageScoring:notApplicable | 9 |
| terminology | lexicalRetrieval:completed | 9 |
| terminology | localReview:completed | 9 |
| terminology | semanticRetrieval:completed | 6 |
| terminology | semanticRetrieval:skippedByPolicy | 3 |

## Durasi tahap warm run

Median detik, tiap workload. Tahap yang tidak dijalankan bernilai nol. Durasi dapat overlap.

| Workload | Tahap | Sebelum | Sesudah | Selisih |
|---|---|---:|---:|---:|
| definitions | candidateBuilding | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| definitions | contextExtraction | 0.000 [0.000–0.001] | 0.000 [0.000–0.000] | -0.000 |
| definitions | contextSegmentation | 0.001 [0.001–0.001] | 0.001 [0.001–0.001] | -0.000 |
| definitions | definitionDetection | 0.071 [0.069–0.075] | 0.056 [0.056–0.057] | -0.015 |
| definitions | definitionResolution | 0.000 [0.000–0.001] | 0.000 [0.000–0.000] | -0.000 |
| definitions | definitionRetrieval | 0.729 [0.709–0.734] | 0.331 [0.330–0.341] | -0.399 |
| definitions | definitionReview | 13.254 [12.038–13.272] | 4.302 [4.228–4.312] | -8.952 |
| definitions | documentFindingDetection | 0.001 [0.001–0.001] | 0.001 [0.001–0.002] | -0.000 |
| definitions | documentStructure | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| definitions | editorMapping | 0.001 [0.001–0.001] | 0.000 [0.000–0.001] | -0.000 |
| definitions | localReview | 0.000 | 0.001 [0.001–0.001] | 0.001 |
| definitions | protectionContext | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| definitions | resultAcknowledgement | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| definitions | spellingCandidateGeneration | 0.004 [0.004–0.005] | 0.003 [0.003–0.008] | -0.001 |
| definitions | suggestionRetrieval | 0.817 [0.816–0.826] | 0.943 [0.942–0.952] | 0.126 |
| definitions | validationConflictResolution | 14.894 [13.649–14.914] | 5.658 [5.584–5.661] | -9.236 |
| local-12 | candidateBuilding | 0.002 [0.002–0.002] | 0.002 [0.002–0.002] | -0.000 |
| local-12 | contextClassification | 3.440 [3.434–3.529] | 3.088 [3.082–3.117] | -0.352 |
| local-12 | contextExtraction | 0.001 [0.000–0.001] | 0.000 [0.000–0.000] | -0.000 |
| local-12 | contextSegmentation | 0.003 [0.003–0.003] | 0.002 [0.002–0.002] | -0.001 |
| local-12 | definitionDetection | 0.168 [0.167–0.170] | 0.127 [0.126–0.128] | -0.041 |
| local-12 | definitionRetrieval | 3.385 [3.378–3.404] | 0.000 | -3.385 |
| local-12 | definitionReview | 8.829 [8.768–8.836] | 0.000 | -8.829 |
| local-12 | documentFindingDetection | 0.002 [0.002–0.004] | 0.002 [0.002–0.002] | -0.001 |
| local-12 | documentStructure | 0.001 [0.000–0.001] | 0.000 [0.000–0.000] | -0.000 |
| local-12 | editorMapping | 0.007 [0.007–0.008] | 0.012 [0.012–0.012] | 0.005 |
| local-12 | localReview | 0.000 | 0.017 [0.017–0.018] | 0.017 |
| local-12 | protectionContext | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| local-12 | resultAcknowledgement | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| local-12 | spellingCandidateGeneration | 0.009 [0.009–0.010] | 0.009 [0.009–0.014] | -0.000 |
| local-12 | suggestionRetrieval | 3.436 [3.434–3.481] | 3.133 [3.117–3.142] | -0.302 |
| local-12 | validationConflictResolution | 15.856 [15.808–15.940] | 3.392 [3.378–3.393] | -12.464 |
| local-180 | candidateBuilding | 0.033 [0.032–0.045] | 0.028 [0.028–0.030] | -0.005 |
| local-180 | contextClassification | 5.578 [3.339–6.431] | 2.870 [2.845–3.095] | -2.708 |
| local-180 | contextExtraction | 0.004 [0.004–0.005] | 0.004 [0.004–0.004] | 0.000 |
| local-180 | contextSegmentation | 0.039 [0.034–0.044] | 0.030 [0.030–0.031] | -0.009 |
| local-180 | definitionDetection | 2.894 [2.860–3.023] | 1.876 [1.876–1.917] | -1.018 |
| local-180 | definitionRetrieval | 52.007 [51.593–54.761] | 0.000 | -52.007 |
| local-180 | definitionReview | 362.042 [352.667–364.851] | 0.000 | -362.042 |
| local-180 | documentFindingDetection | 0.036 [0.033–0.037] | 0.027 [0.027–0.028] | -0.009 |
| local-180 | documentStructure | 0.006 [0.006–0.007] | 0.006 [0.006–0.006] | -0.000 |
| local-180 | editorMapping | 2.490 [2.479–2.597] | 4.882 [4.866–4.938] | 2.392 |
| local-180 | localReview | 0.000 | 2.337 [2.277–2.358] | 2.337 |
| local-180 | protectionContext | 0.003 [0.003–0.003] | 0.002 [0.002–0.002] | -0.001 |
| local-180 | resultAcknowledgement | 0.004 [0.004–0.004] | 0.004 [0.004–0.004] | -0.000 |
| local-180 | spellingCandidateGeneration | 0.177 [0.177–0.180] | 0.164 [0.163–0.172] | -0.014 |
| local-180 | suggestionRetrieval | 56.402 [55.341–59.071] | 47.498 [47.447–48.306] | -8.903 |
| local-180 | validationConflictResolution | 474.308 [470.486–475.589] | 51.262 [51.205–52.183] | -423.046 |
| local-60 | candidateBuilding | 0.012 [0.010–0.012] | 0.010 [0.010–0.010] | -0.002 |
| local-60 | contextClassification | 6.018 [3.257–6.242] | 2.830 [2.800–2.830] | -3.187 |
| local-60 | contextExtraction | 0.002 [0.002–0.002] | 0.002 [0.002–0.002] | -0.000 |
| local-60 | contextSegmentation | 0.012 [0.011–0.017] | 0.009 [0.009–0.010] | -0.003 |
| local-60 | definitionDetection | 0.987 [0.945–1.051] | 0.638 [0.620–0.657] | -0.349 |
| local-60 | definitionRetrieval | 18.300 [17.183–19.343] | 0.000 | -18.300 |
| local-60 | definitionReview | 117.509 [88.014–138.923] | 0.000 | -117.509 |
| local-60 | documentFindingDetection | 0.013 [0.012–0.013] | 0.009 [0.009–0.009] | -0.004 |
| local-60 | documentStructure | 0.002 [0.002–0.003] | 0.002 [0.002–0.002] | -0.000 |
| local-60 | editorMapping | 0.224 [0.210–0.267] | 0.366 [0.357–0.371] | 0.142 |
| local-60 | localReview | 0.000 | 0.229 [0.228–0.234] | 0.229 |
| local-60 | protectionContext | 0.001 [0.001–0.012] | 0.001 [0.001–0.001] | -0.000 |
| local-60 | resultAcknowledgement | 0.001 [0.001–0.002] | 0.001 [0.001–0.001] | -0.000 |
| local-60 | spellingCandidateGeneration | 0.056 [0.051–0.061] | 0.048 [0.047–0.049] | -0.008 |
| local-60 | suggestionRetrieval | 20.730 [17.967–20.835] | 15.994 [15.798–16.352] | -4.737 |
| local-60 | validationConflictResolution | 157.922 [124.381–180.465] | 17.243 [17.020–17.656] | -140.679 |
| mixed | candidateBuilding | 0.014 [0.013–0.015] | 0.012 [0.012–0.012] | -0.002 |
| mixed | contextClassification | 3.790 [3.727–4.085] | 3.468 [3.458–3.510] | -0.322 |
| mixed | contextExtraction | 0.004 [0.004–0.008] | 0.004 [0.004–0.004] | -0.001 |
| mixed | contextSegmentation | 0.012 [0.012–0.013] | 0.013 [0.013–0.013] | 0.000 |
| mixed | definitionDetection | 1.160 [1.106–1.167] | 0.710 [0.707–0.711] | -0.450 |
| mixed | definitionResolution | 0.001 [0.001–0.001] | 0.001 [0.001–0.001] | -0.000 |
| mixed | definitionRetrieval | 17.905 [17.339–18.019] | 0.104 [0.103–0.110] | -17.801 |
| mixed | definitionReview | 92.396 [91.300–94.113] | 0.000 | -92.396 |
| mixed | documentFindingDetection | 0.024 [0.023–0.025] | 0.023 [0.022–0.023] | -0.002 |
| mixed | documentStructure | 0.003 [0.003–0.007] | 0.003 [0.003–0.003] | -0.000 |
| mixed | editorMapping | 0.385 [0.369–0.397] | 0.906 [0.906–0.910] | 0.522 |
| mixed | localReview | 0.000 | 0.527 [0.525–0.540] | 0.527 |
| mixed | protectionContext | 0.002 [0.002–0.002] | 0.002 [0.002–0.002] | -0.000 |
| mixed | resultAcknowledgement | 0.002 [0.002–0.003] | 0.003 [0.003–0.003] | 0.000 |
| mixed | spellingCandidateGeneration | 0.088 [0.081–0.100] | 0.079 [0.077–0.079] | -0.009 |
| mixed | suggestionRetrieval | 60.531 [58.070–61.064] | 18.890 [18.802–19.005] | -41.641 |
| mixed | validationConflictResolution | 172.874 [168.126–174.158] | 20.480 [20.365–20.580] | -152.394 |
| terminology | candidateBuilding | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| terminology | contextExtraction | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| terminology | contextSegmentation | 0.000 [0.000–0.001] | 0.001 [0.001–0.001] | 0.000 |
| terminology | definitionDetection | 0.060 [0.059–0.060] | 0.051 [0.051–0.057] | -0.008 |
| terminology | definitionResolution | 0.000 [0.000–0.001] | 0.000 [0.000–0.001] | 0.000 |
| terminology | definitionRetrieval | 0.800 [0.795–0.804] | 0.568 [0.561–0.575] | -0.232 |
| terminology | definitionReview | 2.513 [2.309–2.656] | 0.000 | -2.513 |
| terminology | documentFindingDetection | 0.001 [0.001–0.001] | 0.001 [0.001–0.001] | 0.000 |
| terminology | documentStructure | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| terminology | editorMapping | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| terminology | localReview | 0.000 | 0.001 [0.001–0.001] | 0.001 |
| terminology | protectionContext | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| terminology | resultAcknowledgement | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| terminology | spellingCandidateGeneration | 0.007 [0.005–0.027] | 0.010 [0.009–0.036] | 0.002 |
| terminology | suggestionRetrieval | 1.501 [1.452–1.514] | 1.946 [1.945–1.977] | 0.445 |
| terminology | validationConflictResolution | 4.901 [4.636–5.045] | 2.596 [2.580–2.644] | -2.304 |

Jumlah repair/fallback/cache hit, waktu tiap tahap, semua per-run, serta status coverage tersedia pada `reports/comparison.json` dan JSON setiap workload. Durasi tahap overlap sehingga tidak dijumlahkan sebagai total. Tambahan kandidat/temuan dan perbedaan diagnostik diperiksa bersama waktu; `findingsChanged` pada JSON juga mencakup assessment `notDefinition`, sehingga tidak selalu berarti perubahan suggestion editor.

## Peak RSS yang teramati

Median dan rentang warm run, dalam GiB. Peak GPU total tidak disimpulkan dari RSS.

| Workload | Sebelum | Sesudah |
|---|---:|---:|
| definitions | 3.614 [3.614–3.683] | 3.189 [3.160–3.632] |
| local-12 | 2.976 [2.976–3.698] | 3.292 [3.284–3.624] |
| local-180 | 0.193 [0.183–3.695] | 3.042 [2.478–3.617] |
| local-60 | 0.877 [0.201–3.697] | 3.565 [3.565–3.614] |
| mixed | 0.209 [0.194–0.547] | 3.173 [3.173–3.626] |
| terminology | 3.636 [3.626–3.685] | 3.599 [3.599–3.599] |

## Kualitas fixture dan integritas

Gold hanya tersedia untuk 12/60/180 segmen ejaan. Workload lain belum diannotasi; field FP di JSON workload tersebut tidak digunakan sebagai false-positive rate hukum.

| Workload warm | TP/FP/FN sebelum | TP/FP/FN sesudah | Anchor invalid sebelum → sesudah | Sumber invalid sebelum → sesudah |
|---|---:|---:|---:|---:|
| definitions | Belum diannotasi | Belum diannotasi | 0.000 → 0.000 | 0.000 → 0.000 |
| local-12 | 36/0/0 | 36/0/0 | 0.000 → 0.000 | 0.000 → 0.000 |
| local-180 | 540/0/0 | 540/0/0 | 0.000 → 0.000 | 0.000 → 0.000 |
| local-60 | 180/0/0 | 180/0/0 | 0.000 → 0.000 | 0.000 → 0.000 |
| mixed | Belum diannotasi | Belum diannotasi | 0.000 → 0.000 | 0.000 → 0.000 |
| terminology | Belum diannotasi | Belum diannotasi | 0.000 → 0.000 | 0.000 → 0.000 |

| Gold ejaan warm | Precision sebelum → sesudah | Recall sebelum → sesudah |
|---|---:|---:|
| local-12 | 1.000 → 1.000 | 1.000 → 1.000 |
| local-180 | 1.000 → 1.000 | 1.000 → 1.000 |
| local-60 | 1.000 → 1.000 | 1.000 → 1.000 |

Precision = TP/(TP+FP); recall = TP/(TP+FN), jika denominator tersedia. Integritas anchor/sumber adalah pemeriksaan teknis, bukan validasi ketepatan hukum. Negasi/modalitas/aktor, eligibility sumber, stale edit, Undo/Redo, binding penyimpanan, dan cancellation juga diperiksa dengan unit test offline.

## Incremental terhadap fresh pada teks akhir yang sama

| Workload | Kesetaraan sebelum (3 pasangan) | Kesetaraan sesudah (3 pasangan) | Waktu incremental sebelum → sesudah |
|---|---|---|---:|
| definitions | [True, True, True] | [True, True, True] | 7.766 [7.717–7.794] → 1.331 [1.325–1.352] |
| local-12 | [True, True, True] | [True, True, True] | 36.107 [27.192–38.112] → 6.529 [6.453–6.573] |

Kesetaraan menggunakan kategori, span, original/replacement, sumber, assessment, dan finding tanpa UUID/timestamp. Prime serta fresh pembanding tidak masuk median waktu incremental.

## Validasi dan batas hasil

Build aplikasi final, build-for-testing, dan 284 unit test offline lulus; 8 test opt-in dilewati, tanpa kegagalan. `git diff --check` juga lulus. Test offline memakai `offline-after-final.xcresult`; build log `build-after-final.log` dan `build-for-benchmark-final.log`. Semua berada di direktori artefak eksternal. Perbaikan incremental dan key cache ditemukan melalui pemeriksaan/test selama implementasi; capture dan log percobaan awal dipertahankan, sedangkan laporan ini hanya menggunakan benchmark final.

Command validasi dijalankan dari root repository, dengan package clone yang sudah tersedia, tanpa mengubah dependency:

```sh
xcodebuild -project AMT.xcodeproj -scheme AMT \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/amt-flow-fix-task/derived-after \
  -clonedSourcePackagesDirPath /tmp/amt-backend-study-tests.qIx3rg/SourcePackages \
  -disableAutomaticPackageResolution build CODE_SIGNING_ALLOWED=NO

xcodebuild -project AMT.xcodeproj -scheme AMT \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/amt-flow-fix-task/derived-after \
  -clonedSourcePackagesDirPath /tmp/amt-backend-study-tests.qIx3rg/SourcePackages \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  -resultBundlePath /private/tmp/amt-flow-fix-task/offline-after-final.xcresult \
  test CODE_SIGNING_ALLOWED=NO

git diff --check
```

Matriks opt-in dijalankan melalui `run_benchmarks.py before|after prepare,cold,warm,cached,control,incremental`, lalu `run_supplemental.py before|after`, di direktori artefak. Instruksi portabel tanpa script eksternal tersedia di dokumen metode. Bundle XCTest disiapkan dengan `build-for-testing` sebelum `test-without-building`; build aplikasi biasa dapat menghapus bundle test dari app.

Tidak ada commit/push. Fixture belum ditinjau sebagai gold hukum; keberhasilan eksperimen tidak menjadi quality gate hukum. Variasi warm run, urutan pengukuran tetap, cache OS dan sampled RSS membatasi generalisasi hasil. Uji edit/Undo/Redo/save-reload dilakukan melalui AppKit dan storage integration test; interaksi popover manual dalam sesi pengguna belum diuji. Counter TataKata matriks utama nol karena kandidat fixture utama berasal dari aturan lokal; eksekusi scorer asli diperiksa terpisah pada benchmark golden. Ini tidak membuktikan throughput dokumen dengan banyak typo di luar rule pack. Satu segmen campuran terlalu panjang tetap tidak dianalisis oleh model dan mencegah snapshot dianggap lengkap.


## Benchmark tambahan

Processor before: cancellation=True; baseline expected-signal 8/8, durasi 0.013 detik; qwenOnly expected-signal 8/8, durasi 7.716 detik; hybrid expected-signal 8/8, durasi 6.314 detik; cachedQwenOnly expected-signal 8/8, durasi 0.016 detik.

Processor after: cancellation=True; baseline expected-signal 8/8, durasi 0.013 detik; qwenOnly expected-signal 8/8, durasi 7.839 detik; hybrid expected-signal 8/8, durasi 6.509 detik; cachedQwenOnly expected-signal 8/8, durasi 0.003 detik.

| Processor tambahan | Durasi sebelum | Durasi sesudah | Selisih | % |
|---|---:|---:|---:|---:|
| baseline | 0.013 | 0.013 | +0.000 | +0.9% |
| qwenOnly | 7.716 | 7.839 | +0.123 | +1.6% |
| hybrid | 6.314 | 6.509 | +0.195 | +3.1% |
| cachedQwenOnly | 0.016 | 0.003 | -0.014 | -82.9% |

Benchmark tambahan hanya satu eksekusi per konfigurasi; kenaikan durasi di tabel tetap dilaporkan, tetapi tidak cukup untuk memisahkan biaya scheduler/routing dari variasi generation dan cache sistem. Matriks utama memakai tiga warm run.

Golden TataKata pada kedua versi lulus; keputusan/replacement empat pasangan sama=True. `datta → data` ditolak oleh threshold skor; `penggua → pengguna`, `memasukan → memasukkan`, dan `metadatta → metadata` diterima. Hasil raw skor tersimpan pada `supplemental-tatakata.json`; ini empat kasus scorer, bukan estimasi akurasi seluruh ejaan. Benchmark processor memeriksa profil generation, structured output, cache, serta cancellation; expected-signal berasal dari fixture eksperimen dan bukan gold hukum.

Peak RSS warm meningkat pada local-12 (+10.6%), local-180 (+1474.1%), local-60 (+306.4%), mixed (+1421.4%). Rentang RSS dilaporkan di atas; resource warm disiapkan pada kedua versi. RSS sampel tidak cukup untuk menyimpulkan total penggunaan GPU atau penyebab kenaikan. Validasi tidak dilonggarkan untuk mengejar hasil memori.
