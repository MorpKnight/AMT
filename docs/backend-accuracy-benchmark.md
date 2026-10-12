Benchmark akurasi backend — 12 Oktober 2026
===========================================

Eksperimen ini memakai backend working tree `gi/flow-fix`, setelah perubahan
cache/resource, teks panjang, dan evaluator. Algoritma produksi dan UI tidak
diubah untuk benchmark. SHA, checksum, konfigurasi, log, JSON per kasus, serta
hasil XCTest disimpan di `/private/tmp/amt-accuracy-task/`.

Seluruh label masih **pending**. Angka berikut mengukur kesesuaian terhadap
expectation sintetis, bukan ketepatan hukum atau kelayakan rilis. Gate yang
memerlukan persetujuan manusia tetap `insufficientEvidence`.

Metode
------

- 113 fixture catalog yang sama dijalankan sekali pada masing-masing mode
  deterministic, hybrid, dan model-only: 339 run dokumen.
- Qwen 3.5 base 4B, revision yang dipin aplikasi, greedy, thinking mati, seed 42;
  TataKata, E5, dan corpus produksi yang sama. Inference berjalan serial.
- Cache hasil/scoring dibersihkan sebelum setiap fixture; resource model tetap
  resident. Resource preparation dilaporkan terpisah.
- Pipeline berjalan melalui `AIConnectorViewModel`, dengan persiapan konteks,
  document review, queue, definition analysis, dan mapping editor.
- Precision/recall koreksi lokal memakai category, status, original,
  replacement, occurrence, dan anchor yang valid. Anotasi read-only tidak
  dihitung sebagai penggantian yang actionable.
- Kasus tanpa perubahan dilaporkan dengan dua ukuran berbeda: adanya edit
  actionable, dan seluruh hasil observasi termasuk anotasi/abstention.
- Ekspektasi semantik kosong (`noChange == false`) tidak dianggap gold negative.
  Agreement label semantik lama tidak digabungkan ke akurasi koreksi lokal.
- Kontrol tambahan menggunakan enam entry corpus eligible dengan satu sumber
  per istilah: teks sumber persis, perubahan `dapat` menjadi `tidak dapat`, dan
  penyebutan biasa. Seluruh input/sumber dibekukan sebelum inference.
- Enam typo di luar rule pack diulang tiga kali pada hybrid, dengan diagnostik
  proposal, scoring, routing, dan keputusan. Kandidat fixed hanya dipakai untuk
  diagnostik TataKata dan tidak dimasukkan ke pipeline produksi.

Hasil dan interpretasi
---------------------

Ketiga mode menghasilkan koreksi lokal yang sama:

| Mode | TP / FP / FN lokal | Precision lokal | Recall lokal | F1 lokal |
|---|---:|---:|---:|---:|
| Deterministic | 32 / 0 / 6 | 100% | 84,2% | 91,4% |
| Hybrid | 32 / 0 / 6 | 100% | 84,2% | 91,4% |
| Model-only | 32 / 0 / 6 | 100% | 84,2% | 91,4% |

Denominator ini terdiri atas **38 koreksi expected pada 42 fixture lokal**.
Ini bukan satu angka akurasi untuk seluruh 113 fixture. Dalam setiap mode:

- Ejaan: 15/21 koreksi ditemukan, recall 71,4%. Kelima belas keberhasilan
  berasal dari tiga pola rule pack yang masing-masing diulang lima kali.
  Keenam typo baru di luar rule pack tidak menghasilkan koreksi: 0/6. Dengan
  membobot setiap tipe typo sekali, tiga dari sembilan tipe berhasil dikoreksi.
- Tata bahasa: 17/17 koreksi ditemukan; semua menguji pola `wajib untuk → wajib`.
  Hasil ini belum mengukur cakupan tata bahasa Indonesia secara umum.
- Tidak ada edit actionable pada 35 fixture berlabel tanpa perubahan: 0/35
  false-positive case untuk edit. Ini tidak membuktikan risiko nol di produksi.
- Tidak ada anchor mapping/observasi yang invalid pada matriks utama. Tidak
  ada suggestion terminologi yang memakai sumber tidak eligible; pengukuran
  ini tidak menilai kebenaran hukum dari isi sumber.

