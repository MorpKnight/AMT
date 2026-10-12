# Analisis definisi dan retrieval lexical

Perubahan backend pada `gi/flow-fix` mempertahankan UI, schema output Qwen, format dokumen, dependency, signing, entitlement, dan deployment target. Pekerjaan flow-fix sebelumnya telah disimpan dalam commit `cff94f61fc8965dc3d638324cd017997643bf59d` (`Implement staged document analysis and benchmark backend flow`). Perubahan tahap ini belum di-commit dan tidak di-push.

## Perilaku dan implementasi

- Detektor menyimpan kekuatan pola internal `strong`/`ambiguous`, default ambiguous. Kutipan berpasangan, frasa “yang dimaksud dengan”, “didefinisikan/diartikan sebagai”, dan heading dengan token “definisi”/“pengertian” menjadi sinyal kuat. Kata penghubung umum atau heading “Ketentuan Umum” saja tidak cukup.
- Kutipan pembungkus dilepas untuk lookup istilah. Target teks, konteks, dan anchor tetap mengacu ke input asli. Pola kuat yang bertentangan dengan keputusan Qwen `notDefinition`/`notApplicable` menjadi `needsReview` pada klasifikasi dan keselarasan, termasuk konflik antarkandidat. Ini bukan keputusan ekuivalensi dan tidak menghasilkan edit otomatis.
- Kegagalan model tetap menghasilkan cakupan tidak lengkap; keputusan model valid yang bertentangan dengan bukti struktur tetap merupakan pemeriksaan selesai dengan hasil perlu review. Guard operator makna dan eligibility sumber tetap dipertahankan.
- `definition-policy-v3-structural-disagreement` masuk profil pipeline serta key cache hasil lengkap. Namespace cache definisi dinaikkan ke v3. Snapshot hasil lama ditolak melalui profil yang sudah tersedia; format serialisasi tidak berubah.
- Corpus menyimpan normalisasi istilah/definisi, exact-term → seluruh indeks entry, dan posting token dari field searchable BM25. BM25 dihitung untuk union kandidat; pencocokan substring tetap memeriksa string corpus yang sudah dinormalisasi. Formula, bonus, priority authority/corpus, limit, dan urutan entry asli untuk tie tetap dipertahankan.
- Lexical gate menyiapkan jumlah hasil sesuai kebutuhan terbesar. Gate dan hybrid masing-masing menerima slice dengan batas semula. Reuse berlaku untuk query yang sama dalam satu request; tidak ada cache baru lintas-run. Query klausa berbeda dihitung tersendiri.
- Diagnostik Debug `suggestionLexicalDiagnostics` mencatat pencarian aktual, kandidat yang diberi skor BM25, dan reuse pada tahap suggestion retrieval. Angka ini tidak menghitung pencarian Dictionary atau retrieval definisi terpisah. Counter query logis dan E5 yang lama tetap memiliki arti semula.
- Hook semantic khusus Debug menerima provider per-request untuk test offline reuse, failure, dan cancellation. Production memakai retriever E5 yang sudah ada; tidak ada override global.

## Metode pengukuran

Baseline baru diukur sebelum perubahan produksi, dari salinan commit di `/private/tmp/amt-definition-retrieval-task/baseline`. Satu overlay test lexical yang identik disalin ke kedua versi; flow produksi baseline tetap asli. Harness pipeline dan fixture tidak berubah. Model, revision, corpus, generation profile greedy/thinking off/seed 42, dan sampler RSS mengikuti [metode benchmark sebelumnya](flow-fix-methodology.md). Resource tersedia dari cache eksperimen sebelumnya; persiapan resource berada di luar timer analisis.

Setiap versi memiliki 18 warm run (enam workload × tiga), enam kontrol deterministic (satu per workload), dan enam pasangan incremental/fresh (dua workload × tiga). Jumlah pengukuran pipeline: 30 per versi, 60 total. Benchmark lexical menambah tiga run pada setiap versi. Resource cold dan cached-rerun matrix tidak diulang dalam eksperimen terfokus ini.

