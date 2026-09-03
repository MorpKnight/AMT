import Foundation
import MLXLMCommon

enum AIConnectorLocalToolError: Error, Equatable, Sendable {
    case emptyQuery
    case missingEntryID
    case missingPassageID
    case missingReferenceID
    case unknownEntry
    case unknownPassage
    case unknownRegulation
    case budgetExceeded
    case resultLimitExceeded
    case timeout
}

/// Read-only tool boundary for the future grounded model path.
///
/// It only reads the versioned corpus/dictionary. It is usable by orchestration
/// and tests, but is not exposed as an open-ended Qwen tool loop.
actor AIConnectorLocalToolDispatcher {
    private let dictionaryStore: LegalDictionaryStore
    private let budget: AIConnectorLocalToolBudget
    private var callCount = 0

    init(
        dictionaryStore: LegalDictionaryStore,
        budget: AIConnectorLocalToolBudget = .default
    ) {
        self.dictionaryStore = dictionaryStore
        self.budget = budget
    }

    func resetBudget() {
        callCount = 0
    }

    func call(
        _ request: AIConnectorLocalToolRequest
    ) async throws -> AIConnectorLocalToolResponse {
        let startedAt = Date()
        guard budget.timeout > 0 else {
            throw AIConnectorLocalToolError.timeout
        }
        guard callCount < budget.maxCalls else {
            throw AIConnectorLocalToolError.budgetExceeded
        }
        callCount += 1

        switch request.name {
        case .searchLegalConcepts:
            guard let query = request.query?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !query.isEmpty else {
                throw AIConnectorLocalToolError.emptyQuery
            }
            let requestedLimit = max(1, request.limit)
            guard requestedLimit <= budget.maxResultsPerCall else {
                throw AIConnectorLocalToolError.resultLimitExceeded
            }
            let entries = dictionaryStore.search(
                query,
                limit: min(requestedLimit, budget.maxResultsPerCall)
            )
            try ensureWithinBudget(startedAt)
            return AIConnectorLocalToolResponse(
                name: request.name,
                payload: Self.encode(entries: entries),
                corpusVersion: Self.responseCorpusVersion(
                    for: entries,
                    fallback: dictionaryStore.activeCorpusVersion
                ),
                isAuthoritative: !entries.isEmpty && entries.allSatisfy {
                    $0.authority == .verified && $0.isActionable
                }
            )

        case .getLegalDefinition:
            guard let entryID = request.entryID,
                  !entryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIConnectorLocalToolError.missingEntryID
            }
            guard let entry = dictionaryStore.entries.first(where: { $0.id == entryID }) else {
                throw AIConnectorLocalToolError.unknownEntry
            }
            try ensureWithinBudget(startedAt)
            return AIConnectorLocalToolResponse(
                name: request.name,
                payload: Self.encode(entries: [entry]),
                corpusVersion: entry.corpusVersion,
                isAuthoritative: entry.authority == .verified && entry.isActionable
            )

        case .getSourcePassage:
            guard let passageID = request.passageID,
                  !passageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIConnectorLocalToolError.missingPassageID
            }
            guard let corpusStore = dictionaryStore.corpusStore,
                  let passage = corpusStore.sourcePassage(id: passageID) else {
                throw AIConnectorLocalToolError.unknownPassage
            }
            try ensureWithinBudget(startedAt)
            return AIConnectorLocalToolResponse(
                name: request.name,
                payload: Self.encode(passage),
                corpusVersion: corpusStore.manifest.corpusVersion,
                isAuthoritative: passage.officialDocumentURL != nil
            )

        case .getRegulationStatus:
            guard let referenceID = request.referenceID,
                  !referenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIConnectorLocalToolError.missingReferenceID
            }
            guard let corpusStore = dictionaryStore.corpusStore,
                  let regulation = corpusStore.regulation(id: referenceID) else {
                throw AIConnectorLocalToolError.unknownRegulation
            }
            try ensureWithinBudget(startedAt)
            return AIConnectorLocalToolResponse(
                name: request.name,
                payload: Self.encode(
                    RegulationStatusPayload(
                        referenceID: regulation.referenceID,
                        status: regulation.applicabilityStatus.rawValue,
                        statusRaw: regulation.officialStatusRaw,
                        officialDetailURL: regulation.officialDetailURL?.absoluteString,
                        officialDocumentURL: regulation.officialDocumentURL?.absoluteString
                    )
                ),
                corpusVersion: corpusStore.manifest.corpusVersion,
                isAuthoritative: regulation.applicabilityStatus == .inForce
            )

        case .getRegulationRelations:
            guard let referenceID = request.referenceID,
                  !referenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIConnectorLocalToolError.missingReferenceID
            }
            guard let corpusStore = dictionaryStore.corpusStore,
                  corpusStore.regulation(id: referenceID) != nil else {
                throw AIConnectorLocalToolError.unknownRegulation
            }
            let relations = corpusStore.relations(for: referenceID)
            try ensureWithinBudget(startedAt)
            return AIConnectorLocalToolResponse(
                name: request.name,
                payload: Self.encode(relations),
                corpusVersion: corpusStore.manifest.corpusVersion,
                isAuthoritative: !relations.isEmpty
            )
        }
    }

    /// The current dictionary lookup is synchronous and in-memory, so a
    /// post-operation deadline is sufficient for this local foundation. A
    /// future indexed corpus should preserve the same deadline at its I/O
    /// boundary rather than allowing an unbounded tool call.
    private func ensureWithinBudget(_ startedAt: Date) throws {
        guard Date().timeIntervalSince(startedAt) <= budget.timeout else {
            throw AIConnectorLocalToolError.timeout
        }
    }

    nonisolated static func toolSpecifications() -> [ToolSpec] {
        [
            [
                "type": "function",
                "function": [
                    "name": AIConnectorLocalToolName.searchLegalConcepts.rawValue,
                    "description": "Cari konsep pada glossary lokal read-only.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": ["type": "string"],
                            "limit": ["type": "integer", "maximum": 5]
                        ],
                        "required": ["query"]
                    ] as [String: any Sendable]
                ] as [String: any Sendable]
            ] as ToolSpec,
            [
                "type": "function",
                "function": [
                    "name": AIConnectorLocalToolName.getLegalDefinition.rawValue,
                    "description": "Ambil definisi glossary berdasarkan stable entry ID.",
                    "parameters": [
                        "type": "object",
                        "properties": ["entryID": ["type": "string"]],
                        "required": ["entryID"]
                    ] as [String: any Sendable]
                ] as [String: any Sendable]
            ] as ToolSpec,
            [
                "type": "function",
                "function": [
                    "name": AIConnectorLocalToolName.getSourcePassage.rawValue,
                    "description": "Ambil passage sumber terstruktur berdasarkan stable passage ID.",
                    "parameters": [
                        "type": "object",
                        "properties": ["passageID": ["type": "string"]],
                        "required": ["passageID"]
                    ] as [String: any Sendable]
                ] as [String: any Sendable]
            ] as ToolSpec,
            [
                "type": "function",
                "function": [
                    "name": AIConnectorLocalToolName.getRegulationStatus.rawValue,
                    "description": "Ambil status berlaku dan metadata resmi regulasi.",
                    "parameters": [
                        "type": "object",
                        "properties": ["referenceID": ["type": "string"]],
                        "required": ["referenceID"]
                    ] as [String: any Sendable]
                ] as [String: any Sendable]
            ] as ToolSpec,
            [
                "type": "function",
                "function": [
                    "name": AIConnectorLocalToolName.getRegulationRelations.rawValue,
                    "description": "Ambil relasi perubahan regulasi dari corpus lokal.",
                    "parameters": [
                        "type": "object",
                        "properties": ["referenceID": ["type": "string"]],
                        "required": ["referenceID"]
                    ] as [String: any Sendable]
                ] as [String: any Sendable]
            ] as ToolSpec
        ]
    }

    private nonisolated static func encode(
        entries: [LegalDictionaryEntry]
    ) -> String {
        let payload = entries.map {
            ToolEntry(
                id: $0.id,
                term: $0.term,
                definition: $0.definition,
                regulation: $0.regulation,
                regulationTitle: $0.regulationTitle,
                sourceURL: $0.sourceURL?.absoluteString,
                officialDocumentURL: $0.officialDocumentURL?.absoluteString,
                referenceID: $0.referenceID,
                applicabilityStatus: $0.applicabilityStatus.rawValue,
                sourcePassageID: $0.sourcePassageID,
                articleLocator: $0.articleLocator,
                pageStart: $0.pageStart,
                pageEnd: $0.pageEnd,
                authority: $0.authority.rawValue,
                corpusVersion: $0.corpusVersion
            )
        }
        guard let data = try? JSONEncoder().encode(payload),
              let result = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return result
    }

    private nonisolated static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let result = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return result
    }

    private nonisolated static func responseCorpusVersion(
        for entries: [LegalDictionaryEntry],
        fallback: String
    ) -> String {
        let versions = Set(entries.map(\.corpusVersion))
        return versions.count == 1 ? versions.first ?? fallback : "mixed-corpus"
    }

    private struct ToolEntry: Codable, Sendable {
        let id: String
        let term: String
        let definition: String
        let regulation: String
        let regulationTitle: String
        let sourceURL: String?
        let officialDocumentURL: String?
        let referenceID: String?
        let applicabilityStatus: String
        let sourcePassageID: String?
        let articleLocator: String?
        let pageStart: Int?
        let pageEnd: Int?
        let authority: String
        let corpusVersion: String
    }

    private struct RegulationStatusPayload: Codable, Sendable {
        let referenceID: String
        let status: String
        let statusRaw: String
        let officialDetailURL: String?
        let officialDocumentURL: String?

        enum CodingKeys: String, CodingKey {
            case referenceID = "reference_id"
            case status
            case statusRaw = "status_raw"
            case officialDetailURL = "official_detail_url"
            case officialDocumentURL = "official_document_url"
        }
    }
}
