import Foundation

enum DocumentDuplicateMatchKind: Equatable, Sendable {
    case sourceFile
    case normalizedContent
}

enum DocumentImportResult {
    case imported(DashboardDocument)
    case duplicate(existing: DashboardDocument, matchKind: DocumentDuplicateMatchKind)
    case cancelled
    case failed(String)
}