Benchmark lexical memakai 20 query exact, prefix, substring, angka, diakritik, whitespace, kata umum, dan kalimat sintetis. Waktu query mencakup retrieval lexical serta lookup exact-term. Inisialisasi store/corpus/index diukur terpisah tiga kali; model tidak dimuat oleh test lexical.

Semua waktu berikut dalam detik. Warm/incremental menampilkan median [minimum–maximum] tiga run. Kontrol deterministic hanya satu run. Stage dapat overlap, sehingga durasinya tidak dijumlahkan sebagai total. Latensi terlihat mengukur publikasi state, bukan frame AppKit yang tergambar. Nilai tanpa temuan tetap `null`.

## Total pipeline warm

| Workload | Sebelum | Sesudah | Selisih | Perubahan |
|---|---:|---:|---:|---:|
| local-12 | 6.500 [6.495–8.034] | 3.923 [3.896–3.992] | -2.578 | -39.7% |
| local-60 | 20.292 [20.173–20.548] | 7.507 [7.470–7.567] | -12.785 | -63.0% |
| local-180 | 60.907 [60.812–60.959] | 22.418 [22.403–22.601] | -38.489 | -63.2% |
| terminology | 2.595 [2.573–3.704] | 0.685 [0.682–0.730] | -1.909 | -73.6% |
| definitions | 5.549 [5.505–5.847] | 4.650 [4.649–4.712] | -0.899 | -16.2% |
| mixed | 25.350 [25.338–25.520] | 10.601 [10.425–10.782] | -14.749 | -58.2% |

## Latensi temuan pertama

| Workload | Terlihat sebelum | Terlihat sesudah | Delta terlihat | Lokal actionable sebelum | Lokal actionable sesudah | Delta lokal |
|---|---:|---:|---:|---:|---:|---:|
| local-12 | 0.014 [0.013–0.025] | 0.014 [0.013–0.026] | -0.000 | 0.014 [0.013–0.025] | 0.014 [0.013–0.026] | -0.000 |
| local-60 | 0.039 [0.038–0.045] | 0.038 [0.037–0.044] | -0.001 | 0.039 [0.038–0.045] | 0.038 [0.037–0.044] | -0.001 |
| local-180 | 0.096 [0.094–0.096] | 0.095 [0.094–0.102] | -0.001 | 0.096 [0.094–0.096] | 0.095 [0.094–0.102] | -0.001 |
| terminology | 1.099 [1.099–2.177] | 0.263 [0.262–0.309] | -0.837 | null | null | null |
| definitions | 0.233 [0.226–0.235] | 0.054 [0.054–0.060] | -0.179 | null | null | null |
| mixed | 0.052 [0.052–0.057] | 0.051 [0.051–0.059] | -0.001 | 0.052 [0.052–0.057] | 0.051 [0.051–0.059] | -0.001 |

## Kontrol deterministic dan incremental

| Workload | Kondisi | Sebelum | Sesudah | Delta | Perubahan |
|---|---|---:|---:|---:|---:|
| local-12 | control | 3.469 | 0.864 | -2.605 | -75.1% |
| local-60 | control | 17.526 | 4.695 | -12.831 | -73.2% |
| local-180 | control | 58.137 | 19.442 | -38.695 | -66.6% |
| terminology | control | 0.846 | 0.244 | -0.603 | -71.2% |
| definitions | control | 0.692 | 0.286 | -0.405 | -58.6% |
| mixed | control | 21.748 | 7.009 | -14.739 | -67.8% |
| local-12 | incremental | 6.515 [6.447–6.521] | 3.887 [3.865–3.890] | -2.628 | -40.3% |
| definitions | incremental | 1.296 [1.295–1.306] | 0.490 [0.490–0.495] | -0.807 | -62.2% |

Enam pasangan incremental/fresh pada masing-masing versi setara berdasarkan kategori, span, teks, replacement, sumber, dan finding; UUID/timestamp tidak dibandingkan.

## Benchmark lexical

