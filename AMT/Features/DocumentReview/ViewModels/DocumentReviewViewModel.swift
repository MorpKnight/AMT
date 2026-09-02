import Foundation
import Observation

enum DocumentReviewSourceAvailability: Equatable {
    case original
    case legacyText
    case missing
    case changed
    case unreadable

    var isOriginal: Bool {
        self == .original
    }

    var notice: String {
        switch self {
        case .original:
            "Layout asli ditampilkan melalui Quick Look."
        case .legacyText:
            "Layout asli tidak tersedia; menampilkan fallback teks biasa."
        case .missing:
            "Salinan DOCX asli tidak ditemukan. Ekspor review dinonaktifkan."
        case .changed:
            "Salinan DOCX berubah sejak impor. Ekspor review dinonaktifkan."
        case .unreadable:
            "Salinan DOCX tidak dapat dibaca. Ekspor review dinonaktifkan."
        }
    }
}

/// Owns review orchestration and draft decisions without mutating the original document.
@MainActor
@Observable
final class DocumentReviewViewModel {
    private(set) var documentID: UUID?
    private(set) var sourceURL: URL?
    private(set) var sourceText = ""
    private(set) var analysisText = ""
    private(set) var sourceFingerprint: String?
    private(set) var sourceAvailability: DocumentReviewSourceAvailability = .missing
    private(set) var analysisStatus: DocumentReviewAnalysisStatus = .idle
    private(set) var reviewItems: [DocumentReviewItem] = []
    private(set) var selectedReviewItemID: UUID?
    private(set) var progress = 0.0
    private(set) var progressDetail = ""
    private(set) var errorMessage: String?
    private(set) var exportErrorMessage: String?
    private(set) var didRestoreSnapshot = false
    private(set) var didRejectStaleSnapshot = false

    private let analyzer: any DocumentReviewAnalyzer
    private let fileManager: FileManager
    private let onSnapshotChanged: (UUID, DocumentReviewSnapshot) -> Void
    private var analysisTask: Task<Void, Never>?
    private var activeOperationID: UUID?
    private var automaticAnalysisStarted = false

    init(
        document: DashboardDocument? = nil,
        originalURL: URL? = nil,
        analyzer: any DocumentReviewAnalyzer,
        fileManager: FileManager = .default,
        onSnapshotChanged: @escaping (UUID, DocumentReviewSnapshot) -> Void = { _, _ in }
    ) {
        self.analyzer = analyzer
        self.fileManager = fileManager
        self.onSnapshotChanged = onSnapshotChanged

        if let document {
            load(document: document, originalURL: originalURL)
        }
    }

    var isAnalyzing: Bool {
        analysisStatus == .analyzing
    }

    var canAnalyze: Bool {
        !isAnalyzing && !analysisText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && sourceAvailability != .missing
            && sourceAvailability != .unreadable
    }

    var acceptedItemCount: Int {
        reviewItems.filter { $0.decision == .accepted }.count
    }

    var actionablePendingItemCount: Int {
        reviewItems.filter { $0.decision == .pending && $0.isActionable }.count
    }

    var canExport: Bool {
        guard sourceAvailability.isOriginal,
              let sourceURL,
              fileManager.fileExists(atPath: sourceURL.path),
              let sourceFingerprint,
              !acceptedItems.isEmpty
        else {
            return false
        }

        guard (try? DocumentFingerprint.sha256(fileURL: sourceURL)) == sourceFingerprint else {
            return false
        }

        return validatedAcceptedItems().isEmpty == false
    }

    var sourceViewerNotice: String {
        return sourceAvailability.notice
    }

    var selectedReviewContext: DocumentReviewSourceContext? {
        guard let selectedReviewItemID else { return nil }
        return sourceContext(for: selectedReviewItemID)
    }

    var selectedReviewItem: DocumentReviewItem? {
        guard let selectedReviewItemID else { return nil }
        return reviewItems.first(where: { $0.id == selectedReviewItemID })
    }

