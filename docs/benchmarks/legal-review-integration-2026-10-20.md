# Integrasi selective review dan fastlane ke backend aplikasi

Status pengukuran: complete.

Backend baru sekarang dijalankan langsung oleh AIConnectorViewModel. UI, dependency, signing, entitlement dan format dokumen tidak berubah. Tidak ada commit/push. Baseline adalah working-tree snapshot sebelum eksperimen, bukan HEAD yang mengabaikan pekerjaan drafting awal.

## Perubahan

- Pemeriksaan pengulangan kata terbatas dan parameter terbuka dipublikasikan sebelum inference. Model hanya menilai pasangan klausul; tidak menyusun replacement bebas.
- Indeks term/fakta membawa konflik definisi Hari/Penerima meskipun tokennya kata umum/aktor; guard kutipan dan code diterapkan saat discovery serta sebelum edit.
- Routing hybrid konservatif mempertahankan model bila ada definisi, kutipan/code, sumber hukum, risiko, kandidat spelling atau seed lexical. Mode pilihan pengguna tidak diubah; keputusan jalur internal dicatat.
- Proposal tambahan memakai tipe editor yang ada. Revision/corpus/opsi/anchor/eligibility dicek sebelum edit; provenance lokal snapshot dibangun kembali. Mutation tetap melalui coordinator editor dan persetujuan pengguna.
- Model memakai scheduler yang sama. Pembatalan milik satu run, cache berbatas per ViewModel, fullFresh melewati hasil cache, dan perpindahan jalur lokal/hybrid memaksa invalidasi native.
- Segmen tetap dihitung sekali. Hasil tambahan partial/uncertain/budget/cancelled mencegah snapshot lengkap. Policy skip dicatat; completePairs tidak berarti seluruh semantik dokumen telah diperiksa.

## Pengukuran pada fixture yang sama

96 input review: 48 retrospektif dan 48 sintetis baru. Keduanya sudah pernah diperiksa dalam eksperimen, sehingga sekarang bukan blind holdout baru. Tiga warm/tiga cached per input; priming terpisah, inference serial, model Qwen3.5-4B MLX/revision/corpus/TataKata/E5/generation dipertahankan.

| Cohort/kondisi | Backend | Request | Target terjangkar, iteration 1 | Koreksi tepat/actionable | Actionable tak sesuai | Median per-input, s |
|---|---|---:|---:|---:|---:|---:|
| retrospective/warm | baseline | 144 | 9/22 | 2/7 | 0 | 2.6898 |
| retrospective/warm | integrated | 144 | 22/22 | 6/7 | 0 | 2.7205 |
| prospective/warm | baseline | 144 | 0/24 | 0/9 | 0 | 2.5562 |
| prospective/warm | integrated | 144 | 24/24 | 9/9 | 0 | 2.5300 |
| retrospective/cached | baseline | 144 | 9/22 | 2/7 | 0 | 0.0123 |
| retrospective/cached | integrated | 144 | 22/22 | 6/7 | 0 | 0.0120 |
| prospective/cached | baseline | 144 | 0/24 | 0/9 | 0 | 0.0122 |
| prospective/cached | integrated | 144 | 24/24 | 9/9 | 0 | 0.0119 |

Median adalah median tiga request per input, lalu median distribusi input. Rentang, p95, total dan per-iteration tersedia dalam JSON eksternal. Waktu baseline berasal dari campaign sebelumnya pada host/resource sama; pengukuran tidak diinterleave dan kondisi host bisa memengaruhi selisih.

Rubrik span/operasi tidak membuktikan ketepatan alasan hukum. Needs-review tidak menjadi koreksi actionable. Audit alasan/evidence terpisah serta kontrol native harus dibaca. Label manusia tetap pending; gate insufficientEvidence.

## Kontinuitas ejaan historis

| Backend | Input | Ejaan terdeteksi | Koreksi ejaan actionable | Local actionable TP/FP pada subset gold |
|---|---:|---:|---:|---:|
| baseline | 181 | 39/43 | 32/43 | 49/0 |
| integrated | 181 | 39/43 | 32/43 | 49/0 |

## Batas dan validasi

