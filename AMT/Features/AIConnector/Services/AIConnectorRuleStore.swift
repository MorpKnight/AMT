import Foundation

enum AIConnectorRuleStatus: String, Codable, Hashable, Sendable {
    case draft
    case active
    case disabled
    case deprecated
}

enum AIConnectorRuleMatcher: String, Codable, Hashable, Sendable {
    case tokenSequence
}

struct AIConnectorRuleDefinition: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let revision: Int
    let category: AIReviewCategory
    let matcher: AIConnectorRuleMatcher
    let value: String
    let replacement: String
    let reason: String
    let priority: Int
    let exceptions: [String]
    let status: AIConnectorRuleStatus
    let sourceNote: String
    let owner: String
    let reviewer: String
    let changelog: String
    let positiveFixtures: [String]
    let negativeFixtures: [String]

    init(
        id: String,
        revision: Int,
        category: AIReviewCategory,
        matcher: AIConnectorRuleMatcher,
        value: String,
        replacement: String,
        reason: String,
        priority: Int,
        exceptions: [String],
        status: AIConnectorRuleStatus,
        sourceNote: String,
        owner: String,
        reviewer: String,
        changelog: String,
        positiveFixtures: [String] = [],
        negativeFixtures: [String] = []
    ) {
        self.id = id
        self.revision = revision
        self.category = category
        self.matcher = matcher
        self.value = value
        self.replacement = replacement
        self.reason = reason
        self.priority = priority
        self.exceptions = exceptions
        self.status = status
        self.sourceNote = sourceNote
        self.owner = owner
        self.reviewer = reviewer
        self.changelog = changelog
        self.positiveFixtures = positiveFixtures
        self.negativeFixtures = negativeFixtures
    }

    var isEnabled: Bool { status == .active }
}

struct AIConnectorRulePack: Codable, Hashable, Sendable {
    let version: String
    let rules: [AIConnectorRuleDefinition]
}

/// Versioned, bundled rules for deterministic low-risk corrections.
///
/// The current pack is intentionally small. New rules should be added with
/// positive and negative fixtures before they are marked active.
struct AIConnectorRuleStore: Sendable {
    nonisolated static let currentVersion = "rule-pack-v1"

    let version: String
    let rules: [AIConnectorRuleDefinition]

    init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "AIConnectorRulePack", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let pack = try? JSONDecoder().decode(AIConnectorRulePack.self, from: data) {
            self.version = pack.version
            self.rules = pack.rules
        } else {
            let pack = Self.defaultPack
            self.version = pack.version
            self.rules = pack.rules
        }
    }

    init(version: String = currentVersion, rules: [AIConnectorRuleDefinition]) {
        self.version = version
        self.rules = rules
    }

    var activeRules: [AIConnectorRuleDefinition] {
        rules.filter(\.isEnabled).sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.id < rhs.id
        }
    }

    nonisolated private static let defaultPack = AIConnectorRulePack(
        version: currentVersion,
        rules: [
            AIConnectorRuleDefinition(
                id: "grammar-wajib-untuk",
                revision: 1,
                category: .grammar,
                matcher: .tokenSequence,
                value: "wajib untuk",
                replacement: "wajib",
                reason: "Menghapus kata yang tidak diperlukan tanpa mengubah makna kewajiban.",
                priority: 10,
                exceptions: [],
                status: .active,
                sourceNote: "Koreksi frasa baku yang dibatasi pada bentuk persis.",
                owner: "AMT",
                reviewer: "pending-human-review",
                changelog: "Initial rule pack migration",
                positiveFixtures: [
                    "Pihak Kedua wajib untuk menyerahkan laporan."
                ],
                negativeFixtures: [
                    "Pihak Kedua wajib menyerahkan laporan."
                ]
            ),
            AIConnectorRuleDefinition(
                id: "spelling-ditanda-tangani",
                revision: 1,
                category: .spelling,
                matcher: .tokenSequence,
                value: "ditanda tangani",
                replacement: "ditandatangani",
                reason: "Memperbaiki ejaan kata menjadi bentuk baku tanpa mengubah makna hukum.",
                priority: 20,
                exceptions: [],
                status: .active,
                sourceNote: "Koreksi ejaan yang tidak mengubah proposisi hukum.",
                owner: "AMT",
                reviewer: "pending-human-review",
                changelog: "Initial rule pack migration",
                positiveFixtures: [
                    "Perjanjian telah ditanda tangani oleh Para Pihak."
                ],
                negativeFixtures: [
                    "Perjanjian telah ditandatangani oleh Para Pihak."
                ]
            ),
            AIConnectorRuleDefinition(
                id: "spelling-di-simpan",
                revision: 1,
                category: .spelling,
                matcher: .tokenSequence,
                value: "di simpan",
                replacement: "disimpan",
                reason: "Memperbaiki pemisahan imbuhan tanpa mengubah makna hukum.",
                priority: 21,
                exceptions: [],
                status: .active,
                sourceNote: "Koreksi ejaan imbuhan yang dibatasi pada bentuk persis.",
                owner: "AMT",
                reviewer: "pending-human-review",
                changelog: "Initial rule pack migration",
                positiveFixtures: [
                    "Dokumen di simpan oleh Pihak Kedua."
                ],
                negativeFixtures: [
                    "Dokumen disimpan oleh Pihak Kedua."
                ]
            )
        ]
    )
}
