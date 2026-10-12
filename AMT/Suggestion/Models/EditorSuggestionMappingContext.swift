import Foundation

/// Prepared UTF-16 view shared by all mapping for one immutable document revision.
struct EditorSuggestionMappingContext {
    let text: String
    let nsText: NSString
    let length: Int

    init(_ text: String) {
        self.text = text
        nsText = text as NSString
        length = nsText.length
    }
}
