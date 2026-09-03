# Kaggle Qwen3.5-4B + IGED training

Artefak ini menyiapkan eksperimen fine-tuning `Qwen/Qwen3.5-4B` dengan
`syauqie/IGED` sebagai Indonesian Grammar Error Correction (GEC). Training
menggunakan QLoRA 4-bit dan menghasilkan adapter PEFT dalam format
Hugging Face/Transformers.

Notebook utama: [`kaggle_qwen35_iged_lora.ipynb`](./kaggle_qwen35_iged_lora.ipynb)

## Tujuan dan batasan

IGED mengajarkan koreksi bahasa umum, bukan proofreading legal. Hasil model
ini hanya kandidat untuk perbaikan ejaan, tata bahasa, diksi, dan struktur
kalimat. Jangan menggunakannya untuk mengubah kewajiban, hak, negasi, angka,
tanggal, defined terms, sanksi, atau substansi hukum secara otomatis.

Notebook menjalankan alur berikut:

1. pin revision model dan dataset serta mengaudit schema/split;
2. membersihkan, membatasi, dan mendeduplikasi pasangan `src -> trg`;
3. menjalankan baseline generation sebelum training;
4. menjalankan SFT smoke test dua langkah;
5. menjalankan pilot sweep tiga konfigurasi LoRA;
6. memilih konfigurasi dengan `eval_loss` terbaik;
7. menjalankan final training yang dibatasi jumlah langkah;
8. menghitung exact match, normalized match, character similarity, protected
   token preservation, dan menyimpan contoh hasil;
9. mengekspor adapter, tokenizer, config, audit, dan manifest.

Default notebook adalah `RUN_MODE = 'smoke'` agar tidak langsung memulai
training panjang. Ubah menjadi `pilot` untuk sweep, lalu `final` untuk
training final. Mode `final` menjalankan smoke test dan pilot terlebih dahulu.

## Menjalankan di Kaggle

1. Buat notebook baru dari file `.ipynb`, atau upload repository ini sebagai
   Kaggle Dataset/input.
2. Aktifkan Internet dan GPU.
3. Jalankan notebook dengan mode `smoke` sampai preflight dan adapter smoke
   berhasil.
4. Jalankan ulang dalam mode `pilot` dan simpan hasil konfigurasi.
5. Jalankan mode `final`. Output berada di `/kaggle/working/amt-qwen35-iged`.

Dataset dan model bersifat publik sehingga token Hugging Face tidak diperlukan.
Jika rate limit terjadi, notebook dapat membaca `HF_TOKEN` atau `HF_HUB_TOKEN`
dari Kaggle Secrets tanpa mencetak nilainya.

Jika sesi Kaggle berhenti sebelum final selesai, checkpoint disimpan di folder
run. Set `AMT_RESUME_CHECKPOINT` ke path checkpoint terakhir pada sesi lanjutan.
Jangan menganggap sesi yang terputus sebagai training selesai; periksa
`trainer_state.json` dan `final_generation_metrics.json`.

## Konfigurasi final awal

Nilai ini adalah starting point yang dipilih secara konservatif; mode `pilot`
tetap memilih berdasarkan `eval_loss`.

```text
model                   Qwen/Qwen3.5-4B
dataset                 syauqie/IGED
quantization            4-bit NF4 + double quantization
adapter                 LoRA/PEFT
max_length              768 tokens
per_device_batch_size   1
gradient_accumulation   16
learning_rate           1e-4
lora_r                  16
lora_alpha              32
lora_dropout            0.05
warmup_ratio            0.03
lr_scheduler            cosine
optimizer               paged_adamw_8bit
loss                    nll (Qwen3.5/TRL compatibility)
weight_decay            0.01
final_train_cap         300,000 pairs
final_eval_cap          2,000 pairs
final_max_steps         8,000
```

`max_steps` dan row cap sengaja membatasi eksperimen agar tidak menghabiskan
seluruh dataset sintetis tanpa bukti bahwa kualitas meningkat. Setelah pilot,
row cap dapat dinaikkan secara terukur.

Notebook secara eksplisit memakai `loss_type = 'nll'`. Jalur default chunked
cross-entropy pada sebagian versi TRL gagal saat menginspeksi `functools.partial`
yang digunakan oleh Qwen3.5. Jika standard NLL menyebabkan out-of-memory, turunkan
`MAX_LENGTH` dari 768 menjadi 512 sebelum mengubah batch size.

## Output dan integrasi AMT

Output utama adalah adapter PEFT, bukan model MLX siap pakai. Training dilakukan
dengan checkpoint Hugging Face, kemudian adapter perlu dievaluasi dan dikonversi
ke format/runtime MLX secara terpisah sebelum dihubungkan ke AMT. Adapter tidak
boleh menggantikan parser, validator, protected-span checks, RAG, atau alur
accept/reject yang sudah ada di aplikasi.

Notebook tidak mengubah repository AMT, tidak mengunggah dataset, dan tidak
menerapkan hasil model ke dokumen pengguna.
