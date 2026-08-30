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

    static var document: DashboardDocument {
        DashboardDocument(
            id: id,
            title: title,
            content: initialContent,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    static func isBuiltIn(_ document: DashboardDocument) -> Bool {
        document.id == id
    }
}
