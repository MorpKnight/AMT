//
//  AIConnectorDummyDocument.swift
//  AMT
//
//  Built-in document fixture for testing the AI Connector.
//

import Foundation

enum AIConnectorDummyDocument {
    private static let identifier = "4A7A2A0D-8C5B-4B47-9E4D-5A0C7F4C0501"

    static let id: UUID = {
        guard let id = UUID(uuidString: identifier) else {
            preconditionFailure("The AI Connector dummy document ID must be a valid UUID")
        }
        return id
    }()

    static let title = "AI Connector — Test Document"

    static let initialContent = """
    PERJANJIAN KERJA SAMA
    PENGELOLAAN LAYANAN DIGITAL DAN DATA

    Nomor: AMT/PKS/2026/001

    Pada hari Senin, tanggal 10 Agustus 2026, bertempat di Jakarta, telah dibuat dan ditanda tangani Perjanjian Kerja Sama Pengelolaan Layanan Digital dan Data (selanjutnya disebut “Perjanjian”) oleh dan antara:

    1. PT Arunika Data Nusantara, suatu perseroan terbatas yang didirikan berdasarkan hukum Republik Indonesia, berkedudukan di Jakarta, dalam hal ini diwakili oleh Raka Pratama selaku Direktur, selanjutnya disebut “Pihak Pertama”; dan

    2. PT Cakrawala Legal Teknologi, suatu perseroan terbatas yang didirikan berdasarkan hukum Republik Indonesia, berkedudukan di Bandung, dalam hal ini diwakili oleh Nadia Kurnia selaku Direktur, selanjutnya disebut “Pihak Kedua”.

    Pihak Pertama dan Pihak Kedua secara bersama-sama disebut “Para Pihak” dan masing-masing disebut “Pihak”. Para Pihak terlebih dahulu menerangkan hal-hal sebagai berikut:

    a. Pihak Pertama mengelola platform digital untuk administrasi dokumen dan memerlukan dukungan pengelolaan data;

    b. Pihak Kedua mempunyai kemampuan teknis untuk menyediakan layanan tersebut; dan

    c. Para Pihak sepakat untuk melaksanakan kerja sama ini berdasarkan syarat dan ketentuan dalam Perjanjian.

    PASAL 1
    DEFINISI DAN INTERPRETASI

    1. “Layanan” adalah penyediaan, pemeliharaan, dan dukungan teknis atas platform digital sebagaimana dijelaskan dalam Lampiran I.

    2. Untuk keperluan pelaksanaan Layanan, data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik selanjutnya disebut “Data Pribadi”.

    3. Dalam Perjanjian ini, kumpulan orang dan/atau kekayaan yang terorganisasi, baik merupakan badan hukum maupun bukan badan hukum, yang dapat dimintakan pertanggungjawaban hukum selanjutnya disebut “Korporasi”.

    4. Suatu keadaan yang terjadi di luar kehendak para pihak dalam Kontrak dan tidak dapat diperkirakan sebelumnya, sehingga kewajiban yang ditentukan dalam Kontrak menjadi tidak dapat dipenuhi, selanjutnya disebut “Keadaan Kahar”.

    5. “Informasi Rahasia” berarti seluruh informasi yang diterima oleh salah satu Pihak dari Pihak lainnya dalam rangka pelaksanaan Perjanjian, baik dalam bentuk tertulis, lisan, elektronik maupun bentuk lainnya.

    6. Judul pasal dibuat untuk kemudahan membaca dan tidak mempengaruhi penafsiran ketentuan dalam Perjanjian. Istilah dalam bentuk tunggal mencakup bentuk jamak dan sebaliknya sepanjang konteksnya menghendaki demikian.

    PASAL 2
    RUANG LINGKUP LAYANAN

    1. Pihak Pertama menunjuk Pihak Kedua untuk menyediakan Layanan pengelolaan dokumen, pencadangan, dan dukungan teknis sesuai dengan ruang lingkup yang disepakati Para Pihak.

    2. Pihak Kedua wajib untuk menyediakan Layanan secara profesional, aman, dan sesuai dengan jadwal yang telah disepakati.

    3. Pihak Kedua akan melakukan konfigurasi awal, pemantauan sistem, dan pemeliharaan berkala terhadap komponen Layanan.

    4. Setiap pekerjaan tambahan di luar ruang lingkup tersebut harus disetujui secara tertulis oleh Para Pihak sebelum pekerjaan dimulai.

    PASAL 3
    HAK DAN KEWAJIBAN PARA PIHAK

    1. Pihak Kedua bertanggungjawab untuk menjaga ketersediaan Layanan dan wajib memberikan laporan bulanan paling lambat tanggal 5 setiap bulan.

    2. Pihak Kedua wajib untuk menyampaikan laporan tersebut kepada Pihak Pertama melalui alamat surat elektronik yang telah ditentukan.

    3. Pihak Pertama wajib memberikan akses, informasi, dan persetujuan yang secara wajar diperlukan agar Pihak Kedua dapat melaksanakan kewajibannya.

    4. Para Pihak akan melakukan kerjasama dengan itikad baik dan saling memberitahukan setiap kendala yang dapat mempengaruhi pelaksanaan Perjanjian.

    5. Pihak yang mengetahui adanya kesalahan atau gangguan pada Layanan wajib segera memberitahukan Pihak lainnya tanpa menunda-nunda.

    PASAL 4
    DATA PRIBADI DAN INFORMASI RAHASIA

    1. Pihak Kedua hanya boleh memproses Data Pribadi untuk tujuan pelaksanaan Layanan dan berdasarkan instruksi tertulis dari Pihak Pertama.

    2. Pada saat pendaftaran pengguna, Pihak Kedua hanya mengumpulkan data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik sejauh diperlukan untuk pelaksanaan Layanan.

    3. Pihak Kedua wajib menerapkan langkah teknis dan organisatoris yang patut untuk mencegah akses, penggunaan, pengungkapan, perubahan, atau pemusnahan Data Pribadi tanpa hak.

    4. Apabila Layanan digunakan untuk data yang berasal dari kelompok masyarakat yang secara turun-temurun bermukim di wilayah geografis tertentu karena adanya ikatan pada asal usul leluhur, hubungan yang kuat dengan lingkungan hidup, serta sistem nilai yang menentukan pranata ekonomi, politik, sosial, dan hukum, Para Pihak wajib melakukan penilaian tambahan sebelum data tersebut diproses.

    5. Para Pihak wajib menjaga kerahasiaan Informasi Rahasia selama jangka waktu Perjanjian dan setelah Perjanjian ini berakhir.

    6. Kewajiban kerahasiaan tidak berlaku terhadap informasi yang telah tersedia untuk umum bukan karena pelanggaran Perjanjian atau wajib diungkapkan berdasarkan putusan pengadilan yang berkekuatan hukum tetap.

    7. Pihak Kedua harus mengembalikan atau memusnahkan Data Pribadi dan Informasi Rahasia setelah menerima permintaan tertulis dari Pihak Pertama, kecuali penyimpanan diwajibkan oleh peraturan yang berlaku.

    PASAL 5
    KEAMANAN DAN PENCATATAN

    1. Pihak Kedua wajib melakukan pencadangan Data Pribadi secara berkala dan menyimpan catatan akses selama 12 (dua belas) bulan.

    2. Dokumen pendukung harus di simpan oleh Pihak Kedua selama 5 (lima) tahun sejak tanggal penerimaan.

    3. Setiap perubahan konfigurasi penting harus dicatat dan dapat ditelusuri oleh Para Pihak.

    4. Pihak Kedua harus segera memulihkan Layanan apabila terjadi gangguan, tetapi upaya pemulihan tersebut tidak boleh mengurangi kewajiban keamanan berdasarkan Perjanjian.

    PASAL 6
    BIAYA DAN PEMBAYARAN

    1. Pihak Pertama wajib membayar biaya Layanan sebesar Rp100.000.000 (seratus juta rupiah) untuk setiap periode sebagaimana disepakati dalam Lampiran II.

    2. Pembayaran biaya Layanan dikenakan pajak pertambahan nilai sebesar 11% sesuai dengan ketentuan perpajakan yang berlaku.

    3. Pihak Pertama melakukan pembayaran paling lambat 14 (empat belas) hari kalender sejak diterimanya tagihan yang lengkap dan benar.

    4. Apabila terdapat perbedaan antara jumlah dalam angka dan jumlah dalam huruf, Para Pihak wajib melakukan klarifikasi tertulis sebelum pembayaran dilakukan.

    PASAL 7
    KEPEMILIKAN DAN PENGGUNAAN

    1. Seluruh dokumen, data, dan materi yang disediakan oleh Pihak Pertama tetap menjadi milik Pihak Pertama.

    2. Dalam pemeriksaan mitra, Pihak Kedua wajib mencatat informasi mengenai kumpulan orang dan/atau kekayaan yang terorganisasi, baik merupakan badan hukum maupun bukan badan hukum, sebelum memberikan akses ke Layanan.

    3. Pihak Kedua tidak memperoleh hak untuk menggunakan dokumen atau data tersebut selain untuk menjalankan Layanan berdasarkan Perjanjian.

    4. Setiap perangkat lunak yang dikembangkan secara khusus untuk Pihak Pertama harus diserahkan bersama dokumentasi teknis yang memadai.

    5. Para Pihak sepakat bahwa penggunaan data untuk tujuan lain memerlukan persetujuan tertulis terlebih dahulu.

    6. Pihak Kedua tidak dapat mengalihkan hak dan kewajibannya berdasarkan Perjanjian ini tanpa persetujuan tertulis dari Pihak Pertama.

    PASAL 8
    JANGKA WAKTU DAN PERUBAHAN

    1. Perjanjian ini berlaku sejak 1 September 2026 sampai dengan 31 Agustus 2027.

    2. Perjanjian ini dapat diperpanjang berdasarkan kesepakatan tertulis Para Pihak paling lambat 30 (tiga puluh) hari kalender sebelum berakhirnya jangka waktu.

    3. Pihak Kedua dapat meminta perubahan jadwal penyampaian laporan, tetapi perubahan tersebut hanya berlaku setelah disetujui secara tertulis oleh Pihak Pertama.

    4. Setiap perubahan atas Perjanjian harus dibuat secara tertulis dan ditanda tangani oleh Para Pihak.

    PASAL 9
    KEADAAN KAHAR DAN TANGGUNG JAWAB

    1. Perusahaan tidak bertanggung jawab atas keterlambatan yang disebabkan oleh Keadaan Kahar, kecuali apabila keterlambatan tersebut timbul karena kesengajaan atau kelalaian berat.

    2. Pihak yang mengalami Keadaan Kahar wajib memberikan pemberitahuan tertulis paling lambat 3 (tiga) hari kerja sejak keadaan tersebut diketahui.

    3. Para Pihak wajib melakukan upaya yang wajar untuk mengurangi resiko dan dampak Keadaan Kahar terhadap pelaksanaan Perjanjian.

    4. Keadaan Kahar tidak menghapus kewajiban pembayaran yang telah jatuh tempo sebelum terjadinya keadaan tersebut.

    PASAL 10
    PENGAKHIRAN

    1. Pihak Pertama dapat mengakhiri Perjanjian ini sewaktu-waktu tanpa pemberitahuan kepada Pihak Kedua apabila terdapat pelanggaran material yang tidak diperbaiki dalam waktu 30 (tiga puluh) hari kalender.

    2. Masing-masing Pihak dapat mengakhiri Perjanjian dengan memberikan pemberitahuan tertulis sekurang-kurangnya 30 (tiga puluh) hari kalender sebelum tanggal pengakhiran.

    3. Pengakhiran Perjanjian tidak membebaskan Para Pihak dari hak dan kewajiban yang telah timbul sebelum tanggal pengakhiran.

    PASAL 11
    PEMBERITAHUAN DAN PENYELESAIAN SENGKETA

    1. Setiap pemberitahuan berdasarkan Perjanjian harus dibuat secara tertulis dan dikirimkan ke alamat Para Pihak yang tercantum di bawah ini.

    2. Borrower wajib memberikan notice tertulis kepada Lender paling lambat 7 (tujuh) hari kerja setelah menerima permintaan pembayaran.

    3. Borrower wajib mengirimkan quarterly report kepada Lender paling lambat 3 (tiga) hari kerja setelah akhir setiap kuartal.

    4. Apabila terjadi sengketa, Para Pihak terlebih dahulu akan menyelesaikannya melalui musyawarah dalam waktu 30 (tiga puluh) hari kalender.

    5. Apabila musyawarah tidak mencapai kesepakatan, sengketa diselesaikan melalui Pengadilan Negeri Jakarta Pusat.

    PASAL 12
    KETENTUAN PENUTUP

    1. Perjanjian ini diatur dan ditafsirkan berdasarkan hukum Republik Indonesia.

    2. Perusahaan wajib mematuhi seluruh peraturan yang berlaku dalam melaksanakan kewajibannya berdasarkan Perjanjian.

    3. Apabila salah satu ketentuan dalam Perjanjian dinyatakan tidak berlaku, ketentuan lainnya tetap berlaku sepenuhnya.

    4. Perjanjian ini dibuat dalam 2 (dua) rangkap asli, masing-masing mempunyai kekuatan hukum yang sama.

    5. Setelah membaca dan memahami seluruh isinya, Para Pihak sepakat untuk menandatangani Perjanjian ini tanpa adanya paksaan dari pihak manapun.

    PIHAK PERTAMA                                      PIHAK KEDUA
    PT Arunika Data Nusantara                          PT Cakrawala Legal Teknologi

    Raka Pratama                                       Nadia Kurnia
    Direktur                                            Direktur
    """