    func load(document: DashboardDocument, originalURL: URL?) {
        cancel()
        documentID = document.id
        sourceURL = originalURL
        sourceText = ""
        analysisText = ""
        sourceFingerprint = nil
        sourceAvailability = .missing
        analysisStatus = .idle
        reviewItems = []
        selectedReviewItemID = nil
        progress = 0
        progressDetail = ""
        errorMessage = nil
        exportErrorMessage = nil
        didRestoreSnapshot = false
        didRejectStaleSnapshot = false
        automaticAnalysisStarted = false

        guard let originalURL else {
            if document.originalSidecarRelativePath == nil {
                sourceAvailability = .legacyText
                sourceText = document.content
                analysisText = document.content
            } else {
                sourceAvailability = .missing
                errorMessage = sourceAvailability.notice
                analysisStatus = .failed
            }
            return
        }

        guard fileManager.fileExists(atPath: originalURL.path) else {
            sourceAvailability = .missing
            errorMessage = sourceAvailability.notice
            analysisStatus = .failed
            return
        }

        do {
            let fingerprint = try DocumentFingerprint.sha256(fileURL: originalURL)
            sourceFingerprint = fingerprint

            if let expectedFingerprint = document.originalFingerprint,
               expectedFingerprint != fingerprint {
                sourceAvailability = .changed
                errorMessage = sourceAvailability.notice
                analysisStatus = .failed
                return
            }

            let extraction = try DocxToMarkdownConverter.extract(fileURL: originalURL)
            sourceAvailability = .original
            sourceText = extraction.sourceText
            analysisText = extraction.analysisText
            restoreSnapshotIfValid(document.reviewSnapshot, fingerprint: fingerprint)
        } catch {
            sourceAvailability = .unreadable
            errorMessage = error.localizedDescription
            analysisStatus = .failed
        }
    }

    func startAutomaticAnalysisIfNeeded() {
        guard sourceAvailability.isOriginal,
              !automaticAnalysisStarted,
              !didRestoreSnapshot,
              analysisStatus == .idle
        else {
            return
        }

        automaticAnalysisStarted = true
        startAnalysis()
    }

    func analyze() {
        guard canAnalyze else {
            errorMessage = "Tidak ada teks yang dapat dianalisis."
            analysisStatus = .failed
            return
        }

        automaticAnalysisStarted = true
        startAnalysis()
    }

    func retryAnalysis() {
        guard !isAnalyzing else { return }
        reviewItems = []
        selectedReviewItemID = nil
        analysisStatus = .idle
        progress = 0
        progressDetail = ""
        errorMessage = nil
        exportErrorMessage = nil
        didRestoreSnapshot = false
        startAnalysis()
    }

    func cancel() {
        guard isAnalyzing || analysisTask != nil else { return }

        activeOperationID = nil
        analysisTask?.cancel()
        analysisTask = nil
        analyzer.cancel()
        analysisStatus = .cancelled
        progressDetail = "Analisis dibatalkan"
        persistSnapshot()
    }

    @discardableResult
    func accept(itemID: UUID) -> Bool {
        guard let index = reviewItems.firstIndex(where: { $0.id == itemID }),
              reviewItems[index].decision == .pending,
              reviewItems[index].isActionable,
              hasSafeSourceRange(for: reviewItems[index])
        else {
            return false
        }

        let candidate = reviewItems[index]
        guard reviewItems.enumerated().allSatisfy({ otherIndex, item in
            guard otherIndex != index,
                  item.decision == .accepted,
                  let acceptedRange = item.sourceRange?.nsRange,
                  let candidateRange = candidate.sourceRange?.nsRange
            else {
                return true
            }
            return NSIntersectionRange(acceptedRange, candidateRange).length == 0
        }) else {
            return false
        }

        reviewItems[index].decision = .accepted
        persistSnapshot()
        return true
    }

    @discardableResult
    func reject(itemID: UUID) -> Bool {
        guard let index = reviewItems.firstIndex(where: { $0.id == itemID }),
              reviewItems[index].decision == .pending
        else {
            return false
        }

        reviewItems[index].decision = .rejected
        persistSnapshot()
        return true
    }

    func selectReviewItem(_ id: UUID?) {
        guard let id,
              reviewItems.contains(where: { $0.id == id }) else {
            selectedReviewItemID = nil
            return
        }
        selectedReviewItemID = id
    }

    func sourceContext(for itemID: UUID) -> DocumentReviewSourceContext? {
        guard let item = reviewItems.first(where: { $0.id == itemID }) else {
            return nil
        }
        return DocumentReviewSourceContext.make(for: item, in: sourceText)
    }

