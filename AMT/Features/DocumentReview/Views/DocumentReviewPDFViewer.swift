import AppKit
import Observation
import PDFKit
import SwiftUI

struct DocumentReviewPDFPageStatus: Equatable, Sendable {
    let currentPageIndex: Int
    let pageCount: Int
    let pageLabel: String

    static let empty = DocumentReviewPDFPageStatus(
        currentPageIndex: 0,
        pageCount: 0,
        pageLabel: "-"
    )
}

/// Controls page navigation for the PDF review viewer without exposing PDFKit
/// objects to the surrounding SwiftUI view hierarchy.
@MainActor
@Observable
final class DocumentReviewPDFViewerController {
    @ObservationIgnored private weak var pdfView: PDFView?

    func attach(to pdfView: PDFView) {
        self.pdfView = pdfView
    }

    func goToPreviousPage() {
        pdfView?.goToPreviousPage(nil)
    }

    func goToNextPage() {
        pdfView?.goToNextPage(nil)
    }

    func goToPage(index: Int) {
        guard let pdfView,
              let document = pdfView.document,
              document.pageCount > 0 else {
            return
        }

        let clampedIndex = min(max(index, 0), document.pageCount - 1)
        guard let page = document.page(at: clampedIndex) else { return }
        pdfView.go(to: page)
    }
}

/// A PDFKit-backed document viewer with continuous pagination, visible page
/// breaks, navigation callbacks, and temporary review highlights.
struct DocumentReviewPDFViewer: NSViewRepresentable {
    let document: PDFDocument
    let reviewItems: [DocumentReviewItem]
    let anchors: [UUID: DocumentReviewPageAnchor]
    let selectedReviewID: UUID?
    let controller: DocumentReviewPDFViewerController
    let onPageChanged: (DocumentReviewPDFPageStatus) -> Void
    let onSelectReview: (UUID?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = DocumentReviewPDFView(frame: .zero)
        pdfView.autoScales = true
        pdfView.onReviewClick = { [weak coordinator = context.coordinator] point in
            coordinator?.selectReview(at: point)
        }
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.pageBreakMargins = NSEdgeInsets(
            top: 24,
            left: 0,
            bottom: 24,
            right: 0
        )
        pdfView.pageShadowsEnabled = true
        pdfView.interpolationQuality = .high
        pdfView.backgroundColor = NSColor.windowBackgroundColor
        pdfView.acceptsDraggedFiles = false
        pdfView.document = document

        context.coordinator.connect(to: pdfView)
        controller.attach(to: pdfView)
        context.coordinator.update(
            document: document,
            reviewItems: reviewItems,
            anchors: anchors,
            selectedReviewID: selectedReviewID
        )
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        context.coordinator.parent = self
        controller.attach(to: pdfView)

        if pdfView.document !== document {
            pdfView.document = document
        }

        context.coordinator.update(
            document: document,
            reviewItems: reviewItems,
            anchors: anchors,
            selectedReviewID: selectedReviewID
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: DocumentReviewPDFViewer

        private weak var pdfView: PDFView?
        private var pageChangedObserver: NSObjectProtocol?
        private var visiblePagesChangedObserver: NSObjectProtocol?
        private var lastSelectedReviewID: UUID?

        init(parent: DocumentReviewPDFViewer) {
            self.parent = parent
        }

        deinit {
            if let pageChangedObserver {
                NotificationCenter.default.removeObserver(pageChangedObserver)
            }
            if let visiblePagesChangedObserver {
                NotificationCenter.default.removeObserver(visiblePagesChangedObserver)
            }
        }

        func connect(to pdfView: PDFView) {
            self.pdfView = pdfView
            pageChangedObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.publishPageStatus()
                }
            }
            visiblePagesChangedObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewVisiblePagesChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.publishPageStatus()
                }
            }
            publishPageStatus()
        }

        func update(
            document: PDFDocument,
            reviewItems: [DocumentReviewItem],
            anchors: [UUID: DocumentReviewPageAnchor],
            selectedReviewID: UUID?
        ) {
            guard let pdfView else { return }
            let selections = makeHighlightedSelections(
                document: document,
                reviewItems: reviewItems,
                anchors: anchors,
                selectedReviewID: selectedReviewID
            )
            pdfView.highlightedSelections = selections

            if selectedReviewID != lastSelectedReviewID {
                lastSelectedReviewID = selectedReviewID
                guard let selectedReviewID,
                      let anchor = anchors[selectedReviewID],
                      let page = document.page(at: anchor.pageIndex),
                      let rect = anchor.rects.first else {
                    publishPageStatus()
                    return
                }
                pdfView.go(to: rect, on: page)
            }

            publishPageStatus()
        }

        func selectReview(at point: NSPoint) {
            guard let pdfView,
                  let document = pdfView.document,
                  let page = pdfView.page(for: point, nearest: false) else {
                parent.onSelectReview(nil)
                return
            }

            let pageIndex = document.index(for: page)
            let pagePoint = pdfView.convert(point, to: page)
            let selectedID = parent.anchors.first { id, anchor in
                anchor.pageIndex == pageIndex
                    && anchor.rects.contains { rect in
                        rect.insetBy(dx: -5, dy: -5).contains(pagePoint)
                    }
            }?.key
            parent.onSelectReview(selectedID)
        }

        private func makeHighlightedSelections(
            document: PDFDocument,
            reviewItems: [DocumentReviewItem],
            anchors: [UUID: DocumentReviewPageAnchor],
            selectedReviewID: UUID?
        ) -> [PDFSelection] {
            let itemsByID = Dictionary(uniqueKeysWithValues: reviewItems.map { ($0.id, $0) })
            return anchors.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { id in
                guard let item = itemsByID[id],
                      let selection = uniqueSelection(
                          for: item.original,
                          in: document
                      ) else {
                    return nil
                }

                selection.color = id == selectedReviewID
                    ? NSColor.systemOrange.withAlphaComponent(0.48)
                    : NSColor.systemYellow.withAlphaComponent(0.36)
                return selection
            }
        }

        private func uniqueSelection(
            for text: String,
            in document: PDFDocument
        ) -> PDFSelection? {
            guard !text.isEmpty else { return nil }
            let matches = document.findString(text, withOptions: .literal)
            return matches.count == 1 ? matches[0] : nil
        }

        private func publishPageStatus() {
            guard let pdfView,
                  let document = pdfView.document,
                  document.pageCount > 0 else {
                parent.onPageChanged(.empty)
                return
            }

            let page = pdfView.currentPage ?? pdfView.visiblePages.first
            let pageIndex = page.map { document.index(for: $0) } ?? 0
            let pageLabel = page?.label?.isEmpty == false
                ? page?.label ?? String(pageIndex + 1)
                : String(pageIndex + 1)
            parent.onPageChanged(
                DocumentReviewPDFPageStatus(
                    currentPageIndex: pageIndex,
                    pageCount: document.pageCount,
                    pageLabel: pageLabel
                )
            )
        }
    }
}

