import Foundation
import MLXLMCommon

enum AIConnectorLocalToolError: Error, Equatable, Sendable {
    case emptyQuery
    case missingEntryID
    case unknownEntry
    case budgetExceeded
    case resultLimitExceeded
    case timeout
}

/// Read-only tool boundary for the future grounded model path.
///
/// It deliberately reports the current legacy corpus as non-authoritative.
/// The dispatcher is usable by tests and future orchestration, but is not
/// attached to Qwen until the corpus has current provenance and status data.
actor AIConnectorLocalToolDispatcher {
    nonisolated static let corpusVersion = "legacy-kamus-v1"

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
            let entries = await dictionaryStore.search(
                query,
                limit: min(requestedLimit, budget.maxResultsPerCall)
            )
            try ensureWithinBudget(startedAt)
            return AIConnectorLocalToolResponse(
                name: request.name,
                payload: Self.encode(entries: entries),
                corpusVersion: Self.corpusVersion,
                isAuthoritative: false
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
                corpusVersion: Self.corpusVersion,
                isAuthoritative: false
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
                sourceURL: $0.sourceURL?.absoluteString
            )
        }
        guard let data = try? JSONEncoder().encode(payload),
              let result = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return result
    }

    private struct ToolEntry: Codable, Sendable {
        let id: String
        let term: String
        let definition: String
        let regulation: String
        let regulationTitle: String
        let sourceURL: String?
    }
}
