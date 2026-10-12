Review manual fixture akurasi backend — 12 Oktober 2026
=======================================================

Saya membaca seluruh input 113 fixture, termasuk enam teks panjang secara utuh,
serta 18 kontrol dengan body sumber pembanding. Saya membuat keputusan tekstual
per kasus, menyimpannya, lalu membandingkannya dengan 339 keluaran pipeline dan
36 keluaran kontrol yang sudah tersedia. Ini review oleh assistant pada sesi
ini, bukan pemanggilan model pembanding melalui API dan bukan approval manusia.

Review ini **retrospektif, tidak blind**: hasil ringkasan sebelumnya dan satu
contoh record sudah terlihat. Label manual berasal dari pembacaan teks, bukan
salinan `fixture.expected`. Penilaian saya tidak membuktikan akurasi saya sendiri
atau ketepatan hukum. Tidak ada klaim peringkat SOTA, perubahan label produksi,
atau persetujuan fixture. Gate tetap `insufficientEvidence`.

Artefak manual terpisah di `/private/tmp/amt-manual-accuracy-review/`:

- `manual-review.json`: keputusan dan alasan untuk setiap input, lokasi UTF-16
  untuk ejaan/gaya/rujukan, digest input, dan keputusan terhadap body kontrol.
- `comparison.json`: perbandingan setiap fixture/mode, sumber corpus yang
  digunakan sistem, dan ringkasan perbedaan.
- `write_manual_review.py`: keputusan manual yang ditulis eksplisit. Script ini
  tidak membaca `fixture.expected` atau record sistem.
- `compare_review.py`: pencocokan mekanis setelah keputusan manual disimpan.
- `manifest.json`: digest artefak, kesesuaian resource dan source dengan
  benchmark sebelumnya, serta batas validasi.

Input/record asal tetap berada di `/private/tmp/amt-accuracy-task/`. Pipeline
tidak dijalankan ulang untuk review ini. Model, resource, fixture, dan hasil
sebelumnya tidak diubah. Hasil lengkap per kasus tercantum pada artefak JSON;
ringkasan di bawah menyorot perbedaan yang bermakna.

Perbandingan dari pembacaan manual
----------------------------------

| Aspek | Penilaian manual saya | Keluaran sistem yang sudah direkam |
|---|---|---|
| Ejaan wajib pada seluruh kategori | 24 occurrence, termasuk 3 pada teks panjang | 18/24 ditemukan pada ketiga mode; 6 terlewat |
| Enam typo baru | Keenamnya punya koreksi jelas dalam konteks | 0/6 ditemukan pada ketiga mode |
| `wajib untuk → wajib` | 17 saran keringkasan opsional | 17 suggestion berlabel grammar |
| Definisi persis body sumber | 6 definisi, MATCH terhadap body yang diberikan | MATCH 6/6 pada deterministic dan hybrid |
| `dapat → tidak dapat` pada predikat sama | Tetap definisi, MISMATCH terhadap body yang diberikan pada 6 kasus | 6/6 NEEDS_REVIEW; tidak ada MISMATCH yang tegas |
| Penyebutan biasa pada kontrol | 6 bukan definisi | Tidak ada assessment 6/6 |
| Rujukan hilang | Pasal 99 dan Lampiran C | Keduanya ditemukan; label lama hanya mencantumkan Pasal 99 |
| Nominal uang Rp10.000.000 | Nominal uang, bukan rujukan struktur | Dua fixture memunculkan rujukan untuk `000.000` |

18/24 atau 75% adalah kesesuaian keluaran dengan **penilaian assistant** untuk
ejaan pada input yang sama, bukan estimasi dari gold yang disetujui. Ini juga
bukan peningkatan model dari recall ejaan 15/21 (71,4%) sebelumnya: tiga typo
pada fixture kategori definition kini ikut dihitung. Keenam miss tetap sama.
Jangan menggabungkan 17 saran gaya dengan ejaan wajib untuk menyatakan akurasi
umum. Tidak ada suggestion ejaan actionable tambahan di luar 24 penilaian saya.

Enam koreksi yang menurut saya seharusnya muncul:

| Fixture | Original | Koreksi manual | Sistem hybrid |
|---|---|---|---|
| backend46-spelling-1 | perjanijan | perjanjian | Tidak ada finding |
| backend46-spelling-2 | kewajban | kewajiban | Tidak ada finding |
| backend46-spelling-3 | pemabyaran | pembayaran | Tidak ada finding |
| backend46-spelling-4 | perjanjain | perjanjian | Tidak ada finding |
| backend46-spelling-5 | dokumne | dokumen | Tidak ada finding |
| backend46-spelling-6 | laproan | laporan | Tidak ada finding |

