# Eksperimen akurasi backend v2

Baseline commit: `b2759f53af56105805fe64fd5009bc3d3128eff5`.
Branch: `gi/flow-fix`. Implementasi sesudahnya diukur sebagai working tree
sebelum commit; hasil dan dokumentasi kemudian dipublikasikan bersama branch.
Laporan hasil ada di
[backend-accuracy-v2-comparison.md](../../backend-accuracy-v2-comparison.md).

## Data dan batas label

- `frozen-fixtures.json`: 181 input; 113 input lama dipertahankan byte-for-byte,
  48 baru (24 regression/24 holdout), 18 kontrol definisi, dua dummy.
- `frozen-expectations.json`: expectation eksperimen v2 per occurrence, terpisah
  dari expectation produksi. Memisahkan ejaan wajib, gaya opsional, rujukan,
  review marker hukum, dan semantik. Label lama retrospektif berasal dari
  review manual assistant; label baru dibuat sebelum implementasi. Perbaikan
  sidecar saat baseline berjalan tidak mengubah input atau keputusan pipeline.
- `frozen-sources.json`: source ID, body, term, dan eligibility kontrol.
- `frozen-manifest.json`: checksum data, resource corpus, overlay, serta
  konfigurasi baseline. Resource/model revision dibekukan melalui source
  konfigurasi dan laporan runtime; seed 42, greedy, thinking mati, Qwen 4B.
- Semua label pending, `humanApproval=false`. Semantik tanpa gold lengkap tidak
  menjadi negative. Holdout tidak dipakai untuk menyetel threshold. Evaluasi
  assistant tidak menggantikan review hukum; gate tetap `insufficientEvidence`.

## Reproduksi

Semua inference berjalan serial. Butuh macOS arm64, resource Qwen/E5/TataKata
tersedia, Xcode serta dependency project yang sama. Download/persiapan resource
berada di luar durasi analisis. Gunakan direktori eksternal baru untuk run baru;
runner melewati record yang sudah tersimpan hanya untuk melanjutkan run yang sama.

Dari root checkout implementasi:

```sh
export AMT_REPOSITORY="$PWD"
export AMT_EXPERIMENT_DIR="$(mktemp -d /private/tmp/amt-accuracy-v2.XXXXXX)"
export AMT_SOURCE_PACKAGES=/private/tmp/amt-accuracy-v2-packages
export HF_HUB_CACHE=/private/tmp/amt-flow-fix-task/hf-hub

cp docs/benchmarks/accuracy-v2/frozen-*.json "$AMT_EXPERIMENT_DIR/"
cp docs/benchmarks/accuracy-v2/run_matrix.py "$AMT_EXPERIMENT_DIR/"
cp docs/benchmarks/accuracy-v2/evaluate_accuracy.py "$AMT_EXPERIMENT_DIR/"
cp docs/benchmarks/accuracy-v2/compare_experiment.py "$AMT_EXPERIMENT_DIR/"
cp AMTTests/AIConnectorAccuracyMatrixTests.swift "$AMT_EXPERIMENT_DIR/"
mkdir "$AMT_EXPERIMENT_DIR/baseline"
git archive b2759f53af56105805fe64fd5009bc3d3128eff5 |
  tar -x -C "$AMT_EXPERIMENT_DIR/baseline"
git -C "$AMT_EXPERIMENT_DIR/baseline" apply \
  "$AMT_REPOSITORY/docs/benchmarks/accuracy-v2/baseline-measurement-overlay.patch"

xcodebuild -project "$AMT_EXPERIMENT_DIR/baseline/AMT.xcodeproj" \
  -scheme AMT -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$AMT_EXPERIMENT_DIR/derived-baseline" \
  -clonedSourcePackagesDirPath "$AMT_SOURCE_PACKAGES" \
  -parallel-testing-enabled NO build-for-testing CODE_SIGNING_ALLOWED=NO
python3 "$AMT_EXPERIMENT_DIR/run_matrix.py" before

xcodebuild -project AMT.xcodeproj -scheme AMT -configuration Debug   -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$AMT_EXPERIMENT_DIR/derived-after" \
  -clonedSourcePackagesDirPath "$AMT_SOURCE_PACKAGES" \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  build-for-testing CODE_SIGNING_ALLOWED=NO
python3 "$AMT_EXPERIMENT_DIR/run_matrix.py" after
python3 "$AMT_EXPERIMENT_DIR/evaluate_accuracy.py" \
  "$AMT_EXPERIMENT_DIR" before after
python3 "$AMT_EXPERIMENT_DIR/compare_experiment.py" "$AMT_EXPERIMENT_DIR"
```

