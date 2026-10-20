import Foundation

/// Maps evidence-bound proposals into the existing editor contract.
/// Runtime authorization is validated again before an approved edit.
@MainActor
final class LegalReviewEditorBridge {
    struct Output {
        let suggestions: [EditorSuggestion]
        let annotations: [EditorReviewAnnotation]
        let incomplete: Bool
        let coverageStatus: String
    }
    private struct AcceptedContext {
        let revision: String; let corpus: String; let policy: String
        let proposals: [UUID: (EditorSuggestion, LegalReviewAgent.Finding)]
    }
    private var current: AcceptedContext?
    private var identities: [String: UUID] = [:]

    func map(_ result: LegalReviewAgent.Result, text: String, corpusVersion: String) -> Output {
        guard result.revision == DocumentFingerprinting.contentSHA256(text) else {
            current = nil
            return .init(suggestions: [], annotations: [], incomplete: true, coverageStatus: "invalidRevision")
        }
        let plan = LegalReviewSignalPlanner().build(text)
        let units = Dictionary(uniqueKeysWithValues: plan.units.map { ($0.id, $0) })
        var suggestions: [EditorSuggestion] = [], annotations: [EditorReviewAnnotation] = []
        var proposals: [UUID: (EditorSuggestion, LegalReviewAgent.Finding)] = [:]
        var incomplete = !result.failures.isEmpty || !["policySkipped", "completePairs"].contains(result.status)
        var seen = Set<String>()
        for finding in result.findings {
            guard seen.insert(finding.id).inserted else { incomplete = true; continue }
            guard finding.range.length > 0, !finding.original.isEmpty, let range = Range(finding.range, in: text), String(text[range]) == finding.original else {
                incomplete = true; continue
            }
            let identity = identities[finding.id] ?? Self.identity(for: finding.id)
            identities[finding.id] = identity
            let prefix = String(text[..<range.lowerBound].suffix(40))
            let suffix = String(text[range.upperBound...].prefix(40))
            if finding.actionable {
                guard finding.category == "grammar", let replacement = finding.replacement,
                      !LegalReviewProtection.contains(finding.range, in: text),
                      (try? LegalReviewAgent.apply(finding, revision: result.revision, to: text)) != nil else {
                    incomplete = true; continue
                }
                let item = EditorSuggestion(id: identity, sourceRange: finding.range, original: finding.original,
                    replacement: replacement, category: .grammar, reason: finding.reason, origin: .deterministic,
                    prefixContext: prefix, suffixContext: suffix)
                suggestions.append(item); proposals[item.id] = (item, finding)
            } else {
                let local = plan.local.contains(finding)
                guard local || (!finding.evidenceIDs.isEmpty && finding.evidenceIDs.allSatisfy { units[$0] != nil }) else {
                    incomplete = true; continue
                }
                let evidence: [AIConnectorFindingEvidence] = local && finding.evidenceIDs.count == 1
                    ? [.init(id: finding.evidenceIDs[0], sourceRange: finding.range, original: finding.original, label: "Teks dokumen")]
                    : finding.evidenceIDs.compactMap { id in units[id].map { .init(id: id, sourceRange: $0.range, original: $0.text, label: $0.heading.isEmpty ? "Klausul terkait" : $0.heading) } }
                annotations.append(.init(id: identity, sourceRange: finding.range, original: finding.original,
                    category: .clarity, kind: .needsReview,
                    title: finding.category == "missing" ? "Parameter terbuka" : "Periksa dua ketentuan",
                    reason: finding.reason, origin: finding.category == "conflict" ? .qwen : .deterministic,
                    prefixContext: prefix, suffixContext: suffix, relatedEvidence: evidence))
            }
        }
        let live = Set(result.findings.map(\.id))
        identities = identities.filter { live.contains($0.key) }
        current = .init(revision: result.revision, corpus: corpusVersion, policy: LegalReviewAgent.policy, proposals: proposals)
        return .init(suggestions: suggestions.sorted { $0.sourceRange.location < $1.sourceRange.location },
                     annotations: annotations.sorted { $0.sourceRange.location < $1.sourceRange.location }, incomplete: incomplete, coverageStatus: result.status)
    }

    /// Called inside the editor's existing MainActor validation boundary.
    func validate(_ item: EditorSuggestion, text: String, corpusVersion: String) -> Bool {
        guard let current, current.revision == DocumentFingerprinting.contentSHA256(text),
              current.corpus == corpusVersion, current.policy == LegalReviewAgent.policy,
              let saved = current.proposals[item.id], saved.0 == item,
              !LegalReviewProtection.contains(item.sourceRange, in: text),
              (try? LegalReviewAgent.apply(saved.1, revision: current.revision, to: text)) != nil else { return false }
        return true
    }
    /// Deterministic identity allows safe local provenance to be rebuilt after snapshot restore.
    static func identity(for findingID: String) -> UUID {
        let hex = Array(LegalReviewAgent.digest("editor|" + LegalReviewAgent.policy + "|" + findingID).prefix(32))
        let value = String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-" + String(hex[12..<16]) + "-" + String(hex[16..<20]) + "-" + String(hex[20..<32])
        return UUID(uuidString: value) ?? UUID()
    }
    func owns(_ id: UUID) -> Bool { current?.proposals[id] != nil }
    func invalidateAfterEdit() { current = nil }
    func reset() { current = nil; identities.removeAll() }
}
