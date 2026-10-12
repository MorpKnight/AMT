# Mapping incremental: implementasi dan benchmark

Progress definisi/retrieval disimpan terlebih dahulu pada commit `ade8ce5ba1daa869a3888eaa5b30120e7515c843` (`Improve definition decision aggregation and lexical retrieval`), branch `gi/flow-fix`. Implementasi mapping berikutnya belum di-commit atau di-push. Tidak ada perubahan View/UI, format dokumen, dependency, signing, entitlement, atau deployment target.

## Perubahan backend

- ViewModel memiliki state mapping turunan per segmen dan indeks occurrence; MainActor tetap menjadi boundary publikasi. UUID dipertahankan dengan kunci segmen/anchor/status/kategori/original/replacement, sementara reason dan metadata terbaru diterapkan.
- Event lokal/final mengganti mapping segmen terkait. Document findings dipetakan terpisah hanya saat berubah; review/definition annotations tetap diikuti grup finding annotations, bukan satu pengurutan global baru.
- Teks dan representasi NSString/UTF-16 disiapkan per revisi. Public signature mapper tetap tersedia; overload internal menerima konteks yang sudah disiapkan.
- Rentang segmen yang overlap, bounds noncanonical, atau metadata hasil yang tidak konsisten menggunakan rebuild penuh. Rematerialisasi hasil melakukan rebuild; reset dan accepted edit menginvalidasi state turunan. Pemulihan snapshot mempertahankan array tersimpan sampai raw hasil tersedia.
- Filtering, batas mapper yang sekarang, eligibility, conflict policy, anchor, output tekstual, run summary, penghitung progress, dan acknowledge queue tetap mengikuti perilaku sebelumnya. Array publik tetap dimaterialisasi/disort; biaya publikasi dan output masih tumbuh bersama jumlah hasil. Tidak diklaim seluruh penerapan event menjadi O(1).

## Metode dan identitas

Baseline produksi dibentuk melalui git archive dari commit di atas. Overlay pengukuran Debug yang identik diterapkan pada baseline dan versi sesudah; tidak mengganti keputusan pipeline. Baseline lengkap selesai dan disimpan sebelum perubahan mapping produksi diterapkan.

Setiap versi: enam workload × tiga warm run, enam kontrol deterministic, enam pasangan incremental/fresh (local-12 dan definitions × tiga), dan sembilan replay mapping offline (180/360/720 × tiga). Total: 60 record pipeline, 12 pasangan incremental/fresh, dan 18 replay mapping offline. Inference dijalankan serial.

Model Qwen 4B, corpus produksi, E5, TataKata, revisions, greedy/thinking off/seed 42, cache reset per warm run, dan sampler RSS mengikuti [metode sebelumnya](flow-fix-methodology.md). Tidak ada download resource baru; resource preparation dilaporkan terpisah dalam JSON. Resource-cold/cached-rerun matrix tidak diulang.

Harness pipeline asli tidak berubah. `editorMapping` tetap mengukur mapping event final. Field Debug `mappingMetrics` menambah durasi mapping lokal/final, durasi penerapan event, jumlah rebuild, jumlah segmen yang diproses mapping, dan jumlah mapping findings. Durasi event mencakup pekerjaan lain dan dapat overlap dengan stage; jangan dijumlahkan sebagai total pipeline. Waktu terlihat adalah publikasi state, bukan frame AppKit.

| Identitas | SHA-256 |
|---|---|
| Source/tests before | `a909137eb2859911527d68efe0e431614dc5862c3307d4f34adbbaaefacb7111` |
| Source/tests after | `2f149cb826f8e448beeeee1c47be441f18e9a2a2d6c3e7d2375e4729792aa7e6` |
| Harness pipeline | `d3b72e52adbe58744c16e643aa8dd12625f652cbee2e5849374f0b1c5f20fde5` |

## Warm pipeline

Detik; median [minimum–maximum] tiga run. Nilai null berarti tidak ada temuan yang memenuhi metrik.

