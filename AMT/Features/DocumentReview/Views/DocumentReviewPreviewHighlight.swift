import SwiftUI

/// Shows the selected source-grounded finding without pretending to know its page coordinates.
struct DocumentReviewPreviewHighlight: View {
    let item: DocumentReviewItem
    let context: DocumentReviewSourceContext
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Label("Temuan terpilih", systemImage: "text.magnifyingglass")
                    .font(.caption.weight(.semibold))

                Text("Segmen \(item.segmentID)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Tutup konteks temuan")
                .accessibilityLabel("Tutup konteks temuan")
            }

            DocumentReviewHighlightedSourceText(
                context: context,
                maximumSideCharacters: 64
            )
                .font(.caption)
                .lineLimit(5)
                .textSelection(.enabled)
                .padding(8)
                .background(
                    Color.accentColor.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 7)
                )

            Text("Konteks teks sumber; editor menampilkan teks analisis untuk debugging.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: 460, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.12))
        )
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Konteks temuan segmen \(item.segmentID)")
    }
}
