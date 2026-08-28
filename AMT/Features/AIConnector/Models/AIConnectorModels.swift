import Foundation

struct AIReviewSegment: Hashable, Sendable {
    let id: Int
    let sourceLocation: Int
    let sourceLength: Int
    let targetText: String
    let previousContext: String?
    let nextContext: String?
}

struct AITextSegmentationResult: Hashable, Sendable {
    let segments: [AIReviewSegment]
    let headingCount: Int
    let tooLongSegmentCount: Int
    let omittedSegmentCount: Int
}

enum AIReviewStatus: String, CaseIterable, Hashable, Sendable {
    case noSuggestion = "NO_SUGGESTION"
    case suggestion = "SUGGESTION"
    case needsReview = "NEEDS_REVIEW"

    var displayTitle: String {
        switch self {
        case .noSuggestion:
            "Tidak ada saran"
        case .suggestion:
            "Saran bahasa"
        case .needsReview:
            "Perlu review"
        }
    }
}

enum AIReviewCategory: String, CaseIterable, Hashable, Sendable {
    case none = "NONE"
    case spelling = "SPELLING"
    case grammar = "GRAMMAR"
    case clarity = "CLARITY"
    case terminology = "TERMINOLOGY"

    var displayTitle: String {
        switch self {
        case .none:
            ""
        case .spelling:
            "Ejaan"
        case .grammar:
            "Tata bahasa"
        case .clarity:
            "Kejelasan"
        case .terminology:
            "Terminologi"
        }
    }
}

enum AIReviewOrigin: String, Hashable, Sendable {
    case qwen = "Qwen"
    case deterministic = "Deterministic rules"
    case deterministicFallback = "Deterministic fallback"

    var displayTitle: String {
        switch self {
        case .qwen:
            "Model Qwen"
        case .deterministic:
            "Aturan deterministik"
        case .deterministicFallback:
            "Pemulihan deterministik"
        }
    }
}

enum AIConnectorReviewMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case deterministic = "deterministic"
    case hybrid = "hybrid"
    case modelOnly = "modelOnly"

    var id: Self { self }

    var title: String {
        switch self {
        case .deterministic:
            "Baseline aman"
        case .hybrid:
            "Hybrid: model + guard"
        case .modelOnly:
            "Qwen langsung"
        }
    }

    var detail: String {
        switch self {
        case .deterministic:
            "Tanpa download model; hanya koreksi yang sudah dibatasi."
        case .hybrid:
            "Qwen dicoba, lalu aturan deterministik memulihkan kasus aman."
        case .modelOnly:
            "Untuk membandingkan kualitas output Qwen tanpa pemulihan."
        }
    }

    var usesModel: Bool {
        self != .deterministic
    }
}

enum AIConnectorModelVariant: String, CaseIterable, Identifiable, Hashable, Sendable {
    case qwen35_2b = "qwen35-2b"
    case qwen3_4b = "qwen3-4b"

    var id: Self { self }

    var title: String {
        switch self {
        case .qwen35_2b:
            "Qwen3.5 2B (baseline)"
        case .qwen3_4b:
            "Qwen3 4B (pembanding)"
        }
    }

    var modelID: String {
        switch self {
        case .qwen35_2b:
            "mlx-community/Qwen3.5-2B-4bit"
        case .qwen3_4b:
            "mlx-community/Qwen3-4B-4bit"
        }
    }

    var revision: String {
        switch self {
        case .qwen35_2b:
            "674aaa7240b91e8012fcad5d791b7dfe5ba90207"
        case .qwen3_4b:
            "4dcb3d101c2a062e5c1d4bb173588c54ea6c4d25"
        }
    }

    var downloadEstimate: String {
        switch self {
        case .qwen35_2b:
            "sekitar 1,6 GB"
        case .qwen3_4b:
            "sekitar 2,3 GB"
        }
    }
}

struct AIParsedReview: Hashable, Sendable {
    let status: AIReviewStatus
    let category: AIReviewCategory
    let original: String?
    let replacement: String?
    let glossaryID: String?
    let reason: String
}