| Workload | Total sebelum | Total sesudah | Delta detik | Perubahan |
|---|---:|---:|---:|---:|
| local-12 | 4.050 [4.002–4.055] | 3.946 [3.941–5.355] | -0.103 | -2.6% |
| local-60 | 7.614 [7.564–7.624] | 7.010 [6.967–7.025] | -0.604 | -7.9% |
| local-180 | 22.653 [22.615–22.894] | 16.101 [15.923–16.102] | -6.552 | -28.9% |
| terminology | 0.711 [0.687–0.893] | 0.708 [0.704–1.751] | -0.003 | -0.4% |
| definitions | 4.751 [4.721–4.864] | 4.669 [4.651–4.800] | -0.082 | -1.7% |
| mixed | 10.876 [10.791–11.043] | 9.395 [9.368–9.429] | -1.481 | -13.6% |

| Workload | Mapping final sebelum | Mapping final sesudah | Mapping lokal sebelum | Mapping lokal sesudah |
|---|---:|---:|---:|---:|
| local-12 | 0.012 [0.012–0.012] | 0.002 [0.002–0.002] | 0.006 [0.006–0.007] | 0.001 [0.001–0.002] |
| local-60 | 0.360 [0.360–0.360] | 0.026 [0.024–0.026] | 0.164 [0.163–0.164] | 0.014 [0.014–0.014] |
| local-180 | 4.862 [4.855–4.868] | 0.177 [0.169–0.185] | 2.051 [2.000–2.052] | 0.098 [0.097–0.098] |
| terminology | 0.000 [0.000–0.000] | 0.000 [0.000–0.003] | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] |
| definitions | 0.001 [0.001–0.002] | 0.000 [0.000–0.003] | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] |
| mixed | 0.912 [0.910–0.914] | 0.052 [0.051–0.056] | 0.427 [0.424–0.427] | 0.026 [0.025–0.027] |

| Workload | Temuan pertama sebelum | Sesudah | Lokal actionable pertama sebelum | Sesudah |
|---|---:|---:|---:|---:|
| local-12 | 0.014 [0.013–0.025] | 0.014 [0.013–0.029] | 0.014 [0.013–0.025] | 0.014 [0.013–0.029] |
| local-60 | 0.038 [0.038–0.042] | 0.038 [0.037–0.049] | 0.038 [0.038–0.042] | 0.038 [0.037–0.049] |
| local-180 | 0.095 [0.094–0.098] | 0.096 [0.095–0.100] | 0.095 [0.094–0.098] | 0.096 [0.095–0.100] |
| terminology | 0.276 [0.260–0.416] | 0.273 [0.273–1.259] | null | null |
| definitions | 0.055 [0.053–0.057] | 0.052 [0.052–0.061] | null | null |
| mixed | 0.055 [0.052–0.056] | 0.051 [0.051–0.059] | 0.055 [0.052–0.056] | 0.051 [0.051–0.059] |

## Kontrol dan incremental

Kontrol memiliki satu run; incremental adalah median/rentang tiga pasangan.

| Workload | Mode | Total sebelum | Total sesudah | Perubahan |
|---|---|---:|---:|---:|
| local-12 | control | 0.886 [0.886–0.886] | 0.856 [0.856–0.856] | -3.3% |
| local-60 | control | 4.644 [4.644–4.644] | 4.057 [4.057–4.057] | -12.6% |
| local-180 | control | 19.917 [19.917–19.917] | 13.037 [13.037–13.037] | -34.5% |
| terminology | control | 0.241 [0.241–0.241] | 0.243 [0.243–0.243] | +0.7% |
| definitions | control | 0.287 [0.287–0.287] | 0.287 [0.287–0.287] | -0.3% |
| mixed | control | 6.970 [6.970–6.970] | 5.695 [5.695–5.695] | -18.3% |
| local-12 | incremental | 3.929 [3.925–3.948] | 3.895 [3.879–3.904] | -0.9% |
| definitions | incremental | 0.519 [0.499–0.520] | 0.482 [0.479–0.489] | -7.0% |

