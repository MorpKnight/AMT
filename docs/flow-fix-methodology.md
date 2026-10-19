# Metode benchmark flow dokumen

Benchmark ini membandingkan commit `94aa70034c61ca2a44bd02158dff6112baed3d8e` dengan perubahan pada `gi/flow-fix`. Seluruh fixture sintetis; tidak ada dokumen pribadi yang digunakan. Hasil eksperimen belum merupakan quality gate hukum.

## Konfigurasi yang dibekukan

- MacBook Pro M5, 10 core CPU, RAM 24 GiB; macOS arm64; Xcode 27.0.
- Corpus produksi `lawtionary-dictionary-official` dengan revision `d6260263333814513e6c97366a3d316bd9ed717286880169e8e3383085a3deec`.
- Qwen `mlx-community/Qwen3.5-4B-MLX-4bit`, revision `32f3e8ecf65426fc3306969496342d504bfa13f3`.
- TataKata `citylighxts/TataKata`, revision `4b90902f013ea22096f47f99f3a7c8aac508e3c7`; window 64 wordpieces, minimum delta 0,25 nats.
- E5 `intfloat/multilingual-e5-small`, revision `614241f622f53c4eeff9890bdc4f31cfecc418b3`.
- Mode utama hybrid, Qwen 4B, greedy, thinking mati, seed 42. Candidate/definition profile memakai batas output 128 token; classification memakai konfigurasi produksi 384 token. Konfigurasi tahap lain mengikuti kode produksi yang dibekukan.
- Harness `AIConnectorFlowBenchmarkTests` yang sama digunakan sebelum dan sesudah. Fixture dan SHA-256 harness dicatat di setiap JSON; checksum bobot disimpan pada manifest resource.

## Cakupan pengukuran

Harness menjalankan `AIConnectorViewModel`, sehingga struktur, profil, review dokumen, queue, definition analysis, dan mapping editor ikut terukur. Enam workload adalah 12/60/180 segmen ejaan lokal, terminologi/parafrasa, definisi/rujukan internal dengan negasi/modalitas, serta campuran list/tabel dan segmen terlalu panjang. Workload campuran juga memuat lebih dari tiga kandidat pada satu segmen.

| Kondisi | Pelaksanaan |
|---|---|
| Resource cold | Satu run setiap workload dalam proses baru. Resource tersedia di disk, belum dimuat oleh VM; cache analisis kosong. Cache filesystem dan shader sistem tidak dipurge. |
| Model warm | Persiapan resource di luar timer, kemudian tiga run dalam proses yang sama. Semua cache hasil dan skor dibersihkan sebelum setiap run. |
| Cached rerun | Satu prime run di luar laporan, lalu tiga rerun identik dengan model/cache dipertahankan. |
| Kontrol deterministic | Satu run setiap workload dalam proses baru, menggunakan routing deterministic dari masing-masing versi. |
| Incremental | Tiga pasangan incremental/fresh pada teks akhir yang sama, untuk workload lokal 12 dan definisi. |

Waktu temuan pertama adalah waktu hasil dipublikasikan ke state editor, dipoll setiap 10 ms; ini tidak mengukur frame AppKit yang sudah tergambar. Koreksi lokal pertama hanya menghitung suggestion ejaan/grammar yang actionable. Tanpa temuan, nil tetap nil. Timer total berhenti saat analisis selesai; harness menunggu task VM selesai sebelum mengambil laporan tahap, agar counter tidak hilang akibat race penyelesaian.

Memory adalah maksimum sampled `mach_task_basic_info.resident_size`, dipoll dengan sampler yang sama, ditambah sampel awal/akhir. Ini merupakan peak RSS yang teramati, bukan pengukuran terpisah seluruh alokasi GPU atau peak sesaat di antara sampel. Durasi tahap dapat bertumpang tindih dan tidak dijumlahkan sebagai waktu total.

