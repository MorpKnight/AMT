# Integrasi backend drafting

Komponen terpilih dari eksperimen drafting kini tersedia sebagai source produksi
di `AMT/Features/Drafting`. Jalur koreksi ejaan/istilah dan prompt lamanya tetap
berjalan seperti sebelumnya. Tidak ada perubahan View, format dokumen, dependency,
signing, atau deployment target. Proposer T5 dan optimasi skor TataKata yang belum
lolos kesetaraan tidak diambil.

## Boundary pemakaian

`AIConnectorViewModel.reviewDrafting(_:documentText:fullFresh:)` menerima permintaan
eksplisit. Layanan menggunakan instance Qwen dan scheduler aplikasi yang sama,
dengan prioritas interactive. Cache hasil dimiliki masing-masing ViewModel,
dibatasi 256 entry/8 MiB, dan dipangkas melalui lifecycle resource yang sudah ada.
Pemanggil dapat memakai `DraftingReviewService` langsung untuk pemrosesan backend.

UI sekarang belum mengirim brief ke API baru ini. Kemampuan tersedia dan diuji
pada backend, tanpa menambahkan layar atau memaksakan proposal drafting ke kartu
koreksi ejaan. `draftingReviewResult` adalah state sementara. Tidak masuk snapshot
dokumen, `EditorSuggestion`, Accept, atau mutation editor. Semua hasil baca-saja.

Contoh pemanggilan backend untuk satu klausul:

```swift
let request = DraftingReview.Request(
    documentText: text,
    documentRevision: DocumentFingerprinting.contentSHA256(text),
    brief: "Ubah tenggat pembayaran menjadi 10 hari.",
    scope: .rewriteTarget,
    clauses: [.init(id: "c1", text: text,
                    sourceRange: NSRange(location: 0, length: text.utf16.count))],
    targetClauseIDs: ["c1"]
)
let result = await viewModel.reviewDrafting(request, documentText: text)
```

## Komponen yang diintegrasikan

- **Preflight dan evidence:** revision SHA-256, target/range UTF-16, ID unik,
  sumber wajib yang eligible, serta definisi internal dengan body utuh yang
  terjangkar ke dokumen. Closure istilah literal mengambil dependensi berantai,
  mempertahankan urutan dan berhenti pada siklus. Scope disertakan; makna implisit
  dan dependensi yang tidak dinyatakan tidak diasumsikan sudah ditemukan.
- **Jalur literal:** permissions terstruktur dari peminta, atau parser sempit
  untuk perintah penuh tenggat laporan/pembayaran, durasi dan frekuensi. Parser
  menolak kutipan/kode, target/nilai ambigu, predikat tidak cocok, dan instruksi
  preservasi yang bertentangan. Penggantian terikat sumber, range unik dan
  non-overlap; nama, kutipan, acronym dan identifier tetap terlindungi. Teks di
  luar permission harus identik. Tidak perlu memuat Qwen/TataKata untuk jalur ini.
- **Validator:** schema ketat, null field, target/quote unik, namespace referensi,
  provenance angka pada sumber yang dikutip, serta pola aktor, modalitas, negasi,
  satuan, pemicu, syarat dan pengecualian. Permission eksplisit memerlukan hasil
  seluruh klausul persis sama dengan penerapan permission, sehingga perubahan
  konsep tambahan juga ditolak. Model tidak dapat membuat izin substansi sendiri.

Review kontekstual memakai prompt drafting tersendiri. Setelah normalisasi format
terbatas yang dijelaskan di bawah, JSON invalid, generation
terpotong, input lengkap >4.096 token dengan chat template aktual, source hilang,
atau penolakan validator menjadi incomplete dengan response tidak dipublikasikan.
Cancellation mempunyai status tersendiri. Semua evidence wajib tetap utuh;
generation dibatasi 768 token, greedy, seed 42, thinking mati.

Mode deterministic tidak menjalankan inference; tugas di luar jalur literal
menjadi incomplete/modelReviewRequired. `fullFresh` selalu melewati cache hasil.
Cache key mencakup seluruh request, dependency/body/revision sumber, permissions,
policy/prompt, model ID/revision, dan kebijakan inference. Hanya hasil processing
complete disimpan; status tersebut bukan approval hukum. Raw model output tidak
disimpan. Reset/pressure ketika inference berlangsung tidak mengisi ulang cache
lama. Edit/reset membatalkan publikasi drafting lama hanya pada ViewModel pemilik.

## Batas keselamatan dan bukti