Kontrol terminology naik 0,001765 detik (+0,7%, satu run); penelusuran stage menunjukkan retrieval naik 0,001568 detik sementara mapping turun 0,000066 detik. Pada warm local-180, temuan pertama naik 0,001339 detik dengan rentang run yang overlap; polling publikasi memakai interval 10 ms. Retrieval warm local-180 naik 0,080422 detik dengan rentang yang overlap, sementara counter tetap sama. Angka kecil ini dicatat tanpa menyimpulkan regresi algoritma dari satu kontrol atau resolusi sampler tersebut.

## Replay mapping offline

Fixture sintetis berisi satu koreksi ejaan per segmen, nomor bagian, dan emoji. Semua event lokal dipublikasikan dahulu, kemudian semua event final mengganti reason. Tidak menjalankan retrieval/model. Pemeriksaan reference, jumlah hasil, UUID stabil, progress, dan anchor dilakukan di luar timer replay. Angka ini tidak langsung sebanding dengan workload pipeline yang memiliki tiga koreksi per segmen.

| Segmen | Replay total sebelum | Sesudah | Perubahan | Mapping lokal sebelum → sesudah (median) | Mapping final sebelum → sesudah (median) |
|---|---:|---:|---:|---:|---:|
| 180 | 0.763 [0.756–0.796] | 0.150 [0.146–0.157] | -80.3% | 0.206 → 0.031 | 0.499 → 0.062 |
| 360 | 4.397 [4.335–4.433] | 0.559 [0.556–0.568] | -87.3% | 1.143 → 0.111 | 2.992 → 0.235 |
| 720 | 27.871 [27.765–28.031] | 2.201 [2.167–2.221] | -92.1% | 7.191 → 0.441 | 19.843 → 0.932 |

## Counter dan kesetaraan

Seluruh 30 pasangan record pipeline sebelum–sesudah menghasilkan normalized findings yang identik. Seluruh 12 pasangan incremental/fresh setara. Tidak ada perubahan klasifikasi yang disengaja pada tahap ini. Anchor/sumber invalid nol; jumlah processed/skipped dan hasil fixture tidak berubah.

Counter per-run Qwen candidate, context classification, definition review, risk review, resolution, E5, TataKata, cache hit, repair, fallback, kandidat, dan query retrieval identik. TataKata scoring tetap nol pada workload utama; ini bukan benchmark typo di luar rule pack. Satu segmen mixed yang terlalu panjang tetap dilewati, sehingga cakupan mixed belum lengkap.

| Workload warm | Full rebuild sebelum → sesudah | Segmen diproses mapping sebelum → sesudah | Mapping findings sebelum → sesudah |
|---|---:|---:|---:|
| local-12 | 25 → 1 | 234 → 24 | 25 → 1 |
| local-60 | 121 → 1 | 5490 → 120 | 121 → 1 |
| local-180 | 361 → 1 | 48870 → 360 | 361 → 1 |
| terminology | 7 → 1 | 6 → 5 | 7 → 1 |
| definitions | 13 → 1 | 21 → 11 | 13 → 2 |
| mixed | 253 → 1 | 15620 → 251 | 253 → 2 |

Kesetaraan mapper diuji terhadap salinan test-only dari commit baseline: seluruh field, urutan, UUID selama run, reference, prefix/suffix, Unicode, anchor invalid/berulang, batas hasil, overlap/tie, penggantian/hasil kosong/skipped, perpindahan status definisi, findings, reset, dua ViewModel, serta fallback metadata tidak konsisten. Test flow lama mencakup delayed classification, cancellation, incremental setelah perubahan teks/heading/configuration, stale edit, dan Undo/Redo. Fixture ini tidak membuktikan ketepatan hukum.

## Memori dan batas eksperimen

