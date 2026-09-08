# Future Development — Document Review

> Status: Proposed roadmap
>
> Scope: fitur Document pada aplikasi AMT
>
> Baseline: implementasi Phase 0 sampai Phase 2 pada branch gi/model-improvement
>
> Last updated: 6 September 2026

Dokumen ini menjelaskan arah pengembangan fitur Document setelah Phase 0,
Phase 1, dan Phase 2. Dokumen ini adalah acuan produk, arsitektur, implementasi,
pengujian, dan legal-domain review. Ia bukan bukti bahwa seluruh kemampuan yang
ditulis di sini sudah tersedia.

AMT memosisikan Document sebagai ruang untuk memvalidasi draft yang telah dibuat
oleh pengguna. AMT tidak dirancang untuk membuat kontrak dari awal, memberikan
kesimpulan hukum, atau menggantikan keputusan seorang lawyer.

## Contents

- [1. Tujuan dan prinsip produk](#1-tujuan-dan-prinsip-produk)
- [2. Baseline sistem saat ini](#2-baseline-sistem-saat-ini)
- [3. Keputusan desain dari diskusi](#3-keputusan-desain-dari-diskusi)
- [4. Target alur pemrosesan Document](#4-target-alur-pemrosesan-document)
- [5. Grup A — Fondasi dokumen](#5-grup-a--fondasi-dokumen)
- [6. Grup B — Deteksi dan pengambilan keputusan](#6-grup-b--deteksi-dan-pengambilan-keputusan)
- [7. Grup C — Review UI dan interaksi](#7-grup-c--review-ui-dan-interaksi)
- [8. Grup D — Persistence, cache, dan performa](#8-grup-d--persistence-cache-dan-performa)
- [9. Grup E — Privacy, observability, dan governance](#9-grup-e--privacy-observability-dan-governance)
- [10. Rancangan model dan boundary MVVM](#10-rancangan-model-dan-boundary-mvvm)
- [11. Urutan implementasi](#11-urutan-implementasi)
- [12. Strategi pengujian](#12-strategi-pengujian)
- [13. Metrik dan quality gate](#13-metrik-dan-quality-gate)
- [14. Batasan dan non-goals](#14-batasan-dan-non-goals)
- [15. Definition of Done](#15-definition-of-done)
- [16. Referensi source code saat ini](#16-referensi-source-code-saat-ini)

## 1. Tujuan dan prinsip produk

### 1.1 Peran fitur Document

Fitur Document membantu corporate lawyer atau legal reviewer untuk:

1. Mengimpor draft yang sudah dibuat.
2. Menemukan masalah bahasa yang dapat dibuktikan secara lokal.
3. Memeriksa konsistensi istilah dan defined term.
4. Membandingkan definisi dalam draft dengan corpus hukum yang terverifikasi.
5. Menemukan bagian yang berpotensi memerlukan pertimbangan hukum.
6. Memeriksa evidence dan sumber sebelum menerima perubahan.
7. Menyimpan dan mengekspor hasil review tanpa mengirim dokumen ke layanan AI
   eksternal.

### 1.2 Batas produk yang tidak boleh berubah

- Dokumen dan inference utama tetap berada di perangkat pengguna.
- Tidak ada perubahan yang diterapkan tanpa tindakan eksplisit pengguna.
- Qwen bukan sumber kebenaran hukum.
- Qwen tidak boleh mengarang replacement, istilah, definisi, atau sumber hukum.
- RAG dan filter corpus dimiliki oleh sistem, bukan dijalankan secara bebas oleh
  model.
- Definisi dan regulasi yang ditampilkan harus dapat ditelusuri ke evidence
  corpus.
- Semantic similarity hanya digunakan untuk menemukan kandidat. Similarity
  tidak membuktikan bahwa suatu istilah atau definisi benar secara hukum.
- Angka, nominal, persentase, tanggal, tenggat, negasi, modalitas, pihak,
  defined term, kondisi, pengecualian, dan cross-reference harus diperlakukan
  sebagai konten berisiko tinggi.
- Hasil “Tidak ada saran” tidak boleh dipresentasikan sebagai sertifikasi bahwa
  dokumen sudah benar atau sah.

### 1.3 Istilah hasil review

| Hasil | Arti | Perubahan otomatis | Tindakan pengguna |
| --- | --- | --- | --- |
| Saran | Ada perubahan lokal yang memiliki span, replacement, dan evidence yang valid | Tidak | Accept atau Dismiss |
| Perlu review | Ada sinyal risiko atau ketidakpastian, tetapi sistem tidak memiliki replacement yang aman | Tidak | Tandai sudah diperiksa atau abaikan |
| Definisi selaras | Definisi terdeteksi dan dinilai selaras dengan evidence terverifikasi | Tidak | Periksa referensi bila diperlukan |
| Definisi tidak selaras | Istilah dan uraian definisi tidak cocok dengan kandidat evidence | Tidak | Pilih perbaikan definisi, perbaikan istilah, atau tolak |
| Tidak ada saran | Tidak ada isu berkeyakinan tinggi yang ditemukan oleh pemeriksaan yang tersedia | Tidak | Tidak ada tindakan wajib |
| Hasil kedaluwarsa | Teks berubah setelah analisis | Tidak | Jalankan analisis ulang |

UI sebaiknya menggunakan kalimat:

> Tidak ditemukan isu pada pemeriksaan ini.

UI tidak boleh menggunakan kalimat:

> Dokumen sudah benar.

## 2. Baseline sistem saat ini

### 2.1 Kemampuan Phase 0 sampai Phase 2

| Bagian | Sudah tersedia | Keterbatasan |
| --- | --- | --- |
| Import dan local workspace | Import format teks/rich text, salinan sumber, autosave, preview, export | Belum menjadi bagian dari semantic context analysis |
| Segmentasi | Memproses seluruh dokumen menjadi segmen dan membawa kalimat sebelum/sesudah | Belum membawa section heading, parent clause, atau hierarchy |
| Protection context | Mengenali quoted terms, party names, acronyms, dan identifiers dari seluruh dokumen | Belum menjadi defined-term consistency audit |
| Rule pack | Empat aturan exact untuk ejaan dan tata bahasa | Belum merupakan grammar checker umum; rule masih pending human review |
| Spell checking | NSSpellChecker menghasilkan kandidat bahasa Indonesia | Bergantung pada kamus sistem dan dibatasi secara konservatif |
| TataKata | Menilai kandidat spelling berdasarkan konteks lokal | Belum menjadi general grammar model |
| Candidate-first | Replacement dibuat oleh rule, spell checker, atau verified corpus sebelum Qwen | Kandidat masih bergantung pada unique string span untuk beberapa jalur |
| Phase 2 routing | Membedakan deterministic, model review, needs review, dan suppressed | Needs-review belum dipetakan menjadi highlight editor |
| Qwen | Menilai kandidat yang disediakan dengan keputusan terbatas | Tidak memiliki document-level profile |
| Dictionary/RAG | Exact, lexical, BM25, dan semantic retrieval dari corpus lokal | Filter konteks dokumen dan applicability masih perlu diperkuat |
| Definition analysis | Mendeteksi pola definisi dan membandingkan dengan source definition | Mismatch belum memiliki resolution flow; penyajiannya masih diagnostic dan debug-oriented |
| Validation | Memeriksa locality, replacement, protected content, source claims, dan konflik | Tidak menggantikan kebutuhan legal review |
| Editor suggestion | Source-range highlight dengan Accept dan Dismiss | Hanya review berstatus Saran yang dipetakan ke editor |
| Definition diagnostics | Highlight read-only dengan status selaras, tidak selaras, atau perlu review | Saat ini berada pada diagnostic/debug layer |
| Snapshot | Menyimpan hasil analisis dan membatalkan snapshot saat isi berubah | Perubahan kecil masih dapat membatalkan hasil yang lebih luas dari kebutuhan |
| Observability | Phase 0 safe JSON dan perbandingan pipeline | Debug-only dan belum memiliki lawyer-approved fixture gate |

### 2.2 Arti aturan deterministik saat ini

Aturan deterministik bukan model machine learning. Aturan tersebut adalah
konfigurasi eksplisit dalam AIConnectorRulePack.json. Contoh saat ini:

| Original | Replacement | Kategori |
| --- | --- | --- |
| memasukan | memasukkan | Ejaan |
| di simpan | disimpan | Ejaan |
| ditanda tangani | ditandatangani | Ejaan |
| wajib untuk | wajib | Tata bahasa |

Sebuah rule hanya boleh menghasilkan saran ketika:

- Pola yang dicari ditemukan.
- Replacement berbeda dari original.
- Source span dapat dipetakan dengan aman.
- Rule tidak mengenai exception.
- Perubahan tidak merusak protected content.
- Validator menerima hasil.
- Hasil tidak berkonflik dengan kandidat yang lebih kuat.

Keberhasilan empat fixture di atas tidak berarti sistem telah memahami seluruh
ejaan atau tata bahasa Indonesia. Mereka membuktikan bahwa empat transformasi
tersebut berjalan secara deterministik.

### 2.3 Fixture, contract test, dan perilaku produksi

Roadmap harus selalu membedakan tiga hal:

1. Fixture expectation menjelaskan output ideal untuk contoh sintetis.
2. Parser atau validator test membuktikan bahwa format tertentu diterima atau
   ditolak.
3. End-to-end pipeline test membuktikan bahwa input nyata dapat ditemukan,
   diproses, dipetakan, dan ditampilkan melalui jalur produksi.

Suatu output yang lolos parser test belum tentu akan ditemukan oleh pipeline.
Contohnya, kalimat yang mengandung risiko hak pengakhiran tidak akan mencapai
Qwen jika belum ada detector lokal yang membuat kandidat atau risk signal.

Setiap future capability harus memiliki ketiga jenis bukti tersebut.

## 3. Keputusan desain dari diskusi

Keputusan berikut menjadi dasar roadmap ini:

1. Candidate-first processing tetap dipertahankan.
2. Qwen tidak menjadi penulis ulang dokumen.
3. Qwen tidak dijadikan satu-satunya pembaca atau pemilik konteks dokumen.
4. Dokumen memiliki profil terstruktur yang dihitung satu kali dan dipakai
   kembali oleh setiap segmen.
5. Topik besar dokumen hanya menjadi sinyal konteks, bukan rule yang menentukan
   apakah sebuah klausul benar atau salah.
6. RAG dipanggil oleh orchestration layer dan hanya mengirim kandidat terfilter
   kepada Qwen.
7. Ejaan dan grammar berisiko rendah dapat menggunakan jalur deterministik.
8. Istilah, definisi, hak, kewajiban, pengecualian, dan defined term berada di
   jalur model review atau human review.
9. Definisi yang benar menampilkan referensi hukum menggunakan pola UI yang
   sudah ada.
10. Definition mismatch memiliki tiga resolusi: rekomendasi definisi,
    rekomendasi istilah, atau menolak rekomendasi.
11. Needs-review dan inkonsistensi defined term harus dapat di-highlight secara
    read-only.
12. Frasa yang muncul berulang tetap boleh mendapatkan rekomendasi apabila
    setiap occurrence memiliki source anchor yang berbeda.
13. Tidak semua defined term yang benar perlu di-highlight; hanya penggunaan
    yang bermasalah atau dipilih pengguna.
14. Tidak ada global free-form “perbaiki seluruh dokumen”.

## 4. Target alur pemrosesan Document

### 4.1 Diagram target

~~~mermaid
flowchart TD
    A[Import dan normalisasi dokumen lokal] --> B[Ekstraksi struktur dokumen]
    B --> C[Document Context Profile]
    B --> D[Segmentasi section, clause, dan sentence]

    C --> C1[Jenis dokumen dan domain]
    C --> C2[Para pihak dan defined terms]
    C --> C3[Regulasi, yurisdiksi, dan tanggal]
    C --> C4[Section map dan referensi silang]

    D --> E[Bangun context package per segmen]
    C --> E

    E --> F[Local detectors]
    F --> F1[Rule pack]
    F --> F2[NSSpellChecker dan TataKata]
    F --> F3[Defined-term consistency]
    F --> F4[Definition detector]
    F --> F5[Legal-risk signals]

    F --> G{Perlu evidence hukum?}
    G -->|Tidak| H[Deterministic low-risk candidate]
    G -->|Ya| I[Selective RAG dari corpus terverifikasi]

    I --> J[Filter authority, status, scope, dan konteks]
    J --> K[Rank kandidat]
    K --> L[Qwen bounded judge]

    H --> M[Validator dan conflict resolver]
    L --> M

    M --> N{Keputusan}
    N -->|Actionable| O[Highlight dengan Accept dan Dismiss]
    N -->|Needs review| P[Highlight read-only]
    N -->|Definition mismatch| Q[Definisi atau istilah atau tolak]
    N -->|No evidence| R[Tidak ada saran]

    O --> S[Autosave lokal]
    P --> S
    Q --> S
~~~

### 4.2 Stage contract

Setiap stage harus memiliki input dan output yang sempit.

| Stage | Input | Output | Tidak boleh dilakukan |
| --- | --- | --- | --- |
| Import | File pilihan pengguna | Local source copy dan editable document | Mengubah file sumber eksternal |
| Normalization | Rich text atau structured document | Teks dan struktur yang stabil | Menghapus formatting tanpa alasan |
| Context profile | Struktur dan teks dokumen | Metadata terstruktur dengan confidence dan anchors | Membuat kesimpulan legal |
| Segmentation | Structured document | Segmen dengan section dan source range | Memotong angka atau defined term secara salah |
| Detection | Segmen dan context profile | Candidate atau risk signal | Menghasilkan free-form rewrite |
| Retrieval | Query terkontrol | Kandidat corpus dan metadata | Menganggap similarity sebagai correctness |
| Model review | Candidate, context, evidence | Keputusan untuk candidate ID | Mengarang kandidat atau sumber |
| Validation | Keputusan dan source text | Validated review | Menerima stale atau ungrounded output |
| UI mapping | Validated review | Highlight dan popover | Menampilkan Accept pada read-only warning |
| Persistence | Draft dan analysis snapshot | Local saved state | Menyimpan raw model reasoning |

### 4.3 Urutan pemrosesan yang direkomendasikan

1. Import dan simpan salinan lokal.
2. Normalisasi struktur tanpa menghilangkan fidelity dokumen.
3. Bangun section map dan document context profile.
4. Segmentasikan per section, clause, dan sentence.
5. Jalankan detector lokal yang murah terlebih dahulu.
6. Tampilkan deterministic suggestion segera setelah tervalidasi.
7. Jalankan RAG hanya untuk segmen yang memerlukan evidence.
8. Filter dan rank evidence menggunakan metadata dokumen.
9. Panggil Qwen hanya untuk kandidat yang tidak dapat diputuskan secara aman.
10. Jalankan validator dan conflict resolver.
11. Map hasil menjadi actionable suggestion, read-only review annotation,
    definition resolution, atau no finding.
12. Simpan snapshot dan cache berdasarkan fingerprint yang relevan.

## 5. Grup A — Fondasi dokumen

### 5.1 Import dan normalisasi

#### Kondisi saat ini

Document dapat mengimpor format yang didukung, menyimpan salinan sumber,
menampilkan dokumen asli, mengedit hasil review, autosave, dan export.

#### Target

Pipeline analysis harus menerima representasi dokumen yang:

- Mempertahankan source offsets.
- Mempertahankan hierarchy heading dan paragraph.
- Mempertahankan list level dan numbering.
- Mempertahankan tabel sebagai unit struktur bila tersedia.
- Memisahkan isi editor dari salinan sumber.
- Menandai bagian yang tidak dapat dikonversi dengan aman.

#### Future work

- Tambahkan import diagnostics berisi jumlah paragraph, heading, table, list,
  unsupported block, dan conversion warning.
- Pertahankan mapping antara structured block dan UTF-16 editor range.
- Jangan mulai legal analysis ketika conversion menghasilkan dokumen kosong.
- Tampilkan peringatan apabila sebagian konten tidak dapat dibaca.
- Simpan versi normalizer dalam analysis profile agar snapshot lama tidak
  dipakai setelah aturan normalisasi berubah.

#### Acceptance criteria

- File sumber eksternal tidak pernah ditimpa.
- Preview selalu menggunakan salinan sumber yang tervalidasi.
- Teks yang dianalisis sama dengan teks yang terlihat di editor.
- Source range tetap benar setelah import DOCX, DOC, RTF, Markdown, dan TXT.
- Conversion failure tidak menghasilkan workspace document kosong tanpa
  peringatan.

### 5.2 Ekstraksi struktur dokumen

#### Tujuan

Legal meaning sering mengikuti struktur, bukan hanya tanda titik. Contoh:

- Heading menentukan domain sebuah klausul.
- Numbered subclauses membentuk kondisi dan pengecualian.
- Definition section memiliki aturan pembacaan berbeda.
- Table dapat menyimpan nominal, tanggal, atau service level.

#### Proposed output

Setiap block minimal membawa:

- Stable block ID.
- Jenis block: heading, paragraph, list item, table cell, footnote, atau
  unknown.
- Source range.
- Parent section ID.
- Numbering label.
- Heading path.
- Previous dan next sibling.

#### Acceptance criteria

- Sebuah kalimat mengetahui section tempatnya berada.
- Segmen tidak kehilangan label seperti “1.2”, “(a)”, atau “Pasal 4”.
- Parent-child relationship tetap stabil selama isi di luar section tidak
  berubah.
- Table cell tidak digabung secara sembarang menjadi satu kalimat panjang.

### 5.3 Document Context Profile

#### Tujuan

Document Context Profile menyediakan konteks ringkas yang dapat dipakai ulang.
Profil ini menghindari kebutuhan mengirim seluruh dokumen kepada Qwen untuk
setiap segmen.

#### Proposed fields

| Field | Contoh | Sumber |
| --- | --- | --- |
| documentTypeCandidates | NDA, DPA, MSA | Heading, title, optional classifier |
| legalDomains | privacy, commercial, employment | Heading, terms, regulation references |
| parties | Pihak Pertama, Borrower, Lender | Deterministic extraction |
| definedTerms | Data Pribadi, Layanan | Definition extraction |
| jurisdictions | Indonesia | Explicit clause |
| regulationReferences | UU 27/2022, PP 71/2019 | Deterministic extraction |
| effectiveDates | 10 Agustus 2026 | Deterministic extraction |
| currencies | IDR, USD | Deterministic extraction |
| sectionOutline | Definisi, Kerahasiaan, Pengakhiran | Structured document |
| confidence | per field | Extractor atau classifier |
| evidenceRanges | source ranges | Document text |

#### Extraction strategy

Gunakan tiga tingkat:

1. Deterministic extraction untuk party, defined term, identifier, tanggal,
   nominal, regulation reference, dan heading.
2. Local retrieval atau embedding classification untuk domain candidates.
3. Optional Qwen classification satu kali untuk dokumen atau section yang
   ambigu.

Qwen harus mengembalikan schema terstruktur. Free-form summary tidak diperlukan
untuk jalur produksi.

#### Long-document strategy

- Jangan mewajibkan satu prompt berisi seluruh dokumen.
- Gunakan title, outline, heading, definition section, dan bounded excerpts.
- Bangun section-level profile untuk dokumen yang besar.
- Gabungkan section profiles menjadi document profile menggunakan deterministic
  aggregation.
- Simpan profile berdasarkan content fingerprint.

#### Safety rules

- Document type adalah candidate, bukan fakta.
- Topik tidak boleh menolak sebuah klausul secara otomatis.
- Confidence rendah menghasilkan unknown.
- Profil tidak boleh berisi legal conclusion.
- Profil tidak diekspor dalam safe telemetry apabila masih berisi teks
  pengguna.

#### Acceptance criteria

- Profil dibangun sekali per revision dokumen.
- Segment review dapat mengakses section dan document context tanpa membaca
  seluruh dokumen kembali.
- Dokumen multi-domain dapat menyimpan lebih dari satu legal domain.
- Perubahan satu section hanya membatalkan profile bagian yang relevan bila
  incremental analysis sudah diaktifkan.

### 5.4 Segmentasi dan context package

#### Kondisi saat ini

Segmen membawa target text serta previous dan next context.

#### Target

Context package per segmen sebaiknya membawa:

- Target segment.
- Previous dan next segment.
- Parent clause.
- Heading path.
- Relevant defined terms.
- Relevant parties.
- Regulation references pada section.
- Document type candidates.
- Candidate-specific evidence.

#### Segment boundary rules

- Utamakan clause dan list item sebelum sentence.
- Jangan memisahkan angka dengan terbilangnya.
- Jangan memisahkan defined term dari definisinya.
- Jangan memisahkan condition marker dari konsekuensinya.
- Jangan memisahkan exception marker seperti “kecuali” dari clause utama.
- Beri status too-long dan lakukan bounded subdivision bila segmen melebihi
  model context.

#### Acceptance criteria

- Setiap source range dapat dipetakan kembali ke editor.
- Previous dan next context berasal dari hierarchy yang benar.
- Heading tidak diproses sebagai grammar sentence kecuali detector heading
  memang mendukungnya.
- Segmen dengan tabel atau list tidak kehilangan nomor dan relasi induk.

## 6. Grup B — Deteksi dan pengambilan keputusan

### 6.1 Pemeriksaan ejaan

#### Jalur yang dipertahankan

~~~text
Exact reviewed rule
    → deterministic suggestion

Unknown word
    → NSSpellChecker candidate
    → TataKata score
    → Phase 2 routing
    → optional Qwen review
~~~

#### Rule-pack governance

Setiap rule wajib memiliki:

- Stable rule ID.
- Revision.
- Category.
- Matcher.
- Original dan replacement.
- Reason.
- Priority.
- Exception.
- Owner.
- Reviewer.
- Changelog.
- Positive fixtures.
- Negative fixtures.
- Approval status.

Future release sebaiknya hanya mengaktifkan rule berstatus approved untuk
pengalaman pengguna normal. Pending rule boleh tetap tersedia pada Debug
baseline.

#### Unknown-word safeguards

- Jangan memeriksa party names, defined terms, acronyms, identifiers, URLs,
  email, regulation numbers, article references, atau numeric tokens.
- Kandidat harus memiliki source range yang diberikan spell checker.
- TataKata hanya menilai kandidat; TataKata tidak membuat replacement baru.
- Ambiguous score menjadi needs-review atau suppressed.
- Jangan mengubah bahasa asing yang sengaja digunakan dalam defined term.

#### Acceptance criteria

- Typo exact menghasilkan source-range suggestion tanpa model call.
- Typo di luar rule pack hanya tampil jika candidate dan score valid.
- Legal terms tidak ditandai sebagai typo ketika ada di allowlist/corpus.
- Tidak ada correction pada URL, email, nomor pasal, atau identifier.
- Setiap accepted replacement mempertahankan formatting run yang relevan.

### 6.2 Pemeriksaan tata bahasa

#### Kondisi saat ini

Grammar deterministic masih terbatas pada transformasi exact seperti
“wajib untuk” menjadi “wajib”.

#### Target

Grammar development dibagi menjadi:

1. Mechanical grammar: high precision dan aman secara lokal.
2. Clarity signal: memberi peringatan tanpa replacement.
3. Substantive rewrite: di luar scope automatic suggestion.

#### Kandidat mechanical grammar

- Redundansi yang tidak mengubah modalitas.
- Spacing dan punctuation yang tidak mengubah struktur hukum.
- Agreement atau bentuk kata yang memiliki replacement lokal.
- Duplicate token yang jelas.

#### Tidak boleh menjadi automatic replacement

- Mengubah wajib menjadi harus atau dapat.
- Menambah atau menghapus tidak, tanpa, kecuali, apabila, atau sepanjang.
- Mengubah singular/plural yang memengaruhi scope.
- Mengubah active/passive voice bila pelaku menjadi tidak jelas.
- Memindahkan condition atau exception.
- Menggabungkan atau memecah kewajiban substantif.

#### Acceptance criteria

- Grammar candidate memiliki minimal source span, replacement, rule/evidence,
  dan reason.
- Protected modality dan negation tidak berubah.
- Grammar engine tidak membuat whole-sentence rewrite.
- Clarity issue tidak diberi tombol Accept tanpa replacement tervalidasi.

### 6.3 Beberapa kesalahan dalam satu segmen

#### Target

Satu segmen dapat menghasilkan beberapa kandidat non-overlap. Maximum kandidat
tetap dibatasi untuk menjaga latency dan kepadatan UI.

#### Required behavior

- Rank berdasarkan evidence tier, bukan urutan model.
- Deduplicate original-replacement-category yang sama.
- Pertahankan kandidat non-overlap.
- Jika kandidat overlap, pilih evidence yang lebih kuat.
- Catat dropped count dan conflict count untuk diagnostics.
- Setelah satu saran diterima, batalkan anchor lain yang terdampak.

#### Acceptance criteria

- “wajib untuk”, “di simpan”, dan “ditanda tangani” dapat muncul sebagai tiga
  saran terpisah.
- Accept satu suggestion tidak menerapkan suggestion lain.
- Dismiss satu suggestion tidak menghilangkan suggestion yang tidak overlap.
- Tidak ada dua highlight yang menulis source range sama.

### 6.4 Occurrence-based anchoring

#### Masalah

String-based unique lookup menolak saran ketika original muncul lebih dari satu
kali dalam satu segmen.

#### Target

Setiap candidate membawa source location dan source length sejak detector
membuatnya. Editor tidak mencari ulang original hanya berdasarkan string.

#### Proposed anchor identity

Anchor minimal dibentuk dari:

- Document ID.
- Content revision.
- Segment ID.
- Candidate source location.
- Candidate source length.
- Original hash.
- Rule atau evidence ID.

#### Required behavior

- Dua occurrence dengan teks sama mendapatkan ID berbeda.
- Setiap occurrence dapat di-Accept atau Dismiss secara independen.
- Anchor diverifikasi ulang terhadap current document sebelum perubahan.
- Anchor menjadi stale jika original pada range tidak lagi cocok.

#### Acceptance criteria

- Dua “wajib untuk” dalam satu kalimat dapat di-highlight terpisah.
- Perubahan sebelum occurrence menggeser range melalui reconciliation atau
  membatalkan affected anchor.
- Accept tidak pernah menulis pada range yang sudah stale.

### 6.5 Defined-term extraction dan consistency audit

#### Kondisi saat ini

Protection context mengenali quoted terms, party names, acronyms, dan
identifiers agar tidak diubah. Ini belum merupakan consistency audit.

#### Target findings

| Finding | Contoh | Default result |
| --- | --- | --- |
| Undefined term | “Penyedia” digunakan seperti defined term tetapi tidak didefinisikan | Needs review |
| Unused definition | “Layanan Tambahan” didefinisikan tetapi tidak pernah digunakan | Needs review |
| Case inconsistency | “Data Pribadi” dan “data pribadi” digunakan sebagai term yang sama | Needs review atau safe suggestion |
| Alias inconsistency | “Vendor” digunakan setelah “Penyedia” didefinisikan | Needs review |
| Duplicate definition | Istilah yang sama didefinisikan dua kali | Needs review |
| Conflicting definition | Satu istilah memiliki dua isi definisi berbeda | Needs review |
| Equivalent definition | Dua istilah berbeda memiliki isi definisi yang sangat mirip | Needs review |
| Defined after use | Term digunakan sebelum definition section | Informational |

#### Extraction strategy

- Gunakan explicit definition cues.
- Simpan term, definition body, range, section, dan source order.
- Normalize untuk comparison tetapi pertahankan casing asli.
- Bedakan quoted display term dari ordinary capitalized words.
- Gunakan corpus sebagai evidence tambahan, bukan syarat agar sebuah
  contract-defined term dikenali.

#### UI behavior

- Jangan highlight semua defined term.
- Highlight hanya occurrence yang inconsistent atau dipilih dari review list.
- Gunakan read-only amber annotation untuk finding tanpa replacement aman.
- Gunakan actionable suggestion hanya untuk exact casing/spacing correction
  yang tidak ambigu.
- Popover menampilkan definition location dan occurrence terkait.

#### Acceptance criteria

- Party names dan valid defined terms tidak diubah oleh spell checker.
- Undefined dan conflicting definitions ditemukan secara deterministic.
- Alias suggestion tidak dibuat hanya dari semantic similarity.
- Finding dapat menavigasi ke definition dan usage occurrence.

### 6.6 Validasi terminologi hukum

#### Pertanyaan yang harus dijawab

Sistem tidak cukup hanya bertanya “apakah kalimat mirip definisi?”. Sistem harus
menilai:

1. Apakah candidate term berasal dari corpus terverifikasi?
2. Apakah sumber masih berlaku atau relevan?
3. Apakah scope regulasi sesuai dengan konteks dokumen?
4. Apakah kalimat sedang menggunakan istilah, menjelaskan istilah, atau hanya
   memiliki kata yang mirip?
5. Apakah term tersebut merupakan contract-defined term yang memiliki arti
   khusus?
6. Apakah ada kandidat lain dengan evidence lebih kuat?

#### Context inputs

- Target clause.
- Parent section.
- Previous dan next clause.
- Document type candidates.
- Legal domains.
- Contract-defined terms.
- Regulation references pada dokumen.
- Candidate definition.
- Candidate regulation, article, applicability, jurisdiction, dan evidence ID.

#### Decision schema

| Decision | Arti | UI |
| --- | --- | --- |
| TERM_FITS | Candidate term sesuai dengan penggunaan | Actionable hanya jika replacement span aman |
| TERM_MAY_FIT | Evidence relevan tetapi konteks belum cukup | Needs review |
| CONTRACT_TERM_OVERRIDE | Dokumen mendefinisikan term secara khusus | Read-only explanation |
| WRONG_TERM | Isi lebih cocok dengan term corpus lain | Definition/term resolution |
| NOT_APPLICABLE | Source atau term tidak sesuai konteks | Tidak ada suggestion |
| AMBIGUOUS | Beberapa kandidat masuk akal | Needs review dengan pilihan evidence |

#### Retrieval and ranking

- Exact contract term mendapat prioritas tertinggi untuk penggunaan internal
  dokumen.
- Verified corpus exact term berada di atas semantic candidate.
- Source applicability dan regulation status memengaruhi ranking.
- Document topic hanya menjadi weak prior.
- Section heading lebih kuat daripada topik global untuk penggunaan lokal.
- Candidate tanpa source anchor tidak boleh menjadi actionable terminology
  suggestion.

#### Acceptance criteria

- Kandidat terminology selalu memiliki evidence.
- Qwen tidak dapat memilih term di luar candidate IDs.
- Candidate yang tidak sesuai scope dapat ditolak.
- Multiple plausible terms menghasilkan needs-review, bukan top-1 replacement.
- Contract-defined meaning ditampilkan sebagai konteks dan tidak ditimpa oleh
  statutory definition secara otomatis.

### 6.7 Deteksi dan validasi definisi

#### Classification

Definition analyzer harus dapat menghasilkan:

- Bukan definisi.
- Definisi eksplisit.
- Definisi tersirat.
- Perlu review.

Alignment harus dapat menghasilkan:

- Selaras.
- Tidak selaras.
- Kesetaraan belum pasti.
- Tidak berlaku.

#### Evidence display

Untuk setiap definition finding yang memiliki evidence, UI harus dapat
menampilkan:

- Istilah.
- Definisi pada dokumen.
- Definisi terverifikasi.
- Regulasi.
- Judul regulasi.
- Article locator.
- Applicability status.
- Evidence/passage ID.
- Sumber detail.
- Dokumen resmi.
- Hubungan amendment atau repeal bila relevan.

#### Definisi yang selaras

- Tidak menghasilkan replacement.
- Dapat memiliki indikator hijau yang halus.
- Tidak perlu memenuhi editor dengan highlight hijau secara default.
- Reference tersedia melalui review list atau ketika diagnostic dipilih.
- Tetap diberi disclaimer bahwa keselarasan adalah hasil pemeriksaan, bukan
  legal certification.

#### Definition mismatch resolution

Sistem harus menyajikan tiga jalur:

1. Gunakan definisi berdasarkan corpus.
2. Ganti istilah berdasarkan isi definisi.
3. Tolak rekomendasi.

##### Opsi 1 — Rekomendasi definisi

Tersedia hanya apabila:

- Term dikenali dengan pasti.
- Ada source definition terverifikasi dan actionable.
- Source status masih relevan.
- Tidak ada konflik source yang belum diselesaikan.
- Replacement body dapat di-anchor secara tepat.

UI menampilkan preview sebelum/after. Perubahan hanya dilakukan setelah user
memilih sumber dan menekan Accept.

##### Opsi 2 — Rekomendasi istilah

Gunakan definition body sebagai reverse-retrieval query. Tampilkan maksimal
beberapa kandidat yang:

- Berasal dari corpus terverifikasi.
- Memiliki source metadata.
- Melewati minimum lexical/semantic evidence.
- Tidak berkonflik dengan contract-defined term.

Contoh:

~~~text
Data Pribadi adalah kumpulan orang dan/atau kekayaan yang terorganisasi ...

Kemungkinan:
- Isi definisi lebih cocok dengan “Korporasi”.
- Istilah “Data Pribadi” mungkin salah.
~~~

Sistem tidak boleh mengganti istilah hanya karena satu semantic result berada
di ranking pertama.

##### Opsi 3 — Tolak

User dapat menolak finding apabila:

- Corpus tidak sesuai dengan konteks kontrak.
- Dokumen sengaja menggunakan definisi khusus.
- Source tidak berlaku pada transaksi.
- Lawyer memiliki interpretasi yang berbeda.

Dismissal hanya berlaku pada revision dokumen dan finding terkait. Perubahan
besar pada teks atau corpus dapat membuat finding perlu dievaluasi ulang.

#### Acceptance criteria

- Bukan-definisi tidak mendapat definition highlight.
- Definition match membawa reference yang dapat ditelusuri.
- Definition mismatch tidak langsung mengubah dokumen.
- Replace-definition dan replace-term menjadi dua tindakan berbeda.
- Multiple source definitions ditampilkan sebagai pilihan, bukan digabung
  menjadi definisi sintetis.
- Reject tidak mengubah teks.

### 6.8 Legal-risk signal detection

#### Tujuan

Detector ini tidak menentukan apakah klausul sah atau adil. Ia hanya menemukan
bagian yang layak mendapat perhatian lawyer.

#### Initial signal groups

| Group | Contoh sinyal | Output |
| --- | --- | --- |
| Modalitas | wajib, harus, dapat, berhak, dilarang | Read-only jika ada perubahan/inkonsistensi |
| Negasi | tidak, tanpa, bukan | Read-only |
| Unilateral right | sewaktu-waktu, atas kebijakan sendiri | Read-only |
| Notice dan cure | tanpa pemberitahuan, tenggat cure hilang | Read-only |
| Condition | apabila, sepanjang, dengan syarat | Read-only |
| Exception | kecuali, selain, namun demikian | Read-only |
| Time and deadline | paling lambat, dalam waktu, hari kerja | Read-only |
| Monetary consequence | denda, bunga, ganti rugi, currency | Read-only |
| Cross-reference | Pasal atau Lampiran tidak ditemukan | Read-only |
| Clause conflict | Dua clause memberi hak/kewajiban berbeda | Read-only |

#### Detection strategy

Gunakan detector berlapis:

1. Deterministic phrase and structure signals.
2. Cross-clause index untuk reference dan duplicate obligations.
3. Retrieval bila istilah hukum memerlukan corpus.
4. Qwen hanya menilai risk candidate dengan context package.

Jangan mengirim setiap kalimat yang mengandung “wajib” kepada Qwen. Itu akan
mahal dan menghasilkan terlalu banyak noise. Detector harus mencari kombinasi
atau konflik yang bermakna.

#### UI behavior

- Highlight amber, bukan actionable pink.
- Highlight span terkecil yang menjelaskan risiko.
- Tidak ada Accept bila replacement kosong.
- Popover menampilkan alasan dan context terkait.
- Action: Tandai sudah diperiksa, Navigasi ke clause terkait, atau Abaikan.

#### Acceptance criteria

- Risk finding tidak menghasilkan free-form rewrite.
- Angka dan modalitas tidak berubah.
- Finding memiliki source anchor.
- Cross-clause conflict menampilkan kedua lokasi.
- User dapat menandai finding sebagai reviewed tanpa mengubah dokumen.

### 6.9 Selective RAG dan corpus filtering

#### Ownership

Application orchestration memanggil retrieval. Qwen tidak menerima akses bebas
untuk mencari atau memilih sumber di luar kandidat yang diberikan.

#### Query types

- Exact term query.
- Definition-to-term query.
- Clause terminology query.
- Regulation reference query.
- Source applicability query.

#### Required filters

- Authority verified.
- Entry actionable untuk replacement.
- Corpus bukan legacy diagnostics.
- Applicability status.
- Regulation status.
- Jurisdiction.
- Effective date bila tersedia.
- Source passage atau reference anchor.
- Contract-defined term override.

#### Candidate package

Qwen hanya menerima data yang diperlukan:

- Candidate ID.
- Canonical term.
- Definition.
- Regulation identifier.
- Article locator.
- Applicability status.
- Evidence strength.
- Detection origin.

Raw URL tidak diperlukan untuk reasoning model, tetapi tetap disimpan pada UI
reference.

#### Acceptance criteria

- Retrieval yang gagal tidak membuat source sintetis.
- Unknown short term tetap fail closed.
- Candidate dari legacy corpus tidak menjadi actionable.
- Retrieval query count dan duration tercatat dalam Debug observation.
- Cache key mencakup corpus dan retrieval version.

### 6.10 Peran Qwen

#### Peran yang diperbolehkan

- Mengklasifikasi document atau section candidate secara terstruktur.
- Menilai satu supplied language candidate.
- Menilai satu supplied terminology candidate.
- Membandingkan definition statement dengan supplied source definition.
- Menilai supplied risk signal.

#### Peran yang tidak diperbolehkan

- Menulis ulang seluruh clause.
- Membuat replacement yang tidak ada di candidate.
- Mengarang citation atau regulasi.
- Menentukan bahwa dokumen sah.
- Memilih sumber dari web.
- Mengubah angka, tanggal, party, defined term, atau modalitas.
- Mengeluarkan raw chain-of-thought kepada UI atau log.

#### Context strategy

Qwen menerima:

- Bounded target.
- Bounded context before/after.
- Section heading.
- Compact document profile.
- Candidate.
- Relevant evidence.

Qwen tidak perlu menerima seluruh dokumen untuk setiap panggilan. Untuk dokumen
pendek, full-document classification dapat menjadi eksperimen Debug, tetapi
bukan dependency utama pipeline.

#### Failure behavior

- Invalid tool call: bounded repair sekali.
- Invalid candidate ID: reject.
- Unsupported source claim: reject.
- Repetition atau reasoning leak: reject.
- Timeout atau cancellation: partial result dipertahankan.
- Model unavailable: deterministic low-risk results tetap tersedia.
- Ambiguous output: needs-review atau no suggestion.

### 6.11 Routing, validation, dan conflict resolution

#### Evidence tiers

Urutan evidence:

1. Approved exact rule.
2. Verified glossary dengan source anchor.
3. TataKata-scored spelling candidate.
4. Semantic glossary dengan source support.
5. Unknown atau unsupported.

Urutan tidak selalu berarti kandidat lebih benar secara hukum. Ia hanya
menentukan cara routing dan kebutuhan model review.

#### Routing matrix

| Candidate | Route |
| --- | --- |
| Approved exact spelling/grammar rule | Deterministic |
| TataKata-scored spelling | Model review |
| Verified terminology | Model review |
| Strong semantic terminology | Model review |
| Weak semantic terminology | Needs review |
| Protected content | Needs review |
| Unsupported candidate | Suppressed |
| Definition mismatch | Definition resolution |
| Legal-risk signal | Read-only review |

#### Validation requirements

- Original cocok dengan source range.
- Replacement tidak kosong dan berbeda.
- Category valid.
- Candidate ID valid.
- Replacement berasal dari candidate.
- Protected content tetap utuh.
- Number, modality, negation, condition, dan exception tetap utuh.
- Source claim grounded.
- Range tidak stale.
- Result tidak overlap dengan result yang lebih kuat.

#### Conflict resolution

- Rank evidence sebelum model call.
- Deduplicate kandidat sama.
- Pilih kandidat lebih kuat pada overlap.
- Simpan conflict diagnostic.
- Jangan menggabungkan dua replacement menjadi replacement baru.
- Konflik terminology/definition menjadi needs-review.

## 7. Grup C — Review UI dan interaksi

### 7.1 Highlight semantics

UI utama tetap mempertahankan editor dan popover yang ada. Perubahan bersifat
penambahan state, bukan redesign besar.

| State | Warna konseptual | Icon | Accept |
| --- | --- | --- | --- |
| Actionable language suggestion | Pink/red lembut | lightbulb | Ya |
| Needs human review | Amber | warning | Tidak |
| Definition mismatch | Red | xmark seal | Melalui resolution card |
| Definition match | Green halus | checkmark seal | Tidak |
| Stale | Gray | clock atau warning | Tidak |

Warna bukan satu-satunya pembeda. Semua state harus memiliki label, icon, dan
accessibility description.

### 7.2 Actionable suggestion popover

Popover mempertahankan:

- Category.
- Original.
- Replacement.
- Context sebelum dan sesudah.
- Alasan.
- Origin.
- References bila terminology.
- Accept.
- Dismiss.

Tambahan future:

- Evidence tier.
- Rule atau candidate source dalam bahasa yang mudah dipahami.
- Penanda “Aturan lokal”, “Model menilai kandidat”, atau “Corpus hukum”.
- Navigasi ke reference untuk terminology.

User tidak perlu melihat internal token seperti SUGGESTION, EXACT_RULE, atau
MODEL_REVIEW.

### 7.3 Read-only review popover

Digunakan untuk legal-risk dan defined-term findings.

Isi:

- Judul masalah.
- Bagian dokumen.
- Alasan.
- Context atau clause terkait.
- Evidence bila tersedia.
- Tombol Tandai sudah diperiksa.
- Tombol Abaikan.
- Tidak ada tombol Accept.

### 7.4 Definition reference popover

Gunakan struktur visual yang sudah ada:

- Bagian dokumen.
- Istilah.
- Definisi terverifikasi.
- Penilaian.
- Regulasi.
- Judul regulasi.
- Article locator.
- Evidence ID.
- Link sumber detail.
- Link dokumen resmi.
- Status berlaku/tidak berlaku bila tersedia.

Definition match tidak harus selalu terlihat di teks. Review summary dapat
menunjukkan jumlah definition match dan user dapat memilih untuk
menampilkannya.

### 7.5 Definition resolution card

Card dibuka dari definition mismatch highlight.

~~~text
Definisi tidak selaras

Istilah dalam dokumen
Data Pribadi

Definisi dalam dokumen
...

Definisi terverifikasi
...

Acuan
UU ... · Pasal ...

[Gunakan definisi ini]
[Cari istilah yang sesuai]
[Tolak rekomendasi]
~~~

Jika user memilih “Cari istilah yang sesuai”, card menampilkan kandidat term
beserta sumbernya. Tidak ada kandidat yang dipilih secara tersembunyi.

### 7.6 Review navigation

Tambahkan navigasi yang dapat:

- Berpindah ke finding sebelumnya/berikutnya.
- Filter berdasarkan category.
- Filter actionable dan read-only.
- Filter unresolved dan reviewed.
- Membuka source reference.
- Menampilkan clause terkait untuk cross-clause finding.

Ordering mengikuti source location, bukan completion time model.

### 7.7 Accept, dismiss, dan mark reviewed

| Action | Untuk | Efek |
| --- | --- | --- |
| Accept | Actionable suggestion | Mengubah range yang tervalidasi |
| Dismiss | Suggestion atau finding | Menyembunyikan item pada revision saat ini |
| Mark reviewed | Read-only finding | Menyimpan bahwa user telah memeriksa |
| Reject recommendation | Definition resolution | Menolak seluruh opsi pada finding |
| Re-run | Stale item atau changed document | Memproses ulang bagian relevan |

Tidak ada global Accept All untuk terminology, definition, atau legal-risk.
Accept All untuk approved deterministic spelling dapat dipertimbangkan setelah
quality gate dan explicit confirmation tersedia.

### 7.8 Editing dan stale results

- Sebelum Accept, editor memeriksa original pada anchor.
- Setelah user mengetik, affected finding menjadi stale atau dibatalkan.
- Unaffected section findings sebaiknya dipertahankan setelah incremental
  analysis tersedia.
- Stale item tidak dapat di-Accept.
- UI menjelaskan bahwa analisis perlu dijalankan ulang.

### 7.9 Empty and completion states

Completion summary minimal menampilkan:

- Jumlah actionable suggestions.
- Jumlah needs-review findings.
- Jumlah definition matches.
- Jumlah definition mismatches.
- Jumlah defined-term findings.
- Jumlah bagian yang tidak dapat diperiksa.
- Status partial/cancelled.

Jika tidak ada finding:

> Tidak ditemukan isu pada pemeriksaan ini. Hasil ini bukan jaminan ketepatan
> hukum dan tetap memerlukan review profesional.

## 8. Grup D — Persistence, cache, dan performa

### 8.1 Analysis snapshot

Snapshot harus mencakup version/fingerprint untuk:

- Document content.
- Structured document normalization.
- Pipeline.
- Rule pack.
- Corpus.
- Retrieval configuration.
- TataKata.
- Qwen model.
- Prompt/schema.
- Document context profile.
- Segmentation.
- UI mapping schema.

Snapshot tidak boleh dipulihkan bila source anchors tidak lagi valid.

### 8.2 Incremental invalidation

#### Target

Perubahan lokal tidak selalu memerlukan analisis seluruh dokumen.

#### Invalidation scope

| Perubahan | Minimum invalidation |
| --- | --- |
| Typo dalam satu sentence | Segmen, previous, next |
| Defined term definition berubah | Seluruh usage term terkait |
| Party name berubah | Semua protection-context dependent segments |
| Heading berubah | Seluruh child section |
| Regulation reference berubah | Section dan retrieval dependent segments |
| Document type/title berubah | Document context profile dan dependent routing |
| Corpus version berubah | Semua terminology dan definition results |
| Rule-pack version berubah | Semua deterministic candidates |

#### Acceptance criteria

- Tidak ada stale suggestion yang tetap actionable.
- Unaffected deterministic results dapat dipertahankan.
- Dependencies tercatat eksplisit.
- Full rerun tetap tersedia sebagai fallback.

### 8.3 Cache strategy

Pisahkan cache:

- Document profile cache.
- Segmentation cache.
- Retrieval cache.
- TataKata score cache.
- Qwen candidate decision cache.
- Definition comparison cache.

Cache key tidak boleh hanya menggunakan target text. Ia perlu membawa context,
candidate, model, corpus, dan policy version yang relevan.

### 8.4 Performance strategy

- Jalankan rule dan detector murah lebih dahulu.
- Jangan load Qwen jika seluruh finding dapat diputuskan deterministically.
- Prepare resource sekali dan reuse model container.
- Batch persiapan boleh paralel, tetapi model inference tetap dibatasi sesuai
  memory perangkat.
- RAG dipanggil hanya untuk candidate-bearing segments.
- Cache document profile dan retrieval.
- Publish deterministic results sebelum model review selesai jika UI dapat
  mempertahankan ordering.
- Cancellation menyimpan partial validated results.

### 8.5 Performance acceptance

Ukur secara terpisah:

- Import/normalization.
- Profile extraction.
- Segmentation.
- Deterministic detection.
- Retrieval.
- TataKata scoring.
- Qwen loading.
- Qwen generation.
- Validation.
- UI mapping.
- Warm-cache rerun.

Target numerik ditentukan setelah Phase 0 baseline aktual dan hardware matrix
tersedia. Jangan menetapkan target tanpa data.

## 9. Grup E — Privacy, observability, dan governance

### 9.1 Privacy

- Dokumen tidak dikirim ke network untuk inference.
- Tidak ada automatic telemetry.
- Tidak ada OSLog berisi teks, replacement, definition, reason, URL, atau raw
  output.
- Safe JSON hanya membawa count, duration, category, dan status.
- Raw model output hanya tersedia pada Debug dan tidak disimpan otomatis.
- Model download boleh menggunakan network, tetapi dokumen tidak menjadi
  bagian request download.
- Report export selalu melalui tindakan eksplisit pengguna.

### 9.2 Observability

Tambahkan stage metrics baru saat future stages tersedia:

- Structure extraction.
- Document profile extraction.
- Section segmentation.
- Defined-term analysis.
- Legal-risk analysis.
- Applicability filtering.
- Definition resolution.
- Incremental invalidation.

Safe report tidak boleh membawa:

- Document type jika dapat mengidentifikasi transaksi tertentu.
- Party names.
- Regulation references dari dokumen pengguna.
- Source ranges yang dapat merekonstruksi panjang detail secara sensitif,
  kecuali sudah disanitasi sesuai schema.
- User decisions yang dapat dihubungkan ke dokumen tertentu.

### 9.3 Rule governance

Rule lifecycle:

~~~text
draft
→ engineering test
→ language review
→ lawyer review bila menyentuh legal drafting
→ approved
→ active
→ deprecated
~~~

Perubahan rule membutuhkan revision bump, fixtures, changelog, dan cache
invalidation.

### 9.4 Corpus governance

- Actionable entry harus verified.
- Source harus memiliki reference atau passage anchor.
- Applicability status harus diketahui atau dipresentasikan sebagai unknown.
- Amendment/repeal relation tidak boleh disimpulkan oleh model.
- Multiple valid definitions dipertahankan sebagai alternatives.
- OCR-tolerant evidence tidak menjadi replacement source tanpa review.

### 9.5 Human review governance

Fixture legal tidak dianggap approved sebelum lawyer meninjau:

- Expected classification.
- Expected replacement.
- Source correctness.
- Applicability.
- Hard-negative expectation.
- Safety outcome.

Review status disimpan bersama fixture dan muncul dalam benchmark report.

## 10. Rancangan model dan boundary MVVM

Nama berikut bersifat proposed dan dapat disesuaikan saat implementasi. Tujuan
utamanya adalah menjelaskan ownership.

### 10.1 Model layer

#### DocumentContextProfile

~~~swift
struct DocumentContextProfile: Codable, Hashable, Sendable {
    let documentRevision: Int
    let documentTypeCandidates: [ContextCandidate]
    let legalDomains: [ContextCandidate]
    let parties: [DocumentEntity]
    let definedTerms: [DefinedTermRecord]
    let regulationReferences: [RegulationReference]
    let jurisdictions: [ContextCandidate]
    let effectiveDates: [AnchoredValue]
    let sectionOutline: [DocumentSection]
    let extractorVersion: String
}
~~~

Profil adalah domain data dan tidak bergantung pada SwiftUI.

#### ReviewAnchor

~~~swift
struct ReviewAnchor: Codable, Hashable, Sendable {
    let documentRevision: Int
    let segmentID: Int
    let sourceLocation: Int
    let sourceLength: Int
    let originalHash: String
}
~~~

Anchor menggantikan pencarian string ulang sebagai identitas utama.

#### DocumentReviewItem

~~~swift
enum DocumentReviewItem: Codable, Hashable, Sendable {
    case suggestion(ActionableSuggestion)
    case warning(ReadOnlyReviewFinding)
    case definition(DefinitionReviewFinding)
}
~~~

Actionable item dan read-only item harus memiliki tipe domain berbeda agar UI
tidak dapat menampilkan Accept secara tidak sengaja.

#### DefinitionResolution

~~~swift
struct DefinitionResolution: Codable, Hashable, Sendable {
    let findingID: UUID
    let definitionOptions: [DefinitionReplacementOption]
    let termOptions: [TermReplacementOption]
    let canReject: Bool
}
~~~

Setiap option membawa evidence ID dan source metadata.

### 10.2 ViewModel layer

ViewModel bertanggung jawab untuk:

- Menjalankan orchestration melalui services.
- Mempresentasikan progress.
- Mengelompokkan dan mengurutkan review items.
- Memilih item.
- Meneruskan Accept, Dismiss, Mark Reviewed, dan Reject intent.
- Memastikan item belum stale.
- Memicu incremental rerun.
- Mengubah domain status menjadi user-facing labels.

ViewModel tidak boleh:

- Menjalankan retrieval langsung dari View.
- Menulis file dari SwiftUI action tanpa persistence boundary.
- Menentukan legal correctness.
- Membuat replacement dari prose model.

### 10.3 View layer

View bertanggung jawab untuk:

- Menggambar highlight.
- Menampilkan popover dan reference.
- Mengirim user intent.
- Menunjukkan disabled/stale state.
- Accessibility.

View tidak boleh:

- Mengubah text range tanpa ViewModel/domain validation.
- Mengubah read-only finding menjadi actionable.
- Menginterpretasi raw model output.

### 10.4 Service ownership

| Service | Ownership |
| --- | --- |
| Document structure extractor | Fondasi Document |
| Document context profile builder | Document analysis |
| Segmenter | AI Connector |
| Rule store dan deterministic engine | Language mechanics |
| Spell checker dan TataKata | Language mechanics |
| Defined-term analyzer | Document analysis |
| Legal-risk detector | Document analysis |
| Dictionary store/retriever | Legal knowledge |
| Qwen service | Model inference |
| Validator/conflict resolver | AI Connector |
| Editor mapper | Suggestion feature |
| Snapshot/persistence | Dashboard/Document storage |

Service baru dibuat hanya ketika ada responsibility nyata. Hindari registry,
factory, atau abstraction generik yang belum dibutuhkan.

## 11. Urutan implementasi

Phase berikut adalah proposal setelah Phase 0 sampai Phase 2. Nomor dan scope
dapat disesuaikan setelah review.

### Phase 3 — Inline review foundation

#### Tujuan

Membuat semua hasil yang sudah dapat ditemukan menjadi terlihat, anchored, dan
aman untuk diinteraksikan.

#### Scope

- Occurrence-based source anchors.
- Highlight read-only untuk needs-review.
- Pemisahan actionable suggestion dan review annotation.
- Defined-term and legal-risk placeholder item types.
- Reference hukum pada definition popover normal.
- Wording no-finding yang aman.
- Navigation dan stale-state behavior.

#### Acceptance

- Duplicate phrases dapat di-highlight terpisah.
- Needs-review tampil amber tanpa Accept.
- Definition reference tersedia tanpa Debug toggle.
- Stale item tidak dapat diterapkan.
- UI utama tidak mengalami redesign besar.

#### Dependency

Tidak membutuhkan document context profile.

### Phase 4 — Structure dan Document Context Profile

#### Tujuan

Memberi konteks section dan dokumen tanpa mengulang seluruh dokumen pada setiap
model call.

#### Scope

- Structured section map.
- Document context profile.
- Section-aware segmentation.
- Context package.
- Profile cache dan fingerprint.
- Debug diagnostics untuk profile tanpa automatic telemetry.

#### Acceptance

- Segmen mengetahui parent heading.
- Defined terms dan parties tersedia pada profile.
- Multi-domain document tidak dipaksa menjadi satu topik.
- Qwen prompt menerima compact context, bukan full document.

#### Dependency

Phase 3 anchors digunakan untuk memetakan hasil struktur ke editor.

### Phase 5 — Defined-term dan legal-risk detectors

#### Tujuan

Menemukan finding penting yang saat ini tidak menghasilkan candidate.

#### Scope

- Defined-term extraction.
- Usage index.
- Case, alias, duplicate, conflict, dan undefined-term findings.
- Initial modal/negation/condition/exception signals.
- Cross-reference validation.
- Read-only highlight dan mark-reviewed flow.

#### Acceptance

- Defined term valid tetap dilindungi.
- Hanya inconsistent usage yang di-highlight.
- Risk finding tidak menawarkan replacement.
- Cross-reference invalid memiliki target/source evidence.

#### Dependency

Membutuhkan Phase 4 structure dan context profile.

### Phase 6 — Terminology dan definition resolution

#### Tujuan

Memperbaiki akurasi istilah dan menyediakan tiga jalur untuk definition
mismatch.

#### Scope

- Context-aware retrieval filters.
- Source applicability metadata.
- Reverse definition-to-term retrieval.
- Definition replacement options.
- Term replacement options.
- Reject recommendation.
- Multiple-source selection.
- Existing-reference UI reuse.

#### Acceptance

- Model tidak dapat memilih term di luar kandidat.
- Replace definition dan replace term terpisah.
- Setiap option memiliki source.
- Multiple definitions tidak digabung menjadi teks sintetis.
- Contract-defined override menghasilkan needs-review.

#### Dependency

Membutuhkan Phase 4 context dan Phase 3 UI boundary.

### Phase 7 — Incremental analysis dan performance

#### Tujuan

Mengurangi waktu rerun tanpa mempertahankan stale result.

#### Scope

- Dependency-aware invalidation.
- Per-stage caches.
- Section rerun.
- Early deterministic result publishing.
- Resource lifecycle optimization.
- Expanded observability.

#### Acceptance

- Perubahan lokal tidak selalu memproses seluruh dokumen.
- Corpus/rule/profile version change tetap melakukan invalidation yang benar.
- Cancellation mempertahankan partial valid results.
- p50/p95 setiap stage dapat dibandingkan dengan Phase 0.

#### Dependency

Membutuhkan model dan anchor yang stabil dari Phase 3 sampai Phase 6.

### Phase 8 — Lawyer-reviewed quality gate

#### Tujuan

Menentukan apakah kemampuan cukup akurat untuk digunakan di luar eksperimen
terkontrol.

#### Scope

- Lawyer review fixtures.
- Anonymized document scenarios.
- Per-category thresholds.
- Hard-negative suite.
- Regression corpus.
- Hardware performance matrix.
- Release gating.

#### Acceptance

- Safety violation harus nol.
- Source grounding harus dapat diverifikasi.
- False-positive rate memenuhi threshold yang disepakati.
- Quality gate dibedakan antara deterministic, terminology, definition, dan
  legal-risk.
- Qwen-only tidak menjadi production default tanpa bukti baru.

## 12. Strategi pengujian

### 12.1 Unit tests

#### Document profile

- Party extraction.
- Defined-term extraction.
- Multiple document domains.
- Regulation reference extraction.
- Unknown classification.
- Profile fingerprint invalidation.

#### Segmentation

- Heading hierarchy.
- Numbered clauses.
- Nested lists.
- Definition sentence.
- Condition dan exception.
- Table cells.
- UTF-16 offsets.

#### Language mechanics

- Approved exact rule.
- Pending rule excluded from production.
- Unknown spelling candidate.
- TataKata threshold.
- Protected terms.
- Number and identifier protection.
- Multiple non-overlap suggestions.
- Duplicate occurrence anchors.

#### Defined terms

- Undefined term.
- Unused term.
- Case inconsistency.
- Alias inconsistency.
- Duplicate definition.
- Conflicting definition.
- Two terms with similar definitions.
- Valid usage negative control.

#### Terminology

- Exact verified term.
- Definition-to-term.
- Contextually wrong regulation.
- Contract-defined override.
- Multiple plausible terms.
- Legacy corpus rejected.
- Missing source anchor.
- Semantic false positive.

#### Definitions

- Explicit match.
- Implicit match.
- Explicit mismatch.
- Mention but not definition.
- Correct definition, wrong term.
- Correct term, wrong definition.
- Multiple source definitions.
- Repealed or non-applicable source.
- No evidence.

#### Legal-risk signals

- Unilateral termination.
- Missing notice.
- Modal conflict.
- Negation conflict.
- Condition removed.
- Exception mismatch.
- Deadline conflict.
- Currency/nominal conflict.
- Missing cross-reference.
- Correct clause negative control.

#### UI mapping logic

- Suggestion maps to actionable highlight.
- Needs-review maps to read-only highlight.
- Definition match is optional display.
- Definition mismatch opens resolution card.
- Duplicate occurrences map separately.
- Stale anchors disabled.
- Accept and Dismiss affect only target item.

### 12.2 Integration tests

Setiap future capability membutuhkan end-to-end test:

~~~text
Document text
→ segmentation
→ detector
→ retrieval if needed
→ routing
→ model mock
→ validation
→ conflict resolution
→ editor item
→ accept/dismiss behavior
~~~

Test tidak cukup berhenti pada parser atau candidate builder.

### 12.3 ViewModel logic tests

Karena arsitektur menggunakan MVVM, test utama tidak perlu menjalankan UI:

- Run lifecycle.
- Progress state.
- Partial cancellation.
- Selected review item.
- Filters.
- Accept intent.
- Dismiss intent.
- Mark reviewed.
- Definition resolution selection.
- Stale invalidation.
- Snapshot restore.
- Incremental rerun.
- Error and retry state.

### 12.4 Privacy tests

Isi seluruh input dengan sentinel rahasia dan pastikan:

- Safe JSON tidak mengandung sentinel.
- Cache diagnostics tidak mengekspor teks.
- Error description tidak membawa document content.
- OSLog tidak membawa source text.
- Model reasoning tidak dipersistenkan.
- Export report tidak membawa URL atau party name dari dokumen.

### 12.5 Performance tests

- Cold resource preparation.
- Warm cache.
- Long document.
- Many short clauses.
- Dense defined-term document.
- Retrieval-heavy definition section.
- Deterministic-only document.
- Model-heavy ambiguous document.
- Cancellation.
- Low-memory behavior.

### 12.6 Manual smoke tests

- Import DOCX dengan heading, list, dan table.
- Preview dokumen asli.
- Automatic analysis.
- Highlight typo.
- Duplicate occurrence.
- Needs-review warning.
- Definition reference.
- Definition mismatch resolution.
- Defined-term navigation.
- Edit setelah analisis.
- Restart dan restore snapshot.
- Export reviewed document.
- Delete workspace tanpa menghapus external source.

### 12.7 Lawyer review set

Dataset review manusia perlu mencakup:

- NDA.
- Data processing agreement.
- Master service agreement.
- Employment agreement.
- Loan agreement.
- Procurement contract.
- Terms and conditions.
- Mixed Indonesian-English drafting.
- Amendments dan addenda.
- Hard negatives dari dokumen yang sudah direview.

Gunakan dokumen sintetis atau dokumen yang telah dianonimkan dan memiliki izin
penggunaan.

## 13. Metrik dan quality gate

### 13.1 Accuracy metrics

Ukur per mode dan per category:

- True positive.
- False positive.
- False negative.
- Precision.
- Recall.
- F1.
- Exact-span accuracy.
- Replacement accuracy.
- No-change accuracy.
- Definition classification accuracy.
- Definition alignment accuracy.
- Wrong-term versus wrong-definition accuracy.
- Defined-term finding accuracy.
- Legal-risk signal precision.

### 13.2 Grounding and safety

- Candidate grounding rate.
- Source anchor rate.
- Unsupported source claim count.
- Protected-content violation count.
- Number/modality/negation change count.
- Stale-anchor application count.
- Model-invented replacement count.
- Legacy-source actionable count.

Safety gate berikut bersifat mutlak:

- Model-invented replacement: 0.
- Unsupported source shown as fact: 0.
- Stale suggestion accepted: 0.
- Automatic document rewrite: 0.
- External document telemetry: 0.

### 13.3 Performance metrics

- Total run duration.
- Time to first deterministic result.
- p50 dan p95 per segment.
- p50 dan p95 per stage.
- Model load duration.
- Retrieval query count.
- Model call count.
- Cache hit.
- Repair count.
- Fallback count.
- Partial completion count.
- Memory high-water mark bila measurement tersedia.

### 13.4 Human-review metrics

Hanya dikumpulkan secara lokal dan opt-in:

- Accept rate.
- Dismiss rate.
- Mark-reviewed rate.
- Replacement edited after Accept.
- Definition option chosen.
- No-action rate.

Metrik tersebut tidak otomatis berarti model benar. Dismiss dapat terjadi
karena preference drafting, sedangkan Accept dapat terjadi tanpa pemeriksaan
yang cukup. Gunakan bersama qualitative lawyer feedback.

### 13.5 Menetapkan threshold

Jangan menetapkan threshold numerik berdasarkan asumsi. Prosesnya:

1. Lawyer menyetujui fixtures.
2. Jalankan Phase 0 baseline aktual.
3. Pisahkan deterministic, model, fallback, dan cache outcomes.
4. Tentukan risiko per category.
5. Tetapkan threshold dengan standar lebih tinggi untuk terminology,
   definition, dan legal-risk.
6. Simpan threshold sebagai versioned quality policy.

## 14. Batasan dan non-goals

Roadmap ini tidak mencakup:

- Membuat dokumen dari prompt.
- Chatbot legal umum.
- Legal advice atau legal opinion otomatis.
- Menentukan enforceability.
- Memberikan skor “dokumen benar”.
- Autonomous web research.
- Cloud inference atas dokumen pengguna.
- Automatic clause replacement.
- Automatic negotiation strategy.
- Model fine-tuning sebagai syarat setiap phase.
- Scanned PDF/OCR workflow.
- Redline kolaboratif multi-user.
- Full document revision history.
- Perubahan format workspace atau UTI tanpa review terpisah.
- Redesign besar dashboard atau editor.

Kemampuan tersebut memerlukan product decision, privacy review, dan scope
terpisah.

## 15. Definition of Done

Sebuah future phase dianggap selesai hanya jika:

### Product

- Perilaku pengguna jelas.
- Hasil tidak mengklaim legal correctness.
- User tetap mengendalikan setiap perubahan.
- Error dan empty state dapat dipahami.

### Architecture

- MVVM boundary dipertahankan.
- View tidak memiliki business logic analysis.
- Model result membedakan actionable dan read-only.
- Qwen tetap candidate-bound.
- Source and version dependencies eksplisit.

### Safety

- Tidak ada model-invented replacement.
- Protected content tetap utuh.
- Definition dan legal-risk tidak auto-applied.
- Stale anchor tidak dapat diterapkan.
- Source dapat ditelusuri.

### Tests

- Unit tests lulus.
- Integration tests lulus.
- ViewModel logic tests lulus.
- Privacy tests lulus.
- Hard-negative tests lulus.
- Cancellation dan partial result tests lulus.
- Lawyer review status tercatat.

### Validation

- Full XCTest menggunakan external DerivedData.
- Debug arm64 build lulus dengan CODE_SIGNING_ALLOWED=NO.
- Release arm64 build lulus untuk perubahan production.
- git diff --check lulus.
- Actual local-model smoke test dijalankan jika phase mengubah Qwen, TataKata,
  E5, prompt, atau resource lifecycle.
- Manual editor smoke test dijalankan jika phase mengubah highlight, popover,
  Accept, Dismiss, atau source anchoring.

### Documentation

- README diperbarui bila behavior production berubah.
- Schema dan version bump didokumentasikan.
- Migration atau invalidation behavior dijelaskan.
- Known limitations diperbarui.

## 16. Referensi source code saat ini

| Area | File |
| --- | --- |
| Document model | AMT/Dashboard/Models/DashboardDocument.swift |
| Structured document | AMT/Dashboard/Models/StructuredDocument.swift |
| Analysis snapshot | AMT/Dashboard/Models/DocumentAnalysisSnapshot.swift |
| Storage | AMT/Dashboard/Services/DocumentStorageManager.swift |
| Export | AMT/Dashboard/Services/DocumentExporter.swift |
| Editor composition | AMT/Suggestion/Views/DocumentEditorView.swift |
| Highlighted editor | AMT/Suggestion/Views/HighlightedDocumentTextEditor.swift |
| Suggestion popover | AMT/Suggestion/Views/SuggestionPopoverView.swift |
| Editor review model | AMT/Suggestion/Models/EditorSuggestion.swift |
| Review ViewModel | AMT/Features/AIConnector/ViewModels/AIConnectorViewModel.swift |
| Segmenter | AMT/Features/AIConnector/Services/LegalTextSegmenter.swift |
| Protection context | AMT/Features/AIConnector/Services/AIConnectorDocumentProtectionContextBuilder.swift |
| Rule pack | AMT/Features/AIConnector/Resources/AIConnectorRulePack.json |
| Deterministic engine | AMT/Features/AIConnector/Services/AIConnectorDeterministicSuggestionEngine.swift |
| Spell checker | AMT/Features/AIConnector/Services/AIConnectorSpellingCandidateProvider.swift |
| TataKata | AMT/Features/AIConnector/Services/TataKataLanguageScorer.swift |
| Candidate builder | AMT/Features/AIConnector/Services/AIConnectorCandidateBuilder.swift |
| Phase 2 policy | AMT/Features/AIConnector/Models/AIConnectorPhaseTwoModels.swift |
| Work queue | AMT/Features/AIConnector/Services/AIConnectorWorkQueue.swift |
| Qwen | AMT/Features/AIConnector/Services/QwenSuggestionService.swift |
| Definition detector | AMT/Features/AIConnector/Services/AIConnectorDefinitionDetector.swift |
| Definition analyzer | AMT/Features/AIConnector/Services/AIConnectorDefinitionAnalyzer.swift |
| Validator | AMT/Features/AIConnector/Services/AIConnectorSuggestionValidator.swift |
| Corpus store | AMT/Dictionary/Services/LegalDictionaryStore.swift |
| Observability | AMT/Features/AIConnector/Services/AIConnectorObservationCollector.swift |

Dokumen ini perlu ditinjau kembali setiap kali satu phase selesai. Item yang
sudah diimplementasikan harus dipindahkan dari future proposal ke baseline,
disertai bukti test dan batas validasi yang aktual.
