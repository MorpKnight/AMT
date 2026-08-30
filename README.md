# AMT

**AMT (Lawtionary)** adalah aplikasi macOS awal untuk membantu penulisan dokumen hukum Indonesia. Aplikasi ini menggabungkan editor dokumen sederhana, kamus istilah hukum berbasis sumber, dan eksperimen suggestion berbasis model bahasa lokal.

> [!WARNING]
> AMT masih berada pada tahap MVP/early development. Hasil Dictionary dan Suggestion bukan nasihat hukum, bukan validasi hukum otomatis, dan tetap memerlukan review manusia.

## Fitur saat ini

- **Dashboard dokumen**
  - Membuat, membuka, mencari, dan menghapus dokumen.
  - Menyimpan dokumen secara lokal di folder `Documents/AMT_Documents` sebagai JSON.
  - Mengimpor `.docx`, `.doc`, `.rtf`, dan `.txt` melalui Finder. Isi file diubah menjadi teks biasa untuk kebutuhan editor saat ini.
  - Menyediakan dokumen bawaan **AI Connector — Test Document** untuk smoke test. Dokumen ini selalu dibuat ulang saat aplikasi dibuka dan perubahan pada dokumen tersebut tidak disimpan ke disk.
- **Dictionary / Lawtionary**
  - Memuat `AMT/Dictionary/Resources/kamus_hukum.csv` sebagai resource aplikasi.
  - Mencari berdasarkan istilah atau bagian dari pengertian melalui ranking lexical BM25.
  - Menggabungkan corpus CSV utama dengan `rag_export/documents.json` secara asynchronous; corpus RAG lama selalu berstatus legacy dan tidak mengalahkan entry verified untuk istilah yang sama.
  - Menonaktifkan semantic embedding sampai pasangan model dan tokenizer BGE-M3 yang terverifikasi tersedia. Tidak ada pseudo-embedding sebagai fallback.
  - Menampilkan pengertian, peraturan, judul peraturan, dan tautan sumber jika tersedia.
  - Menampilkan status provenance agar corpus legacy tidak terlihat sebagai sumber terverifikasi.
- **Suggestion eksperimental**
  - Meninjau teks dokumen menggunakan `mlx-community/Qwen3.5-4B-MLX-4bit` melalui MLX Swift sebagai model utama Debug. Qwen3.5 Legal 4B dan Qwen3.5 2B tetap tersedia untuk pembanding historis.
  - Inferensi berjalan lokal setelah model selesai diunduh dan disimpan di cache Hugging Face.
  - Memproses seluruh dokumen per kalimat/klausul melalui work queue serial dalam batch 12; hasil valid muncul secara incremental.
  - Menggunakan cache hasil relatif terhadap segmen/kandidat, rule pack deterministik, bounded repair satu kali, challenge terbatas untuk `REJECT`, circuit breaker, dan fallback aman.
  - Membuat maksimal tiga candidate lokal non-overlap per segmen dari rule engine dan glossary verified. Qwen hanya menilai satu candidate per call dan tidak boleh membuat replacement, sumber, atau candidate baru.
  - Menggunakan structured tool decision `submit_review(candidate_id, decision)` sebagai jalur utama. Parser enam baris lama dipertahankan hanya untuk kompatibilitas benchmark historis.
  - Melindungi angka, tenggat, modalitas, kondisi, pengecualian, identifier, dan defined terms dari perubahan yang tidak sah.
  - Menyediakan tiga mode Debug: baseline aturan deterministik, Hybrid dengan pemulihan terbatas, dan Qwen langsung untuk pembanding. Default Debug sementara adalah Hybrid + Qwen3.5 Base 4B.
  - Pada Hybrid, Qwen berfungsi sebagai confirmation/diagnostic; kegagalan model dapat dipulihkan melalui rule deterministik berisiko rendah, sedangkan `REJECT` eksplisit tidak diubah menjadi suggestion.
  - Menyediakan benchmark reproducible melalui work queue produksi untuk baseline, tiga generation profile Base 4B, cache rerun, Hybrid, thinking, dan cancellation.
  - Mendukung streaming internal, Cancel, Retry, dan pilihan thinking mode.
  - Menyediakan delapan dummy sample untuk smoke test perilaku awal, termasuk terminologi `Data Pribadi`.