    /// Fiksi untuk menguji retrieval, perlindungan defined terms, dan batas
    /// review pada dokumen pengolahan data pribadi yang lebih panjang.
    private static let dataProcessingAgreementContent = """
    DOKUMEN FIKTIF UNTUK PENGUJIAN AI CONNECTOR
    PERJANJIAN PENGOLAHAN DATA PRIBADI DAN TRANSFER INTERNASIONAL

    Nomor: AMT/DPA/2026/014

    Pada tanggal 18 Agustus 2026, PT Sagara Komputasi Indonesia, suatu Korporasi yang didirikan berdasarkan hukum Republik Indonesia dan berkedudukan di Jakarta, yang dalam hal ini diwakili oleh Maya Adiningsih selaku Direktur, disebut sebagai “Pengendali” atau “Pihak Pertama”; dan PT Lintas Awan Nusantara, suatu Korporasi yang mempunyai pusat operasi di Surabaya dan kantor perwakilan di Singapura, diwakili oleh Fajar Wicaksana selaku Chief Executive Officer, disebut sebagai “Prosesor” atau “Pihak Kedua”, bersama-sama disebut “Para Pihak”, sepakat membuat Perjanjian ini.

    Perjanjian ini adalah fixture fiktif dan tidak dimaksudkan menjadi nasihat hukum, dasar pemrosesan, atau pernyataan kepatuhan terhadap peraturan tertentu. Beberapa ejaan, istilah, rujukan silang, tanggal, dan instruksi pada fixture ini sengaja bermasalah untuk kebutuhan pengujian.

    PASAL 1
    DEFINISI

    1. “Data Pribadi” adalah setiap data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya, baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik.

    2. “Data Pribadi Sensitif” berarti Data Pribadi yang memerlukan perlindungan tambahan, termasuk data kesehatan, biometrik, keuangan, identitas, lokasi, dan informasi tentang anak, walaupun tidak semua kategori tersebut diuraikan secara sama dalam Lampiran A.

    3. “Subjek Data” berarti orang perseorangan yang datanya diproses. Dalam beberapa bagian Perjanjian ini istilah Data Subject, pengguna, customer, dan pemilik data digunakan bergantian tanpa mengubah maksud Para Pihak, atau setidaknya demikian yang Para Pihak maksudkan.

    4. “Pemrosesan” adalah setiap tindakan terhadap Data Pribadi, termasuk memperoleh, mencatat, mengorganisir, menyimpan, mengubah, mengambil, menggunakan, mengungkapkan, mengirimkan, menghapus, dan memusnahkan Data Pribadi.

    5. “Pengendali Data Pribadi” adalah Pihak yang menentukan tujuan dan kendali pemrosesan. Pihak Pertama juga disebut Controller, Data Controller, dan Client di dalam dokumen lain yang menjadi satu kesatuan dengan Perjanjian ini.

    6. “Prosesor Data Pribadi” adalah Pihak yang memproses Data Pribadi atas nama dan berdasarkan instruksi Pengendali Data Pribadi. Pihak Kedua juga disebut Processor, Service Provider, Vendor, dan Penyedia, sehingga pembaca wajib melihat konteks dan tidak langsung menganggap semua istilah tersebut sebagai pihak yang berbeda.

    7. “Subprosesor” adalah pihak ketiga yang ditunjuk untuk melakukan sebagian Pemrosesan, termasuk penyedia cloud, penyedia analytics, penyedia layanan email, dan pihak lain yang belum dicantumkan namanya dalam daftar final.

    8. “Insiden Keamanan” adalah kejadian yang menyebabkan atau patut diduga menyebabkan akses, perolehan, penggunaan, pengungkapan, perubahan, kehilangan, atau pemusnahan Data Pribadi tanpa hak.

    9. “Transfer Internasional” berarti pemindahan Data Pribadi dari Indonesia ke lokasi di luar Indonesia, termasuk perpindahan melalui backup otomatis yang lokasinya tidak selalu dapat diketahui secara real time.

    10. “Layanan” berarti hosting, support, pemeliharaan, pemantauan, pencadangan, pemulihan, dan pekerjaan lain sebagaimana disebut dalam Statement of Work, SOW, Lampiran A, dan tiket pekerjaan yang disetujui.

    11. “Hari Kerja” berarti hari Senin sampai Jumat, tidak termasuk hari libur nasional di Indonesia, tetapi untuk notifikasi kepada Subprosesor di Singapura dapat dihitung berdasarkan kalender Singapura jika lebih cepat.

    PASAL 2
    RUANG LINGKUP DAN INSTRUKSI

    1. Pihak Pertama menunjuk Pihak Kedua untuk memproses Data Pribadi hanya untuk menyediakan Layanan dan Pihak Kedua menerima penunjukan tersebut dengan segala keterbatasan teknis yang diketahui pada saat Perjanjian di tanda tangani.

    2. Instruksi awal Pihak Pertama terdapat pada Lampiran A. Instruksi tambahan dapat disampaikan melalui email, portal tiket, pesan lisan yang kemudian di catat, atau bentuk lain yang secara wajar dapat dibuktikan sebagai instruksi.

    3. Pihak Kedua wajib untuk memproses Data Pribadi sesuai instruksi terdokumentasi dan tidak boleh menggunakan Data Pribadi untuk iklan, profiling, pelatihan model, atau tujuan komersialnya sendiri, kecuali terdapat persetujuan tertulis yang secara spesifik menyebut tujuan tersebut.

    4. Apabila instruksi Pihak Pertama bertentangan dengan Perjanjian, Pihak Kedua harus memberitahukan Pihak Pertama sebelum instruksi di lakukan, namun Pihak Kedua tetap dapat mengambil tindakan sementara yang diperlukan untuk mencegah kerusakan yang lebih besar.

    5. Pihak Kedua tidak menentukan tujuan Pemrosesan dan tidak boleh menjual, menyewakan, menggabungkan, atau memperkaya Data Pribadi dari Pihak Pertama dengan database pihak lain, termasuk untuk membuat model scoring internal.

    6. Perubahan ruang lingkup wajib di dokumentasikan. Perubahan melalui tiket yang tidak menyebut versi lampiran tetap dianggap berlaku apabila Pihak Pertama tidak menyampaikan keberatan dalam waktu 3 (tiga) Hari Kerja.

    PASAL 3
    KATEGORI DATA DAN SUBJEK DATA

    1. Kategori Data Pribadi yang diproses meliputi nama, alamat, nomor telepon, alamat email, nomor identitas, data rekening, metadata penggunaan, alamat IP, log akses, dan isi dokumen yang diunggah ke Layanan.

    2. Pihak Kedua dapat menerima Data Pribadi Sensitif secara tidak sengaja apabila Subjek Data mengunggah dokumen pendukung. Pihak Kedua wajib memberi tanda, membatasi akses, dan menghapus data tersebut sesuai instruksi, tetapi tidak wajib membaca isi setiap dokumen secara manual.

    3. Subjek Data dapat berupa pelanggan, pegawai, calon pegawai, kuasa, saksi, vendor, pengguna anonim, dan pihak lain yang datanya dicantumkan oleh pengguna. Daftar tersebut tidak membatasi kategori Subjek Data yang dapat timbul dari penggunaan Layanan.

    4. Pihak Pertama bertanggungjawab untuk memastikan tujuan dan dasar Pemrosesan telah tersedia. Pihak Kedua bertanggung jawab menjalankan instruksi, menjaga keamanan, serta membantu Pihak Pertama sepanjang bantuan itu tersedia secara teknis dan tidak bertentangan dengan kewajiban kepada Korporasi lain.

    5. Apabila ada permintaan dari Subjek Data, Pihak Kedua tidak boleh langsung menyetujui atau menolak permintaan tersebut. Permintaan di teruskan kepada Pihak Pertama paling lambat 2 (dua) Hari Kerja setelah diterima.

    6. Pihak Kedua mengumpulkan Data Pribadi seminimal mungkin, tetapi kata minimal tersebut tidak menjelaskan daftar field wajib, optional field, atau data yang diperlukan untuk audit dan penagihan.

    PASAL 4
    KEAMANAN INFORMASI

    1. Pihak Kedua wajib menerapkan langkah teknis dan organisatoris yang patut, termasuk kontrol akses berdasarkan peran, autentikasi multi faktor, enkripsi saat transit dan saat di simpan, pencatatan aktivitas, pemantauan anomali, serta pengujian pemulihan.

    2. Hak akses harus diberikan berdasarkan kebutuhan untuk mengetahui dan harus di cabut paling lambat 24 (dua puluh empat) jam setelah pegawai tidak lagi membutuhkan akses, kecuali akses darurat masih diperlukan untuk pemulihan Layanan.

    3. Akun bersama tidak boleh digunakan untuk administrasi, namun akun break-glass dapat dipakai jika keadaan darurat dan pengguna mencatat alasan penggunaannya sesudah tindakan selesai.

    4. Pihak Kedua wajib untuk melakukan review hak akses sekurang-kurangnya setiap 90 (sembilan puluh) hari. Hasil review boleh berbentuk tiket, spreadsheet, atau catatan sistem selama dapat ditunjukan ketika audit.

    5. Backup harus di simpan secara terenkripsi dan diuji pemulihannya sekurang-kurangnya 1 (satu) kali dalam 6 (enam) bulan. Backup yang gagal diuji tidak otomatis dianggap tidak ada, tetapi kegagalan tersebut harus di laporkan kepada Pihak Pertama.

    6. Pihak Kedua wajib membuat rencana respons Insiden Keamanan, menunjuk petugas penghubung, dan mengkoordinir proses eskalasi dengan Subprosesor. Kontak darurat: [NAMA PETUGAS BELUM DIISI].

    7. Para Pihak sepakat bahwa standar keamanan pada Lampiran B adalah standar minimum. Apabila terdapat standar yang lebih ketat pada instruksi baru, Pihak Kedua wajib menerapkannya setelah dampak biaya dan resiko disetujui.

    PASAL 5
    INSIDEN KEAMANAN

    1. Pihak Kedua wajib memberitahukan Insiden Keamanan kepada Pihak Pertama tanpa penundaan yang tidak beralasan dan paling lambat 72 (tujuh puluh dua) jam sejak Insiden Keamanan diketahui oleh personel yang berwenang.

    2. Pemberitahuan awal sekurang-kurangnya memuat waktu kejadian, waktu diketahui, sistem yang terdampak, kategori Data Pribadi, perkiraan jumlah Subjek Data, tindakan sementara, dan nama contact person. Informasi yang belum tersedia dapat di susulkan.

    3. Pihak Kedua wajib melakukan investigasi, preservasi bukti, dan langkah mitigasi yang wajar. Pihak Kedua tidak boleh menghapus log untuk mengurangi resiko reputasi atau untuk menghindari pemeriksaan.

    4. Pihak Pertama mengendalikan komunikasi kepada Subjek Data dan regulator, sedangkan Pihak Kedua menyediakan fakta teknis yang telah di verifikasi. Tidak ada Pihak yang boleh membuat pengumuman publik atas nama Pihak lainnya tanpa persetujuan tertulis.

    5. Jika Insiden Keamanan terjadi pada Subprosesor, Pihak Kedua tetap menjadi pihak yang bertanggungjawab kepada Pihak Pertama untuk koordinasi, meskipun Pihak Kedua dapat meminta penggantian biaya dari Subprosesor berdasarkan kontraknya sendiri.

    6. Para Pihak wajib melakukan post-incident review paling lambat 30 (tiga puluh) hari setelah layanan normal. Rekomendasi review tidak boleh mengubah tujuan Pemrosesan tanpa instruksi baru.

    PASAL 6
    SUBPROSESOR DAN TRANSFER INTERNASIONAL

    1. Pihak Kedua dapat menggunakan Subprosesor yang tercantum pada Lampiran C. Penunjukan Subprosesor baru wajib diberitahukan paling lambat 14 (empat belas) hari sebelum akses diberikan, kecuali penggantian mendesak untuk menjaga kesinambungan Layanan.

    2. Pihak Kedua wajib memastikan Subprosesor terikat kewajiban perlindungan Data Pribadi yang setara atau tidak lebih rendah dari Perjanjian ini. Klausul “setara” tidak menghapus kewajiban Pihak Kedua untuk melakukan due diligence.

    3. Data dapat di proses di Indonesia, Singapura, dan Jepang melalui infrastruktur cloud. Transfer Internasional harus menggunakan mekanisme pengamanan yang disepakati, dengan memperhatikan bahwa lokasi metadata dapat berbeda dari lokasi isi dokumen.

    4. Pihak Pertama dapat menolak Subprosesor baru karena alasan keamanan yang beralasan. Keberatan harus menjelaskan resiko spesifik dan tidak boleh hanya berupa ketidak sukaan terhadap nama vendor.

    5. Jika Para Pihak tidak menyelesaikan keberatan dalam 10 (sepuluh) hari, Pihak Pertama dapat meminta rencana alternatif atau menghentikan bagian Layanan yang terdampak. Penghentian tersebut tidak otomatis menghapus tagihan yang telah jatuh tempo.

    PASAL 7
    HAK SUBJEK DATA DAN BANTUAN

    1. Pihak Kedua wajib membantu Pihak Pertama menjawab permintaan akses, koreksi, penghapusan, pembatasan, keberatan, dan portabilitas sepanjang permintaan itu dapat diidentifikasi dari sistem.

    2. Bantuan standar termasuk pencarian berdasarkan user ID dan rentang tanggal. Pencarian berdasarkan nama yang salah eja, dokumen hasil scan, atau backup offline dapat memerlukan pekerjaan tambahan.

    3. Pihak Kedua wajib untuk memberikan hasil pencarian awal dalam waktu 5 (lima) Hari Kerja. Tenggat ini dapat diperpanjang jika data berada dalam arsip dan Pihak Pertama telah diberitahu sebelum tenggat berakhir.

    4. Pihak Kedua tidak boleh mengubah isi Data Pribadi untuk memenuhi permintaan Subjek Data tanpa instruksi tertulis. Koreksi pada salinan kerja harus dapat dibedakan dari perubahan pada dokumen sumber.

    5. Setiap salinan yang dikirim kepada Pihak Pertama harus menggunakan kanal yang aman dan tidak boleh memuat credential, token, atau data milik Subjek Data lain.

    PASAL 8
    RETENSI DAN PENGHAPUSAN

    1. Data Pribadi disimpan selama jangka waktu Layanan dan paling lama 24 (dua puluh empat) bulan setelah tanggal berakhirnya Perjanjian, kecuali Pihak Pertama memberikan instruksi retensi lebih lama berdasarkan kewajiban hukum.

    2. Lampiran C menyebut masa retensi backup 12 (dua belas) bulan, sedangkan Pasal ini menyebut 24 (dua puluh empat) bulan. Para Pihak harus melakukan klarifikasi tertulis sebelum memilih periode yang lebih pendek.

    3. Setelah instruksi penghapusan diterima, Pihak Kedua wajib menghapus Data Pribadi dari sistem aktif dalam waktu 30 (tiga puluh) hari. Penghapusan dari backup dilakukan pada siklus rotasi berikutnya dan harus di dokumentasikan.

    4. Pihak Kedua wajib memberikan sertifikat pemusnahan atau catatan sistem yang memadai. Pernyataan bahwa data telah “dihapus secara permanen” tidak boleh diberikan jika salinan yang sah masih wajib disimpan.

    5. Data yang telah dianonimkan secara efektif dapat dipertahankan untuk statistik Layanan. Pihak Kedua tidak boleh menyebut data sebagai anonim apabila masih mungkin menghubungkannya kembali dengan Subjek Data.

    PASAL 9
    AUDIT DAN DOKUMENTASI

    1. Pihak Pertama dapat melakukan audit satu kali setiap tahun dengan pemberitahuan 15 (lima belas) Hari Kerja. Audit tambahan dapat dilakukan setelah Insiden Keamanan atau apabila terdapat bukti ketidak sesuaian yang material.

    2. Audit harus dilakukan pada jam kerja, tidak boleh mengganggu Korporasi lain, dan tidak boleh membuka Data Pribadi yang tidak berhubungan dengan Layanan. Pihak Kedua boleh memberikan ringkasan laporan independen sebagai pengganti akses langsung.

    3. Pihak Kedua wajib menyimpan catatan instruksi, akses, perubahan konfigurasi, Insiden Keamanan, penghapusan, dan Transfer Internasional selama 5 (lima) tahun setelah catatan dibuat.

    4. Pihak Kedua harus menyediakan dokumen pendukung paling lambat 7 (tujuh) Hari Kerja sejak permintaan. Dokumen yang belum tersedia harus disebutkan secara terbuka dan tidak boleh di buat setelah tanggal audit hanya untuk melengkapi berkas.

    5. Biaya audit yang wajar ditanggung oleh Pihak Pertama sampai batas Rp450.000.000 per tahun. Batas tersebut tidak berlaku untuk audit akibat pelanggaran yang terbukti dilakukan dengan sengaja.

    PASAL 10
    BIAYA, TANGGUNG JAWAB, DAN KERUGIAN

    1. Biaya bantuan tambahan adalah Rp175.000.000 per paket pekerjaan dan belum termasuk PPN sebesar 11%. Tagihan dibayar paling lambat 14 (empat belas) hari kalender setelah dokumen pendukung diterima.

    2. Pihak Kedua bertanggung jawab atas pelaksanaan instruksi dan tindakan Subprosesor. Tanggung jawab tersebut tidak berarti Pihak Kedua menjamin tidak akan pernah terjadi gangguan atau serangan siber.

    3. Masing-masing Pihak wajib mengambil langkah yang wajar untuk mengurangi kerugian. Pihak yang tidak melakukan mitigasi tidak dapat meminta penggantian atas bagian kerugian yang seharusnya dapat dicegah.

    4. Tidak ada ketentuan dalam Perjanjian ini yang mengalihkan status Pengendali Data Pribadi, menghapus kewajiban kerahasiaan, atau memberi hak kepada Pihak Kedua untuk memakai Data Pribadi di luar instruksi.

    5. Batas tanggung jawab sebesar 100% biaya Layanan selama 12 bulan terakhir berlaku untuk kerugian langsung, tetapi tidak berlaku untuk kesengajaan, pelanggaran kerahasiaan, atau penyalahgunaan Data Pribadi.

    PASAL 11
    JANGKA WAKTU DAN PENGAKHIRAN

    1. Perjanjian berlaku sejak 1 September 2026 sampai dengan 31 Agustus 2028. Perjanjian dapat diperpanjang untuk periode 12 (dua belas) bulan berdasarkan persetujuan tertulis Para Pihak.

    2. Pihak Pertama dapat mengakhiri Perjanjian jika Pihak Kedua tidak memperbaiki pelanggaran material dalam 30 (tiga puluh) hari sejak pemberitahuan. Untuk Insiden Keamanan yang sedang berlangsung, jangka waktu perbaikan dapat dipersingkat secara wajar.

    3. Pengakhiran tidak membebaskan Para Pihak dari kewajiban yang telah timbul. Kewajiban penghapusan, audit, kerahasiaan, dan pembatasan penggunaan tetap berlaku sesuai sifatnya.

    4. Jika instruksi Pihak Pertama mengharuskan Pihak Kedua melanggar hukum, Pihak Kedua dapat menangguhkan instruksi tersebut setelah memberikan pemberitahuan. Penangguhan bukan pengakhiran otomatis.

    PASAL 12
    HUKUM, PEMBERITAHUAN, DAN PENUTUP

    1. Perjanjian diatur berdasarkan hukum Republik Indonesia. Perselisihan diselesaikan lebih dahulu melalui musyawarah selama 30 (tiga puluh) hari kalender dan kemudian melalui Pengadilan Negeri Jakarta Selatan.

    2. Pemberitahuan dikirim ke privacy@sagara.example dan dpo@lintasawan.example. Alamat tersebut adalah alamat dummy dan tidak boleh digunakan untuk mengirim Data Pribadi nyata.

    3. Apabila ada ketentuan yang tidak berlaku, ketentuan lainnya tetap berlaku. Judul pasal hanya untuk kemudahan membaca, sedangkan defined terms harus dipertahankan persis ketika digunakan oleh sistem.

    4. Perjanjian ini dibuat dalam bahasa Indonesia dan bahasa Inggris. Jika terdapat perbedaan, versi bahasa Indonesia berlaku, kecuali Lampiran teknis secara tegas menyatakan lain.

    5. Setelah membaca, memahami, dan meninjau seluruh lampiran, Para Pihak sepakat menanda tangani Perjanjian ini tanpa paksaan. Kesalahan ketik dalam fixture ini tidak boleh dianggap sebagai persetujuan perubahan hak atau kewajiban.

    PIHAK PERTAMA                                      PIHAK KEDUA
    PT Sagara Komputasi Indonesia                      PT Lintas Awan Nusantara

    Maya Adiningsih                                    Fajar Wicaksana
    Direktur                                           Chief Executive Officer
    """

