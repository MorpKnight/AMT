# Integrasi backend review selektif

Backend ini melanjutkan pipeline yang sudah ada dengan pemeriksaan lokal dan
review pasangan klausul yang terikat evidence. Tidak ada perubahan View, model
LLM default, dependency, format dokumen, signing, atau deployment target.

## Perilaku yang tersedia

- Pengulangan kata kerja/kata fungsi tertentu mendapat proposal penghapusan satu
  occurrence. Nama, kutipan, code, akronim dan reduplikasi Indonesia dilindungi.
- Placeholder dan parameter “akan ditentukan/disepakati” menjadi catatan baca-saja.
- Perbedaan parameter pada kalimat dengan redaksi yang sama diberi dua bukti;
  sistem tidak memilih angka yang benar.
- Konflik kandidat antarklausul dan definisi dinilai oleh Qwen melalui tools
  read-only `read_clauses` dan `submit_review`. Model tidak dapat membuat
  replacement baru, menjalankan tool lain, atau memilih keputusan bisnis.
- Hybrid memakai routing konservatif. Pemeriksaan lokal tetap tersedia sebelum
  inference. Mode deterministic tidak memuat Qwen untuk pemeriksaan tambahan.
- Anggaran: 64 unit, 12 pasangan, 4 pasangan/batch, 3 turn/batch, 60 detik,
  prompt bertemplate maksimal 4.096 token dan output 768 token. Kegagalan,
  uncertain, batas unit/pasangan/token/waktu dan cancellation menghasilkan
  cakupan parsial dan menolak snapshot lengkap.

`policySkipped` berarti tidak ada signal atau tahap dilewati menurut pilihan
mode. `completePairs` berarti pasangan yang dijadwalkan selesai, bukan seluruh
semantik dokumen telah terbukti benar. RAG sumber hukum tetap memakai pipeline
existing; jalur baru menelaah evidence internal dokumen.

## Penerapan edit dan lifecycle

Proposal masuk ke tipe editor yang ada. Runtime memvalidasi revision, corpus,
identitas opsi, anchor dan eligibility lokal sebelum mutation yang disetujui
pengguna. Editor/coordinator existing menangani Undo/Redo, reconciliation dan
penyimpanan. Snapshot kompatibel merekonstruksi provenance lokal; hasil model
lama tidak menjadi izin edit substantif.

Cache bounded dimiliki masing-masing ViewModel. FullFresh melewati hasil cache;
perubahan text/heading/configuration/corpus dan perpindahan native mode
lokal/hybrid menginvalidasi hasil. Resource model memakai scheduler aplikasi yang
sama; cancellation tidak mematikan pemilik lain. Tekanan memori memangkas cache
baru melalui lifecycle existing.

## Mencoba secara manual

Buka/copy `manual-testing/05-selective-review-backend.txt` ke dokumen aplikasi,
lalu jalankan Hybrid. Fixture ini sintetis, bukan kontrak untuk digunakan.

1. `wajib wajib` dan `menerima menerima` seharusnya mempunyai koreksi minimal.
2. Tenggat 8 versus 21 hari seharusnya mempunyai catatan dengan kedua bukti,
   tanpa replacement angka.
3. Definisi Hari seharusnya dapat dibandingkan sebagai konflik kandidat;
   warning sumber eksternal yang tidak tersedia merupakan keluaran terpisah.
4. Alamat terbuka dan placeholder seharusnya tetap baca-saja.
5. Nama perusahaan, kutipan, dan biaya untuk objek berbeda tidak boleh mendapat
   koreksi tambahan dari pemeriksa baru. Warning native lain dapat tetap muncul.
6. Terapkan satu koreksi, Undo/Redo, simpan/buka ulang, dan jalankan ulang.
   Mengubah teks sebelum Accept harus menolak proposal yang stale.

## Batas yang masih ada

`Datta → Data` belum menjadi koreksi actionable oleh perubahan ini. Parafrasa
minim kata bersama dapat terlewat. Dokumen panjang mempertahankan jalur dasar
serta hasil lokal, tetapi konteks tambahannya bisa partial. Noise native pada
Lampiran, defined-term dalam kutipan, dan kalimat nominal belum diperbaiki di
integrasi ini. Memori tidak diklaim lebih hemat.

## Pengujian dan hasil

Test offline tidak memuat model. Build/test macOS arm64 memakai DerivedData
eksternal dan `CODE_SIGNING_ALLOWED=NO`. Benchmark model opt-in ada pada
`LegalReviewBackendBenchmarkTests`; matriks memakai fixture/model/resource beku.
Source akhir lulus build Debug/Release dan 424 test offline, 18
opt-in dilewati, nol kegagalan. Matriks utama 576 record, 181 input historis,
9 pasangan incremental/fresh aktual, dan dokumen manual sintetis selesai.
Setelah matriks, perbaikan dismissal divalidasi terpisah dengan 24 matched-model
smoke; seluruh keluaran/coverage tetap setara. Timing utama tetap berasal dari
source primary sebelum perbaikan lifecycle tersebut.

[Laporan dan batas pengukuran](benchmarks/legal-review-integration-2026-10-20.md)
memisahkan kualitas, latency, RSS/MLX, source primary/final dan status pending
review manusia. Input dan runner reproduksi ada di
[eksperimen integrasi](../experiments/legal-review-integration/README.md).
