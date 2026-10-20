# Benchmark backend yang terintegrasi

Jalur ini mengukur `AIConnectorViewModel` aplikasi, bukan processor terisolasi.
Input sintetis dibekukan: 96 review (48 lama + 48 baru) dan 181 historis.
Seluruh label pending; skor span/operasi bukan akurasi hukum atau approval ahli.

[Laporan](../../docs/benchmarks/legal-review-integration-2026-10-20.md) memuat
hasil serta batas source primary/final. Raw JSON/log/xcresult dan snapshot
source berada di `/private/tmp/amt-review-integration-20261020`.

## Reproduksi

Gunakan output baru di `/private/tmp/`, package cache dengan revision project,
dan Hub cache yang memuat resource dipin. Source drift ditolak bila melanjutkan
output root yang sama. Runner tidak mengubah source, format dokumen atau signing.

```sh
python3 -B run.py build --repo /path/to/AMT --output /private/tmp/amt-review-repro --packages /path/to/SourcePackages --hub /path/to/hf-hub
python3 -B run.py offline --repo /path/to/AMT --output /private/tmp/amt-review-repro --packages /path/to/SourcePackages --hub /path/to/hf-hub
```

Dengan argumen path yang sama, jalankan action `warm`, `cached`, `history`,
`incremental`, lalu `release` secara berurutan. Warm/cached default tiga ulang;
history satu ulang. Cached mempunyai priming fresh terpisah, lalu incremental
rerun tanpa perubahan. FullFresh tidak diberi override untuk menerima cache.
Inference harus serial; jangan membangun target lain sambil mengukur.

Model default benchmark Qwen3.5-4B MLX 4-bit, revision
`32f3e8ecf65426fc3306969496342d504bfa13f3`, greedy, thinking mati, seed42.
Resource preparation dilaporkan terpisah; sampler RSS/MLX10ms. Baseline asli
memerlukan snapshot source sebelum integrasi; HEAD saja tidak cukup karena ada
pekerjaan drafting yang belum di-commit saat baseline dibekukan.

`fixtures-primary.json` memuat expectation span/operasi pending. Label historis
ada di `expectations-history.json`; pertahankan pemisahan ejaan wajib, gaya,
rujukan, dan keputusan semantik. Jangan menilai warning definisi umum sebagai
bukti deteksi konflik hanya karena span-nya overlap.