| Pengukuran | Sebelum | Sesudah | Delta | Perubahan |
|---|---:|---:|---:|---:|
| 20 query | 2.003 [1.994–2.018] | 0.372 [0.360–0.374] | -1.631 | -81.4% |
| Inisialisasi store/corpus/index | 0.414 [0.410–0.415] | 0.413 [0.412–0.419] | -0.001 | -0.3% |

Seluruh tiga pengulangan menghasilkan ID, urutan ranking, source passage, actionable, dan exact-term IDs yang sama. Skor dibandingkan dengan toleransi absolut 1e-9/relatif 1e-12. Test offline juga membandingkan retrieval dengan reference full scan dari baseline pada fixture sintetis dan corpus produksi.

## Counter dan cakupan warm

| Workload | Qwen sebelum → sesudah | E5 sebelum → sesudah | Kandidat sebelum → sesudah | Cache hit | Repair | Fallback | Skipped |
|---|---:|---:|---:|---:|---:|---:|---:|
| local-12 | 1 → 1 | 0 → 0 | 36 → 36 | 0 → 0 | 0 → 0 | 0 → 0 | 0 |
| local-60 | 1 → 1 | 0 → 0 | 180 → 180 | 0 → 0 | 0 → 0 | 0 → 0 | 0 |
| local-180 | 1 → 1 | 0 → 0 | 540 → 540 | 0 → 0 | 0 → 0 | 0 → 0 | 0 |
| terminology | 0 → 0 | 7 → 7 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 |
| definitions | 2 → 2 | 4 → 4 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 |
| mixed | 1 → 1 | 2 → 2 | 240 → 240 | 0 → 0 | 0 → 0 | 0 → 0 | 1 |

Invocation scoring TataKata tetap nol pada matriks ini, karena kandidat ejaan berasal dari rule pack. Benchmark ini tidak mengukur dokumen dengan banyak typo di luar aturan lokal. Satu segmen mixed terlalu panjang tetap dilewati dan mencegah snapshot dianggap lengkap.

| Workload | Pencarian lexical aktual sesudah | Evaluasi kandidat BM25 sesudah | Reuse sesudah |
|---|---:|---:|---:|
| local-12 | 12 | 31068 | 0 |
| local-60 | 60 | 155340 | 0 |
| local-180 | 180 | 466020 | 0 |
| terminology | 6 | 12585 | 2 |
| definitions | 6 | 3728 | 2 |
| mixed | 125 | 159232 | 1 |

Pada workload lokal, kata “nomor” juga muncul dalam field peraturan sehingga union posting masih mencakup semua 2.589 entry per query. Inverted index tidak otomatis membuat setiap query selektif. String substring juga tetap diperiksa di seluruh corpus. Pengurangan normalisasi berulang dan reuse konsisten dengan penurunan waktu yang terukur; kontribusi masing-masing perubahan belum dipisahkan melalui ablation.

## Kualitas, kesetaraan, dan penerapan

- Seluruh 60 pengukuran pipeline selesai, dengan nol anchor invalid dan nol sumber invalid. Semua workload ejaan lokal mempertahankan expected corrections, tanpa false positive/negative pada gold sintetis tersebut.
- Pada seluruh warm run definisi, `"Data" adalah informasi yang tidak dapat dipublikasikan.` berubah dari `notDefinition/notApplicable` menjadi `needsReview/needsReview`. Ini merupakan perubahan perilaku yang disengaja. Temuan internal reference dan hasil definisi lainnya pada fixture tetap sama.
- Tidak muncul `matches` atau replacement actionable pada hard-negative definisi yang diukur. Fixture ini belum ditinjau sebagai gold hukum, sehingga hasil tidak menjadi pembuktian ketepatan hukum atau recall seluruh definisi.
- Test offline mencakup pertentangan pola kuat/model, kutipan Unicode, heading, deskripsi ambigu, sumber tidak eligible, konflik antarkandidat, failure, guard operator, cache heading/fresh, lexical reuse/fallback/cancellation. Test edit stale, Undo/Redo, persistence, queue/back-pressure, dan cancellation lintas dokumen sebelumnya tetap lulus.

## Peak RSS dan regresi yang masih perlu ditelusuri

Peak RSS adalah maksimum sampled process resident bytes dengan sampler yang sama, bukan seluruh memori GPU atau peak di antara polling. Nilai dalam GiB.