Satu putaran fixture membutuhkan total waktu analisis 12,17 detik pada
deterministic, 277,47 detik pada hybrid, dan 275,84 detik pada model-only.
Preparation resource terpisah: 2,70 detik. Ini satu pengukuran serial, bukan
median benchmark performa; mode model juga mengerjakan klasifikasi/semantik
tambahan. Kesimpulan yang didukung ialah **tidak ada tambahan recall koreksi
lokal pada sampel ini**, bukan bahwa pekerjaan semantik tidak bermanfaat.

Penyebab enam koreksi yang terlewat
---------------------------------

Spell checker produksi memiliki bahasa `id` dan mengusulkan pengganti expected
untuk seluruh enam typo. Lima kandidat benar dibuang oleh provider sebelum
TataKata/Qwen karena pertukaran huruf dihitung sebagai dua edit:

| Original → expected | Masuk provider | Delta TataKata untuk kandidat fixed | Lolos threshold 0,25 |
|---|---:|---:|---:|
| `perjanijan → perjanjian` | Tidak | 1,685 | Ya |
| `kewajban → kewajiban` | Ya | 1,002 | Ya |
| `pemabyaran → pembayaran` | Tidak | 0,983 | Ya |
| `perjanjain → perjanjian` | Tidak | −1,061 | Tidak |
| `dokumne → dokumen` | Tidak | 1,002 | Ya |
| `laproan → laporan` | Tidak | 0,970 | Ya |

Delta fixed adalah diagnostik terpisah; ia tidak mengubah hasil pipeline.
`perjanjain` tetap membutuhkan penelusuran scoring apabila transposisi nanti
didukung. Mengurangi threshold sedikit tidak menyelesaikan delta negatif ini.

`kewajban` lolos proposal/scoring dan mencapai review, tetapi ditolak pada
validator. Diagnostik produksi mencatat rejection class `validator`, bukan
keputusan Qwen `REJECT`. Pengujian validator langsung pada span yang sama
mengidentifikasi `legalStructureChanged`: pengganti menambahkan token
`kewajiban`, yang berada dalam daftar structural marker. Guard ini menjaga
perubahan makna; jangan menonaktifkannya untuk mengejar recall.

Keenam kasus diulang tiga kali pada hybrid dengan cache dibersihkan. Seluruh
18 pengulangan tetap tidak menghasilkan finding koreksi; penolakan validator
untuk `kewajban` konsisten pada ketiga pengulangan.

Kontrol definisi dengan sumber eligible
--------------------------------------

Enam sumber adalah Sarana perkeretaapian, Sertifikat Deposito, Usia Pensiun,
WUPK, Objek Sita, dan Tempat Uji Kompetensi. Setiap sumber hanya memiliki satu
entry eligible dalam lookup istilah. Teks/sumber dibekukan sebelum run.
Delapan belas input dijalankan pada deterministic dan hybrid: 36 run kontrol.

| Kontrol | Deterministic | Hybrid |
|---|---|---|
| Definisi persis sama dengan sumber | MATCH 6/6 | MATCH 6/6 |
| `dapat` diganti menjadi `tidak dapat` | MATCH 0/6; needsReview 6/6 | MATCH 0/6; needsReview 6/6 |
| Penyebutan istilah biasa | Tidak ada assessment 6/6 | Tidak ada assessment 6/6 |

Sumber yang dipilih benar pada seluruh 12 assessment per mode. Tidak ada
anchor invalid pada kontrol. **Abstention pada negasi tidak dihitung sebagai
keputusan semantik yang tepat dan lengkap**: pada hybrid, empat kasus gagal
dengan `AIConnectorDefinitionReviewParserError.invalidDecision`, sedangkan dua
kasus menghasilkan `NOT_A_DEFINITION/NOT_APPLICABLE` yang bertentangan dengan
pola eksplisit kuat. Agregator mempertahankan `needsReview`.

Jadi, hasil akhir menjaga guard pada keenam kasus negasi, tetapi model belum
menghasilkan klasifikasi/alignment valid yang menjelaskan perbedaan tersebut.
Raw tool arguments dari empat parser failure tidak tersedia dalam report ini;
kita belum dapat menentukan nilai atau pasangan field spesifik penyebabnya.
Inspeksi source menemukan prompt memperbolehkan MATCH/MISMATCH/NEEDS_REVIEW
untuk semua classification selain NOT_A_DEFINITION, sementara parser meminta
NEEDS_REVIEW dipasangkan hanya dengan NEEDS_REVIEW. Ketidaksesuaian kontrak ini
merupakan kandidat penyebab yang perlu diperiksa, bukan kesimpulan dari raw output.

Noise, coverage, dan label
-------------------------