    /// Fiksi pembiayaan dengan defined terms, nominal, tenggat, jaminan, dan
    /// konflik klausul untuk menguji perlindungan angka serta modalitas.
    private static let financingAgreementContent = """
    DOKUMEN FIKTIF UNTUK PENGUJIAN AI CONNECTOR
    PERJANJIAN FASILITAS PEMBIAYAAN DAN JAMINAN

    Nomor: AMT/FIN/2026/022

    Pada hari Selasa, 25 Agustus 2026, PT Dana Arunika Finance, suatu Korporasi pembiayaan yang berkedudukan di Jakarta dan bertindak sebagai “Lender” atau “Pihak Pertama”, dan PT Bumi Inovasi Logistik, suatu Korporasi yang berkedudukan di Semarang dan bertindak sebagai “Borrower” atau “Pihak Kedua”, membuat Perjanjian Fasilitas Pembiayaan ini bersama PT Penjamin Nusantara sebagai “Guarantor”.

    Dokumen ini sepenuhnya fiktif. Isinya sengaja mencampur bahasa Indonesia dan English legal terms, memakai beberapa ejaan keliru, angka yang harus dipertahankan, serta klausul yang mungkin memerlukan klarifikasi manusia. Tidak ada pihak, rekening, atau jaminan nyata yang dimaksudkan.

    PASAL 1
    DEFINISI DAN PENAFSIRAN

    1. “Facility” berarti fasilitas pembiayaan berulang dengan jumlah maksimum Rp25.750.000.000 (dua puluh lima miliar tujuh ratus lima puluh juta rupiah) yang dapat ditarik oleh Borrower sesuai syarat Perjanjian.

    2. “Principal” berarti jumlah pokok yang benar-benar ditarik dan belum dibayar kembali, bukan jumlah maksimum Facility, kecuali apabila konteksnya menunjukan lain.

    3. “Interest Rate” berarti bunga tetap sebesar 10,75% per tahun, dihitung berdasarkan actual/360, sedangkan surat konfirmasi dapat menulis 10.75% dengan arti yang sama.

    4. “Maturity Date” berarti 14 September 2029. Setiap perubahan Maturity Date harus disetujui Lender dan Borrower secara tertulis serta ditanda tangani oleh pejabat berwenang.

    5. “Business Day” berarti hari ketika bank di Jakarta buka untuk bisnis umum. Jika tanggal pembayaran jatuh pada hari bukan Business Day, pembayaran dilakukan pada Business Day berikutnya tanpa mengubah perhitungan bunga.

    6. “Event of Default” meliputi gagal bayar, pernyataan yang menyesatkan, insolvency, pelanggaran covenant, penyitaan aset, atau keadaan lain yang secara wajar dapat menyebabkan kewajiban tidak dibayar.

    7. “Collateral” berarti tanah, bangunan, persediaan, piutang, rekening, dan aset lain yang dijaminkan kepada Lender berdasarkan dokumen security yang relevan.

    8. “Finance Documents” berarti Perjanjian ini, Akta Jaminan, Corporate Guarantee, notice, certificate, surat permintaan penarikan, dan dokumen lain yang disebut sebagai finance document.

    9. “Material Adverse Effect” berarti dampak merugikan yang material terhadap usaha, aset, kemampuan pembayaran, atau keabsahan kewajiban Borrower, tetapi bukan perubahan pasar biasa yang tidak mempengaruhi pembayaran.

    10. “Korporasi” adalah kumpulan orang dan/atau kekayaan yang terorganisasi, baik merupakan badan hukum maupun bukan badan hukum, yang dapat dimintakan pertanggungjawaban hukum. Penggunaan istilah Corporation, Company, dan Korporasi harus dibaca berdasarkan pihak yang didefinisikan.

    11. “Data Pribadi” adalah data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi. Lender dan Borrower wajib membatasi akses ke Data Pribadi pengurus, penjamin, karyawan, dan contact person.

    12. Judul Pasal tidak mempengaruhi penafsiran. Singkatan boleh digunakan setelah istilah ditulis lengkap, namun defined terms Borrower, Lender, Facility, Principal, dan Maturity Date tidak boleh diterjemahkan di tengah dokumen.

    PASAL 2
    FASILITAS DAN PENARIKAN

    1. Lender menyediakan Facility kepada Borrower sampai batas maksimum Rp25.750.000.000. Borrower tidak wajib menarik seluruh Facility dan Lender tidak wajib membayar lebih dari batas tersebut.

    2. Setiap penarikan dilakukan melalui Drawdown Request paling lambat 3 (tiga) Business Day sebelum tanggal penarikan. Request harus mencantumkan jumlah, rekening penerima, tujuan penggunaan, dan tanggal pembayaran kembali.

    3. Borrower wajib untuk menyerahkan dokumen pendahuluan, laporan keuangan, board resolution, dan bukti tidak adanya Event of Default sebelum penarikan pertama.

    4. Lender dapat menolak Drawdown Request apabila persyaratan belum terpenuhi. Penolakan harus diberitahukan secara tertulis dan tidak dianggap sebagai waiver atas hak Lender lainnya.

    5. Dana hanya boleh digunakan untuk modal kerja, pembelian perangkat, dan biaya operasional yang disetujui. Dana tidak boleh digunakan untuk membayar dividen, memberikan pinjaman kepada afiliasi, membeli aset terlarang, atau melakukan transaksi yang melanggar hukum.

    6. Borrower menyatakan bahwa seluruh informasi pada Drawdown Request benar, lengkap, dan tidak menyesatkan. Perubahan kecil pada format dokumen tidak mengubah pernyataan tersebut, tetapi perubahan jumlah atau tujuan wajib diberitahukan.

    PASAL 3
    BUNGA DAN PEMBAYARAN

    1. Bunga atas Principal berjalan sejak tanggal pencairan sampai dengan tanggal pelunasan. Bunga dibayar setiap tanggal 15 pada bulan berikutnya, kecuali tanggal tersebut bukan Business Day.

    2. Borrower wajib membayar Principal, bunga, commitment fee sebesar 0,50% per tahun, dan biaya lain yang secara sah terutang. Pembayaran tidak boleh dikurangi dengan counterclaim kecuali diwajibkan oleh hukum.

    3. Pembayaran dilakukan ke rekening Lender yang ditentukan dalam Payment Notice. Perubahan rekening harus dikonfirmasi melalui dua kanal yang berbeda untuk mengurangi resiko fraud.

    4. Apabila jumlah pembayaran tidak cukup untuk melunasi seluruh kewajiban, pembayaran dialokasikan terlebih dahulu untuk biaya, denda, bunga, dan kemudian Principal, kecuali Lender menentukan urutan lain secara tertulis.

    5. Keterlambatan pembayaran dikenakan default interest sebesar 2% di atas Interest Rate. Default interest tidak menghapus hak Lender untuk menagih biaya atau menjalankan jaminan.

    6. Borrower harus melakukan pembayaran tanpa potongan pajak. Apabila pemotongan diwajibkan, Borrower menambah pembayaran agar jumlah bersih yang diterima Lender sama dengan jumlah yang seharusnya diterima.

    7. Bukti pembayaran wajib di kirim kepada Lender paling lambat 1 (satu) Business Day setelah transfer. Bukti transfer bukan bukti pelunasan apabila dana belum diterima secara irrevocable.

    PASAL 4
    JAMINAN DAN PERNYATAAN

    1. Borrower menjaminkan Collateral kepada Lender dengan peringkat dan nilai yang disepakati dalam Akta Jaminan. Borrower wajib menjaga agar Collateral tidak dialihkan, disewakan, atau dibebani lagi tanpa persetujuan.

    2. Borrower menyatakan bahwa ia memiliki kewenangan untuk menandatangani Finance Documents dan pelaksanaan kewajiban tidak bertentangan dengan anggaran dasar, perjanjian lain, atau putusan pengadilan.

    3. Guarantor menjamin pembayaran seluruh kewajiban Borrower sebagai co-obligor, bukan hanya kewajiban Principal. Guarantor tidak dapat mencabut Guarantee sebelum seluruh Finance Documents dilunasi.

    4. Setiap dokumen jaminan harus di buat dan didaftarkan sesuai hukum yang berlaku. Kesalahan administrasi yang tidak mempengaruhi prioritas jaminan harus segera diperbaiki oleh Borrower.

    5. Borrower bertanggungjawab atas pajak, biaya notaris, pendaftaran, appraisal, asuransi, dan biaya pemeliharaan Collateral. Lender dapat membayar biaya tersebut dan membebankannya kembali jika Borrower tidak membayar.

    6. Nilai Collateral harus ditinjau setiap 12 (dua belas) bulan. Jika nilai turun lebih dari 20%, Borrower wajib memberikan tambahan jaminan dalam waktu 10 (sepuluh) hari kalender.

    PASAL 5
    COVENANTS BORROWER

    1. Borrower wajib menjaga izin usaha, membayar pajak, memelihara aset, dan menjalankan usaha dengan itikad baik. Borrower harus mengkoordinir laporan dari anak perusahaan agar informasi yang disampaikan konsisten.

    2. Borrower tidak boleh menjual aset material, mengubah bidang usaha utama, melakukan merger, atau mengakuisisi perusahaan lain tanpa persetujuan Lender terlebih dahulu.

    3. Borrower dapat melakukan transaksi dengan afiliasi dalam kegiatan usaha biasa dengan harga wajar. Transaksi dengan direktur atau pemegang saham wajib diungkapkan dalam quarterly report.

    4. Borrower wajib mempertahankan rasio Debt Service Coverage Ratio minimum 1,20x dan leverage maksimum 3,50x. Perhitungan yang berbeda antara laporan internal dan laporan audited harus dijelaskan, bukan langsung dipilih angka yang lebih menguntungkan.

    5. Borrower wajib untuk menyampaikan laporan keuangan bulanan paling lambat tanggal 20 bulan berikutnya dan laporan tahunan audited paling lambat 120 hari setelah tahun buku berakhir.

    6. Setiap laporan wajib ditandatangani oleh pejabat yang berwenang. Laporan yang belum ditanda tangani dapat dipakai sebagai informasi sementara, tetapi tidak memenuhi kewajiban penyerahan dokumen.

    7. Borrower harus mematuhi ketentuan anti pencucian uang, anti korupsi, sanksi, dan perlindungan Data Pribadi. Pelanggaran oleh vendor tidak otomatis menjadi pelanggaran Borrower apabila Borrower telah melakukan due diligence yang wajar.

    PASAL 6
    INFORMASI DAN PEMERIKSAAN

    1. Lender dapat meminta informasi tentang keuangan, operasi, pemegang saham, manajemen, litigasi, pajak, dan Collateral. Borrower wajib menjawab secara akurat dalam waktu 7 (tujuh) Business Day.

    2. Lender dapat melakukan inspection atas aset dengan pemberitahuan 5 (lima) hari kerja. Inspection tidak boleh mengganggu kegiatan usaha dan tidak memberi hak untuk mengambil aset tanpa prosedur yang berlaku.

    3. Informasi yang diberikan oleh Borrower merupakan Informasi Rahasia. Lender boleh mengungkapkannya kepada afiliasi, penasihat, auditor, regulator, calon assignee, atau pihak yang diwajibkan oleh hukum.

    4. Pihak yang menerima Data Pribadi wajib menerapkan perlindungan yang patut. Pihak Kedua wajib memberitahukan apabila ada permintaan subjek data yang terkait dengan Finance Documents.

    5. Borrower tidak boleh menyembunyikan dokumen material hanya karena dokumen tersebut menggunakan format lama, scan, atau bahasa asing. Jika dokumen belum tersedia, Borrower harus menyatakan hal itu dengan jelas.

    PASAL 7
    EVENT OF DEFAULT

    1. Event of Default terjadi apabila Borrower tidak membayar kewajiban pada tanggal jatuh tempo dan kegagalan tersebut tidak diperbaiki dalam 3 (tiga) Business Day setelah pemberitahuan.

    2. Event of Default juga terjadi apabila pernyataan Borrower terbukti material tidak benar, Borrower melanggar covenant dan tidak memperbaikinya dalam 10 (sepuluh) hari, atau terjadi insolvency yang berkelanjutan.

    3. Pelanggaran yang bersifat administratif dan tidak berdampak pada kemampuan pembayaran dapat diperbaiki dalam waktu 15 (lima belas) hari. Ketentuan ini tidak menghapus kewajiban memberi notice kepada Lender.

    4. Jika Event of Default terjadi, Lender dapat membatalkan komitmen yang belum ditarik, menyatakan seluruh Principal dan bunga jatuh tempo, meminta pembayaran segera, atau mengeksekusi Collateral sesuai hukum.

    5. Lender tidak wajib menggunakan haknya. Keterlambatan atau tidak digunakannya hak tidak merupakan waiver, dan waiver atas satu pelanggaran tidak merupakan waiver atas pelanggaran berikutnya.

    6. Borrower wajib membantu proses penagihan dan tidak boleh menghalangi akses ke Collateral. Semua biaya penegakan yang wajar dapat ditagihkan kepada Borrower.

    PASAL 8
    ASURANSI, RISIKO, DAN KEADAAN KAHAR

    1. Borrower wajib mengasuransikan Collateral dengan perusahaan asuransi yang dapat diterima Lender. Polis harus mencantumkan Lender sebagai loss payee apabila disyaratkan dalam Akta Jaminan.

    2. Risiko kerusakan Collateral tetap berada pada Borrower sampai kewajiban lunas. Klaim asuransi wajib digunakan untuk memperbaiki aset atau membayar Principal sesuai instruksi Lender.

    3. Keadaan Kahar berarti kejadian di luar kendali wajar Para Pihak yang menghambat pembayaran atau pelaksanaan kewajiban, termasuk bencana, perang, wabah, gangguan sistemik, dan perubahan kebijakan pemerintah.

    4. Keadaan Kahar tidak menghapus kewajiban pembayaran yang telah jatuh tempo. Pihak yang terkena wajib memberi pemberitahuan paling lambat 5 (lima) hari setelah kejadian diketahui.

    5. Borrower wajib mengambil langkah mitigasi yang wajar dan menyediakan rencana kesinambungan usaha. Klaim Keadaan Kahar tidak berlaku jika keterlambatan disebabkan kelalaian atau kekurangan dana yang telah ada sebelumnya.

    PASAL 9
    PENGALIHAN DAN KERAHASIAAN

    1. Lender dapat mengalihkan haknya kepada bank, lembaga pembiayaan, atau assignee lain dengan pemberitahuan. Borrower tidak dapat mengalihkan kewajiban tanpa persetujuan tertulis Lender.

    2. Borrower wajib menjaga kerahasiaan suku bunga, laporan, struktur Facility, dan Finance Documents. Pengungkapan kepada direktur, pegawai, auditor, atau penasihat diperbolehkan jika mereka terikat kerahasiaan.

    3. Para Pihak tidak boleh menggunakan nama pihak lain untuk iklan tanpa persetujuan. Kewajiban ini tetap berlaku selama 5 (lima) tahun setelah Maturity Date.

    4. Pihak yang menerima dokumen dalam bentuk elektronik wajib memastikan dokumen di simpan dan dapat diambil kembali selama masa retensi. Menghapus email asli sebelum periode tersebut berakhir tidak diperbolehkan.

    PASAL 10
    BIAYA DAN PAJAK

    1. Borrower membayar arrangement fee sebesar 1,25% dari jumlah maksimum Facility dan commitment fee sesuai Pasal 3. Semua angka dalam schedule harus diperiksa terhadap jumlah yang tertulis dalam huruf.

    2. Biaya legal, notaris, appraisal, registrasi, dan penagihan yang wajar dibayar oleh Borrower. Biaya yang tidak berhubungan dengan Finance Documents tidak dapat dibebankan tanpa persetujuan.

    3. Pajak pertambahan nilai, withholding tax, dan bea lain dibayar sesuai hukum. Borrower wajib memberikan bukti setor kepada Lender paling lambat 14 (empat belas) hari.

    PASAL 11
    JANGKA WAKTU DAN PENYELESAIAN SENGKETA

    1. Perjanjian berlaku sejak 15 September 2026 sampai dengan Maturity Date. Dalam draft sebelumnya tanggal mulai tertulis 1 September 2026; tanggal yang berlaku harus dikonfirmasi melalui amendment.

    2. Perselisihan diselesaikan melalui perundingan selama 30 (tiga puluh) hari kalender. Jika gagal, Para Pihak sepakat memilih domisili hukum Pengadilan Negeri Jakarta Pusat.

    3. Perjanjian ini ditafsirkan berdasarkan hukum Republik Indonesia. Bahasa Inggris pada istilah Facility, Principal, Borrower, Lender, dan Event of Default dipertahankan agar tidak terjadi pergeseran arti.

    4. Setiap amendment wajib di buat secara tertulis, merujuk pasal yang diubah, dan ditandatangani oleh Lender, Borrower, serta Guarantor jika amendment mempengaruhi Guarantee.

    5. Jika salah satu ketentuan tidak berlaku, ketentuan lainnya tetap berlaku. Para Pihak akan berusaha mengganti ketentuan tersebut dengan ketentuan yang paling mendekati maksud komersial awal tanpa mengurangi kewajiban pembayaran.

    PIHAK PERTAMA / LENDER                         PIHAK KEDUA / BORROWER
    PT Dana Arunika Finance                        PT Bumi Inovasi Logistik

    PENJAMIN / GUARANTOR
    PT Penjamin Nusantara
    """