Permission bertipe adalah otorisasi yang diberikan pemanggil, bukan sesuatu yang
boleh dihasilkan model dari isi dokumen. Kehadiran replacement dalam brief/sumber
hanya memvalidasi binding nilai, bukan membuktikan interpretasi seluruh brief.
Parser bebas masih sempit; abstain parser tidak menjamin jawaban fallback benar.
Guard leksikal tidak membuktikan ekuivalensi hukum atau menangkap semua hubungan
aktor/konsep. Tidak ada penerapan perubahan substantif otomatis.

Angka eksperimen sebelumnya (misalnya waktu -57,2%) tidak menjadi klaim performa
integrasi ini karena envelope dan pemeriksaan produksi berubah. Label sintetis
tetap pending; quality gate tetap insufficientEvidence. Tidak ada migrasi UI,
adapter Windows, benchmark M4 atau klaim ketepatan hukum umum.

## Reproduksi validasi

Gunakan `xcodebuild`, destination `platform=macOS,arch=arm64`, DerivedData di
`/private/tmp/`, `CODE_SIGNING_ALLOWED=NO`; jalankan build Debug/Release dan seluruh
test reguler. `DraftingReviewTests` tidak memuat model. Smoke model bersifat opt-in:

```sh
TEST_RUNNER_AMT_RUN_DRAFTING_INTEGRATION_SMOKE=1 \
TEST_RUNNER_AMT_DRAFTING_INTEGRATION_REPORT=/private/tmp/drafting-integration-smoke.json \
xcodebuild -project AMT.xcodeproj -scheme AMT -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/amt-drafting-integration-derived \
  -parallel-testing-enabled NO \
  -only-testing:AMTTests/DraftingReviewModelSmokeTests \
  test CODE_SIGNING_ALLOWED=NO
```

Smoke memakai enam input sintetis: dua literal, no-change, klarifikasi lokasi,
pilihan laporan yang belum ditentukan, serta evidence terlalu panjang. Ia
memeriksa runtime, routing, budget dan cache; tidak menetapkan kebenaran semantik
model sebagai quality gate.

## Hasil validasi 18 Oktober 2026

Source baseline `c709919833e1f7a76430ce6bd6e1b144e9278165`, branch `gi/flow-fix`.
Artefak di `/private/tmp/amt-drafting-integration-20261018.kLE62x`:

- Build Debug dan Release melalui `xcodebuild` lulus, signing dimatikan dan
  destination macOS arm64. Release juga membangun binary universal bawaan project.
- Suite final `offline-current.log`/`.xcresult`: **377 executed, 361 passed,
  16 opt-in skipped, 0 failures**. Termasuk 28 test drafting offline baru.
- Smoke opt-in `model-smoke.log`/`.xcresult` lulus; enam input sintetis, satu warm
  dan satu cached rerun masing-masing (12 record). Lima input menghasilkan
  processing complete; satu input terlalu panjang ditolak sebagaimana diharapkan.
- `git diff --check` dan whitespace check semua file baru lulus. Sepuluh file
  source/test cocok dengan manifest setelah validasi; hanya dua source tracked
  lama berubah (Qwen service dan ViewModel). Tidak ada commit/push.

| Fixture smoke | Hasil warm | Waktu warm | Cached hit |
|---|---|---:|---|
| Tenggat pembayaran 5 → 10 hari | Literal, revise, tanpa LLM | 0,007233 s | Ya |
| Frekuensi bulanan → mingguan | Literal, revise, tanpa LLM | 0,002449 s | Ya |
| Jasa jarak jauh sudah sesuai brief | Model, no_change | 2,171127 s | Ya |
| Lokasi penyerahan belum tersedia | Model, clarify lokasi | 2,184134 s | Ya |
| Jenis laporan belum dipilih | Model, clarify jenis laporan | 2,459645 s | Ya |
| Evidence melebihi anggaran prompt | Incomplete, requiredEvidenceTooLong | 0,224589 s | Tidak |

Persiapan model resident 2,103618 s diukur terpisah. Angka waktu adalah satu
pengukuran tiap fixture, bukan median tiga run atau pembandingan keseluruhan
backend. Pemeriksaan isi dilakukan pada output sintetis; label tetap pending.
Counter `modelCalls` pada report adalah invocation tahap generator, termasuk
attempt yang ditolak budget sebelum generation. Fixture oversized tidak
menghasilkan output model dan tidak disimpan sebagai hasil lengkap.