Warm run baseline menunjukkan variasi waktu serta RSS. Pemeriksaan OS sesaat mencatat halaman bebas rendah, tetapi `memory_pressure -Q` masih melaporkan 50% memory free (termasuk ruang yang dapat direklamasi). Ini tidak cukup untuk mendiagnosis tekanan memori sebagai penyebab variasi; rentang tiga run tetap dilaporkan dan penggunaan memori GPU tidak disimpulkan dari RSS saja. Urutan sebelum lalu sesudah mengikuti rencana dan tidak diacak; kondisi termal, proses lain, serta cache OS dapat memengaruhi perbandingan. Tiga pengulangan adalah ukuran eksperimen ini, bukan confidence interval statistik.

Counter Qwen menjumlahkan review kandidat, definisi, risiko, resolution, serta classification yang benar-benar dijalankan pada run tersebut. Counter E5 merupakan jumlah query inference yang diminta oleh pipeline. Counter TataKata merupakan invocation scorer pada tahap scoring, bukan jumlah forward pass masked-token. Resource preparation dan download dilaporkan terpisah.

## Interpretasi kualitas dan cakupan

Gold ejaan hanya tersedia pada workload lokal 12/60/180: tiga koreksi per segmen. Precision/recall di workload lain tidak digunakan, karena expected finding-nya belum diannotasi. Nilai FP yang tersimpan oleh harness pada workload tanpa gold adalah jumlah temuan di luar daftar expected kosong, sehingga tidak boleh dipresentasikan sebagai false-positive rate hukum.

Negasi, modalitas, aktor, kondisi/pengecualian, sumber yang tidak layak, stale edit, Undo/Redo, dan invalidation diuji melalui regresi offline. Workload definisi menjadi pemeriksaan hard-negative deskriptif, bukan corpus hukum yang telah ditinjau. Validitas anchor/sumber menguji integritas teknis; tidak membuktikan ketepatan hukum.

Flow baru membedakan `completed`, `notApplicable`, `skippedByPolicy`, `failed`, `tooLong`, dan `cancelled`. Semantic retrieval yang dilewati kebijakan bukan pemeriksaan semantik yang selesai. Tambahan kandidat/hasil atau perubahan routing ditandai pada perbandingan supaya waktu untuk cakupan berbeda tidak disamakan dengan regresi pekerjaan identik. Snapshot lengkap ditahan bila tahap yang diwajibkan gagal atau ada segmen terlalu panjang.

Kesetaraan incremental membandingkan hasil yang dinormalisasi menurut kategori, span, teks, replacement, sumber, dan finding; UUID/timestamp tidak dibandingkan. Prime run dan fresh pembanding tidak masuk median incremental.

## Artefak dan reproduksi

JSON per-run, manifest resource, log, dan `.xcresult` berada di `/private/tmp/amt-flow-fix-task/`, di luar repository. Capture instrumentasi awal yang tidak lengkap dipertahankan terpisah dan dikeluarkan dari perbandingan. Pengukuran sesudah sebelum perbaikan key cache final juga diarsipkan terpisah sebagai `reports/after-cache-key-v1/`; seluruh matriks sesudah diulang pada source final. Tidak ada commit/push atau perubahan kontrak dokumen, signing, entitlement, UTI, maupun deployment target.

Build sekali sebelum benchmark opt-in:

```sh
benchmark_dir="$(mktemp -d /private/tmp/amt-flow-reproduce.XXXXXX)"
xcodebuild \
  -project AMT.xcodeproj -scheme AMT -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$benchmark_dir/DerivedData" \
  build-for-testing CODE_SIGNING_ALLOWED=NO
```

Jalankan `prepare` terlebih dahulu untuk memastikan download selesai. Kemudian jalankan setiap kombinasi fixture dan kondisi secara serial, dengan invocation xcodebuild baru untuk setiap kombinasi. Nilai fixture: `local-12`, `local-60`, `local-180`, `terminology`, `definitions`, `mixed`; nilai kondisi: `cold`, `warm`, `cached`, `control`. Kondisi `incremental` hanya untuk `local-12` dan `definitions`.