    /// Fiksi pengadaan pemerintah dengan SLA, addendum, serah terima, denda,
    /// Keadaan Kahar, serta banyak rujukan operasional untuk uji dokumen luas.
    private static let procurementAgreementContent = """
    DOKUMEN FIKTIF UNTUK PENGUJIAN AI CONNECTOR
    KONTRAK PENGADAAN DAN IMPLEMENTASI SISTEM INFORMASI LAYANAN PUBLIK

    Nomor: AMT/SPK/2026/031

    Pada tanggal 2 September 2026, Pejabat Pembuat Komitmen pada Badan Layanan Administrasi Publik, selanjutnya disebut “PPK” atau “Pihak Pertama”, dan PT Nusantara Solusi Terpadu, sebuah Korporasi penyedia teknologi yang berkedudukan di Yogyakarta, selanjutnya disebut “Penyedia” atau “Pihak Kedua”, bersama-sama disebut “Para Pihak”, sepakat melaksanakan Kontrak ini.

    Fixture ini dibuat untuk menguji dokumen panjang yang memuat istilah pengadaan, kewajiban teknis, data publik, biaya, jadwal, dan masalah penulisan. Fixture ini bukan dokumen pengadaan nyata, bukan dasar pembayaran, dan bukan pengganti pemeriksaan PPK, auditor, atau penasihat hukum.

    PASAL 1
    DEFINISI

    1. “Pekerjaan” berarti analisis kebutuhan, desain, pengembangan, migrasi, pengujian, pelatihan, implementasi, pemeliharaan, dan serah terima Sistem.

    2. “Sistem” berarti aplikasi layanan publik, API, database, dashboard, dokumentasi, konfigurasi, dan komponen pendukung yang disebut dalam Kerangka Acuan Kerja.

    3. “Keluaran” berarti deliverable yang harus diserahkan Penyedia, termasuk source code, binary, manual, laporan pengujian, daftar aset, dan berita acara.

    4. “HPS” adalah Harga Perkiraan Sendiri sebesar Rp8.450.000.000, sedangkan “Nilai Kontrak” adalah Rp8.375.000.000 termasuk pajak dan biaya lain yang sah.

    5. “PPK” adalah pejabat yang diberi kewenangan untuk mengadakan perikatan. “Penyedia” adalah badan usaha yang melaksanakan Pekerjaan, bukan subkontraktor yang belum disetujui.

    6. “SPMK” berarti Surat Perintah Mulai Kerja. “BAST” berarti Berita Acara Serah Terima. “BAU” berarti Berita Acara Uji, walaupun singkatan tersebut pada Lampiran II pernah ditulis sebagai BAP.

    7. “SLA” adalah service level agreement yang mengatur ketersediaan, waktu respons, waktu pemulihan, dan pengecualian. SLA tidak otomatis mengubah Acceptance Criteria.

    8. “Data Pribadi” berarti data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi. Data yang masuk melalui Sistem tetap harus diperlakukan sebagai data yang memerlukan perlindungan.

    9. “Informasi Rahasia” berarti informasi teknis, keamanan, anggaran, data pengguna, dan dokumen lain yang tidak tersedia untuk umum. “Informasi Publik” tidak otomatis berarti seluruh data dapat dibuka tanpa redaksi.

    10. “Keadaan Kahar” berarti keadaan di luar kehendak dan kemampuan Para Pihak yang menghambat pelaksanaan, termasuk bencana alam, perang, kerusuhan, wabah, gangguan infrastruktur, atau kebijakan pemerintah yang tidak dapat diantisipasi.

    PASAL 2
    RUANG LINGKUP PEKERJAAN

    1. Pihak Pertama menugaskan Pihak Kedua untuk membangun Sistem sebagaimana dijelaskan pada KAK, proposal teknis, dan klarifikasi. Jika terdapat perbedaan, urutan dokumen harus dilihat pada daftar prioritas yang belum diisi.

    2. Pihak Kedua wajib untuk melakukan analisis proses bisnis, membuat backlog, menyusun arsitektur, dan menyerahkan desain awal paling lambat 14 (empat belas) hari kalender sejak SPMK diterbitkan.

    3. Pihak Kedua harus mengembangkan modul pendaftaran, verifikasi, pelacakan, notifikasi, pelaporan, dan administrasi. Modul tambahan tidak boleh dikerjakan tanpa instruksi dan persetujuan tertulis PPK.

    4. Seluruh Pekerjaan wajib di laksanakan oleh personel yang memiliki kompetensi sesuai proposal. Pergantian Project Manager harus diberitahukan 7 (tujuh) hari sebelumnya dan mendapat persetujuan PPK.

    5. Penyedia boleh menggunakan subkontraktor untuk pekerjaan non-kritis setelah mendapat persetujuan. Penyedia tetap bertanggungjawab atas hasil subkontraktor dan tidak boleh mengalihkan kewajiban keseluruhan.

    6. Dalam keadaan tertentu PPK dapat meminta prioritas modul tertentu. Perintah tersebut harus di catat dalam notulen dan tidak boleh mengurangi kebutuhan keamanan, pengujian, atau dokumentasi.

    PASAL 3
    JADWAL DAN LOKASI

    1. Pekerjaan dimulai pada 5 September 2026 dan harus selesai paling lambat 180 (seratus delapan puluh) hari kalender. Jadwal rinci pada Lampiran I mencantumkan 165 hari kerja, sehingga Penyedia wajib meminta klarifikasi sebelum menjadikan salah satunya sebagai baseline.

    2. Tahap analisis berlangsung 14 hari, pengembangan 90 hari, integrasi 30 hari, User Acceptance Test 21 hari, dan deployment 7 hari. Beberapa tahap dapat tumpang tindih jika risiko telah disetujui.

    3. Keterlambatan yang disebabkan Pihak Pertama harus dibuktikan melalui dependency log. Keterlambatan Penyedia tidak dapat dibenarkan hanya karena rapat koordinasi belum dijadwalkan.

    4. Pihak Kedua wajib menyerahkan laporan mingguan setiap hari Jumat. Laporan yang di kirim setelah pukul 17.00 dianggap diterima pada Hari Kerja berikutnya, kecuali sistem penerimaan sedang mengalami gangguan.

    5. Pekerjaan dapat dilakukan di kantor PPK, kantor Penyedia, atau lokasi lain yang disepakati. Akses ke ruang server wajib mengikuti prosedur keamanan dan tidak boleh dipinjamkan kepada pihak manapun.

    PASAL 4
    HAK DAN KEWAJIBAN PPK

    1. PPK menyediakan informasi, akses, narahubung, dan keputusan yang secara wajar dibutuhkan. Penyedia wajib menyampaikan daftar informasi yang belum tersedia, bukan hanya menunggu tanpa pemberitahuan.

    2. PPK berhak memeriksa kemajuan, meminta demonstrasi, menolak Keluaran yang tidak sesuai, dan menginstruksikan perbaikan. Pemeriksaan PPK tidak membebaskan Penyedia dari tanggung jawab atas kesalahan.

    3. PPK menunjuk tim teknis untuk melakukan review. Catatan tim teknis menjadi masukan dan keputusan penerimaan tetap diberikan oleh pejabat yang berwenang.

    4. PPK wajib memberikan tanggapan atas dokumen yang lengkap dalam waktu 5 (lima) Hari Kerja. Jika tanggapan terlambat, Para Pihak harus mencatat dampaknya terhadap jadwal.

    5. PPK tidak boleh meminta Penyedia menggunakan data produksi untuk pengujian tanpa dasar, masking, atau persetujuan yang diperlukan. Data uji harus di buat seperlunya dan dihapus setelah testing selesai.

    PASAL 5
    HAK DAN KEWAJIBAN PENYEDIA

    1. Penyedia wajib melaksanakan Pekerjaan dengan profesional, cermat, transparan, dan sesuai peraturan. Penyedia harus melakukan koordinasi dan kerjasama dengan PPK secara berkala.

    2. Penyedia bertanggungjawab terhadap mutu Keluaran, keamanan Sistem, dokumentasi, dan kompetensi personel. Penyedia tidak boleh menyatakan modul selesai apabila acceptance evidence belum tersedia.

    3. Penyedia wajib menyerahkan source code, konfigurasi, daftar dependency, hasil pemindaian keamanan, dan panduan operasi dalam format yang dapat digunakan PPK.

    4. Penyedia harus memelihara repository selama masa Kontrak dan memberikan akses read-only kepada PPK. Akses admin hanya diberikan kepada personel yang di tunjuk dan dicatat.

    5. Penyedia tidak boleh memasukkan credential, secret, token, atau data nyata ke dalam source code, log, screenshot, atau dokumen pelatihan. Temuan tersebut wajib dihapus dan dilaporkan sebagai insiden.

    6. Penyedia wajib memberi pelatihan minimal 4 (empat) sesi untuk operator, administrator, dan tim teknis. Materi pelatihan harus diserahkan paling lambat 7 (tujuh) hari sebelum sesi pertama.

    PASAL 6
    SPESIFIKASI DAN PENGUJIAN

    1. Sistem harus memiliki ketersediaan bulanan minimum 99,5%, waktu respons API p95 paling tinggi 800 milidetik, dan pemulihan layanan paling lambat 4 jam setelah insiden dikategorikan sebagai major.

    2. Angka SLA tidak berlaku pada maintenance terjadwal yang diberitahukan minimal 3 (tiga) hari sebelumnya, tetapi maintenance darurat tetap harus dicatat dan dijelaskan kepada PPK.

    3. Penyedia wajib melakukan unit test, integration test, security test, performance test, dan User Acceptance Test. Hasil test harus menyebut versi Sistem, data uji, tanggal, tester, dan status lulus atau gagal.

    4. Defect kritis harus diperbaiki sebelum BAST. Defect sedang dapat diterima dengan rencana perbaikan yang disetujui, sedangkan defect rendah harus dicatat dalam backlog dan tidak boleh disembunyikan.

    5. Kriteria penerimaan tidak boleh diubah secara lisan. Setiap perubahan harus dibuat dalam change request yang mencantumkan alasan, dampak biaya, dampak jadwal, dan persetujuan PPK.

    6. Apabila hasil pengujian berbeda antara environment, Penyedia wajib menjelaskan konfigurasi dan tidak boleh memilih hasil yang paling menguntungkan tanpa dasar teknis.

    PASAL 7
    DATA PRIBADI DAN KEAMANAN

    1. Pihak Kedua hanya boleh memproses Data Pribadi untuk Pekerjaan dan berdasarkan instruksi Pihak Pertama. Data Pribadi tidak boleh digunakan untuk demo publik, marketing, pelatihan model, atau analisis di luar ruang lingkup.

    2. Penyedia wajib menerapkan least privilege, autentikasi multi faktor, enkripsi, backup, logging, monitoring, dan review akses. Dokumen keamanan harus di simpan untuk kebutuhan audit.

    3. Insiden Keamanan harus diberitahukan kepada PPK paling lambat 24 (dua puluh empat) jam setelah diketahui, disusul laporan awal dalam 3 (tiga) hari kerja. Pemberitahuan tidak boleh menunggu seluruh investigasi selesai.

    4. Data Pribadi pada lingkungan pengembangan harus dimasking. Jika masking tidak memungkinkan, Penyedia wajib meminta persetujuan khusus dan membatasi akses berdasarkan kebutuhan.

    5. Setelah BAST dan berakhirnya masa pemeliharaan, Penyedia wajib mengembalikan atau memusnahkan data sesuai instruksi. Salinan yang wajib disimpan untuk audit harus diisolasi dan dihapus setelah masa retensi berakhir.

    6. Penyedia harus melaporkan subprosesor, lokasi hosting, dan Transfer Internasional. Perubahan lokasi cloud tanpa pemberitahuan merupakan ketidak sesuaian yang perlu dievaluasi PPK.

    PASAL 8
    HAK KEKAYAAN INTELEKTUAL

    1. Keluaran yang dibayar berdasarkan Nilai Kontrak menjadi hak Pihak Pertama setelah pembayaran sesuai Kontrak. Komponen open source dan komponen pihak ketiga tetap tunduk pada lisensinya.

    2. Penyedia wajib memberikan daftar lisensi dan notice yang diperlukan. Penyedia tidak boleh menggunakan library dengan lisensi yang melarang penggunaan sebagaimana tujuan Sistem tanpa persetujuan tertulis.

    3. Hak Pihak Pertama atas Keluaran tidak memberi hak untuk membuka Informasi Rahasia milik vendor lain. Penyedia wajib memisahkan kode dan dokumentasi yang memang merupakan milik pihak lain.

    4. Penyedia menjamin bahwa Keluaran tidak sengaja melanggar hak pihak ketiga. Jika ada klaim, Penyedia harus membantu pembelaan dan memberikan alternatif yang setara tanpa mengurangi fungsi utama.

    PASAL 9
    NILAI KONTRAK DAN PEMBAYARAN

    1. Nilai Kontrak adalah Rp8.375.000.000 termasuk PPN 11%. Nilai tersebut mencakup personel, perjalanan, perangkat, lisensi, pelatihan, support, dokumentasi, dan biaya lain yang diperlukan.

    2. Pembayaran dilakukan berdasarkan milestone: 20% setelah desain disetujui, 30% setelah demo integrasi, 30% setelah UAT lulus, dan 20% setelah BAST. Total persentase harus tetap 100% dan tidak boleh diubah dalam salinan.

    3. Setiap tagihan harus dilengkapi invoice, faktur pajak, laporan kemajuan, evidence, dan berita acara. Tagihan yang tidak lengkap dapat dikembalikan untuk dilengkapi tanpa dianggap sebagai penolakan Pekerjaan.

    4. PPK membayar paling lambat 30 (tiga puluh) hari kalender setelah dokumen lengkap dan benar diterima. Perbedaan nominal angka dan huruf harus diklarifikasi sebelum pembayaran dilakukan.

    5. Pihak Pertama dapat menahan retensi sebesar 5% sampai masa pemeliharaan selesai. Retensi tidak menghapus kewajiban Penyedia memperbaiki defect.

    PASAL 10
    DENDA DAN GANTI RUGI

    1. Keterlambatan yang menjadi tanggung jawab Penyedia dikenakan denda 1/1000 (satu per seribu) dari Nilai Kontrak sebelum pajak untuk setiap hari kalender, dengan batas maksimum 5% dari Nilai Kontrak.

    2. Denda tidak dikenakan atas keterlambatan akibat Pihak Pertama atau Keadaan Kahar yang telah diberitahukan dan dibuktikan. Penyedia tetap wajib melakukan mitigasi dan melanjutkan pekerjaan setelah keadaan berakhir.

    3. Pihak Kedua mengganti kerugian langsung yang terbukti timbul karena kelalaian berat, pelanggaran kerahasiaan, atau penyalahgunaan Data Pribadi. Kerugian tidak langsung tunduk pada batas yang disepakati dalam Lampiran Komersial.

    4. Para Pihak wajib mengambil langkah wajar untuk mengurangi resiko. Permintaan ganti rugi harus disertai dokumen yang menjelaskan kejadian, sebab, jumlah, dan tindakan mitigasi.

    PASAL 11
    PERUBAHAN DAN ADDENDUM

    1. Perubahan ruang lingkup, jadwal, Nilai Kontrak, spesifikasi, atau personel utama harus dibuat dalam Addendum atau change order yang ditanda tangani PPK dan Penyedia.

    2. Notulen rapat dapat menjadi bukti pembahasan tetapi bukan Addendum. Kalimat “disepakati untuk ditindaklanjuti” tidak boleh dibaca sebagai persetujuan biaya tambahan.

    3. Penyedia harus menyampaikan proposal perubahan paling lambat 5 (lima) Hari Kerja sejak kebutuhan diketahui. Proposal wajib mencantumkan analisis dampak, asumsi, dependency, dan resiko.

    4. PPK dapat menolak perubahan yang tidak memiliki anggaran atau dasar kebutuhan. Penyedia tidak boleh memulai pekerjaan tambahan sebelum persetujuan diterbitkan.

    PASAL 12
    KEADAAN KAHAR DAN PENGAKHIRAN

    1. Pihak yang mengalami Keadaan Kahar wajib memberi pemberitahuan tertulis dalam 3 (tiga) hari kerja. Pemberitahuan harus menjelaskan kejadian, kewajiban terdampak, perkiraan durasi, dan rencana pemulihan.

    2. Keadaan Kahar tidak menghapus kewajiban menjaga keamanan, kerahasiaan, backup, atau pembayaran yang telah jatuh tempo. Para Pihak wajib berunding untuk mengurangi dampak.

    3. PPK dapat mengakhiri Kontrak jika Penyedia gagal memperbaiki pelanggaran material dalam 14 (empat belas) hari setelah pemberitahuan. Untuk risiko keamanan kritis, PPK dapat menangguhkan akses segera sambil melakukan pemeriksaan.

    4. Penyedia dapat meminta pengakhiran jika PPK tidak membayar tagihan yang telah lengkap selama lebih dari 60 (enam puluh) hari, setelah memberikan dua pemberitahuan tertulis.

    5. Setelah pengakhiran, Penyedia wajib menyerahkan seluruh Keluaran yang telah dibayar, membantu transition, mengembalikan Data Pribadi, dan menghapus akses yang tidak diperlukan.

    PASAL 13
    PEMERIKSAAN DAN PENYELESAIAN SENGKETA

    1. PPK, auditor, dan pejabat berwenang dapat memeriksa dokumen Kontrak, penggunaan anggaran, Keluaran, dan catatan keamanan. Penyedia wajib memberikan akses yang patut tanpa membuka data Korporasi lain.

    2. Catatan proyek di simpan selama 5 (lima) tahun sejak BAST, kecuali hukum atau kebijakan arsip mewajibkan periode yang lebih lama. Catatan harus dapat dibaca dan ditelusuri.

    3. Sengketa diselesaikan melalui rapat pimpinan selama 30 (tiga puluh) hari kalender. Jika tidak selesai, Para Pihak memilih Pengadilan Negeri Yogyakarta, tanpa menghilangkan hak meminta tindakan sementara.

    4. Kontrak diatur berdasarkan hukum Republik Indonesia. Jika istilah teknis bahasa Inggris dan terjemahan bahasa Indonesia berbeda, definisi pada Pasal 1 menjadi rujukan awal, bukan satu-satunya bukti maksud.

    5. Apabila satu klausul tidak berlaku, klausul lain tetap berlaku. Perubahan harus di buat tertulis, ditandatangani, dan disimpan bersama dokumen Kontrak.

    PIHAK PERTAMA / PPK                           PIHAK KEDUA / PENYEDIA
    Badan Layanan Administrasi Publik              PT Nusantara Solusi Terpadu

    Nama: ____________________                     Nama: ____________________
    Jabatan: __________________                    Jabatan: __________________
    """

