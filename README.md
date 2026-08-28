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
  - Mencari berdasarkan istilah atau bagian dari pengertian.
  - Menampilkan pengertian, peraturan, judul peraturan, dan tautan sumber jika tersedia.
- **Suggestion eksperimental**
  - Meninjau teks dokumen menggunakan `morpknight/qwen3.5-4b-indonesian-legal-mlx-4bit` melalui MLX Swift.
  - Inferensi berjalan lokal setelah model selesai diunduh dan disimpan di cache Hugging Face.
  - Memproses dokumen per kalimat/klausul, kemudian mengambil maksimal satu kandidat glossary lokal melalui guard BM25 konservatif.
  - Memvalidasi output model dengan kontrak tagged fields sebelum menampilkannya.
  - Melindungi angka, tenggat, modalitas, dan defined terms dari perubahan yang tidak sah.
  - Menyediakan tiga mode Debug: baseline aturan deterministik, Hybrid dengan pemulihan terbatas, dan Qwen langsung untuk pembanding. Default Debug adalah Hybrid + Legal 4B.
  - Jika output Qwen ditolak pada mode Hybrid, koreksi bahasa berisiko rendah atau no-suggestion yang aman dapat dipulihkan; klausul lain tetap ditahan.
  - Menyediakan benchmark reproducible untuk baseline, Legal 4B Qwen-only, dan Hybrid; Qwen3.5 2B tetap tersedia sebagai baseline historis.
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
    Dashboard --> Editor[DocumentEditorView]
    Editor --> AIView[AIConnectorDebugPanel<br/>(Debug only)]
    AIView --> VM[AIConnectorViewModel]
    VM --> Retrieval[Local BM25 glossary retrieval]
    Retrieval --> CSV[kamus_hukum.csv]
    VM --> Rules[Deterministic bounded rules]
    VM --> Service[QwenSuggestionService<br/>(Hybrid / Qwen langsung)]
    Service --> MLX[MLX Swift + Qwen]
    Service --> Parser[Tagged output parser]
    Parser --> Validator[Safety validator]
    Rules --> Validator
    Validator --> AIView
    VM --> Benchmark[Fixture benchmark + expected signal]
    Benchmark --> AIView
