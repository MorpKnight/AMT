# Perubahan flow backend

Flow baru mempublikasikan hasil lokal setelah struktur/profil lokal dan protection context tersedia. Klasifikasi Qwen serta review dokumen kemudian berjalan, sebelum queue review konteks menyelesaikan hasil tiap segmen. Hasil akhir melakukan upsert terhadap occurrence yang sama, mempertahankan identitas temuan lokal, dan menghitung progress segmen sekali. Kedua jenis event hasil memerlukan acknowledgement dari consumer.

## Boundary resource dan cache

Composition aplikasi memiliki satu `AIConnectorInferenceScheduler` bersama bagi Qwen, TataKata, dan E5. Popover memakai prioritas interactive; scheduler memberi kesempatan background setelah tiga pekerjaan interactive berturut-turut. Operasi yang sedang memegang lease menyelesaikan/keluar dari operasinya sebelum pekerjaan berikutnya diterima. Cancellation menghapus request milik task yang dibatalkan dan tidak memanggil pembatalan loading global lintas dokumen.

Cache hasil lengkap diperiksa sebelum retrieval dan scoring. Key mengandung teks/context/anchor, profil, konfigurasi generation, versi corpus/rule/validator/pipeline serta revision resource. Flag thinking dibedakan meskipun profil generation eksplisit sama; cache definisi juga memasukkan posisi segmen dan presence penalty agar assessment tidak membawa anchor revisi lain. Hasil gagal, fallback, ditolak atau tidak lengkap tidak masuk cache lengkap. `fullFresh` membersihkan cache hasil dan scoring; resource resident tetap tersedia. Hook Debug benchmark dapat mempertahankan cache untuk mengukur cached rerun secara eksplisit.

Incremental planner memeriksa konfigurasi dan dependensi dokumen, memperluas invalidation ke tetangga serta scope definisi/rujukan. Profil hasil klasifikasi diperiksa ulang sebelum reuse. Baseline incremental tetap menunjuk revisi terakhir yang dianalisis; mengetik beberapa perubahan tidak menggantinya dengan hasil yang sudah diinvalidasi. Hanya segmen yang selesai dari run sebelumnya boleh direuse, termasuk setelah cancellation. Scope ambigu kembali memproses seluruh dokumen. Snapshot lengkap tidak dibuat untuk analisis yang gagal, dibatalkan, terlalu panjang, atau konfigurasi yang sudah berubah. Versi profil pipeline dinaikkan; format dokumen tetap sama.

## Keputusan dan penerapan edit

Lexical retrieval berjalan terlebih dahulu; E5 diminta untuk indikasi definisi/terminologi yang memerlukan retrieval lebih lanjut. Melewati E5 berdasarkan kebijakan dicatat sebagai `skippedByPolicy`, bukan bukti semantic review. Deterministic control tidak meminta inference semantik.

Semua kandidat non-overlap diproses dalam batch berukuran tiga. Spell checker menyediakan kandidat, TataKata menyaring berdasarkan skor bahasa, dan Qwen memberi keputusan terstruktur pada kandidat yang memerlukan konteks. Bounded repair dan conflict resolver tetap dipakai.

Perbandingan definisi lokal hanya menyatakan match untuk token makna yang sama. Negasi, modalitas, angka, kondisi, pengecualian, operator logika, dan penanda aktor tertentu menjadi guard tambahan terhadap keputusan MATCH model. Parafrasa yang belum dibuktikan tetap membutuhkan review. Guard ini konservatif dan tidak membuktikan ekuivalensi hukum.

Referensi corpus yang belum verified, tidak actionable, atau belum in force tetap dapat ditampilkan sebagai referensi. Penggantian actionable memerlukan sumber eligible dan pemeriksaan definisi internal dokumen. Penerapan suggestion/resolution memeriksa teks/revisi dokumen, profil konfigurasi, corpus, identitas opsi dan anchor sebelum mutation. Mutation MainActor memakai Undo/Redo, reconciliation, dan autosave yang sudah ada. Snapshot Undo merupakan salinan immutable teks sebelum edit.

## Pemeriksaan regresi