    private static func fixtureID(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("The AI Connector fixture ID must be a valid UUID")
        }
        return id
    }

    private static let dataProcessingAgreementID = fixtureID(
        "B2A8F3D4-7C10-4F93-AB6D-1E2C5A7D9002"
    )
    private static let financingAgreementID = fixtureID(
        "C3B9A4E5-8D21-4FA4-BC7E-2F3D6B8EA003"
    )
    private static let procurementAgreementID = fixtureID(
        "D4CAB5F6-9E32-40B5-CD8F-304E7C9FB104"
    )

    /// Dokumen bawaan ini tidak dipersistenkan dan selalu dikembalikan ke isi
    /// awal saat aplikasi dibuka ulang.
    static let builtInDocuments: [DashboardDocument] = [
        DashboardDocument(
            id: id,
            title: title,
            content: initialContent
        ),
        DashboardDocument(
            id: dataProcessingAgreementID,
            title: "DPA — Pengolahan Data Pribadi dan Transfer Internasional",
            content: dataProcessingAgreementContent
        ),
        DashboardDocument(
            id: financingAgreementID,
            title: "Financing Agreement — Facility, Collateral, dan Default",
            content: financingAgreementContent
        ),
        DashboardDocument(
            id: procurementAgreementID,
            title: "Kontrak Pengadaan — Sistem Informasi Layanan Publik",
            content: procurementAgreementContent
        )
    ]

    static var document: DashboardDocument {
        builtInDocuments[0]
    }

    static func isBuiltIn(_ document: DashboardDocument) -> Bool {
        builtInDocuments.contains { $0.id == document.id }
    }
}