| Workload | Sebelum | Sesudah | Delta GiB | Perubahan |
|---|---:|---:|---:|---:|
| local-12 | 1.085 [1.085–1.586] | 0.802 [0.776–0.809] | -0.283 | -26.0% |
| local-60 | 0.858 [0.858–2.393] | 3.173 [3.167–3.628] | 2.315 | +269.7% |
| local-180 | 2.968 [2.968–3.614] | 2.298 [2.298–3.625] | -0.670 | -22.6% |
| terminology | 3.604 [3.586–3.604] | 3.623 [3.623–3.623] | 0.019 | +0.5% |
| definitions | 2.788 [2.787–3.636] | 3.316 [3.271–3.622] | 0.528 | +18.9% |
| mixed | 1.630 [1.629–3.614] | 1.901 [1.901–3.628] | 0.271 | +16.6% |

Seluruh median total warm dan kontrol deterministic membaik. RSS meningkat pada local-60, terminology, definitions, dan mixed. Investigasi per-run menunjukkan local-60 sebelum: 2,393/0,858/0,858 GiB, sesudah: 3,628/3,173/3,167 GiB. Definitions dan mixed memiliki RSS run pertama hampir sama pada kedua versi, tetapi berbeda pada pengulangan berikutnya. Counter inference/cakupan tetap sama dan tidak ditambahkan cache lintas-run. Pola ini membatasi atribusi kenaikan RSS ke indeks baru; residency/compression, allocator/model cache, dan overhead indeks belum dipisahkan. Penyebab kenaikan belum terdiagnosis dan membutuhkan profiling memori tersendiri. Tidak diklaim sebagai perbaikan memori atau bukti leak.

Urutan baseline lalu sesudah tetap, cache filesystem tidak dipurge, serta tiga pengulangan bukan confidence interval. Angka performa berlaku pada workload dan kondisi eksperimen ini.

## Validation dan identitas source

- Tahap normalisasi/reuse: 27 test terpilih, nol kegagalan, sebelum inverted index ditambahkan.
- Build masih mengeluarkan warning dependency MLX dan actor isolation pada kode editor yang tidak diubah dalam tahap ini; hasil lulus tidak berarti bebas warning.
- Final: build Debug dan Release lulus; 295 test offline dijalankan, 9 opt-in dilewati, nol kegagalan (286 test tidak dilewati). `git diff --check` lulus.
- Build, test, model benchmark, dan pembandingan laporan dilakukan tanpa signing atau push. UI setelah commit baseline tidak berubah.

| Identitas | SHA-256 |
|---|---|
| Harness pipeline identik | `d3b72e52adbe58744c16e643aa8dd12625f652cbee2e5849374f0b1c5f20fde5` |
| Source baseline + overlay lexical | `2f85594bdc494992683b94d84e1d0f737cf0e361d0ab9f4b8176b6fcdeb6e4b6` |
| Source sesudah, termasuk tests | `5041d0fb0c39f05d1105d740bfc8dca9dd7f724d8d59a0a051181c2983d03836` |

JSON mentah, manifest/checksum, `comparison.json`, log, dan `.xcresult` berada di `/private/tmp/amt-definition-retrieval-task/`. `comparison.json` mengandung ringkasan serta checksum laporan. Log build final: `build-final-debug.log` dan `build-final-release.log`; unit test: `offline-final.log`/`offline-final.xcresult`. DerivedData baseline ada di direktori artefak; versi sesudah memakai ulang `/private/tmp/amt-flow-fix-task/derived-after` setelah pengukuran baseline selesai.

## File yang berubah