## Arsitektur ringkas

```mermaid
flowchart LR
    App[AMTApp]
    App --> Dashboard[DashboardView]
    Dashboard --> Docs[DocumentStorageManager\nDashboardDocument]
    Dashboard --> Dictionary[DictionaryView]
    Dictionary --> Store[LegalDictionaryStore]
    Store --> CSV[kamus_hukum.csv]
    Store --> LocalRAG[LocalRAG actor<br/>lexical BM25]
    LocalRAG --> LegacyCorpus[rag_export documents<br/>legacy]
    Dashboard --> Editor[DocumentEditorView]
    Editor --> AIView[AIConnectorDebugPanel<br/>(Debug only)]
    AIView --> VM[AIConnectorViewModel]
    VM --> Queue[Document-wide work queue<br/>batch 12 • serial]
    Queue --> Processor[Shared segment processor]
    Processor --> Cache[(In-memory segment cache)]
    Processor --> Retrieval[Local BM25 glossary retrieval<br/>maks. 3 evidence]
    Retrieval --> CSV[kamus_hukum.csv]
    Processor --> Rules[Versioned deterministic rule pack]
    Rules --> Candidates[Candidate builder<br/>maks. 3 non-overlap]
    Retrieval --> Candidates
    Processor --> Candidates
    Candidates --> Service[QwenSuggestionService<br/>candidate judge]
    Service --> MLX[MLX Swift + Qwen]
    MLX --> ToolParser[submit_review tool parser]
    ToolParser --> Decision[ACCEPT / REJECT / NEEDS_REVIEW]
    Decision --> Validator[Expanded safety validator]
    Candidates --> Validator
    Rules --> Resolver[Conflict resolver ≤3 non-overlap]
    Validator --> Resolver
    Service --> Repair[One bounded format repair]
    Repair --> ToolParser
    Service --> Challenge[One REJECT challenge]
    Challenge --> ToolParser
    Processor --> Fallback[Deterministic fallback]
    Fallback --> Resolver
    Resolver --> VM
    VM --> AIView
    VM --> Editor[Inline highlights + popover]
    VM --> Benchmark[Fixture benchmark + expected signal]
    Processor -. prepared, not connected .-> Tools[Typed local tools]
    MLX -. candidate-only; no tool retrieval .-> Tools
```

`AMTApp` membuat `QwenSuggestionService` dan `LegalDictionaryStore`, lalu meneruskannya secara eksplisit ke view yang membutuhkan. ViewModel memiliki satu processor dan queue selama lifecycle editor. Queue menjalankan seluruh segmen secara serial sehingga model container tidak menerima generation bersamaan; hasil tiap segmen dapat langsung dipetakan menjadi highlight. Kode baru dikelompokkan berdasarkan fitur, sedangkan model dokumen dan storage dashboard masih berada pada boundary yang digunakan project saat ini.

## Cara kerja Dictionary

Dictionary saat ini bukan chatbot dan tidak menggunakan semantic embedding. Entry CSV utama dimuat sebagai index immutable, sedangkan corpus `rag_export` dimuat dan dicari melalui actor `LocalRAG` agar I/O serta ranking corpus tidak memblokir MainActor. Kedua sumber digabungkan menggunakan lexical BM25 dan exact-term boost. File vector lama tidak dibaca sampai AMT memiliki model serta tokenizer BGE-M3 yang kompatibel dan tervalidasi.

Urutan prioritas pencarian adalah:

1. Istilah sama persis, lalu prefix dan substring istilah.
2. Kecocokan frasa pada pengertian.
3. Skor BM25 token istilah dan pengertian.
4. Entry verified untuk duplicate term.
5. Corpus CSV utama untuk tie antara dua entry legacy.

Pencarian mengabaikan perbedaan huruf besar-kecil, diakritik, dan spasi berlebih. Hasil dibatasi hingga 30 entry. Regex hanya digunakan untuk merapikan whitespace, bukan sebagai mesin pencarian semantik.