```

`AMTApp` membuat `QwenSuggestionService` dan `LegalDictionaryStore`, lalu meneruskannya secara eksplisit ke view yang membutuhkan. Kode baru dikelompokkan berdasarkan fitur, sedangkan model dokumen dan storage dashboard masih berada pada boundary yang digunakan project saat ini.

## Cara kerja Dictionary

Dictionary saat ini bukan chatbot, bukan RAG, dan tidak menggunakan embedding. Semua entry CSV dimuat ke memori ketika aplikasi dimulai, kemudian query dinormalisasi dan dicocokkan secara deterministik.

Urutan prioritas pencarian adalah:

1. Istilah sama persis.
2. Istilah diawali query.
3. Istilah mengandung query.
4. Pengertian mengandung query.
5. Ada token query yang cocok dengan istilah atau pengertian.

Pencarian mengabaikan perbedaan huruf besar-kecil, diakritik, dan spasi berlebih. Hasil dibatasi hingga 30 entry. Regex hanya digunakan untuk merapikan whitespace, bukan sebagai mesin pencarian semantik.

Format utama CSV yang digunakan:

```text
istilah,pengertian,undang_undang,uu,url,status
```

Entry dengan `status` selain `OK` dilewati. Jika resource CSV tidak dapat dimuat, aplikasi menggunakan beberapa entry preview agar layar Dictionary tetap dapat dibuka.

## Cara kerja Suggestion

Suggestion menggunakan prompt sederhana untuk meninjau ejaan, tata bahasa, kejelasan, dan konsistensi istilah tanpa mengubah makna hukum. Dokumen dipecah per kalimat/klausul. Untuk setiap segmen, aplikasi menjalankan BM25 lokal atas target segmen untuk mencari maksimal satu kandidat yang kuat dan tidak ambigu. Model tidak digunakan sebagai sumber hukum.

Pada panel Debug, strategi **Baseline aman** tidak mengunduh model dan hanya
menjalankan koreksi deterministik yang sudah dibatasi. Strategi **Hybrid: model
+ guard** mencoba Qwen terlebih dahulu, kemudian hanya memulihkan output yang
ditolak jika ada koreksi deterministik yang eksplisit dan berisiko rendah.
Strategi **Qwen langsung** dipakai untuk membandingkan kepatuhan format dan
kualitas model tanpa pemulihan. Tombol benchmark menjalankan seluruh delapan
fixture secara berurutan; unit test tidak mengunduh atau menjalankan model.

Model diwajibkan menghasilkan enam tagged fields (`STATUS`, `CATEGORY`, `ORIGINAL`, `REPLACEMENT`, `GLOSSARY_ID`, dan `REASON`). Output ditahan di memori sampai parser dan safety validator memeriksa bahwa bagian asli unik, replacement aman, angka serta istilah terproteksi tetap sama, dan tidak ada klaim sumber hukum baru. Output yang gagal pemeriksaan ditolak dan tidak menjadi saran.

Guard retrieval saat ini bersifat provisional untuk integrasi awal: kandidat non-exact harus memiliki skor BM25 minimal `20`, sedikitnya `4` token definisi yang cocok, dan margin minimal `3` terhadap kandidat berbeda berikutnya. Istilah multi-kata yang muncul langsung di teks dapat lolos sebagai direct term match. Guard ini bukan confidence hukum dan belum menggantikan review sumber resmi.

Konfigurasi penting saat ini:

| Komponen | Nilai |
| --- | --- |
| Model utama Debug | `morpknight/qwen3.5-4b-indonesian-legal-mlx-4bit` |
| Revision model utama | `2517cc7962517b85d97aff8988785cdb02c8fea1` |
| Ukuran download model utama | sekitar 2,39 GB |
| Model baseline Debug | `mlx-community/Qwen3.5-2B-4bit` |
| Revision baseline | `674aaa7240b91e8012fcad5d791b7dfe5ba90207` |
| Input target | Maksimal 512 token per segmen |
| Konteks | Satu segmen sebelum dan sesudah, maksimal 128 token masing-masing |
| Segmen per Run | Maksimal 12 segmen |
| Output non-thinking Legal 4B | Maksimal 256 token, greedy (`temperature=0`) |
| Output non-thinking baseline 2B | Maksimal 256 token, `temperature=0.2`, `top-p=0.9`, `top-k=20` |
| Output thinking | Maksimal 768 token |
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
7. Pada panel **Suggestion — Eksperimental** (Debug), pilih sumber input, opsional pilih dummy sample, lalu tekan **Jalankan review** untuk satu dokumen/fixture.
8. Untuk membandingkan kualitas, pilih strategi dan model, lalu tekan **Benchmark 8 fixture**. Hasil benchmark hanya evaluasi Debug dan tidak mengubah dokumen.

Panel menampilkan jumlah segmen, progress kalimat, hasil yang lolos validator, hasil yang memerlukan review manusia, dan output yang ditolak. Current Document dibatasi ke 4.000 karakter pertama dan panel memberi indikator jika terpotong. Tidak ada hasil yang diterapkan otomatis ke dokumen.

Dashboard juga selalu menampilkan **AI Connector — Test Document**. Dokumen ini memuat contoh redundansi, typo, istilah hukum, preservasi angka, tanggal, mata uang, persentase, defined terms, negasi, pengecualian, terminologi campuran, dan klausul sensitif. Isinya sengaja lebih dari batas 12 segmen agar indikator segmen yang dilewati juga dapat diuji. Dokumen dapat diedit untuk pengujian, tetapi akan kembali ke isi awal ketika aplikasi dijalankan ulang.

Pada Run atau benchmark model pertama, tunggu proses download dan loading Legal 4B selesai. Run berikutnya menggunakan cache Hugging Face lokal selama cache masih tersedia. Cache Qwen3.5 2B tidak dihapus dan tetap terpisah untuk perbandingan historis.

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

Benchmark P0.9 yang mengunduh model Legal 4B dapat dijalankan hanya bila memang
diinginkan. Pada Xcode 26, `xcodebuild` hanya meneruskan environment ke proses
XCTest jika nama variabel diberi prefix `TEST_RUNNER_`; prefix tersebut dilepas
oleh test runner sebelum dibaca oleh test:

```bash
TEST_RUNNER_AMT_RUN_P09_MODEL_BENCHMARK=1 \
TEST_RUNNER_AMT_P09_REPORT_PATH=/private/tmp/amt-p09-legal-4b.json \
xcodebuild \
  -project AMT.xcodeproj \
  -scheme AMT \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/AMT-P09-DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:AMTTests/AIConnectorModelBenchmarkTests \
  test