- Dokumen di atas 64 unit mempertahankan pemeriksaan dasar dan hasil lokal; inference kontekstual opsional dilewati dengan partial coverage. Parafrasa tanpa signal lexical tetap blind spot.
- Datta belum diperbaiki oleh tahap integrasi ini. Warning native Lampiran/defined-term pada kutipan dan kalimat nominal masih perlu pekerjaan terpisah; tidak disembunyikan dari hasil.
- Tidak ada klaim lebih hemat memori. Peak RSS dan alokasi MLX dilaporkan terpisah, tanpa dijumlahkan.
- FullFresh menggunakan model resident bila sudah tersedia, tetapi tidak memakai hasil analisis. Cached rerun memakai incremental tanpa perubahan, tanpa override debug untuk menerima cache pada fullFresh.
- Test offline mencakup local-first, deduplikasi, progress, cancellation dua dokumen, perpindahan mode routing, cache, snapshot, stale/forged edit, Unicode/protection dan Accept/Undo/Redo/save. Model benchmark tetap opt-in.
- Latensi temuan pertama mengamati array publik ViewModel dengan polling 10 ms. Sekarang proposal tambahan memang terhubung ke editor; keterlambatan rendering visual belum diukur.

## Reproduksi

Gunakan LegalReviewBackendBenchmarkTests dengan TEST_RUNNER_AMT_RUN_INTEGRATED_REVIEW=1 serta AMT_INTEGRATED_REVIEW_FIXTURES/OUTPUT/PHASE/REPEATS (semua env ke XCTest memakai prefix TEST_RUNNER_). Fixture/output wajib /private/tmp/. Scope warm fullFresh; cached mempunyai priming fresh terpisah lalu incremental rerun. Untuk pasangan aktual pakai TEST_RUNNER_AMT_RUN_INTEGRATED_INCREMENTAL=1.

Build/test: xcodebuild -project AMT.xcodeproj -scheme AMT -configuration Debug -destination "platform=macOS,arch=arm64" -derivedDataPath /private/tmp/AMT-Review-Validation CODE_SIGNING_ALLOWED=NO test. Opt-in tidak dijalankan oleh test reguler. Release divalidasi terpisah.

Raw JSON, source/resource/fixture manifest, log, xcresult dan script campaign berada di `/private/tmp/amt-review-integration-20261020`. Source manifest harus sama sebelum dan sesudah run; jangan melanjutkan record beku setelah mengubah source.

## Total, resource, dan integritas hasil

Total 288 request warm turun dari 829.930 ke 629.221 detik (24.2%). Ini total pekerjaan pada matriks, bukan peningkatan seragam per dokumen.

| Backend | Peak RSS MiB | Peak MLX active MiB | Context attempts tambahan, warm |
|---|---:|---:|---:|
| baseline | 926.89 | 4221.74 | 0 |
| integrated | 1326.31 | 4241.10 | 99 |

Memori RSS lebih tinggi. Alokasi MLX dicatat terpisah dan tidak dijumlahkan; counter tambahan tidak mencakup semua generation native. Tidak ada klaim penghematan resource umum.

Metadata native: {'exact': 288} pada 96 input × tiga layer. Runtime UUID/timestamp diabaikan, urutan/field/evidence/source reference tetap diperiksa. Temuan baru dipisah sebelum membandingkan.

Incremental/fresh aktual: 9/9 pasangan setara; meliputi lokal, definisi/heading dan teks panjang, masing-masing tiga ulang. Status partial juga dibandingkan.

offline-5: 423 passed, 18 skipped opt-in, 0 gagal.

offline-6: 424 passed, 18 skipped opt-in, 0 gagal.

Dokumen manual sintetis dicoba end-to-end sekali: 27.700 detik, contextual status completePairs. Dua koreksi duplikasi, dua parameter terbuka, satu perbedaan tenggat dan satu konflik definisi muncul; nama/kutipan tidak dikoreksi. Ini smoke, bukan holdout baru.

## Perbaikan lifecycle setelah primary

Sesudah matriks beku, peninjauan menemukan dismissal proposal tambahan dapat hilang pada incremental rerun tanpa perubahan. Perbaikan hanya mempertahankan ID yang diabaikan pada revision, struktur dan konfigurasi yang persis sama; fullFresh/perubahan tetap menginvalidasi. Benchmark primary tidak memuat dismissed/reviewed ID, sehingga cabang baru ini tidak aktif pada input pengukuran. Source yang diukur tetap disimpan; manifest final dan amendment terpisah.

Angka waktu utama berasal dari build sebelum perbaikan lifecycle itu. Source akhir mendapat build Debug/Release, seluruh test offline, dan matched model smoke 12 input × warm/cached; hasilnya dibandingkan dengan primary. Tidak menyebut smoke tersebut sebagai pengulangan seluruh matriks latency.

Matched smoke source akhir: 24/24 keluaran/coverage setara dengan primary.