Penilaian tersebut berasal dari kalimat, bukan skor TataKata. Penelusuran kode
dan diagnostik lama kemudian menjelaskan mekanismenya: provider mensyaratkan
lowercase dan Levenshtein satu edit, sehingga lima transposisi terbuang sebelum
review. `kewajban` mencapai review tetapi validator menolak pemulihan marker
`kewajiban` sebagai `legalStructureChanged`. Kandidat fixed `perjanjain` juga
mendapat delta TataKata negatif pada eksperimen terdahulu. Karena itu, sekadar
menurunkan threshold tidak menutup seluruh miss.

`Datta → Data` tidak ada pada 113 fixture ini dan tidak masuk denominator.
Konteks kalimat pengguna belum tersedia pada artefak. Jalur provider saat ini
menolak original kapital; golden TataKata lama menolak pasangan lowercase
`datta → data`. Ini dua hambatan berbeda, bukan bukti inference end-to-end untuk
`Datta` pada dokumen pengguna. Nama produk `Memasukan` dan perusahaan
`PT Di Simpan Indonesia` pada fixture protected harus tetap dipertahankan.

Masalah baru yang terlihat saat memeriksa sumber
-----------------------------------------------

Terdapat delapan assessment pada hybrid, dan delapan pada model-only, yang
memakai source term berbeda dari document term. Perbedaan nama tidak otomatis
berarti salah: alias dan istilah terkait bisa relevan. Namun contoh berikut
jelas tidak menyediakan definisi untuk istilah target:

| Fixture / istilah dokumen | Source term yang benar-benar dipilih | Hasil sistem |
|---|---|---|
| phase8-p0-definition-explicit-mismatch-1 / Data Pribadi | Ketransmigrasian | NOT_A_DEFINITION / NOT_APPLICABLE |
| backend46-eligibility-2 / Korporasi | Harta Benda Wakaf | NOT_A_DEFINITION / NOT_APPLICABLE |
| backend46-protected-1 / nama produk Memasukan | Ijarah | NEEDS_REVIEW / NEEDS_REVIEW |
| backend46-protected-2 / Nama perusahaan | Tunjangan keluarga | NOT_A_DEFINITION / NOT_APPLICABLE |
| backend46-eligibility-5 / Perusahaan | Proposal Perubahan Bentuk Badan Hukum | NEEDS_REVIEW / NEEDS_REVIEW |

Source term diverifikasi langsung melalui `sourceID` pada record dan
`dictionary_primary.json`, bukan ditebak dari judul peraturan. Source yang
verified/actionable tidak otomatis relevan terhadap target. Pada keluaran ini
tidak ada edit terminologi actionable; guard menahan penggantian. Temuan ini
menyangkut kualitas evidence yang dipilih dan keputusan review, bukan bukti
bahwa sumber salah sudah diterapkan ke editor.

Ada penjelasan implementasi yang lebih spesifik daripada menganggap model
kurang mampu:

1. Detector mencoba sumber exact yang eligible. Ketika tidak ada, ia dapat
   memakai retrieved candidates tanpa mensyaratkan kesesuaian identitas term
   dengan explicit signal.
2. `AIConnectorDefinitionCandidate.term` berasal dari `match.entry.term`.
3. Prompt mengirim `TERM: candidate.term` dan menanyakan apakah TARGET
   mendefinisikan istilah yang diberikan. Pada kasus Data Pribadi di atas,
   istilah yang diberikan ke model adalah Ketransmigrasian.
4. Karena itu, NOT_A_DEFINITION dapat konsisten dengan tugas yang dikirim ke
   model, walaupun kalimat dokumen sebenarnya sedang memberi definisi yang
   buruk tentang Data Pribadi. Agregasi kemudian mengasosiasikan hasil itu
   dengan document term. Ini pencampuran dua pertanyaan.

Penjelasan tersebut didukung binding source dan kode pembentukan prompt. Report
tidak merekam raw argumen seluruh call, sehingga alasan internal model tetap
tidak diketahui. Saya menilai dua kalimat Data Pribadi/Korporasi tersebut
berfungsi sebagai definisi tekstual, meskipun isinya bermasalah atau sumbernya
tidak cocok. Definisi yang salah tidak dengan sendirinya menjadi bukan definisi.

Kelengkapan keputusan berbeda dari guard yang aman
-------------------------------------------------

Pada enam kontrol negasi, source body dan target tersedia utuh. Contohnya:
`kendaraan yang dapat bergerak di jalan rel` dibandingkan dengan `kendaraan yang
tidak dapat bergerak di jalan rel`. Dalam perbandingan tekstual ini, keduanya
tidak ekuivalen. Saya menghasilkan DEFINITION/MISMATCH pada semua enam kasus.

Sistem menahan MATCH pada semuanya, tetapi hybrid mengalami empat parser
failure dan dua konflik antara pola definisi eksplisit dengan keputusan model
bukan definisi. NEEDS_REVIEW menjaga keselamatan; itu belum menyelesaikan tugas
semantik. Report raw tidak memungkinkan atribusi nilai field yang salah pada
empat parser failure.