Peak RSS adalah sampled resident bytes proses dengan sampler yang sama, bukan seluruh GPU memory atau peak di antara polling. GiB, median/rentang warm.

| Workload | Sebelum | Sesudah | Perubahan |
|---|---:|---:|---:|
| local-12 | 0.612 [0.523–1.304] | 1.218 [1.210–1.761] | +99.1% |
| local-60 | 2.392 [2.390–3.617] | 0.804 [0.803–0.919] | -66.4% |
| local-180 | 1.209 [1.209–3.558] | 2.170 [2.170–3.628] | +79.5% |
| terminology | 1.738 [1.737–1.738] | 3.615 [3.615–3.615] | +108.0% |
| definitions | 1.756 [1.754–2.160] | 2.369 [2.366–3.604] | +34.9% |
| mixed | 1.404 [1.403–3.562] | 2.160 [2.160–3.628] | +53.9% |

RSS meningkat pada sebagian workload dan turun pada yang lain. Kontrol deterministic berada sekitar 0,394–0,397 GiB pada kedua versi; variasi besar muncul pada warm yang memuat model. Counter model/cakupan tidak berubah. Penelusuran terbatas pada nilai per-run dan kontrol tanpa inference di bawah; penyebab residency/allocator/compression belum dipisahkan, sehingga kenaikan tidak diatribusikan ke state mapping dan tidak diklaim sebagai bukti leak. Profiling serta kebijakan memori poin 4 tetap di luar tahap ini.

| Workload | RSS warm sebelum per-run (GiB) | Sesudah per-run | RSS kontrol sebelum → sesudah (GiB) |
|---|---:|---:|---:|
| local-12 | 1.304/0.612/0.523 | 1.761/1.210/1.218 | 0.394 → 0.395 |
| local-60 | 3.617/2.392/2.390 | 0.919/0.803/0.804 | 0.396 → 0.395 |
| local-180 | 3.558/1.209/1.209 | 3.628/2.170/2.170 | 0.397 → 0.395 |
| terminology | 1.737/1.738/1.738 | 3.615/3.615/3.615 | 0.396 → 0.395 |
| definitions | 2.160/1.756/1.754 | 3.604/2.366/2.369 | 0.394 → 0.394 |
| mixed | 3.562/1.403/1.404 | 3.628/2.160/2.160 | 0.397 → 0.395 |

## Validasi

- Build Debug dan Release: lulus. Seluruh test offline: 306 dieksekusi, 10 opt-in dilewati, nol kegagalan (296 tidak dilewati).
- Test terarah awal: 33 lulus; guard metadata tidak konsisten kemudian ditambahkan dan diverifikasi dalam suite offline final.
- Build awal reference test gagal karena initializer privat; diperbaiki melalui initializer berlabel khusus pada salinan test, tanpa mengubah algoritma reference.
- Warning dependency MLX dan actor isolation editor yang sudah ada tetap muncul; build lulus tidak berarti bebas warning.
- `git diff --check` lulus. Source/tests setelah benchmark cocok dengan fingerprint yang diukur. Overlay reproduksi diverifikasi byte-for-byte terhadap baseline pengukuran.

Artefak JSON, comparison, manifest, log, serta `.xcresult`: `/private/tmp/amt-mapping-task/`. Harness, revision dan persiapan resource tercatat di envelope JSON. Test model/mapping tetap opt-in; suite reguler offline.

## Reproduksi

Jalankan dari checkout sesudah. Bentuk baseline dengan overlay khusus pengukuran berikut; patch tidak mengubah keputusan flow produksi.

```sh
repository_dir="$(pwd)"
baseline_dir="$(mktemp -d /private/tmp/amt-mapping-baseline.XXXXXX)"
git archive ade8ce5ba1daa869a3888eaa5b30120e7515c843 | tar -x -C "$baseline_dir"
git -C "$baseline_dir" apply --check --unidiff-zero "$repository_dir/docs/benchmarks/mapping-baseline-overlay.patch"
git -C "$baseline_dir" apply --unidiff-zero "$repository_dir/docs/benchmarks/mapping-baseline-overlay.patch"
```