`source-manifest.json`, `static-verification.json`, `validation.json`, dan
`artifact-checksums.json` menyimpan identitas source serta bukti validasi final.
Log putaran pengembangan sebelumnya dipertahankan, tetapi angka final di atas
hanya berasal dari `offline-current` dan smoke pada source yang sama.


## Perbaikan sebelum benchmark lanjutan — 19 Oktober 2026

Kebijakan internal naik ke `drafting-review-v2`. Perubahan ini belum mempunyai
hasil benchmark model baru. Benchmark sebelumnya tetap dihentikan dan artefaknya
tidak ditimpa; hasil parsial lama tidak boleh digabungkan dengan versi ini.

- Normalisasi lokal mengisi hanya field tidak aktif yang hilang dengan `null`,
  atau menghapus duplikasi key dengan nilai JSON identik. Tidak mengisi field
  aktif, mengganti keputusan, teks, sumber, izin, atau nilai bisnis. Key berulang
  yang bertentangan, unknown field, output terpotong, dan format invalid tetap
  ditolak. Parser ketat tetap dijalankan sesudah normalisasi, diikuti semua guard.
  Input parser dibatasi 128 KiB dan kedalaman 32. Tidak ada panggilan repair LLM.
- `formatRepairCount` mencatat normalisasi pada request aktif. Cache hit tidak
  dihitung sebagai repair baru. Raw output tetap tidak disimpan dalam cache;
  hasil yang gagal validator tetap incomplete dan tidak di-cache sebagai lengkap.
- Compiler brief menerima bentuk pembayaran pasif dan keluarga durasi
  kerahasiaan, masa pemberitahuan pengakhiran, serta masa jaminan. Target harus
  tunggal dengan satu atom waktu/frekuensi yang terikat ke predikat yang cocok.
  Konteks klausul dan definisi yang tidak terkait tidak otomatis menjadi target.
  Jika brief menyebut pemicu waktu, pemicu itu harus cocok dengan teks asal.
  Kutipan, kondisi pendahulu, konflik preservasi, beberapa nilai, definisi relevan,
  serta sumber wajib tetap memerlukan pemeriksaan kontekstual/izin terstruktur.
- Prompt mempertegas seluruh key wajib, null, larangan duplicate key, pemenuhan
  melalui konteks/definisi, serta pertanyaan klarifikasi yang sesuai parameter.
  Dampak semantiknya belum diuji dengan inference pada tahap validasi ini.
- Evaluator baru ada di `experiments/drafting-validation`. Ia mengukur pertanyaan
  waktu seperti “kapan” tanpa mensyaratkan kata “hari”, memakai batas kata dan
  tetap mempertahankan skor v3 sebagai `legacyRubricUseful`. Evaluator lama dan
  label fixture tidak diubah. Pada benchmark berikutnya kedua evaluator harus
  diterapkan ke kedua arm yang sama. Label tetap pending/insufficientEvidence.

Perubahan aktor, penambahan kewajiban, pemetaan sumber ke edit, atau brief bebas
yang tidak dapat dibuktikan oleh compiler ini tetap membutuhkan permission
terstruktur. Perbaikan ini tidak menyatakan bahwa semua regresi semantik sudah
hilang. Kegagalan tetap incomplete; tidak ada negative cache yang menyamarkannya
sebagai hasil lengkap.


### Hasil validasi offline perbaikan

Artefak: `/private/tmp/amt-drafting-validation-20261019.jhXu8t`.

- Build-for-testing Debug dan build Release lulus dengan macOS arm64 sebagai
  destination, DerivedData eksternal, dan signing dimatikan. Konfigurasi Release
  tetap membangun binary universal bawaan project.
- Seluruh test offline: **387 executed, 371 passed, 16 opt-in skipped, 0 failures**.
  Di dalamnya ada 38 test drafting, termasuk 10 test regresi baru. Generator test
  memakai stub; flag opt-in benchmark/model dibersihkan dari environment.
- Empat unit test evaluator berversi lulus. Parser Python/whitespace dan
  `git diff --check` lulus. Kode Qwen service/ViewModel tidak berubah pada tahap ini.
- Semua 451 checksum file beku dari run benchmark lama tetap cocok. Run tetap
  paused; tidak ada benchmark model, smoke inference, atau pengukuran akurasi
  baru pada tahap ini. Belum ada klaim peningkatan performa setelah perbaikan.
- Tidak ada commit atau push. Manifest source, log build/test, `.xcresult`, dan
  hasil pemeriksaan disimpan bersama artefak validasi.
