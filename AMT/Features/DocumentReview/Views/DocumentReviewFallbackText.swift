import Foundation

/// Removes the small set of Markdown markers used by legacy document content.
enum DocumentReviewFallbackText {
    static func plainText(from markdown: String) -> String {
        markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { plainLine(String($0)) }
            .joined(separator: "\n")
    }

    private static func plainLine(_ value: String) -> String {
        var line = value.trimmingCharacters(in: .whitespaces)

        while line.first == "#" {
            line.removeFirst()
        }
        if line.first == " " {
            line.removeFirst()
        }

        for marker in ["> ", "- ", "* ", "+ "] where line.hasPrefix(marker) {
            line.removeFirst(marker.count)
            break
        }

        if let dot = line.firstIndex(of: "."),
           line[..<dot].isEmpty == false,
           line[..<dot].allSatisfy(\.isNumber),
           line.index(after: dot) < line.endIndex,
           line[line.index(after: dot)] == " " {
            line.removeSubrange(...line.index(after: dot))
        }

        return line
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "~~", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "`", with: "")
    }
}
