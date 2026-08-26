import Foundation

enum AIConnectorInputSource: String, CaseIterable, Identifiable {
    case currentDocument
    case dummy

    var id: Self { self }

    var title: String {
        switch self {
        case .currentDocument:
            "Current Document"
        case .dummy:
            "Dummy Sample"
        }
    }
}

struct AIConnectorSample: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let text: String
    let expectedSignal: String

    static let samples: [AIConnectorSample] = [
        AIConnectorSample(
            id: "redundant-wajib-untuk",
            title: "Redundansi: wajib untuk",
            text: "Pihak Kedua wajib untuk menyerahkan laporan bulanan paling lambat tanggal 5 setiap bulan.",
            expectedSignal: "Sarankan 'wajib menyerahkan'."
        ),
        AIConnectorSample(
            id: "spelling-ditanda-tangani",
            title: "Ejaan: ditanda tangani",
            text: "Perjanjian ini telah ditanda tangani oleh Para Pihak pada tanggal 10 Agustus 2026.",
            expectedSignal: "Sarankan 'ditandatangani'."
        ),
        AIConnectorSample(
            id: "no-issue-governing-law",
            title: "Tanpa masalah: governing law",
            text: "Perjanjian ini diatur dan ditafsirkan berdasarkan hukum Republik Indonesia.",
            expectedSignal: "Tidak memaksakan perubahan."
        ),
        AIConnectorSample(
            id: "substantive-termination-clause",
            title: "Sensitif: hak pengakhiran",
            text: "Pihak Pertama dapat mengakhiri Perjanjian ini sewaktu-waktu tanpa pemberitahuan kepada Pihak Kedua.",
            expectedSignal: "Tidak menulis ulang substansi; minta review manusia bila perlu."
        ),
        AIConnectorSample(
            id: "preserve-deadline",
            title: "Preservasi: tenggat 30 hari",
            text: "Pihak Kedua wajib menyampaikan pemberitahuan tertulis sekurang-kurangnya 30 (tiga puluh) hari kalender sebelum tanggal pengakhiran.",
            expectedSignal: "Pertahankan angka dan tenggat."
        ),
        AIConnectorSample(
            id: "mixed-defined-terms",
            title: "Istilah campuran: Borrower/Lender",
            text: "Borrower wajib memberikan notice tertulis kepada Lender paling lambat 7 (tujuh) hari kerja.",
            expectedSignal: "Tandai konsistensi istilah tanpa menerjemahkan defined terms sembarang."
        ),
        AIConnectorSample(
            id: "no-source-claim",
            title: "Tanpa sumber: peraturan berlaku",
            text: "Perusahaan wajib mematuhi seluruh peraturan yang berlaku.",
            expectedSignal: "Jangan mengarang peraturan atau kutipan."
        ),
    ]
}

enum AIConnectorRunState: Equatable {
    case idle
    case loading
    case downloading(Double)
    case generating
    case completed
    case cancelled
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .loading, .downloading, .generating:
            true
        case .idle, .completed, .cancelled, .failed:
            false
        }
    }

    var title: String {
        switch self {
        case .idle:
            "Ready"
        case .loading:
            "Loading model..."
        case .downloading:
            "Downloading model..."
        case .generating:
            "Generating response..."
        case .completed:
            "Completed"
        case .cancelled:
            "Cancelled"
        case .failed:
            "Failed"
        }
    }
}