- Dua nominal uang (`Rp 1.000.000` dan `Rp 2.000.000`) menghasilkan finding
  rujukan internal untuk substring `000.000`. Regex menerima angka bertitik
  tanpa bukti bahwa span tersebut merujuk struktur dokumen.
- Report observasi memiliki finding pada sembilan dari 35 no-change case per
  mode. Ini termasuk abstention yang mungkin dibutuhkan dan assessment
  NOT_A_DEFINITION yang tidak dimapping menjadi anotasi editor. Angka tersebut
  bukan sembilan false-positive yang terlihat pengguna. Dua kasus nominal uang
  merupakan contoh noise yang dapat diidentifikasi secara langsung.
- `backend46-long-3` pada hybrid dan model-only memiliki semantic retrieval dan
  definition review berstatus `failed`. State run tetap `completed` dan
  `wasPartial == false`. Report eksperimen menandainya sebagai cakupan berkurang.
  Completed, skipped-by-policy, dan pemeriksaan semantik yang berhasil harus
  tetap dibedakan. Perlindungan cache/snapshot yang sudah ada tidak diuji ulang
  secara khusus dalam benchmark akurasi ini.
- 24 fixture memiliki expectation semantik kosong dan `noChange == false`.
  Precision/recall semantik untuk kasus tersebut belum dapat dihitung.
- Delapan expectation penggantian terminologi lama dan sejumlah expectation
  definisi memakai Data Pribadi. Entry corpus aktif berstatus `unreviewed` dan
  tidak actionable. Korporasi juga tidak memiliki primary eligible. Backend
  yang menahan penggantian tersebut tidak boleh dinilai salah hanya karena
  label lama mengharapkan edit.
- Label rujukan lama memakai status `flagged`, sedangkan backend menghasilkan
  `uncertain`; fixture missing-reference juga hanya melabel Pasal 99 meskipun
  teks menyebut Lampiran C yang tidak tersedia. Label perlu ditinjau sebelum
  digunakan sebagai gold untuk precision/recall lintas kategori.
- Tidak ada persetujuan manusia yang ditambahkan. Seluruh 113 fixture pending,
  dan evaluator yang ada menghasilkan gate `insufficientEvidence`.

Rekomendasi berdasarkan hasil
-----------------------------

1. **Dukung satu transposisi bersebelahan pada proposal ejaan.** Pertahankan
   sumber kandidat spell checker, batas kandidat, dan protection/anchor guard.
   Damerau distance satu menangani lima contoh ini lebih sempit daripada
   menerima seluruh edit distance dua. Target eksperimen berikutnya: recall
   proposal enam kasus mencapai 6/6 tanpa tambahan edit pada hard negative.
   Ini belum menjamin keenamnya menjadi suggestion; scoring/validator masih
   harus diperiksa.
2. **Selaraskan kontrak keputusan definisi dan tambahkan bounded repair untuk
   parser error yang recoverable.** Nyatakan pasangan classification/alignment
   secara eksplisit dan bedakan definition shape dari kesesuaian makna. Catat
   error code/pasangan pada diagnostik sintetis Debug. Definition analyzer saat
   ini menghentikan kandidat pada parser error, walaupun parser menyebut error
   itu recoverable. Maksimal satu format repair dapat dievaluasi dengan guard
   makna tetap aktif. Target: enam negasi memberi keputusan valid atau abstention
   yang beralasan, tanpa satu pun klaim MATCH yang salah.
3. **Pisahkan pemulihan typo structural keyword dari perubahan proposisi.**
   Untuk kasus seperti `kewajban`, pilihan aman awal adalah hasil `needsReview`
   yang teranchored beserta alasan guard, bukan menghilangkan temuan. Penggantian
   actionable memerlukan policy/label yang ditinjau untuk membuktikan bahwa
   operator, aktor, dan scope dipertahankan. Jangan membuat pengecualian umum
   untuk kata hak/kewajiban/negasi.
4. **Perbaiki deteksi rujukan angka dan pelaporan coverage.** Pakai marker dan
   struktur dokumen untuk angka bertitik; bedakan currency, tanggal, ID, dan
   rujukan yang benar. Pastikan output evaluator menilai stage failure, bukan
   hanya state completed, serta memakai filtering yang setara dengan mapping
   produk untuk metrik temuan yang terlihat.