```

Report benchmark memuat output diagnosis yang sudah di-redact, candidate
glossary, status parser/validator, origin fallback, token/durasi, stop reason,
repetition ratio, dan keputusan quality gate. Model reasoning tidak ditulis ke
report. Pada runtime Legal 4B saat ini, Qwen-only memperoleh `0/8`, Hybrid
`7/8` dengan fallback deterministik, dan quality gate tetap `NO_GO` karena
format output serta repetition; detail evidence ada di
[`docs/p0.9-legal-model-validation.md`](docs/p0.9-legal-model-validation.md).

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

- Pencarian Dictionary masih menggunakan lexical search; belum mendukung typo correction, stemming, sinonim, atau semantic retrieval. Candidate generation untuk Suggestion sudah memakai BM25 provisional, tetapi belum menjadi ranking final Dictionary.
- Suggestion belum menghasilkan suggestion cards dengan accept/reject dan belum mengubah isi dokumen.
- Thinking mode pada model kecil dapat berhenti sebelum jawaban final; aplikasi akan menampilkan error dan menyarankan non-thinking mode.
- P0.8 memperkuat baseline deterministik dan benchmark Hybrid/Qwen, tetapi belum meluluskan Qwen-only untuk suggestion cards atau TestFlight.
- P0.9 menguji model Legal 4B dengan metrik generation dan quality gate reproducible. Hasil final berada di `docs/p0.9-legal-model-validation.md`; Release/TestFlight tetap tidak mengaktifkan networking atau tombol analisis pada tahap ini.
- Editor saat ini menyimpan teks biasa. Toolbar formatting masih berupa prototype dan belum menyimpan rich-text formatting.
- Import `.docx`/`.doc` berfokus pada ekstraksi teks; export kembali ke `.docx` belum tersedia.
- Dataset dan output model belum membuktikan ketepatan hukum. Kasus ambigu atau berdampak pada hak dan kewajiban harus diperlakukan sebagai `needs review` oleh manusia.

## Arah pengembangan berikutnya

1. Evaluasi Dictionary dengan query istilah, pengertian, typo, dan paraphrase yang direview manusia.
2. Kalibrasikan kembali guard BM25 dengan source review manusia pada corpus yang lebih luas.
3. Hubungkan retrieval Dictionary dengan suggestion cards setelah candidate generation lolos decision gate.
4. Pisahkan hasil grammar, istilah, dan isu substantif dengan status review yang jelas.
5. Hasil benchmark historis Qwen3.5 2B dan Qwen3 4B tercatat di `docs/p0.8-quality-remediation.md`; hasil Legal 4B dicatat di `docs/p0.9-legal-model-validation.md`.
6. Jika Qwen-only belum memenuhi quality gate, pertahankan Hybrid + fallback deterministik dan evaluasi model/rule engine berikutnya pada fixture yang sama.

## Referensi teknis

- [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm)
- [Swift Hugging Face](https://github.com/huggingface/swift-huggingface)
- [Swift Transformers](https://github.com/huggingface/swift-transformers)
- [Qwen3.5 model card](https://huggingface.co/Qwen/Qwen3.5-2B)
- Sumber setiap entry Dictionary ditentukan oleh kolom `url` pada `kamus_hukum.csv`.
