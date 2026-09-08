<p align="center">
  <img src="AMT/Assets.xcassets/logo_black.imageset/Lawtionary%20Logo%20Black.png" alt="Logo Lawtionary" width="112">
</p>

<h1 align="center">Lawtionary (AMT)</h1>

<p align="center">
  Aplikasi macOS untuk membantu membaca draft dokumen dan menelusuri istilah hukum Indonesia.
</p>

Lawtionary memiliki dua MVP yang saling melengkapi:

- <strong>Document</strong> untuk mengimpor, membaca, mengedit, meninjau saran, dan mengekspor draft.
- <strong>Dictionary</strong> untuk mencari istilah hukum, definisi, serta dasar dan konteks sumbernya.

> [!WARNING]
> Lawtionary adalah alat bantu kerja dan masih berada pada tahap MVP. Aplikasi ini bukan pemberi nasihat hukum, tidak menyatakan sebuah dokumen sudah benar secara hukum, dan tidak mengubah isi dokumen tanpa keputusan pengguna. Semua hasil tetap harus diperiksa oleh profesional yang berwenang.

## Daftar isi

- [Dua MVP utama](#dua-mvp-utama)
- [MVP 1 — Document](#mvp-1--document)
- [MVP 2 — Dictionary](#mvp-2--dictionary)
- [Penyimpanan lokal dan penggunaan yang aman](#penyimpanan-lokal-dan-penggunaan-yang-aman)
- [Menjalankan aplikasi](#menjalankan-aplikasi)
- [Untuk pengembang](#untuk-pengembang)
- [Dokumen lanjutan](#dokumen-lanjutan)

## Dua MVP utama

| MVP | Tujuan sederhana | Hasil yang pengguna lihat |
| --- | --- | --- |
| Document | Membuka draft di satu tempat untuk diedit dan ditinjau. | Dokumen kerja, penanda bagian yang perlu diperiksa, pilihan menerima atau mengabaikan saran, lalu ekspor Word. |
| Dictionary | Menemukan arti istilah hukum berdasarkan kamus yang disertakan aplikasi. | Definisi utama, konteks sumber atau regulasi bila tersedia, serta istilah terkait. |

Kedua fitur dipisahkan dengan sengaja. Dictionary berfokus pada informasi istilah yang memiliki bukti sumber, sedangkan Document berfokus pada draft pengguna dan keputusan review manusia.

## MVP 1 — Document

Fitur Document adalah ruang kerja untuk draft yang sudah dimiliki pengguna. Pengguna dapat mengimpor file <code>.docx</code>, <code>.doc</code>, <code>.rtf</code>, <code>.md</code>, <code>.markdown</code>, atau <code>.txt</code> dari Finder.

AMT membuat salinan kerja lokal, memeriksa apakah file atau isi yang sama sudah pernah diimpor, lalu membuka dokumen di editor. Di dalam editor, pengguna dapat mengubah teks dan format dasar, membaca saran yang ditandai, melihat alasan atau sumber pendukung bila ada, kemudian memilih sendiri tindakan yang tepat.

### Alur kerja Document

~~~mermaid
flowchart TD
    A["Pilih tab Document"] --> B["Impor file dari Finder"]
    B --> C{"Isi file dapat dibaca?"}
    C -- "Tidak" --> X["Tampilkan pesan bahwa impor gagal"]
    C -- "Ya" --> D{"File atau isi yang sama sudah ada?"}
    D -- "Ya" --> E["Arahkan pengguna ke dokumen yang sudah tersimpan"]
    D -- "Tidak" --> F["Simpan salinan kerja secara lokal"]
    F --> G["Buka dokumen di editor"]
    G --> H["AMT menandai bagian yang mungkin perlu diperiksa"]
    H --> I["Pengguna membaca saran dan bukti yang tersedia"]
    I --> J{"Setujui perubahan?"}
    J -- "Ya" --> K["Terapkan perubahan pada editor"]
    J -- "Tidak atau belum yakin" --> L["Abaikan atau tandai sudah diperiksa"]
    K --> M["Simpan perubahan secara lokal"]
    L --> M
    M --> N["Ekspor hasil sebagai file Word (.docx)"]
~~~

Hal yang perlu diingat saat memakai Document:

- Saran adalah titik awal review, bukan perintah untuk mengubah dokumen.
- Pengguna dapat menerima, mengabaikan, atau menandai temuan sebagai sudah diperiksa.
- Jika isi dokumen diubah, hasil review lama dapat menjadi tidak relevan; jalankan pemeriksaan kembali sebelum mengandalkannya.
- Aplikasi tidak ditujukan untuk membuat kontrak dari nol, mengganti banyak bagian sekaligus, atau memutuskan akibat hukum suatu klausul.

## MVP 2 — Dictionary

Fitur Dictionary membantu pengguna mencari istilah hukum atau memasukkan uraian singkat untuk menemukan istilah yang relevan. Hasil yang ditampilkan berasal dari paket kamus berversi yang dibawa bersama aplikasi, bukan jawaban bebas seperti chatbot.

Untuk istilah yang pendek dan jelas, AMT hanya menampilkan hasil yang memiliki kecocokan kata di kamus. Jika tidak ada kecocokan yang cukup, aplikasi akan menyatakan istilah tidak ditemukan daripada memberi jawaban yang terdengar meyakinkan tetapi tidak berkaitan. Untuk uraian yang lebih panjang, aplikasi dapat memakai pencarian berdasarkan makna sebagai pelengkap.

### Alur kerja Dictionary

~~~mermaid
flowchart TD
    A["Pilih tab Dictionary"] --> B["Masukkan istilah atau uraian singkat"]
    B --> C["Cari di kamus Lawtionary"]
    C --> D{"Ada hasil dengan dasar yang cukup?"}
    D -- "Tidak" --> E["Tampilkan bahwa istilah belum ditemukan"]
    E --> F["Periksa ejaan atau gunakan istilah lain"]
    D -- "Ya" --> G["Tampilkan daftar hasil yang relevan"]
    G --> H["Pilih istilah yang ingin dibaca"]
    H --> I["Baca definisi utama dan konteksnya"]
    I --> J["Buka dasar hukum, sumber, atau istilah terkait bila tersedia"]
    J --> K["Gunakan sebagai bahan pemeriksaan profesional"]
~~~

Pada halaman detail, pengguna dapat menemukan definisi utama, definisi kontekstual bila ada, status atau riwayat regulasi, rujukan hukum, kutipan bukti yang terpetakan, dan istilah lain untuk ditelusuri. Tidak semua entri memiliki seluruh informasi tersebut.

> [!NOTE]
> Pencarian istilah yang singkat menggunakan pencarian lokal. Pencarian berdasarkan uraian yang lebih panjang dapat memerlukan pemuatan komponen pencarian tambahan pada penggunaan pertama.

## Penyimpanan lokal dan penggunaan yang aman

- Workspace Document disimpan secara lokal di <code>~/Documents/AMT_Documents</code>.
- File asli di lokasi awal tidak ditimpa. AMT menyimpan salinan kerja agar dokumen dapat dibuka dan dipulihkan dari workspace.
- Menghapus dokumen dari AMT hanya menghapus catatan workspace dan salinan kerja AMT; file asli di lokasi awal tetap ada.
- Beberapa fitur pemeriksaan berbantuan model dapat memerlukan unduhan komponen model pada penggunaan pertama. Unduhan model bukan bukti bahwa hasil review sudah benar secara hukum.
- Tidak ditemukannya istilah di Dictionary bukan berarti istilah tersebut tidak pernah ada dalam hukum. Itu berarti AMT belum memiliki hasil yang cukup tepat dari paket kamus aktif.

## Menjalankan aplikasi

### Kebutuhan

- macOS 26.5 atau lebih baru.
- Xcode 26.6, atau toolchain Xcode 26 yang kompatibel.
- Apple Silicon direkomendasikan bila ingin mencoba pemeriksaan berbantuan model.

### Membuka proyek

~~~sh
git clone https://github.com/MorpKnight/AMT.git
cd AMT
open AMT.xcodeproj
~~~

Di Xcode, pilih scheme <code>AMT</code>, pilih tujuan macOS, lalu jalankan aplikasi dengan <code>⌘R</code>.

### Mencoba kedua MVP

1. Pada tab Document, pilih kartu impor lalu pilih sebuah file yang didukung.
2. Buka dokumen hasil impor, edit bila perlu, dan tinjau saran secara satu per satu.
3. Ekspor versi kerja sebagai <code>.docx</code> setelah review selesai.
4. Pada tab Dictionary, cari istilah seperti <em>Data Pribadi</em>, atau tulis uraian dari istilah yang ingin ditemukan.
5. Baca definisi dan sumber yang tersedia sebelum menggunakannya dalam pekerjaan profesional.

## Untuk pengembang

### Peta proyek

~~~text
AMT/
├── Dashboard/                 # Impor, penyimpanan lokal, dan daftar dokumen
├── Suggestion/                # Editor rich-text dan tampilan review
├── Dictionary/                # Pencarian serta detail istilah hukum
├── Features/AIConnector/      # Pemeriksaan dokumen yang dibatasi dan dapat ditinjau
├── Shared/LegalKnowledge/     # Pembacaan corpus dan pencarian berbasis makna
├── Resources/legal_corpus/    # Paket kamus aktif beserta manifest versinya
└── AMTApp.swift               # Titik masuk aplikasi
AMTTests/                      # Test deterministik dan integrasi
Scripts/export_amt_legal_corpus.py
~~~

Corpus aktif dicatat dalam [manifest kamus](AMT/Resources/legal_corpus/manifest.json). Manifest tersebut menyimpan versi corpus, jumlah data, konfigurasi pencarian, serta hash untuk membantu memeriksa konsistensi paket data.

### Build dan test

Gunakan DerivedData di luar repository agar artefak build tidak masuk ke working tree.

~~~sh
validation_dir="$(mktemp -d /tmp/amt-build-validation.XXXXXX)"
xcodebuild \
  -project AMT.xcodeproj \
  -scheme AMT \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$validation_dir" \
  build \
  CODE_SIGNING_ALLOWED=NO
~~~

~~~sh
test_dir="$(mktemp -d /tmp/amt-test-validation.XXXXXX)"
xcodebuild \
  -project AMT.xcodeproj \
  -scheme AMT \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$test_dir" \
  test \
  CODE_SIGNING_ALLOWED=NO
~~~

~~~sh
git diff --check
~~~

Test reguler dirancang untuk berjalan tanpa mengunduh model Qwen. Benchmark model bersifat opt-in karena mengunduh model dan hanya menjadi bukti eksperimen, bukan bukti ketepatan hukum.

## Dokumen lanjutan

- [Audit produk Document](docs/document-product-audit-2026-09-08.md) menjelaskan kondisi saat ini, keterbatasan yang telah ditemukan, dan batas validasinya.
- [Rencana pengembangan Document](docs/document-future-development.md) adalah roadmap. Dokumen ini tidak berarti semua kemampuan yang tertulis di dalamnya sudah tersedia.
- [Aturan kerja repository](AGENTS.md) menjelaskan arsitektur, batas perubahan, dan perintah validasi proyek.