Overlay baseline hanya menambahkan accessor Debug untuk findings, harness matrix,
jalur cached incremental yang benar, dan priming fixed-candidate TataKata.
Tidak mengganti keputusan produksi. Harness yang sama dipakai sesudahnya.

Setiap versi berisi 3.258 record matrix: 181 input × tiga mode × tiga warm dan
tiga cached. Warm memakai `fullFresh`, cache analisis/scoring dibersihkan.
Cached memakai priming terpisah, lalu incremental tanpa perubahan dengan cache
dipertahankan. Hook yang membolehkan cache pada fullFresh dimatikan.
Analisis tidak lengkap tetap tidak lengkap dan dapat memproses ulang segmennya.
Model-only tetap mode produk candidate-first, bukan penemuan typo generatif.

Runner juga menjalankan sepuluh workload pipeline × warm/cached (masing-masing
tiga run), tiga workload incremental/fresh (masing-masing tiga pasangan), serta
fixed-candidate TataKata warm/cached. RSS dan MLX disampel 10 ms pada kedua
versi. Memori adalah peak proses/runtime terukur, bukan ukuran cache payload.
Nilai first-visible/actionable yang tidak ada ditulis null/field tidak hadir;
evaluator memperlakukannya sebagai null.

`evaluate_accuracy.py` melaporkan recall occurrence dan precision hanya ketika
gold lokal lengkap. Finding semantik yang belum diberi label tidak dihitung
false positive. `needsReview` tidak actionable. Latensi global lintas fixture
hanya deskriptif; perbandingan performa utama memakai workload yang sama.
Normalisasi incremental/fresh harness membandingkan isi/posisi/status/sumber
tanpa UUID atau timestamp; tidak mengklaim menguji seluruh field model.

Counter repair kandidat pada report lama bersifat per segmen yang melakukan
repair, bukan jumlah seluruh attempt. Evaluator menamainya
`candidateRepairSegments`; repair definisi baru dicatat terpisah sebagai jumlah
retry format. Keduanya tidak dijumlahkan menjadi satu klaim jumlah call repair.

Sebagian nama metrik stage diwarisi dari harness sebelumnya. Stage dapat
bersifat inklusif atau saling overlap; jumlah seluruh durasi stage bukan
dekomposisi aditif durasi total. RSS juga dipengaruhi proses/runtime resident,
bukan hanya workload aktif. Tiga run memberikan median/rentang observasi,
bukan interval kepercayaan atau bukti signifikansi statistik.

## Validasi offline

Gunakan DerivedData eksternal; test reguler tidak mengaktifkan benchmark model.
Build Debug dilakukan oleh perintah test. Build Release terpisah:

```sh
xcodebuild -project AMT.xcodeproj -scheme AMT -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/amt-accuracy-validation-debug \
  -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO
xcodebuild -project AMT.xcodeproj -scheme AMT -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/amt-accuracy-validation-release \
  build CODE_SIGNING_ALLOWED=NO
git diff --check
```

Artefak validasi eksperimen final memakai dependency yang sudah tersedia dengan
`-clonedSourcePackagesDirPath /tmp/amt-backend-study-tests.qIx3rg/SourcePackages`
dan `-disableAutomaticPackageResolution`. Nama direktori ini spesifik mesin;
ganti dengan cache dependency yang sesuai pada mesin reproduksi.
