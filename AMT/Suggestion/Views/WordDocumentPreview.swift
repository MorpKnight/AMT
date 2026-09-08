//
//  WordDocumentPreview.swift
//  AMT
//

import QuickLookUI
import SwiftUI

/// Displays the untouched imported file with macOS Quick Look. This preserves
/// Word's page-oriented layout independently from AMT's editable rich-text view.
struct WordDocumentPreview: NSViewRepresentable {
    let sourceURL: URL

    func makeNSView(context: Context) -> NSView {
        // The designated Objective-C initializer is imported as failable.
        guard let preview = QLPreviewView(frame: .zero, style: .normal) else {
            return NSView(frame: .zero)
        }
        preview.autoresizingMask = [.width, .height]
        preview.previewItem = sourceURL as NSURL
        return preview
    }

    func updateNSView(_ preview: NSView, context: Context) {
        guard let preview = preview as? QLPreviewView else { return }
        if (preview.previewItem as? NSURL)?.path != sourceURL.path {
            preview.previewItem = sourceURL as NSURL
        }
    }
}

#Preview {
    ContentUnavailableView(
        "Pratinjau dokumen",
        systemImage: "doc.richtext",
        description: Text("Pratinjau tersedia setelah file Word diimpor.")
    )
    .frame(width: 700, height: 500)
}
