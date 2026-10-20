import Foundation

typealias LegalReviewRoutingHandler = @MainActor (
    String, Bool, AIConnectorDocumentStructure
) async throws -> LegalReviewFastRouter.Decision


/// Conservatively admits only locally decidable inputs to the base deterministic path.
@MainActor
final class LegalReviewFastRouter {
    static let policy = "legal-review-fastlane-integrated-v1"
    struct Decision {
        let needsHybrid: Bool; let reason: String; let lexicalQueries: Int; let cacheHit: Bool
        var mode: AIConnectorReviewMode { needsHybrid ? .hybrid : .deterministic }
    }
    private let store: LegalDictionaryStore
    private let provider: any AIConnectorSpellingCandidateProviding
    private let engine = AIConnectorDeterministicSuggestionEngine()
    private var cache = AIConnectorAnalysisLRUCache<Decision>(capacity: 128, maximumCost: 2*1_024*1_024)
    private var epoch = 0
    init(dictionaryStore: LegalDictionaryStore, provider: (any AIConnectorSpellingCandidateProviding)? = nil) {
        store = dictionaryStore; self.provider = provider ?? SystemIndonesianSpellingCandidateProvider()
    }
    func clearCache() { epoch += 1; cache.removeAll() }
    func route(_ text: String, fullFresh: Bool, structure suppliedStructure: AIConnectorDocumentStructure? = nil) async throws -> Decision {
        try Task.checkCancellation()
        let structure = suppliedStructure ?? AIConnectorDocumentStructureBuilder().build(documentText:text)
        let key = LegalReviewAgent.digest(text+"|"+structure.fingerprint+"|"+store.activeCorpusVersion+"|"+Self.policy+"|"+AIConnectorRuleStore.currentVersion)
        if !fullFresh, let previous = cache[key] {
            return .init(needsHybrid: previous.needsHybrid, reason: previous.reason, lexicalQueries: 0, cacheHit: true)
        }
        let startEpoch = epoch
        func finish(_ hybrid: Bool, _ reason: String, _ queries: Int = 0) -> Decision {
            let decision = Decision(needsHybrid: hybrid, reason: reason, lexicalQueries: queries, cacheHit: false)
            if startEpoch == epoch { cache[key] = decision }
            return decision
        }
        if text.utf16.count > 8_192 { return finish(true,"longDocument") }
        let guardedPatterns = [
            ("quotationOrCode", #"[“”\"‘’«»`]|(?<![\p{L}\p{N}])'"#),
            ("definitionCue", #"(?i)\b(?:adalah|ialah|merupakan|berarti|didefinisikan|diartikan)\b|yang\s+dimaksud\s+dengan|selanjutnya\s+disebut"#),
            ("externalLegalSource", #"(?i)undang[ -]undang|peraturan\s+(?:pemerintah|presiden|menteri)|\bKUHP(?:erdata)?\b|\bUU\s*(?:No\b|Nomor\b|[0-9])"#),
            ("riskCue", #"(?i)tanggung\s+jawab|bertanggung\s+jawab|ganti\s+(?:rugi|kerugian)|tanpa\s+batas"#)
        ]
        for (reason, pattern) in guardedPatterns where text.range(of: pattern, options: .regularExpression) != nil {
            return finish(true,reason)
        }
        let context = AIConnectorDocumentProtectionContextBuilder().build(documentText:text)
        let blocks = structure.blocks.filter{$0.kind != .heading}
        var queries = 0
        for (index, block) in blocks.enumerated() {
            try Task.checkCancellation()
            let segment = AIReviewSegment(id:index,sourceLocation:block.sourceRange.location,sourceLength:block.sourceRange.length,targetText:block.text,previousContext:nil,nextContext:nil)
            let excluded = Set(engine.suggestions(for:segment).compactMap(\.original))
            if !provider.candidates(for:segment,protectionContext:context,excludedOriginals:excluded).isEmpty {
                return finish(true,"nativeSpellingCandidate",queries)
            }
            // Use existing lexical eligibility/detection; do not load E5 just to route.
            let lexical = await store.suggestionCandidateResultAsync(for:block.text,limit:3,allowSemantic:false)
            queries += lexical.queryCount
            try Task.checkCancellation()
            if !lexical.matches.isEmpty {
                return finish(true,"lexicalRetrievalEvidence",queries)
            }
        }
        let profile = AIConnectorDocumentContextProfileBuilder().build(documentText:text,structure:structure)
        let review = await AIConnectorDocumentReviewDetector().analyze(documentText:text,structure:structure,profile:profile,mode:.deterministic,modelVariant:.qwen35Base4B)
        try Task.checkCancellation()
        if review.findings.contains(where: \.requiresModelReview) { return finish(true,"nativeRiskCandidate",queries) }
        try Task.checkCancellation()
        return finish(false,"localBaseWithSelectiveContextualReview",queries)
    }
}