- `AMT/Dictionary/Services/LegalDictionaryStore.swift`
- `AMT/Features/AIConnector/Models/AIConnectorDefinitionModels.swift`
- `AMT/Features/AIConnector/Models/AIConnectorObservationModels.swift`
- `AMT/Features/AIConnector/Services/AIConnectorDefinitionAnalyzer.swift`
- `AMT/Features/AIConnector/Services/AIConnectorDefinitionDetector.swift`
- `AMT/Features/AIConnector/Services/AIConnectorObservationCollector.swift`
- `AMT/Features/AIConnector/Services/AIConnectorWorkQueue.swift`
- `AMT/Features/AIConnector/ViewModels/AIConnectorViewModel.swift`
- `AMTTests/AIConnectorDefinitionAnalysisTests.swift`
- `AMTTests/AIConnectorFlowFixTests.swift`
- `README.md`
- `AMTTests/LegalLexicalBenchmarkTests.swift`
- `AMTTests/LegalLexicalSearchTests.swift`
- `docs/definition-retrieval-improvements.md`

## Reproduksi

Ikuti konfigurasi resource pada [metode sebelumnya](flow-fix-methodology.md). Bentuk baseline commit ini, lalu tambahkan hanya overlay test lexical:

```sh
repository_dir="$(pwd)"
baseline_dir="$(mktemp -d /private/tmp/amt-definition-baseline.XXXXXX)"
git archive cff94f61fc8965dc3d638324cd017997643bf59d | tar -x -C "$baseline_dir"
cp "$repository_dir/AMTTests/LegalLexicalBenchmarkTests.swift" "$baseline_dir/AMTTests/LegalLexicalBenchmarkTests.swift"
```

Jalankan blok berikut dari baseline, lalu ulangi dari checkout sesudah dengan direktori output/DerivedData baru. Identitas build mencakup SHA seluruh source/tests, karena versi sesudah belum di-commit. Jika resource tersedia di lokasi cache lain, sesuaikan `resource_cache`.

```sh
benchmark_dir="$(mktemp -d /private/tmp/amt-definition-benchmark.XXXXXX)"
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

TEST_RUNNER_AMT_RUN_LEXICAL_BENCHMARK=1 \
TEST_RUNNER_AMT_LEXICAL_OUTPUT="$benchmark_dir/reports" \
TEST_RUNNER_AMT_FLOW_BUILD="$source_sha" \
xcodebuild -project AMT.xcodeproj -scheme AMT -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$benchmark_dir/DerivedData" \
  -parallel-testing-enabled NO \
  -only-testing:AMTTests/LegalLexicalBenchmarkTests/testFrozenLexicalQueries \
  -resultBundlePath "$benchmark_dir/lexical.xcresult" \
  test-without-building CODE_SIGNING_ALLOWED=NO
```

## Durasi stage warm

Seluruh stage yang dilaporkan harness ditampilkan berikut. Median/rentang dihitung per-run; durasi dapat overlap.

### local-12

| Stage | Sebelum | Sesudah | Delta |
|---|---:|---:|---:|
| candidateBuilding | 0.002 [0.002–0.002] | 0.002 [0.002–0.002] | -0.000 |
| contextClassification | 3.056 [3.053–4.526] | 3.077 [3.051–3.109] | 0.021 |
| contextExtraction | 0.000 [0.000–0.001] | 0.000 [0.000–0.001] | -0.000 |
| contextSegmentation | 0.002 [0.002–0.002] | 0.002 [0.002–0.002] | 0.000 |
| definitionDetection | 0.126 [0.126–0.127] | 0.127 [0.127–0.128] | 0.001 |
| documentFindingDetection | 0.002 [0.002–0.003] | 0.002 [0.002–0.002] | 0.000 |
| documentStructure | 0.000 [0.000–0.000] | 0.000 [0.000–0.001] | -0.000 |
| editorMapping | 0.012 [0.012–0.012] | 0.011 [0.011–0.011] | -0.000 |
| localReview | 0.017 [0.017–0.020] | 0.017 [0.016–0.021] | -0.001 |
| protectionContext | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| resultAcknowledgement | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| spellingCandidateGeneration | 0.009 [0.009–0.014] | 0.007 [0.007–0.015] | -0.001 |
| suggestionRetrieval | 3.144 [3.111–3.187] | 0.643 [0.641–0.649] | -2.501 |
| validationConflictResolution | 3.392 [3.384–3.437] | 0.792 [0.791–0.809] | -2.600 |

### local-60

