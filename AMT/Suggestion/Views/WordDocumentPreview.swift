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

    func makeNSView(context: Context) -> QLPreviewView {
        // The designated Objective-C initializer is imported as failable.
        // Quick Look always provides this view on supported macOS versions.
        let preview = QLPreviewView(frame: .zero, style: .normal)!
        preview.autoresizingMask = [.width, .height]
        preview.previewItem = sourceURL as NSURL
        return preview
    }

    func updateNSView(_ preview: QLPreviewView, context: Context) {
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