final class DocumentReviewPDFView: PDFView {
    var onReviewClick: ((NSPoint) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        super.mouseDown(with: event)
        onReviewClick?(point)
    }
}

struct DocumentReviewPDFContainer: View {
    let document: PDFDocument
    let reviewItems: [DocumentReviewItem]
    let anchors: [UUID: DocumentReviewPageAnchor]
    let selectedReviewID: UUID?
    let onSelectReview: (UUID?) -> Void

    @State private var pageStatus = DocumentReviewPDFPageStatus.empty
    @State private var pageInput = "1"
    @State private var viewerController = DocumentReviewPDFViewerController()

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider()
            DocumentReviewPDFViewer(
                document: document,
                reviewItems: reviewItems,
                anchors: anchors,
                selectedReviewID: selectedReviewID,
                controller: viewerController,
                onPageChanged: { status in
                    pageStatus = status
                    if status.pageCount > 0 {
                        pageInput = String(status.currentPageIndex + 1)
                    }
                },
                onSelectReview: onSelectReview
            )
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button {
                viewerController.goToPreviousPage()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(pageStatus.currentPageIndex == 0)
            .help("Halaman sebelumnya")

            Button {
                viewerController.goToNextPage()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(
                pageStatus.pageCount == 0
                    || pageStatus.currentPageIndex >= pageStatus.pageCount - 1
            )
            .help("Halaman berikutnya")

            Text("Halaman \(pageStatus.pageLabel) dari \(pageStatus.pageCount)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            TextField("Halaman", text: $pageInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .onSubmit(goToEnteredPage)

            Button("Ke halaman", action: goToEnteredPage)
                .buttonStyle(.bordered)
                .disabled(pageStatus.pageCount == 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigasi halaman dokumen")
    }

    private func goToEnteredPage() {
        guard let page = Int(pageInput.trimmingCharacters(in: .whitespacesAndNewlines)),
              pageStatus.pageCount > 0 else {
            pageInput = String(pageStatus.currentPageIndex + 1)
            return
        }
        viewerController.goToPage(index: page - 1)
    }
}

#Preview {
    DocumentReviewPDFContainer(
        document: {
            let data = try? DocumentReviewPDFRenderer.render(
                attributedString: NSAttributedString(
                    string: Array(repeating: "Contoh halaman dokumen hukum.", count: 100)
                        .joined(separator: "\n\n")
                ),
                configuration: DocumentReviewPDFConfiguration(
                    paperSize: NSSize(width: 320, height: 420),
                    margins: NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
                )
            )
            return PDFDocument(data: data ?? Data()) ?? PDFDocument()
        }(),
        reviewItems: [],
        anchors: [:],
        selectedReviewID: nil,
        onSelectReview: { _ in }
    )
    .frame(width: 520, height: 600)
}
