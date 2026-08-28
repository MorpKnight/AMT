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
    PERJANJIAN UJI AI CONNECTOR

    Pihak Kedua wajib untuk menyerahkan laporan bulanan paling lambat tanggal 5 setiap bulan.

    Perjanjian ini telah ditanda tangani oleh Para Pihak pada tanggal 10 Agustus 2026.

    Perjanjian ini diatur dan ditafsirkan berdasarkan hukum Republik Indonesia.

    Data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik.

    Pihak Pertama dapat mengakhiri Perjanjian ini sewaktu-waktu tanpa pemberitahuan kepada Pihak Kedua.

    Pihak Kedua wajib menyampaikan pemberitahuan tertulis sekurang-kurangnya 30 (tiga puluh) hari kalender sebelum tanggal pengakhiran.

    Borrower wajib memberikan notice tertulis kepada Lender paling lambat 7 (tujuh) hari kerja.

    Perusahaan wajib mematuhi seluruh peraturan yang berlaku.

    KETENTUAN UMUM DAN ISTILAH

    “Informasi Rahasia” berarti seluruh informasi yang diterima oleh salah satu Pihak dari Pihak lainnya dalam rangka pelaksanaan Perjanjian ini.

    Para Pihak wajib menjaga kerahasiaan Informasi Rahasia selama jangka waktu Perjanjian ini dan setelah Perjanjian ini berakhir.

    Pembayaran biaya layanan sebesar Rp100.000.000 (seratus juta rupiah) dikenakan pajak pertambahan nilai sebesar 11%.

    Dokumen pendukung harus di simpan oleh Pihak Kedua selama 5 (lima) tahun sejak tanggal penerimaan.

    KETENTUAN RISIKO DAN PERUBAHAN

    Pihak Kedua dapat meminta perubahan jadwal penyampaian laporan, tetapi perubahan tersebut hanya berlaku setelah disetujui secara tertulis oleh Pihak Pertama.

    Perusahaan tidak bertanggung jawab atas keterlambatan yang disebabkan oleh keadaan kahar, kecuali apabila keterlambatan tersebut timbul karena kesengajaan atau kelalaian berat.

    Nomor kontrak adalah AMT-2026-001 dan tanggal mulai berlaku adalah 1 September 2026.

    Perjanjian ini dapat diperpanjang berdasarkan kesepakatan tertulis Para Pihak.

    Setiap perubahan atas Perjanjian ini harus dibuat secara tertulis dan ditandatangani oleh Para Pihak.

    Borrower wajib mengirimkan quarterly report kepada Lender paling lambat 3 (tiga) hari kerja setelah akhir setiap kuartal.

    Pihak Kedua tidak dapat mengalihkan hak dan kewajibannya berdasarkan Perjanjian ini tanpa persetujuan tertulis dari Pihak Pertama.

    Apabila terjadi sengketa, Para Pihak terlebih dahulu akan menyelesaikannya melalui musyawarah.
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
