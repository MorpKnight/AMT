# Dokumen untuk pengujian manual

Semua isi fiktif. Ini fixture teknis, bukan template kontrak atau saran hukum.
Gunakan build terbaru dari branch `gi/flow-fix`; aplikasi terpasang/TestFlight
yang lebih lama belum tentu berisi source yang sedang diuji.

## Uji lewat UI aplikasi sekarang

1. Impor file `.txt` melalui kartu impor dokumen, lalu buka hasil impornya.
2. Jalankan review dokumen seperti biasa. Untuk kontrol tanpa model pilih mode
   deterministic pada panel AI Connector Debug; untuk model pilih hybrid.
   Sumber input harus dokumen aktif (`currentDocument`), bukan dummy panel.
   Tombol pada panel Debug bernama **Mulai review**.
3. Catat original, replacement/status, posisi highlight dan waktu yang dirasakan.
   Bedakan koreksi yang dapat diterapkan dari temuan baca-saja/needsReview.

### 01-koreksi-bahasa.txt

Mulai dari file pendek ini. Tiga bentuk salah berasal dari rule pack produksi:

| Teks di PASAL 2 | Koreksi yang diharapkan |
|---|---|
| memasukan | memasukkan |
| ditanda tangani | ditandatangani |
| di simpan | disimpan |

PASAL 3 berisi bentuk yang sudah benar. Tiga bentuk benar tersebut tidak
seharusnya dikoreksi lagi. Nama **PT Datta Nusantara** harus tetap utuh; `Datta`
pada nama perusahaan bukan typo yang boleh diganti menjadi `Data`.
Kalimat terakhir mempertahankan `wajib`, `5 hari kerja`, pemicu `sejak`, dan
pengecualian `kecuali`. Tidak diminta perubahan substansi terhadap kalimat ini.
Ini target pemeriksaan, bukan klaim bahwa seluruh kemungkinan temuan model
sudah diinventarisasi atau disetujui manusia.

Untuk memeriksa penerapan edit: terima satu koreksi, lakukan Undo dan Redo,
tutup/buka kembali dokumen, lalu periksa teks tersimpan. Untuk memeriksa anchor:
tambahkan satu baris sebelum temuan, jalankan review ulang, dan pastikan highlight
tetap menunjuk kata yang benar. Ini langkah uji manual yang masih perlu dilakukan
pengguna; pembuatan fixture tidak berarti interaksi UI tersebut sudah diuji.

### 02-dummy-asli.txt dan 03-dummy-datta.txt

File 02 menyalin `AIConnectorDummyDocument.initialContent` bawaan aplikasi.
File 03 identik kecuali satu penggantian pada PASAL 4 ayat 1:

```text
Pihak Kedua hanya boleh memproses Data Pribadi ...
Pihak Kedua hanya boleh memproses Datta Pribadi ...
```

Deklarasi **Data Pribadi** pada PASAL 1 tetap benar. Tujuan pengujian adalah
memeriksa apakah typo pada penggunaan istilah itu terdeteksi dan terjangkar ke
occurrence yang tepat. Benchmark produksi sebelumnya menemukan `Datta` sebagai
**needsReview**, belum koreksi actionable menjadi `Data`; jangan menyamakan
deteksi dengan keberhasilan mengganti kata.

Bandingkan kedua file pada konfigurasi yang sama. Review corpus/definisi dapat
menambah temuan lain; seluruh temuan tambahan perlu dibaca isinya. Nominal,
persentase, dan redaksi hukum di dokumen adalah data uji fiktif, bukan pernyataan
tentang ketentuan hukum yang berlaku saat ini.

## Uji tiga komponen drafting yang baru

**Mengimpor file 04 lalu menekan Mulai review belum menjalankan layanan drafting.**
UI sekarang memanggil review bahasa/istilah; belum mempunyai input brief yang
memanggil `AIConnectorViewModel.reviewDrafting`. Dokumen ini menyediakan bahan
untuk API/test backend tanpa mengubah UI.

Berikan satu klausul target dan brief terpisah dari isi dokumen:

| Target di file 04 | Brief peminta | Hasil yang dituju |
|---|---|---|
| Penyedia membayar dalam 5 hari setelah tagihan diterima. | Ubah tenggat pembayaran menjadi 10 hari. | Literal: hanya 5 → 10; pemicu tagihan tetap |
| Penyedia mengirim laporan bulanan. | Ubah frekuensi laporan menjadi mingguan. | Literal: hanya bulanan → mingguan |
| Penyerahan dilakukan di lokasi pilihan Pelanggan. | Cantumkan lokasi penyerahan; lokasinya belum diberikan. | Clarify: tanyakan lokasi, tanpa mengarang alamat |
| Penyedia mengirim laporan teknis atau laporan keuangan. | Pastikan laporan yang diminta disebutkan, tetapi jenis laporannya belum dipilih. | Clarify: tanyakan jenis laporan |
| Jasa diberikan jarak jauh. | Pastikan jasa diberikan jarak jauh. | No change |

Dua jalur literal telah diuji tanpa panggilan LLM. Tiga keputusan model di tabel
pernah muncul pada smoke test integrasi, tetapi bukan jaminan jawaban semua
model/run. Semua proposal drafting tetap baca-saja.

Untuk menjalankan kembali kasus-kasus tersebut melalui runtime backend yang
sudah tersedia, gunakan smoke test opt-in pada
[dokumentasi integrasi](../drafting-backend-integration.md#reproduksi-validasi).
Test tersebut memakai fixture dalam source test, **tidak membaca file 04**.

Untuk mencoba file 04 melalui pemanggil API backend, bentuk request seperti
contoh berikut pada konteks MainActor. `documentText` adalah isi file 04 dan
`viewModel` adalah ViewModel dokumen tersebut:

```swift
let target = "Penyedia membayar dalam 5 hari setelah tagihan diterima."
let request = DraftingReview.Request(
    documentText: documentText,
    documentRevision: DocumentFingerprinting.contentSHA256(documentText),
    brief: "Ubah tenggat pembayaran menjadi 10 hari.",
    scope: .rewriteTarget,
    clauses: [.init(id: "c1", text: target,
                    sourceRange: (documentText as NSString).range(of: target))],
    targetClauseIDs: ["c1"]
)
let result = await viewModel.reviewDrafting(request, documentText: documentText)
```

Jangan menempelkan brief ke akhir dokumen lalu menganggapnya sebagai instruksi
pengguna: isi dokumen tetap diperlakukan sebagai data. Pemanggilan file melalui
API di atas adalah contoh untuk caller backend, bukan tombol baru di aplikasi
atau klaim bahwa import UI sudah terhubung ke drafting.

## Status paket

File 01/04 ditulis sebagai fixture manual baru; tidak masuk benchmark atau quality
gate. File 02 diekstrak dari source dummy; file 03 hanya mengubah satu occurrence.
`manifest.json` mencatat checksum dan perbedaannya. File sudah diperiksa sebagai
UTF-8 dan target setiap contoh drafting muncul tepat sekali. Interaksi UI manual
belum dijalankan dalam penyiapan paket ini.