| Stage | Sebelum | Sesudah | Delta |
|---|---:|---:|---:|
| candidateBuilding | 0.009 [0.009–0.009] | 0.008 [0.008–0.008] | -0.001 |
| contextClassification | 2.811 [2.789–2.850] | 2.787 [2.780–2.805] | -0.024 |
| contextExtraction | 0.002 [0.002–0.002] | 0.002 [0.002–0.002] | -0.000 |
| contextSegmentation | 0.009 [0.009–0.010] | 0.010 [0.009–0.010] | 0.000 |
| definitionDetection | 0.633 [0.628–0.640] | 0.645 [0.643–0.645] | 0.012 |
| documentFindingDetection | 0.009 [0.009–0.009] | 0.009 [0.009–0.009] | 0.000 |
| documentStructure | 0.002 [0.002–0.002] | 0.002 [0.002–0.002] | -0.000 |
| editorMapping | 0.359 [0.355–0.360] | 0.355 [0.354–0.357] | -0.004 |
| localReview | 0.226 [0.225–0.228] | 0.226 [0.224–0.228] | -0.000 |
| protectionContext | 0.001 [0.001–0.001] | 0.001 [0.001–0.001] | -0.000 |
| resultAcknowledgement | 0.001 [0.001–0.001] | 0.001 [0.001–0.001] | 0.000 |
| spellingCandidateGeneration | 0.045 [0.045–0.047] | 0.036 [0.035–0.037] | -0.010 |
| suggestionRetrieval | 15.609 [15.478–15.744] | 3.257 [3.255–3.287] | -12.352 |
| validationConflictResolution | 16.824 [16.687–17.008] | 4.024 [4.018–4.101] | -12.800 |

### local-180

| Stage | Sebelum | Sesudah | Delta |
|---|---:|---:|---:|
| candidateBuilding | 0.027 [0.027–0.027] | 0.023 [0.023–0.024] | -0.004 |
| contextClassification | 2.814 [2.812–2.838] | 2.793 [2.792–2.821] | -0.022 |
| contextExtraction | 0.004 [0.004–0.004] | 0.004 [0.004–0.004] | -0.000 |
| contextSegmentation | 0.030 [0.030–0.031] | 0.031 [0.030–0.031] | 0.000 |
| definitionDetection | 1.899 [1.888–1.899] | 1.904 [1.892–1.928] | 0.006 |
| documentFindingDetection | 0.027 [0.027–0.028] | 0.027 [0.027–0.027] | -0.000 |
| documentStructure | 0.006 [0.006–0.006] | 0.006 [0.006–0.006] | -0.000 |
| editorMapping | 4.854 [4.848–4.862] | 4.828 [4.815–4.840] | -0.026 |
| localReview | 2.244 [2.242–2.250] | 2.232 [2.231–2.269] | -0.012 |
| protectionContext | 0.002 [0.002–0.002] | 0.002 [0.002–0.002] | 0.000 |
| resultAcknowledgement | 0.004 [0.004–0.004] | 0.004 [0.004–0.004] | 0.000 |
| spellingCandidateGeneration | 0.158 [0.156–0.159] | 0.129 [0.129–0.136] | -0.029 |
| suggestionRetrieval | 46.802 [46.748–46.803] | 9.770 [9.769–9.836] | -37.031 |
| validationConflictResolution | 50.556 [50.483–50.593] | 12.156 [12.131–12.239] | -38.400 |

### terminology

| Stage | Sebelum | Sesudah | Delta |
|---|---:|---:|---:|
| candidateBuilding | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| contextExtraction | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| contextSegmentation | 0.001 [0.001–0.001] | 0.001 [0.001–0.001] | 0.000 |
| definitionDetection | 0.051 [0.051–0.051] | 0.051 [0.051–0.051] | 0.000 |
| definitionResolution | 0.000 [0.000–0.001] | 0.000 [0.000–0.001] | -0.000 |
| definitionRetrieval | 0.566 [0.564–0.573] | 0.154 [0.153–0.156] | -0.412 |
| documentFindingDetection | 0.001 [0.001–0.002] | 0.001 [0.001–0.001] | -0.000 |
| documentStructure | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| editorMapping | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| localReview | 0.001 [0.001–0.002] | 0.001 [0.001–0.001] | 0.000 |
| protectionContext | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| resultAcknowledgement | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| spellingCandidateGeneration | 0.010 [0.010–0.023] | 0.010 [0.010–0.036] | -0.000 |
| suggestionRetrieval | 1.940 [1.921–3.017] | 0.450 [0.448–0.464] | -1.491 |
| validationConflictResolution | 2.579 [2.557–3.678] | 0.670 [0.666–0.711] | -1.909 |