```sh
fixture="local-12"
phase="prepare"
runner_sha="$(shasum -a 256 AMTTests/AIConnectorFlowBenchmarkTests.swift | cut -d ' ' -f 1)"
TEST_RUNNER_AMT_RUN_FLOW_BENCHMARK=1 \
TEST_RUNNER_AMT_FLOW_FIXTURE="$fixture" \
TEST_RUNNER_AMT_FLOW_PHASE="$phase" \
TEST_RUNNER_AMT_FLOW_OUTPUT="$benchmark_dir/reports" \
TEST_RUNNER_AMT_FLOW_RUNNER_SHA="$runner_sha" \
TEST_RUNNER_AMT_FLOW_BUILD="$(git rev-parse HEAD)" \
xcodebuild \
  -project AMT.xcodeproj -scheme AMT -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$benchmark_dir/DerivedData" \
  -parallel-testing-enabled NO \
  -only-testing:AMTTests/AIConnectorFlowBenchmarkTests/testFrozenProductionFlow \
  -resultBundlePath "$benchmark_dir/$fixture-$phase.xcresult" \
  test-without-building CODE_SIGNING_ALLOWED=NO
```

Gunakan resource cache yang sama untuk kedua versi; jika memakai cache yang disiapkan eksperimen ini, tambahkan `TEST_RUNNER_HF_HUB_CACHE=/private/tmp/amt-flow-fix-task/hf-hub`. Menjalankan test reguler tidak mengaktifkan benchmark atau download model.

Baseline dibentuk melalui `git archive 94aa700` ke direktori terpisah, dengan overlay khusus pengukuran: harness opt-in, hook Debug untuk resource/cache/menunggu completion/validitas sumber, counter cached classification yang benar, metadata sumber pada fixture benchmark processor, serta kompatibilitas `StubLanguageScorer` di test. Algoritma produksi baseline tetap asli. Overlay yang identik dan instruksi pembentukannya disimpan pada direktori artefak agar baseline dapat direproduksi.

Untuk membentuk baseline dari repository ini:

```sh
baseline_dir="$(mktemp -d /private/tmp/amt-flow-baseline.XXXXXX)"
git archive 94aa70034c61ca2a44bd02158dff6112baed3d8e | tar -x -C "$baseline_dir"
(cd "$baseline_dir" && git apply /Users/giovan/Programming/apple/AMT/docs/benchmarks/baseline-measurement-overlay.patch)
```

Kemudian jalankan build-for-testing dan matriks yang sama dari `baseline_dir`, menggunakan DerivedData terpisah. Patch tersebut membekukan harness serta perubahan khusus pengukuran baseline; ia tidak memuat perubahan flow produksi. `git apply --check` telah dijalankan pada salinan commit asli.

## Benchmark tambahan

Pemeriksaan processor P0.11 dan golden fixture TataKata dijalankan serial setelah matriks utama, dengan DerivedData yang sama untuk versi terkait. Keduanya opt-in. Processor memakai fixture sintetis kecil miliknya sendiri; angka waktunya tidak digabungkan ke tabel pipeline dokumen. TataKata memeriksa skor/keputusan empat pasangan typo, bukan precision/recall seluruh dokumen.

```sh
TEST_RUNNER_AMT_RUN_P011_MODEL_BENCHMARK=1 \
TEST_RUNNER_AMT_P011_MODEL_VARIANT=qwen35-base-4b \
TEST_RUNNER_AMT_P011_REPORT_PATH="$benchmark_dir/supplemental-processor.json" \
xcodebuild -project AMT.xcodeproj -scheme AMT \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$benchmark_dir/DerivedData" \
  -parallel-testing-enabled NO \
  -only-testing:AMTTests/AIConnectorModelBenchmarkTests/testP011CandidateFirstSelectedModelBenchmark \
  test-without-building CODE_SIGNING_ALLOWED=NO

TEST_RUNNER_AMT_RUN_TATAKATA_BENCHMARK=1 \
TEST_RUNNER_AMT_TATAKATA_GOLDEN_REPORT_PATH="$benchmark_dir/supplemental-tatakata.json" \
xcodebuild -project AMT.xcodeproj -scheme AMT \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$benchmark_dir/DerivedData" \
  -parallel-testing-enabled NO \
  -only-testing:AMTTests/AIConnectorTataKataBenchmarkTests/testOptInTataKataGoldenFixtures \
  test-without-building CODE_SIGNING_ALLOWED=NO
```