    func exportReviewedDocument(title: String) {
        guard canExport,
              let sourceURL,
              let sourceFingerprint
        else {
            exportErrorMessage = "Ekspor tidak tersedia: sumber berubah, hilang, atau belum ada perubahan yang diterima."
            return
        }

        DocumentExporter.exportReviewedAsDocx(
            title: title,
            originalURL: sourceURL,
            expectedFingerprint: sourceFingerprint,
            acceptedItems: validatedAcceptedItems()
        ) { [weak self] result in
            guard let self else { return }
            if case let .failure(error) = result {
                self.exportErrorMessage = error.localizedDescription
            } else {
                self.exportErrorMessage = nil
            }
        }
    }

    private var acceptedItems: [DocumentReviewItem] {
        reviewItems.filter { $0.decision == .accepted }
    }

    private func validatedAcceptedItems() -> [DocumentReviewItem] {
        let candidates = acceptedItems.filter { hasSafeSourceRange(for: $0) }
        let sorted = candidates.sorted {
            ($0.sourceRange?.location ?? 0) < ($1.sourceRange?.location ?? 0)
        }

        for pair in zip(sorted, sorted.dropFirst()) {
            guard let left = pair.0.sourceRange?.nsRange,
                  let right = pair.1.sourceRange?.nsRange
            else {
                return []
            }
            if NSIntersectionRange(left, right).length > 0 {
                return []
            }
        }

        return candidates.count == acceptedItems.count ? candidates : []
    }

    private func hasSafeSourceRange(for item: DocumentReviewItem) -> Bool {
        guard item.isActionable,
              let range = item.sourceRange,
              range.isValid(inUTF16Length: sourceText.utf16.count),
              NSMaxRange(range.nsRange) <= sourceText.utf16.count
        else {
            return false
        }

        return (sourceText as NSString).substring(with: range.nsRange) == item.original
    }

    private func startAnalysis() {
        guard canAnalyze else { return }

        analysisTask?.cancel()
        analyzer.cancel()
        let operationID = UUID()
        activeOperationID = operationID
        let input = analysisText
        let source = sourceText
        analysisStatus = .analyzing
        progress = 0
        progressDetail = "Menyiapkan teks"
        errorMessage = nil
        exportErrorMessage = nil

        analysisTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let reviews = try await analyzer.analyze(documentText: input) { [weak self] update in
                    guard let self, self.activeOperationID == operationID else { return }
                    guard update.fraction >= self.progress else { return }
                    self.progress = update.fraction
                    self.progressDetail = update.detail
                }

                guard activeOperationID == operationID else { return }
                reviewItems = DocumentReviewMapper.make(reviews: reviews, sourceText: source)
                progress = 1
                progressDetail = "Analisis selesai"
                analysisStatus = .completed
                analysisTask = nil
                persistSnapshot()
            } catch is CancellationError {
                guard activeOperationID == operationID else { return }
                analysisTask = nil
                analysisStatus = .cancelled
                progressDetail = "Analisis dibatalkan"
                persistSnapshot()
            } catch {
                guard activeOperationID == operationID else { return }
                analysisTask = nil
                analysisStatus = .failed
                errorMessage = error.localizedDescription
                progressDetail = "Analisis gagal"
                persistSnapshot()
            }
        }
    }

    private func restoreSnapshotIfValid(
        _ snapshot: DocumentReviewSnapshot?,
        fingerprint: String
    ) {
        guard let snapshot else { return }
        guard snapshot.schemaVersion == DocumentReviewSnapshot.currentSchemaVersion,
              snapshot.sourceFingerprint == fingerprint,
              snapshot.analysisStatus != .analyzing
        else {
            didRejectStaleSnapshot = true
            return
        }

        reviewItems = snapshot.reviewItems
        analysisStatus = snapshot.analysisStatus
        didRestoreSnapshot = true
        if analysisStatus == .completed {
            progress = 1
            progressDetail = "Analisis selesai"
        } else {
            progressDetail = analysisStatus.displayTitle
        }
    }

    private func persistSnapshot() {
        guard let documentID,
              let sourceFingerprint,
              sourceAvailability.isOriginal,
              analysisStatus != .analyzing
        else {
            return
        }

        onSnapshotChanged(
            documentID,
            DocumentReviewSnapshot(
                sourceFingerprint: sourceFingerprint,
                analysisStatus: analysisStatus,
                reviewItems: reviewItems
            )
        )
    }
}