### definitions

| Stage | Sebelum | Sesudah | Delta |
|---|---:|---:|---:|
| candidateBuilding | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| contextExtraction | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| contextSegmentation | 0.001 [0.001–0.001] | 0.001 [0.001–0.001] | -0.000 |
| definitionDetection | 0.055 [0.055–0.056] | 0.052 [0.051–0.052] | -0.003 |
| definitionResolution | 0.000 [0.000–0.001] | 0.001 [0.001–0.001] | 0.001 |
| definitionRetrieval | 0.330 [0.328–0.331] | 0.124 [0.122–0.126] | -0.205 |
| definitionReview | 4.200 [4.160–4.227] | 4.143 [4.141–4.187] | -0.057 |
| documentFindingDetection | 0.001 [0.001–0.002] | 0.001 [0.001–0.002] | -0.000 |
| documentStructure | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | -0.000 |
| editorMapping | 0.000 [0.000–0.002] | 0.001 [0.001–0.003] | 0.000 |
| localReview | 0.001 [0.001–0.001] | 0.001 [0.001–0.001] | -0.000 |
| protectionContext | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| resultAcknowledgement | 0.000 [0.000–0.000] | 0.000 [0.000–0.000] | 0.000 |
| spellingCandidateGeneration | 0.003 [0.003–0.011] | 0.003 [0.003–0.009] | -0.000 |
| suggestionRetrieval | 0.933 [0.929–1.176] | 0.307 [0.306–0.312] | -0.626 |
| validationConflictResolution | 5.531 [5.489–5.822] | 4.633 [4.632–4.687] | -0.898 |

### mixed

| Stage | Sebelum | Sesudah | Delta |
|---|---:|---:|---:|
| candidateBuilding | 0.012 [0.012–0.012] | 0.010 [0.010–0.011] | -0.002 |
| contextClassification | 3.412 [3.406–3.529] | 3.403 [3.390–3.481] | -0.008 |
| contextExtraction | 0.004 [0.004–0.004] | 0.004 [0.004–0.004] | -0.000 |
| contextSegmentation | 0.013 [0.013–0.013] | 0.013 [0.013–0.016] | -0.000 |
| definitionDetection | 0.718 [0.712–0.721] | 0.715 [0.696–0.728] | -0.003 |
| definitionResolution | 0.001 [0.001–0.001] | 0.001 [0.001–0.001] | -0.000 |
| definitionRetrieval | 0.109 [0.109–0.111] | 0.052 [0.049–0.063] | -0.057 |
| documentFindingDetection | 0.023 [0.022–0.023] | 0.023 [0.023–0.024] | -0.000 |
| documentStructure | 0.003 [0.003–0.003] | 0.003 [0.003–0.003] | 0.000 |
| editorMapping | 0.898 [0.897–0.900] | 0.887 [0.869–0.891] | -0.010 |
| localReview | 0.519 [0.519–0.526] | 0.520 [0.511–0.522] | 0.000 |
| protectionContext | 0.002 [0.002–0.002] | 0.002 [0.002–0.002] | 0.000 |
| resultAcknowledgement | 0.003 [0.003–0.003] | 0.003 [0.003–0.003] | 0.000 |
| spellingCandidateGeneration | 0.076 [0.076–0.080] | 0.059 [0.059–0.063] | -0.016 |
| suggestionRetrieval | 18.770 [18.747–18.771] | 4.677 [4.517–4.708] | -14.094 |
| validationConflictResolution | 20.346 [20.325–20.377] | 5.637 [5.453–5.698] | -14.709 |