Format utama CSV yang digunakan:

```text
istilah,pengertian,undang_undang,uu,url,status
```

Entry dengan `status=VERIFIED` menjadi evidence yang dapat dipakai sebagai candidate terminology. Entry `status=OK` atau status kosong dipertahankan sebagai corpus legacy untuk pencarian/diagnostics, tetapi tidak actionable dan tidak dapat menghasilkan highlight atau Accept. Semua entry dari `rag_export` juga diperlakukan sebagai legacy. Status lain dilewati. Jika resource CSV tidak dapat dimuat, aplikasi menggunakan beberapa entry preview agar layar Dictionary tetap dapat dibuka; entry preview tetap legacy dan ditandai perlu verifikasi sumber.

## Cara kerja Suggestion

Suggestion menggunakan prompt sederhana untuk meninjau ejaan, tata bahasa, kejelasan, dan konsistensi istilah tanpa mengubah makna hukum. Dokumen dipecah per kalimat/klausul, lalu seluruh segmen dimasukkan ke work queue dengan batch persiapan 12 dan eksekusi serial. Untuk setiap segmen, rule engine dan BM25 lokal mengumpulkan evidence, lalu candidate builder memilih paling banyak tiga proposal non-overlap. Candidate berasal sepenuhnya dari aplikasi; model tidak digunakan sebagai sumber hukum dan tidak diberi kewenangan membuat replacement baru.

Pada panel Debug, strategi **Baseline aman** tidak mengunduh model dan hanya
menjalankan koreksi dari rule pack serta evidence glossary verified. Strategi
**Hybrid: model + guard** mengirim satu candidate per generation kepada Qwen.
Keputusan tool yang malformed dan recoverable mendapat tepat satu repair dengan
evidence yang sama. `REJECT` yang valid mendapat satu challenge, tetapi reject
akhir tidak menjadi fallback suggestion. Jika model gagal secara non-recoverable,
Hybrid hanya memulihkan rule deterministik berisiko rendah; terminology tetap
memerlukan glossary verified dan keputusan `ACCEPT` dari model. Setelah tiga
kegagalan dari empat segmen pertama yang memiliki candidate, circuit breaker
melewati Qwen untuk sisa run.

Strategi **Qwen langsung** dipakai untuk mengukur keputusan model tanpa fallback;
hanya `ACCEPT` yang dapat menjadi suggestion dan semua candidate tetap divalidasi
oleh aplikasi. Qwen menerima satu tool `submit_review` dengan dua field:
`candidate_id` dan `decision` (`ACCEPT`, `REJECT`, atau `NEEDS_REVIEW`). Original,
replacement, alasan, dan referensi berasal dari candidate/rule/glossary lokal.
Output biasa, reasoning, template marker, tool call ganda, atau token-limit hit
tidak menjadi suggestion. Parser enam baris tetap tersedia untuk benchmark lama,
tetapi bukan jalur utama candidate-first. Unit test tidak mengunduh atau
menjalankan model.

Guard retrieval saat ini bersifat provisional untuk integrasi awal: kandidat non-exact harus memiliki skor BM25 minimal `20`, sedikitnya `4` token definisi yang cocok, dan margin minimal `3` terhadap kandidat berbeda berikutnya. Paling banyak tiga match dikirim ke candidate builder, tetapi hanya entry verified yang dapat menjadi terminology candidate actionable. Istilah multi-kata yang muncul langsung di teks dapat lolos sebagai direct term match untuk pencarian, bukan otomatis menjadi replacement. Guard ini bukan confidence hukum dan belum menggantikan review sumber resmi.

Konfigurasi penting saat ini:

| Komponen | Nilai |
| --- | --- |
| Model utama Debug | `mlx-community/Qwen3.5-4B-MLX-4bit` |
| Revision model utama | `32f3e8ecf65426fc3306969496342d504bfa13f3` |
| Ukuran download model utama | sekitar 3,1 GB |
| Model pembanding Legal 4B | `morpknight/qwen3.5-4b-indonesian-legal-mlx-4bit` |
| Revision Legal 4B | `2517cc7962517b85d97aff8988785cdb02c8fea1` |
| Ukuran download Legal 4B | sekitar 2,39 GB |
| Model baseline historis | `mlx-community/Qwen3.5-2B-4bit` |
| Revision baseline historis | `674aaa7240b91e8012fcad5d791b7dfe5ba90207` |
| Input target | Maksimal 512 token per segmen |
| Konteks | Satu segmen sebelum dan sesudah, maksimal 128 token masing-masing |
| Segmentasi / queue | Seluruh dokumen; queue disiapkan dalam batch 12 dan dieksekusi serial |
| Segmen terlalu panjang | >512 token ditandai dan dilewati tanpa dipotong |
| Rule pack | `rule-pack-v1`, hanya rule berstatus `active` |
| Cache | In-memory, key SHA-256 mencakup model/prompt/schema/rule/corpus/validator |
| Candidate per segmen | Maksimal 3 candidate lokal non-overlap; satu candidate per model call |
| Candidate tool | `submit_review(candidate_id, decision)` |
| Default non-thinking profile | `greedy`: 128 token, `temperature=0`, `top-p=1`, `top-k=0`, tanpa penalty |
| Benchmark profile lain | `low-variance` dan `official-instruct` |
| Output thinking | Maksimal 512 token pada candidate-first; tetap eksperimen |
| Thinking default | Off |
| Generation | Streaming internal, hasil ditahan sampai tervalidasi, dan dapat dibatalkan |

Model tidak dibundel ke repository. Pada penggunaan pertama, aplikasi membutuhkan koneksi internet untuk mengunduh model. Setelah itu, model digunakan dari cache lokal. Teks dokumen tidak dikirim ke API LLM eksternal oleh implementasi ini.

## Persyaratan

- macOS dengan environment Xcode yang mendukung target project `macOS 26.5`.
- Xcode dan Git.
- Mac Apple Silicon direkomendasikan untuk menjalankan Suggestion dengan MLX.
- Koneksi internet pada penggunaan pertama Suggestion untuk mengunduh model. Hanya konfigurasi Debug yang mengaktifkan outbound network; Release tetap tanpa izin tersebut.

Dependency Swift yang dipin dan disimpan pada `AMT.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`:

- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) `3.31.4`
- [swift-huggingface](https://github.com/huggingface/swift-huggingface) `0.9.0`
- [swift-transformers](https://github.com/huggingface/swift-transformers) `1.3.3`

Produk yang digunakan target AMT adalah `MLXLLM`, `MLXLMCommon`, `MLXHuggingFace`, `HuggingFace`, dan `Tokenizers`.

## Menjalankan aplikasi

1. Clone repository:

   ```bash
   git clone https://github.com/MorpKnight/AMT.git
   cd AMT
   ```

2. Buka `AMT.xcodeproj` dengan Xcode.
3. Pilih scheme `AMT` dan destination macOS.
4. Jalankan dengan `⌘R`.
5. Pilih **Dictionary** pada sidebar untuk mencari istilah atau pengertian.
6. Pilih dokumen pada dashboard untuk membuka editor.
7. Pada panel **Suggestion — Eksperimental** (Debug), pilih sumber input, opsional pilih dummy sample, lalu tekan **Jalankan review** untuk seluruh dokumen/fixture. Tombol sparkles pada toolbar juga memulai analisis dokumen aktif; panel Debug tersedia dari menu opsi.
8. Untuk membandingkan kualitas, pilih strategi dan model, lalu tekan **Benchmark 8 fixture**. Hasil benchmark hanya evaluasi Debug dan tidak mengubah dokumen.

Panel menampilkan jumlah segmen, batch queue, progress seluruh dokumen, cache, repair, fallback, hasil yang lolos validator, hasil yang memerlukan review manusia, dan output yang ditolak. Preview Current Document dibatasi ke 4.000 karakter pertama, tetapi analisis memakai seluruh isi dokumen dan panel memberi indikator jika preview terpotong. Tidak ada hasil yang diterapkan otomatis ke dokumen; highlight dapat ditinjau melalui popover editor dan Accept tetap merupakan aksi pengguna.

Dashboard juga selalu menampilkan **AI Connector — Test Document**. Dokumen ini memuat contoh redundansi, typo, istilah hukum, preservasi angka, tanggal, mata uang, persentase, defined terms, negasi, pengecualian, terminologi campuran, dan klausul sensitif. Isinya sengaja lebih dari 12 segmen agar pembentukan batch `12/12/...` dan hasil incremental dapat diuji; segmen >512 token diuji terpisah. Dokumen dapat diedit untuk pengujian, tetapi akan kembali ke isi awal ketika aplikasi dijalankan ulang.

Pada Run atau benchmark model pertama, tunggu proses download dan loading model selesai. Run berikutnya menggunakan cache Hugging Face lokal selama cache masih tersedia. Cache Qwen3.5 2B, Legal 4B, dan base 4B tetap terpisah untuk perbandingan historis.

## Build dari command line

Gunakan DerivedData di luar repository dan nonaktifkan code signing untuk validasi lokal:

```bash
xcodebuild \
  -project AMT.xcodeproj \
  -scheme AMT \
  -configuration Debug \
  -sdk macosx \
  -arch arm64 \
  -derivedDataPath /tmp/amt-build-debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Untuk memvalidasi Release, ganti `Debug` menjadi `Release` dan gunakan DerivedData berbeda, misalnya `/tmp/amt-build-release`.

Pemeriksaan whitespace yang tersedia:

```bash
git diff --check
```

Jalankan unit test deterministic dengan target `AMTTests`:

```bash
xcodebuild \
  -project AMT.xcodeproj \
  -scheme AMT \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/amt-tests \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Unit test mencakup segmentasi, retrieval BM25, parser, safety validator, generation diagnostics, report encoding, dan quality-gate calculation. Download model dan evaluasi output Qwen tetap merupakan benchmark opt-in; test reguler tidak menyentuh model.

Benchmark P0.11 yang mengunduh atau memuat model dapat dijalankan hanya bila
memang diinginkan. Default-nya Base 4B (`qwen35-base-4b`). Benchmark ini
membandingkan profile `greedy`, `low-variance`, dan `official-instruct`, lalu
menjalankan cache rerun, Hybrid, satu thinking run, dan cancellation smoke test.
Gunakan `AMT_P011_MODEL_VARIANT=qwen35-legal-4b` hanya untuk membandingkan model
domain. Pada Xcode 26, `xcodebuild` hanya meneruskan environment ke proses
XCTest jika nama variabel diberi prefix `TEST_RUNNER_`; prefix tersebut dilepas
oleh test runner sebelum dibaca oleh test:

```bash
TEST_RUNNER_AMT_RUN_P011_MODEL_BENCHMARK=1 \
TEST_RUNNER_AMT_P011_MODEL_VARIANT=qwen35-base-4b \
TEST_RUNNER_AMT_P011_REPORT_PATH=/private/tmp/amt-p011-base-4b.json \
xcodebuild \
  -project AMT.xcodeproj \
  -scheme AMT \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/AMT-P011-DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:AMTTests/AIConnectorModelBenchmarkTests \
  test
```

Report benchmark memuat diagnosis per sample dan per candidate: sumber
candidate, keputusan Qwen, origin final, attempt/repair/challenge, fallback,
token/durasi, stop reason, repetition ratio, rejection class, dan quality gate.
Reasoning, source claim, raw tool output, dan output berbahaya tidak ditulis ke
report. Entry glossary test yang verified dipasang terpisah dari corpus produksi
agar fixture terminology dapat diuji tanpa menganggap corpus legacy mutakhir.
Quality gate model hanya berlaku pada run `modelOnly` yang benar-benar berisi
record `modelOnly`. Run Hybrid dan deterministic tetap melaporkan utility akhir,
jumlah hasil asal model, serta fallback secara terpisah dan tidak dapat memperoleh
status GO model. Benchmark tidak mengubah dokumen dan hasilnya belum otomatis
mengaktifkan Release/TestFlight.

## Struktur project

```text
AMT/
├── AMTApp.swift
├── Dashboard/
│   ├── Models/
│   ├── Services/
│   └── Views/
├── Dictionary/
│   ├── Resources/
│   ├── Services/
│   └── Views/
├── Features/AIConnector/
│   ├── Models/
│   ├── Services/
│   ├── ViewModels/
│   └── Views/
├── Suggestion/Views/
├── Components/Sidebar/
└── Info.plist
```

## Batasan MVP

- Pencarian Dictionary menggunakan lexical BM25; belum mendukung typo correction, stemming, sinonim, atau semantic retrieval. Semantic BGE-M3 gagal secara tertutup sampai model dan tokenizer yang cocok tersedia.
- Suggestion sekarang memiliki highlight inline dan popover dengan Accept/Dismiss; tidak ada auto-rewrite tanpa aksi pengguna.
- Thinking mode pada model kecil dapat berhenti sebelum jawaban final; aplikasi akan menampilkan error dan menyarankan non-thinking mode.
- P0.8 memperkuat baseline deterministik dan benchmark Hybrid/Qwen, tetapi belum meluluskan Qwen-only untuk suggestion cards atau TestFlight.
- P0.9 menguji model Legal 4B dengan metrik generation dan quality gate reproducible. Release/TestFlight tetap tidak mengaktifkan networking atau tombol analisis pada tahap ini.
- P0.10 menambahkan document-wide work queue, cache segment-relative, bounded repair, circuit breaker, rule pack, multi-suggestion internal, conflict resolver, safety protection context, serta typed local-tool boundary yang belum dihubungkan ke model.
- P0.11 mengubah jalur utama menjadi candidate-first: rule/retrieval lokal membuat maksimal tiga candidate, Qwen memilih melalui structured `submit_review`, lalu safety validator dan conflict resolver menentukan hasil yang dapat ditampilkan. Profile benchmark dan candidate-level diagnostics tersedia, tetapi Qwen-only belum menjadi jalur produksi.
- Editor saat ini menyimpan teks biasa. Toolbar formatting masih berupa prototype dan belum menyimpan rich-text formatting.
- Import `.docx`/`.doc` berfokus pada ekstraksi teks; export kembali ke `.docx` belum tersedia.
- Dataset dan output model belum membuktikan ketepatan hukum. Kasus ambigu atau berdampak pada hak dan kewajiban harus diperlakukan sebagai `needs review` oleh manusia.

## Arah pengembangan berikutnya

1. Evaluasi Dictionary dengan query istilah, pengertian, typo, dan paraphrase yang direview manusia.
2. Kalibrasikan kembali guard BM25 dengan source review manusia pada corpus yang lebih luas.
3. Hubungkan retrieval Dictionary dengan suggestion cards setelah candidate generation lolos decision gate.
4. Pisahkan hasil grammar, istilah, dan isu substantif dengan status review yang jelas.
5. Pertahankan catatan benchmark historis Qwen3.5 2B, Qwen3 4B, dan Legal 4B di luar source tree jika diperlukan untuk evaluasi lanjutan.
6. Uji presisi rule pack pada corpus nyata dan siapkan corpus glossary mutakhir sebelum local tools atau evidence-aware retrieval diberikan kepada model.
7. Tinjau report P0.11 pada holdout synthetic set dan benchmark Base 4B sebelum memilih profile/prompt final; jangan melakukan tuning terhadap fixture gate yang sama.
8. Jika Qwen-only belum memenuhi quality gate, pertahankan Hybrid + fallback deterministik dan evaluasi model/rule engine berikutnya pada fixture yang sama.

## Referensi teknis

- [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm)
- [Swift Hugging Face](https://github.com/huggingface/swift-huggingface)
- [Swift Transformers](https://github.com/huggingface/swift-transformers)
- [Qwen3.5 model card](https://huggingface.co/Qwen/Qwen3.5-2B)
- Sumber setiap entry Dictionary ditentukan oleh kolom `url` pada `kamus_hukum.csv`.