Source juga memperlihatkan prompt membolehkan alignment MATCH/MISMATCH untuk
classification NEEDS_REVIEW, sementara parser mengharuskan NEEDS_REVIEW hanya
berpasangan dengan NEEDS_REVIEW. Kontrak ini perlu disejajarkan, tetapi belum
terbukti sebagai penyebab spesifik empat failure tanpa raw output.

Kekurangan benchmark, selain kekurangan sistem
-----------------------------------------------

- Keberhasilan ejaan lama mengulang tiga jenis typo lima kali dengan nomor
  Pihak/Dokumen berbeda. Grammar positif mengulang satu pola 17 kali. Ini
  kesesuaian pada pola terbatas, bukan cakupan bahasa yang luas.
- Evaluator ringkasan memfilter kategori fixture sebelum menghitung koreksi.
  Ia melewatkan tiga `memasukan` pada backend46-long-1/2/6 walaupun sistem
  menemukan semuanya. Label occurrence perlu lintas kategori.
- Label Lampiran C belum ada. Satu teks berisi dua masalah tidak cukup diberi
  satu expected finding.
- Menghapus `untuk` dapat membuat kalimat ringkas, tetapi dalam penilaian saya
  bukan perbaikan atas tata bahasa yang pasti salah. Ukur gaya terpisah atau
  sebagai kepatuhan terhadap kebijakan editorial.
- Fixture eligibility umumnya hanya menyebut kamus lama/peraturan tak diketahui
  tanpa source ID/status yang menjadi constraint. Case tersebut belum menguji
  penerapan eligibility terhadap sumber tertentu secara kuat.
- Kalimat kategori operators/quantities terpisah tidak membuktikan guard mampu
  membedakan pasangan definisi dengan perubahan aktor, angka, satuan, atau
  pengecualian. Perlu pasangan target/body sumber dan keputusan expected.
- Fixture incremental berisi teks akhir statis. Run ini tidak menguji urutan
  perubahan meskipun pengujian incremental lain tersedia di tahap sebelumnya.
- Enam teks panjang berisi repetisi ekstrem; berguna untuk stress/window, tetapi
  bukan representasi dokumen alami yang bebas masalah. Saya mencatat kebutuhan
  review keterbacaan tanpa mengarang pengganti yang menghapus kondisi di akhir.
- Anotasi read-only/noise dan incomplete coverage harus dinilai terpisah dari
  keamanan edit. Salah membaca nominal uang tetap masalah meski tidak ada edit.

Prioritas perbaikan yang mengikuti temuan
-----------------------------------------

1. **Cakupan proposal ejaan.** Dukung transposisi huruf, serta kapitalisasi
   berdasarkan konteks tanpa mengoreksi nama diri sembarangan. Pertahankan span,
   protected content, dan review. Catat alasan token/kandidat dibuang. Bila
   proposal lokal gagal, evaluasi jalur penemuan kandidat kontekstual yang
   terbatas; Qwen yang hanya menilai kandidat tidak dapat memulihkan kandidat
   yang tidak pernah masuk. Ukur biaya tambahan jalur ini.
2. **Identitas target dan relevansi sumber.** Bedakan document term dan source
   term di input review. Klasifikasi apakah teks adalah definisi harus merujuk
   document term. Perbandingan ke sumber hanya dilakukan setelah relevansi/
   scope lolos. Exact/alias valid dan definisi internal lebih kuat daripada
   source yang sekadar verified. Sumber tidak cocok ditolak sebelum inference.
3. **Pemulihan typo marker hukum.** Bedakan restorasi leksikal seperti kewajban
   dari perubahan kewajiban/izin/larangan. Jangan menonaktifkan guard; kandidat
   yang belum memenuhi bukti cukup dapat menjadi review terjangkar, bukan
   hilang tanpa penjelasan.
4. **Keputusan definisi yang lengkap.** Sejajarkan prompt/schema/parser dan
   gunakan repair format yang bounded. Pisahkan failure teknis, ketidakpastian
   sumber, konflik pola, dan MISMATCH tekstual yang jelas. Tetap hindari klaim
   legal alignment ketika tidak ada evidence yang layak.
5. **Perbaiki pengukuran.** Label seluruh occurrence lintas kategori, pisahkan
   ejaan wajib/gaya/rujukan/semantik, tambah Datta dalam konteks lengkap dan
   hard negative nama diri, serta split berdasarkan jenis typo/scenario.
   Laporkan abstention dan completeness selain precision/recall. Review manusia
   tetap diperlukan sebelum menjadikan label sebagai gold atau quality gate.

Perubahan tahap ini hanya dokumentasi dan artefak review eksternal. Tidak ada
perubahan backend/UI, commit, atau push. Build dan test model tidak diulang;
validasi tahap ini adalah integritas source/resource/artefak, pencocokan 113×3
record dan 18×2 kontrol, anchor UTF-16 penilaian manual, serta `git diff --check`.
