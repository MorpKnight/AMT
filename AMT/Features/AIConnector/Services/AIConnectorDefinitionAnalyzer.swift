import Foundation

typealias AIConnectorDefinitionReviewHandler = @MainActor @Sendable (
    AIConnectorDefinitionReviewRequest,
    @escaping @Sendable (Double) -> Void,
    @escaping @MainActor @Sendable (Int) -> Void
) async throws -> QwenDefinitionReviewResult

/// Coordinates local definition-shape detection, guarded RAG candidates, and
/// an optional Qwen semantic judgment. It never returns a replacement text.
@MainActor
struct AIConnectorDefinitionAnalyzer: Sendable {
    private let dictionaryStore: LegalDictionaryStore
    private let detector: AIConnectorDefinitionDetector
    private let reviewHandler: AIConnectorDefinitionReviewHandler?

    init(
        dictionaryStore: LegalDictionaryStore,
        reviewHandler: AIConnectorDefinitionReviewHandler? = nil
    ) {
        self.dictionaryStore = dictionaryStore
        self.detector = AIConnectorDefinitionDetector(dictionaryStore: dictionaryStore)
        self.reviewHandler = reviewHandler
    }

    func analyze(
        segment: AIReviewSegment,
        glossaryMatches: [LegalDictionaryMatch],
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        thinkingEnabled: Bool,
        forceDeterministic: Bool,
        generationProfile: AIConnectorGenerationProfile,
        downloadProgress: @escaping @Sendable (Double) -> Void,
        generationProgress: @escaping @MainActor @Sendable (Int) -> Void,
        semanticProgress: @escaping @Sendable (Double) -> Void,
        progressStage: @escaping @MainActor @Sendable (AIConnectorProgressStage) -> Void
    ) async throws -> AIConnectorDefinitionAnalysisResult {
        guard !segment.isTooLong else {
            return AIConnectorDefinitionAnalysisResult()
        }

        var detection = detector.detect(
            segment: segment,
            glossaryMatches: glossaryMatches
        )
        if detection.candidates.isEmpty,
           mode.usesModel,
           !forceDeterministic,
           looksDefinitionLike(segment.targetText) {
            let retrievedMatches = try await retrieveDefinitionCandidates(
                for: segment.targetText,
                semanticProgress: semanticProgress
            )
            progressStage(.semanticRetrieval)
            if !retrievedMatches.isEmpty {
                detection = detector.detect(
                    segment: segment,
                    glossaryMatches: glossaryMatches + retrievedMatches
                )
            }
        }
        guard let detectionKind = detection.detection else {
            return AIConnectorDefinitionAnalysisResult()
        }

        guard !detection.candidates.isEmpty else {
            guard detectionKind == .explicitPattern else {
                return AIConnectorDefinitionAnalysisResult()
            }

            return AIConnectorDefinitionAnalysisResult(
                assessment: assessmentWithoutEvidence(
                    segment: segment,
                    detection: detection,
                    classification: .needsReview,
                    alignment: .needsReview,
                    reason: "Pola definisi ditemukan, tetapi tidak ada pengertian terverifikasi yang cocok di corpus.",
                    origin: forceDeterministic ? .deterministicFallback : .deterministic
                )
            )
        }

        guard mode.usesModel, !forceDeterministic else {
            return deterministicAnalysis(
                segment: segment,
                detection: detection,
                origin: forceDeterministic ? .deterministicFallback : .deterministic
            )
        }

        guard let reviewHandler else {
            return deterministicAnalysis(
                segment: segment,
                detection: detection,
                origin: .deterministicFallback
            )
        }

        progressStage(.definitionReview)
        var outcomes: [ModelOutcome] = []
        var modelCallCount = 0
        var lastFailure: Error?

        for candidate in detection.candidates {
            try Task.checkCancellation()
            modelCallCount += 1

            do {
                let result = try await reviewHandler(
                    AIConnectorDefinitionReviewRequest(
                        segment: segment,
                        candidate: candidate,
                        thinkingEnabled: thinkingEnabled,
                        modelVariant: modelVariant,
                        generationProfile: generationProfile,
                        retryInstruction: nil
                    ),
                    downloadProgress,
                    generationProgress
                )
                guard result.candidateID == candidate.id,
                      !result.containsReasoningMarkers else {
                    lastFailure = AIConnectorDefinitionReviewParserError.invalidDecision
                    break
                }
                outcomes.append(
                    ModelOutcome(candidate: candidate, result: result)
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastFailure = error
                break
            }
        }

        guard !outcomes.isEmpty else {
            let detail = lastFailure?.localizedDescription ?? "Model tidak menghasilkan keputusan."
            return AIConnectorDefinitionAnalysisResult(
                assessment: makeAssessment(
                    segment: segment,
                    detection: detection,
                    candidate: detection.candidates[0],
                    classification: .needsReview,
                    alignment: .needsReview,
                    reason: "Pemeriksaan model gagal (\(detail)); hasil harus diverifikasi manusia.",
                    origin: .deterministicFallback,
                    modelReviewed: false
                ),
                modelCallCount: modelCallCount
            )
        }

        return AIConnectorDefinitionAnalysisResult(
            assessment: aggregateModelOutcomes(
                segment: segment,
                detection: detection,
                outcomes: outcomes,
                hadFailure: lastFailure != nil
            ),
            modelCallCount: modelCallCount
        )
    }

    private func deterministicAnalysis(
        segment: AIReviewSegment,
        detection: AIConnectorDefinitionDetectionResult,
        origin: AIReviewOrigin
    ) -> AIConnectorDefinitionAnalysisResult {
        var outcomes: [(AIConnectorDefinitionCandidate, AIConnectorDefinitionAlignment)] = []

        for candidate in detection.candidates {
            outcomes.append(
                (
                    candidate,
                    lexicalAlignment(
                        statement: candidate.statementText,
                        sourceDefinition: candidate.sourceDefinition,
                        term: candidate.term
                    )
                )
            )
        }

        guard let first = outcomes.first else {
            return AIConnectorDefinitionAnalysisResult(
                assessment: assessmentWithoutEvidence(
                    segment: segment,
                    detection: detection,
                    classification: .needsReview,
                    alignment: .needsReview,
                    reason: "Pengertian terverifikasi belum tersedia untuk dibandingkan.",
                    origin: origin
                )
            )
        }

        let hasUncertainOutcome = outcomes.contains { $0.1 == .needsReview }
        let allMatch = outcomes.allSatisfy { $0.1 == .matches }
        let alignment: AIConnectorDefinitionAlignment
        let classification: AIConnectorDefinitionClassification
        let reason: String

        if allMatch {
            alignment = .matches
            classification = first.0.detection == .explicitPattern
                ? .explicitDefinition
                : .implicitDefinition
            reason = "Uraian memiliki kesesuaian leksikal kuat dengan pengertian corpus; kesimpulan hukum tetap memerlukan review manusia."
        } else if hasUncertainOutcome {
            alignment = .needsReview
            classification = .needsReview
            reason = "Kandidat pengertian ditemukan, tetapi kesetaraan makna tidak dapat dipastikan hanya dari pemeriksaan lokal."
        } else {
            alignment = .needsReview
            classification = .needsReview
            reason = "Kandidat pengertian ditemukan, tetapi hasil pembanding lokal belum cukup untuk menyatakan kesesuaian hukum."
        }

        return AIConnectorDefinitionAnalysisResult(
            assessment: makeAssessment(
                segment: segment,
                detection: detection,
                candidate: first.0,
                classification: classification,
                alignment: alignment,
                reason: reason,
                origin: origin,
                modelReviewed: false
            )
        )
    }

    private func aggregateModelOutcomes(
        segment: AIReviewSegment,
        detection: AIConnectorDefinitionDetectionResult,
        outcomes: [ModelOutcome],
        hadFailure: Bool
    ) -> AIConnectorDefinitionAssessment {
        let matching = outcomes.filter {
            $0.result.alignment == .matches
                && $0.result.classification != .notDefinition
        }
        let mismatching = outcomes.filter {
            $0.result.alignment == .mismatch
        }
        let needsReview = outcomes.filter {
            $0.result.alignment == .needsReview
                || $0.result.classification == .needsReview
        }

        let selected = matching.first ?? mismatching.first ?? needsReview.first ?? outcomes[0]
        let classification: AIConnectorDefinitionClassification
        let alignment: AIConnectorDefinitionAlignment
        let reason: String

        if hadFailure {
            classification = .needsReview
            alignment = .needsReview
            reason = "Sebagian kandidat pengertian gagal diperiksa oleh model; pilih evidence dan verifikasi manusia."
        } else if !matching.isEmpty, !mismatching.isEmpty {
            classification = .needsReview
            alignment = .needsReview
            reason = "Model menemukan hasil yang berbeda pada beberapa definisi corpus; pilih evidence dan verifikasi manusia."
        } else if let match = matching.first {
            classification = match.result.classification == .explicitDefinition
                ? .explicitDefinition
                : .implicitDefinition
            alignment = .matches
            reason = hadFailure
                ? "Model menilai uraian selaras, tetapi sebagian kandidat gagal diperiksa; hasil tetap memerlukan review manusia."
                : "Model menilai kalimat sebagai definisi yang maknanya selaras dengan pengertian corpus terverifikasi; hasil tetap memerlukan review manusia."
        } else if let mismatch = mismatching.first {
            classification = mismatch.result.classification == .explicitDefinition
                ? .explicitDefinition
                : .implicitDefinition
            alignment = .mismatch
            reason = "Model menilai kalimat sebagai definisi, tetapi maknanya tidak selaras dengan pengertian corpus terverifikasi."
        } else if outcomes.allSatisfy({
            $0.result.classification == .notDefinition
                && $0.result.alignment == .notApplicable
        }) {
            classification = .notDefinition
            alignment = .notApplicable
            reason = "Kandidat legal term ditemukan, tetapi model menilai kalimat ini bukan pengertian atau definisi."
        } else {
            classification = .needsReview
            alignment = .needsReview
            reason = "Model belum dapat memastikan apakah kalimat merupakan definisi dan apakah maknanya setara."
        }

        return makeAssessment(
            segment: segment,
            detection: detection,
            candidate: selected.candidate,
            classification: classification,
            alignment: alignment,
            reason: reason,
            origin: .qwen,
            modelReviewed: true
        )
    }

    private func assessmentWithoutEvidence(
        segment: AIReviewSegment,
        detection: AIConnectorDefinitionDetectionResult,
        classification: AIConnectorDefinitionClassification,
        alignment: AIConnectorDefinitionAlignment,
        reason: String,
        origin: AIReviewOrigin
    ) -> AIConnectorDefinitionAssessment {
        AIConnectorDefinitionAssessment(
            segment: segment,
            term: detection.term,
            statementText: detection.statementText,
            candidate: nil,
            candidateCount: 0,
            detection: detection.detection,
            classification: classification,
            alignment: alignment,
            reason: reason,
            origin: origin,
            modelReviewed: false,
            retrievalOrigin: nil,
            semanticScore: nil,
            requiresHumanReview: true
        )
    }

    private func makeAssessment(
        segment: AIReviewSegment,
        detection: AIConnectorDefinitionDetectionResult,
        candidate: AIConnectorDefinitionCandidate,
        classification: AIConnectorDefinitionClassification,
        alignment: AIConnectorDefinitionAlignment,
        reason: String,
        origin: AIReviewOrigin,
        modelReviewed: Bool
    ) -> AIConnectorDefinitionAssessment {
        AIConnectorDefinitionAssessment(
            segment: segment,
            term: detection.term ?? candidate.term,
            statementText: candidate.statementText,
            candidate: candidate,
            candidateCount: detection.candidates.count,
            detection: detection.detection,
            classification: classification,
            alignment: alignment,
            reason: reason,
            origin: origin,
            modelReviewed: modelReviewed,
            retrievalOrigin: candidate.match.retrievalOrigin,
            semanticScore: candidate.match.semanticScore,
            requiresHumanReview: true
        )
    }

    private func lexicalAlignment(
        statement: String,
        sourceDefinition: String,
        term: String
    ) -> AIConnectorDefinitionAlignment {
        let statementTokens = contentTokens(statement, removingTerm: term)
        let sourceTokens = contentTokens(sourceDefinition, removingTerm: term)
        guard !statementTokens.isEmpty, !sourceTokens.isEmpty else {
            return .needsReview
        }

        if statementTokens == sourceTokens {
            return .matches
        }

        let shared = Set(statementTokens).intersection(sourceTokens).count
        let sourceCoverage = Double(shared) / Double(Set(sourceTokens).count)
        let statementCoverage = Double(shared) / Double(Set(statementTokens).count)
        return sourceCoverage >= 0.80 && statementCoverage >= 0.45
            ? .matches
            : .needsReview
    }

    private func retrieveDefinitionCandidates(
        for text: String,
        semanticProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [LegalDictionaryMatch] {
        let request = LegalRetrievalRequest(
            query: text,
            intent: .reverseLookup,
            limit: AIConnectorDefinitionDetector.maximumCandidates * 2
        )
        let matches: [LegalRetrievalMatch]
        do {
            matches = try await dictionaryStore.retrieve(
                request,
                semanticProgress: semanticProgress
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return []
        }

        let semanticThreshold = dictionaryStore.semanticRetrievalConfiguration?
            .suggestionSemanticThreshold
            ?? LegalDictionaryStore.dictionarySemanticThreshold
        return matches.compactMap { match in
            guard let entry = dictionaryStore.entries.first(where: {
                $0.id == match.concept.recordID
            }), AIConnectorDefinitionDetector.isUsableEvidence(entry) else {
                return nil
            }
            if let semanticScore = match.semanticScore,
               (!semanticScore.isFinite || semanticScore < semanticThreshold) {
                return nil
            }

            let score = match.fusionScore
                ?? Double(match.semanticScore ?? Float(match.lexicalScore ?? 0))
            return LegalDictionaryMatch(
                entry: entry,
                score: score,
                rank: match.rank,
                matchedDefinitionTokenCount: sharedTokenCount(
                    text,
                    entry.definition
                ),
                isDirectTermMatch: containsTerm(
                    entry.term,
                    in: text
                ),
                semanticScore: match.semanticScore,
                fusionScore: match.fusionScore,
                retrievalOrigin: match.origin
            )
        }
    }

    private func looksDefinitionLike(_ text: String) -> Bool {
        let tokens = Self.tokenize(text)
        guard tokens.count >= 4 else { return false }
        if tokens.contains("yang") {
            return true
        }
        return Self.definitionLeadTokens.contains(tokens[0])
    }

    private func containsTerm(_ term: String, in text: String) -> Bool {
        let termTokens = Self.tokenize(term)
        let textTokens = Self.tokenize(text)
        guard !termTokens.isEmpty, textTokens.count >= termTokens.count else {
            return false
        }
        return (0 ... (textTokens.count - termTokens.count)).contains { start in
            Array(textTokens[start ..< start + termTokens.count]) == termTokens
        }
    }

    private func sharedTokenCount(_ lhs: String, _ rhs: String) -> Int {
        Set(Self.tokenize(lhs)).intersection(Self.tokenize(rhs)).count
    }

    private func contentTokens(
        _ text: String,
        removingTerm term: String
    ) -> [String] {
        var tokens = Self.tokenize(text)
        let termTokens = Self.tokenize(term)
        if tokens.starts(with: termTokens) {
            tokens.removeFirst(termTokens.count)
            if let first = tokens.first, Self.definitionCues.contains(first) {
                tokens.removeFirst()
                if first == "didefinisikan" || first == "diartikan",
                   tokens.first == "sebagai" {
                    tokens.removeFirst()
                }
            }
        }
        return tokens.filter { !Self.stopWords.contains($0) }
    }

    private static func tokenize(_ value: String) -> [String] {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private static let definitionCues: Set<String> = [
        "adalah", "ialah", "merupakan", "berarti", "didefinisikan", "diartikan"
    ]

    private static let stopWords: Set<String> = [
        "adalah", "ialah", "merupakan", "berarti", "didefinisikan", "diartikan",
        "sebagai", "yang", "dan", "atau", "serta", "dalam", "dengan", "untuk",
        "dari", "pada", "oleh", "terhadap", "suatu", "sebuah", "dapat", "telah",
        "akan", "tidak", "secara", "baik", "lebih", "lain", "lainnya", "ini", "itu"
    ]

    private static let definitionLeadTokens: Set<String> = [
        "orang", "individu", "badan", "data", "informasi", "rangkaian", "kegiatan",
        "proses", "keadaan", "hubungan", "sistem", "pihak", "perjanjian", "tindakan",
        "kondisi", "barang", "jasa", "hak", "kewajiban", "dokumen", "penyelenggara",
        "setiap", "segala", "sesuatu"
    ]

    private struct ModelOutcome: Sendable {
        let candidate: AIConnectorDefinitionCandidate
        let result: QwenDefinitionReviewResult
    }
}