5. **Perkuat gold set dan scoring sebelum mengubah threshold/model.** Review
   eligibility sumber dan label semantik, tambah pola grammar yang berbeda,
   kasus parafrasa/aktor/kondisi, serta negatif scoring dengan kandidat tetap.
   Telusuri bias tokenisasi/window pada `perjanjain`. Pisahkan calibration dari
   holdout; enam kasus benchmark ini bukan izin untuk menyetel threshold pada
   holdout. Review sumber Data Pribadi secara sah bila hendak memperluas cakupan
   actionable, tanpa mengubah status verification secara otomatis.

Peningkatan model bukan langkah pertama yang didukung eksperimen ini. Kandidat
yang hilang sebelum inference dan penolakan validator tidak dapat diselesaikan
hanya dengan model yang lebih besar. Ukur ulang per tahap setelah perubahan;
tambahan kandidat/repair dapat menambah panggilan model dan waktu total.

Reproduksi
----------

Gunakan Xcode dan dependency yang telah di-resolve project. Artefak model yang
dipin harus tersedia; benchmark opt-in dapat mengunduhnya bila belum tersedia.
Semua path output di luar repository. Contoh menjalankan kedua harness secara
serial dalam satu proses XCTest:

```sh
TEST_RUNNER_HF_HUB_CACHE=/private/tmp/amt-flow-fix-task/hf-hub \
TEST_RUNNER_AMT_RUN_ACCURACY_BENCHMARK=1 \
TEST_RUNNER_AMT_ACCURACY_OUTPUT=/private/tmp/amt-accuracy-reproduction \
TEST_RUNNER_AMT_ACCURACY_BUILD='<source/tests SHA256>' \
xcodebuild \
  -project AMT.xcodeproj \
  -scheme AMT \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/amt-accuracy-derived \
  -parallel-testing-enabled NO \
  -only-testing:AMTTests/AIConnectorAccuracyBenchmarkTests \
  -only-testing:AMTTests/AIConnectorAccuracyControlTests \
  -resultBundlePath /private/tmp/amt-accuracy-reproduction.xcresult \
  test CODE_SIGNING_ALLOWED=NO
```

Xcode meneruskan `TEST_RUNNER_*` ke XCTest tanpa prefix. Harness reguler
melewati seluruh test benchmark akurasi bila flag opt-in tidak disetel. Jangan memakai output path
atau `.xcresult` run sebelumnya untuk eksperimen baru.

Hitung ringkasan setelah seluruh harness selesai:

```sh
python3 docs/benchmarks/analyze-accuracy.py /private/tmp/amt-accuracy-reproduction
```

Script menolak matriks/kontrol/pengulangan yang parsial atau terduplikasi dan
menulis `accuracy-summary.json`. Ia tidak menyetujui label atau mengubah gate.

Artefak dan validasi
-------------------

Direktori run ini: `/private/tmp/amt-accuracy-task/`.

- `fixtures.json`, `definition-controls.json`: input/label/sumber beku.
- `records.json`, `definition-control-records.json`,
  `spelling-repeat-records.json`: hasil per fixture/run.
- `spelling-diagnostics.json`, `validator-diagnostic.json`: atribusi tahap.
- `accuracy-summary.json`, `reviewed-quality-gate.json`, `runtime.json`.
- `manifest.json`, `controls-manifest.json`, `validation.json`,
  `artifact-checksums.json`: provenance dan checksum. Hash harness dicatat per
  tahap; test diagnostik validator ditambahkan setelah matriks/kontrol model.
- `accuracy.xcresult`, `controls.xcresult`, `validator.xcresult`,
  `offline-final.xcresult`, serta log build/test.

Source produksi sebelum/sesudah identik:
`720be1a27702ab08de1cfa04868f2bde4b6ee2d0b0ce345c34087498575b04c3`.
Hanya dua file test baru, report ini, dan script analisis ditambahkan dalam
pekerjaan benchmark akurasi. Perubahan backend sebelumnya tetap dipertahankan.
Tidak ada commit/push atau perubahan UI/dependency/format dokumen.

`xcodebuild build-for-testing` Debug berhasil, termasuk build target aplikasi.
Matriks, kontrol model, dan diagnostik validator opt-in berhasil. Seluruh test
offline melalui `xcodebuild test-without-building` berhasil: **325 dieksekusi,
311 passed, 14 opt-in skipped, 0 gagal**. Destination macOS arm64, signing mati,
dan DerivedData eksternal. `git diff --check` berhasil. Release tidak dibuild
ulang pada pekerjaan ini karena tidak ada perubahan source produksi.