Ulangi blok ini dari baseline dan checkout sesudah dengan direktori artefak baru. Resource cache harus menunjuk resource pinned yang sama seperti metode sebelumnya.

```sh
benchmark_dir="$(mktemp -d /private/tmp/amt-mapping-benchmark.XXXXXX)"
resource_cache="/private/tmp/amt-flow-fix-task/hf-hub"
runner_sha="$(shasum -a 256 AMTTests/AIConnectorFlowBenchmarkTests.swift | cut -d " " -f 1)"
source_sha="$(python3 - <<'PY_SOURCE'
from pathlib import Path
import hashlib
root=Path.cwd(); digest=hashlib.sha256()
for path in sorted(list((root/"AMT").rglob("*.swift"))+list((root/"AMTTests").rglob("*.swift"))):
    digest.update(str(path.relative_to(root)).encode()); digest.update(path.read_bytes())
print(digest.hexdigest())
PY_SOURCE
)"
xcodebuild -project AMT.xcodeproj -scheme AMT -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$benchmark_dir/DerivedData" \
  build-for-testing CODE_SIGNING_ALLOWED=NO

run_flow() {
  fixture="$1"
  phase="$2"
  TEST_RUNNER_HF_HUB_CACHE="$resource_cache" \
  TEST_RUNNER_AMT_RUN_FLOW_BENCHMARK=1 \
  TEST_RUNNER_AMT_FLOW_FIXTURE="$fixture" \
  TEST_RUNNER_AMT_FLOW_PHASE="$phase" \
  TEST_RUNNER_AMT_FLOW_OUTPUT="$benchmark_dir/reports" \
  TEST_RUNNER_AMT_FLOW_RUNNER_SHA="$runner_sha" \
  TEST_RUNNER_AMT_FLOW_BUILD="$source_sha" \
  xcodebuild -project AMT.xcodeproj -scheme AMT -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$benchmark_dir/DerivedData" \
    -parallel-testing-enabled NO \
    -only-testing:AMTTests/AIConnectorFlowBenchmarkTests/testFrozenProductionFlow \
    -resultBundlePath "$benchmark_dir/$fixture-$phase.xcresult" \
    test-without-building CODE_SIGNING_ALLOWED=NO
}
for phase in warm control; do
  for fixture in local-12 local-60 local-180 terminology definitions mixed; do
    run_flow "$fixture" "$phase"
  done
done
for fixture in local-12 definitions; do
  run_flow "$fixture" incremental
done

TEST_RUNNER_AMT_RUN_MAPPING_BENCHMARK=1 \
TEST_RUNNER_AMT_MAPPING_OUTPUT="$benchmark_dir/reports" \
TEST_RUNNER_AMT_FLOW_BUILD="$source_sha" \
xcodebuild -project AMT.xcodeproj -scheme AMT -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$benchmark_dir/DerivedData" \
  -parallel-testing-enabled NO \
  -only-testing:AMTTests/AIConnectorMappingBenchmarkTests/testFrozenMappingReplay \
  -resultBundlePath "$benchmark_dir/mapping.xcresult" \
  test-without-building CODE_SIGNING_ALLOWED=NO
```

## Durasi stage warm

Stage lama dicantumkan agar perubahan mapping dapat dipisahkan dari retrieval/inference.

### local-12

| Stage | Sebelum | Sesudah | Delta detik |
|---|---:|---:|---:|
| suggestionRetrieval | 0.662 [0.652–0.704] | 0.650 [0.648–0.656] | -0.011 |
| definitionDetection | 0.130 [0.126–0.132] | 0.127 [0.125–0.128] | -0.003 |
| definitionRetrieval | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | +0.000 |
| definitionReview | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | +0.000 |
| editorMapping | 0.012 [0.012–0.012] | 0.002 [0.002–0.002] | -0.010 |