Test offline mencakup publikasi lokal sebelum classifier yang ditunda, acknowledgement/upsert/progress, kandidat tambahan, negasi/modalitas/aktor, sumber tidak eligible, konflik definisi di bagian lain dokumen, stale edit, Undo/Redo dan pembaruan binding dokumen, cache fresh, serta cancellation/prioritas scheduler. Pembatalan queue membawa ID run agar pembatalan yang terlambat tidak mengenai run penggantinya. Benchmark full pipeline menambahkan pasangan incremental/fresh dengan hasil dinormalisasi tanpa UUID/timestamp.

Resource dan dependency tetap memakai yang sudah tersedia. Tidak ada perubahan MVVM secara luas, format dokumen, target, signing, entitlement, deployment target, commit, maupun push.

## File yang berubah

Daftar source, test, dan dokumentasi implementasi/benchmark dalam pekerjaan ini:

- `AMT/AMTApp.swift`
- `AMT/Dictionary/Services/LegalDictionaryStore.swift`
- `AMT/Features/AIConnector/Models/AIConnectorDefinitionModels.swift`
- `AMT/Features/AIConnector/Models/AIConnectorDefinitionResolutionModels.swift`
- `AMT/Features/AIConnector/Models/AIConnectorIncrementalAnalysisModels.swift`
- `AMT/Features/AIConnector/Models/AIConnectorModels.swift`
- `AMT/Features/AIConnector/Models/AIConnectorObservationModels.swift`
- `AMT/Features/AIConnector/Models/AIConnectorPhaseTwoModels.swift`
- `AMT/Features/AIConnector/Services/AIConnectorBenchmarkRunner.swift`
- `AMT/Features/AIConnector/Services/AIConnectorCandidateBuilder.swift`
- `AMT/Features/AIConnector/Services/AIConnectorDefinitionAnalyzer.swift`
- `AMT/Features/AIConnector/Services/AIConnectorDefinitionResolutionService.swift`
- `AMT/Features/AIConnector/Services/AIConnectorDocumentContextCoordinator.swift`
- `AMT/Features/AIConnector/Services/AIConnectorIncrementalAnalysisPlanner.swift`
- `AMT/Features/AIConnector/Services/AIConnectorInferenceScheduler.swift`
- `AMT/Features/AIConnector/Services/AIConnectorObservationCollector.swift`
- `AMT/Features/AIConnector/Services/AIConnectorSpellingCandidateProvider.swift`
- `AMT/Features/AIConnector/Services/AIConnectorSuggestionConflictResolver.swift`
- `AMT/Features/AIConnector/Services/AIConnectorSuggestionValidator.swift`
- `AMT/Features/AIConnector/Services/AIConnectorWorkQueue.swift`
- `AMT/Features/AIConnector/Services/LegalTextSegmenter.swift`
- `AMT/Features/AIConnector/Services/QwenSuggestionService.swift`
- `AMT/Features/AIConnector/Services/TataKataLanguageScorer.swift`
- `AMT/Features/AIConnector/ViewModels/AIConnectorViewModel.swift`
- `AMT/Shared/LegalKnowledge/Services/LegalSemanticRetriever.swift`
- `AMT/Suggestion/Views/DocumentEditorView.swift`
- `AMT/Suggestion/Views/HighlightedDocumentTextEditor.swift`
- `AMTTests/AIConnectorDefinitionAnalysisTests.swift`
- `AMTTests/AIConnectorFlowBenchmarkTests.swift`
- `AMTTests/AIConnectorFlowFixTests.swift`
- `AMTTests/AIConnectorModelBenchmarkTests.swift`
- `AMTTests/AIConnectorP011CandidateFirstTests.swift`
- `AMTTests/AIConnectorP09OfflineTests.swift`
- `AMTTests/AIConnectorPhaseSixTests.swift`
- `AMTTests/AIConnectorTataKataPilotTests.swift`
- `AMTTests/AIConnectorTests.swift`
- `README.md`
- `docs/benchmarks/baseline-measurement-overlay.patch`
- `docs/flow-fix-implementation.md`
- `docs/flow-fix-methodology.md`
- `docs/flow-fix-benchmark.md`