struct AIValidatedReview: Identifiable, Hashable, Sendable {
    let segment: AIReviewSegment
    let status: AIReviewStatus
    let category: AIReviewCategory
    let original: String?
    let replacement: String?
    let reason: String
    let glossaryMatch: LegalDictionaryMatch?
    let origin: AIReviewOrigin

    var id: Int { segment.id }
}

struct AIReviewGlossarySnapshot: Identifiable, Hashable, Sendable {
    let segment: AIReviewSegment
    let matches: [LegalDictionaryMatch]

    var id: Int { segment.id }
}

struct AIReviewRejection: Identifiable, Hashable, Sendable {
    let segment: AIReviewSegment
    let rawOutput: String
    let reason: String

    var id: Int { segment.id }
}

struct AIConnectorRunSummary: Hashable, Sendable {
    let reviewMode: AIConnectorReviewMode
    let modelVariant: AIConnectorModelVariant
    let processedSegmentCount: Int
    let suggestionCount: Int
    let needsReviewCount: Int
    let noSuggestionCount: Int
    let recoveredCount: Int
    let rejectedCount: Int
    let skippedSegmentCount: Int
}

enum AIConnectorFixtureExpectation: Hashable, Sendable {
    case suggestion(
        original: String,
        replacement: String,
        category: AIReviewCategory
    )
    case preserveDefinedTerms
    case noReplacement
}

struct AIConnectorFixtureEvaluation: Identifiable, Hashable, Sendable {
    let sample: AIConnectorSample
    let expectation: AIConnectorFixtureExpectation
    let actualStatus: AIReviewStatus?
    let actualOriginal: String?
    let actualReplacement: String?
    let passed: Bool
    let detail: String

    var id: String { sample.id }
}

struct AIConnectorBenchmarkSummary: Hashable, Sendable {
    let title: String
    let reviewMode: AIConnectorReviewMode
    let modelVariant: AIConnectorModelVariant
    let duration: TimeInterval
    let evaluations: [AIConnectorFixtureEvaluation]

    var passedCount: Int {
        evaluations.filter(\.passed).count
    }

    var totalCount: Int {
        evaluations.count
    }
}

enum AIConnectorInputSource: String, CaseIterable, Identifiable {
    case currentDocument
    case dummy

    var id: Self { self }

    var title: String {
        switch self {
        case .currentDocument:
            "Dokumen saat ini"
        case .dummy:
            "Contoh dummy"
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
            id: "terminology-data-pribadi",
            title: "Terminologi: Data Pribadi",
            text: "Data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik.",
            expectedSignal: "Usulkan istilah canonical 'Data Pribadi' jika kandidat glossary cocok."
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

    var expectation: AIConnectorFixtureExpectation {
        switch id {
        case "redundant-wajib-untuk":
            .suggestion(
                original: "wajib untuk",
                replacement: "wajib",
                category: .grammar
            )
        case "spelling-ditanda-tangani":
            .suggestion(
                original: "ditanda tangani",
                replacement: "ditandatangani",
                category: .spelling
            )
        case "terminology-data-pribadi":
            .suggestion(
                original: "Data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik",
                replacement: "Data Pribadi",
                category: .terminology
            )
        case "mixed-defined-terms":
            .preserveDefinedTerms
        default:
            .noReplacement
        }
    }
}

enum AIConnectorRunState: Equatable {
    case idle
    case segmenting
    case loading
    case downloading(Double)
    case reviewing(current: Int, total: Int)
    case completed
    case cancelled
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .segmenting, .loading, .downloading, .reviewing:
            true
        case .idle, .completed, .cancelled, .failed:
            false
        }
    }

    var title: String {
        switch self {
        case .idle:
            "Siap"
        case .segmenting:
            "Menyiapkan teks..."
        case .loading:
            "Memuat model..."
        case .downloading:
            "Mengunduh model..."
        case let .reviewing(current, total):
            "Meninjau segmen \(current) dari \(total)..."
        case .completed:
            "Selesai"
        case .cancelled:
            "Dibatalkan"
        case .failed:
            "Gagal"
        }
    }
}