### local-60

| Stage | Sebelum | Sesudah | Delta detik |
|---|---:|---:|---:|
| suggestionRetrieval | 3.275 [3.260–3.314] | 3.220 [3.217–3.237] | -0.055 |
| definitionDetection | 0.640 [0.635–0.643] | 0.635 [0.635–0.640] | -0.005 |
| definitionRetrieval | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | +0.000 |
| definitionReview | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | +0.000 |
| editorMapping | 0.360 [0.360–0.361] | 0.026 [0.024–0.027] | -0.334 |

### local-180

| Stage | Sebelum | Sesudah | Delta detik |
|---|---:|---:|---:|
| suggestionRetrieval | 9.848 [9.766–9.859] | 9.928 [9.814–9.991] | +0.080 |
| definitionDetection | 1.931 [1.907–1.935] | 1.944 [1.898–1.946] | +0.012 |
| definitionRetrieval | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | +0.000 |
| definitionReview | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | +0.000 |
| editorMapping | 4.862 [4.855–4.868] | 0.177 [0.169–0.185] | -4.685 |

### terminology

| Stage | Sebelum | Sesudah | Delta detik |
|---|---:|---:|---:|
| suggestionRetrieval | 0.469 [0.458–0.592] | 0.467 [0.464–1.485] | -0.002 |
| definitionDetection | 0.054 [0.053–0.060] | 0.052 [0.052–0.052] | -0.002 |
| definitionRetrieval | 0.162 [0.151–0.169] | 0.158 [0.157–0.159] | -0.004 |
| definitionReview | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | +0.000 |
| editorMapping | 0.000 [0.000–0.000] | 0.000 [0.000–0.003] | -0.000 |

### definitions

| Stage | Sebelum | Sesudah | Delta detik |
|---|---:|---:|---:|
| suggestionRetrieval | 0.313 [0.296–0.318] | 0.305 [0.294–0.399] | -0.008 |
| definitionDetection | 0.053 [0.052–0.053] | 0.052 [0.052–0.053] | -0.000 |
| definitionRetrieval | 0.114 [0.113–0.116] | 0.123 [0.122–0.124] | +0.010 |
| definitionReview | 4.246 [4.236–4.347] | 4.163 [4.158–4.188] | -0.083 |
| editorMapping | 0.001 [0.001–0.002] | 0.000 [0.000–0.003] | -0.000 |

### mixed

| Stage | Sebelum | Sesudah | Delta detik |
|---|---:|---:|---:|
| suggestionRetrieval | 4.764 [4.668–4.794] | 4.645 [4.583–4.697] | -0.118 |
| definitionDetection | 0.725 [0.720–0.731] | 0.722 [0.717–0.725] | -0.002 |
| definitionRetrieval | 0.050 [0.048–0.052] | 0.054 [0.047–0.055] | +0.004 |
| definitionReview | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | +0.000 |
| editorMapping | 0.912 [0.910–0.914] | 0.052 [0.051–0.056] | -0.860 |

## Inventori perubahan

- `AMT/Features/AIConnector/Models/AIConnectorEditorMappingState.swift`
- `AMT/Features/AIConnector/Models/AIConnectorMappingBenchmarkMetrics.swift`
- `AMT/Features/AIConnector/Models/AIConnectorObservationModels.swift`
- `AMT/Features/AIConnector/ViewModels/AIConnectorViewModel.swift`
- `AMT/Suggestion/Models/EditorSuggestion.swift`
- `AMT/Suggestion/Models/EditorSuggestionMappingContext.swift`
- `AMTTests/AIConnectorIncrementalMappingTests.swift`
- `AMTTests/AIConnectorMappingBenchmarkTests.swift`
- `AMTTests/LegacyEditorSuggestionMapper.swift`
- `README.md`
- `docs/benchmarks/mapping-baseline-overlay.patch`
- `docs/incremental-mapping-benchmark.md`
