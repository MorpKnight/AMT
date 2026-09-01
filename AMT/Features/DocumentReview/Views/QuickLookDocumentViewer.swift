import QuickLookUI
import SwiftUI

struct QuickLookDocumentViewer: NSViewRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        guard let previewView = QLPreviewView(frame: .zero, style: .normal) else {
            return NSView(frame: .zero)
        }
        previewView.autostarts = true
        context.coordinator.update(previewView, with: fileURL)
        return previewView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let previewView = nsView as? QLPreviewView else { return }
        context.coordinator.update(previewView, with: fileURL)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        guard let previewView = nsView as? QLPreviewView else { return }
        previewView.previewItem = nil
        previewView.refreshPreviewItem()
    }

    final class Coordinator {
        private var previewItem: PreviewItem?

        func update(_ previewView: QLPreviewView, with fileURL: URL) {
            guard previewItem?.url != fileURL else { return }
            let item = PreviewItem(url: fileURL)
            previewItem = item
            previewView.previewItem = item
            previewView.refreshPreviewItem()
        }
    }

    private final class PreviewItem: NSObject, QLPreviewItem {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        var previewItemURL: URL? {
            url
        }

        var previewItemTitle: String? {
            url.lastPathComponent
        }
    }
}

struct DocumentSourceViewer: View {
    let originalURL: URL?
    let fallbackText: String
    let notice: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: originalURL == nil ? "doc.text" : "doc.richtext")
                    .foregroundStyle(.secondary)
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if let originalURL {
                QuickLookDocumentViewer(fileURL: originalURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(fallbackText.isEmpty ? "Dokumen tidak memiliki isi teks." : fallbackText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(28)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
}
