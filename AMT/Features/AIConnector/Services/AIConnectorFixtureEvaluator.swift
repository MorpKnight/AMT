import Foundation

/// Evaluates the bounded fixture set without relying on model confidence.
///
/// The evaluator is a Debug experiment aid. It compares observable output to
/// explicit expectations and treats any replacement outside the expectation as
/// a failed case.
struct AIConnectorFixtureEvaluator: Sendable {
    private let segmenter = LegalTextSegmenter()
    private let deterministicEngine = AIConnectorDeterministicSuggestionEngine()
    private let validator = AIConnectorSuggestionValidator()

    func evaluate(
        sample: AIConnectorSample,
        reviews: [AIValidatedReview]
    ) -> AIConnectorFixtureEvaluation {
        let expectation = sample.expectation
        let actual = reviews.first(where: { $0.status == .suggestion }) ?? reviews.first

        switch expectation {
        case let .suggestion(expectedOriginal, expectedReplacement, expectedCategory):
            let passed = actual?.status == .suggestion
                && actual?.category == expectedCategory
                && actual?.original == expectedOriginal
                && actual?.replacement == expectedReplacement

            return AIConnectorFixtureEvaluation(
                sample: sample,
                expectation: expectation,
                actualStatus: actual?.status,
                actualOriginal: actual?.original,
                actualReplacement: actual?.replacement,
                passed: passed,
                detail: passed
                    ? "Saran sesuai expected signal."
                    : "Saran tidak sama dengan expected signal."
            )

        case .preserveDefinedTerms:
            let hasSafeStatus = !reviews.isEmpty
                && reviews.allSatisfy { review in
                    switch review.status {
                    case .noSuggestion, .needsReview:
                        return true
                    case .suggestion:
                        guard let original = review.original,
                              let replacement = review.replacement else {
                            return false
                        }
                        return ["Borrower", "Lender"].allSatisfy { term in
                            original.contains(term) == replacement.contains(term)
                                && replacement.contains(term)
                        }
                    }
                }

            return AIConnectorFixtureEvaluation(
                sample: sample,
                expectation: expectation,
                actualStatus: actual?.status,
                actualOriginal: actual?.original,
                actualReplacement: actual?.replacement,
                passed: hasSafeStatus,
                detail: hasSafeStatus
                    ? "Defined terms Borrower/Lender tetap utuh."
                    : "Defined terms Borrower/Lender berubah atau hasil aman tidak terbentuk."
            )

        case .noReplacement:
            let hasUnexpectedReplacement = reviews.contains { $0.replacement != nil }
            let hasSafeStatus = !reviews.isEmpty
                && reviews.allSatisfy { review in
                    review.status == .noSuggestion || review.status == .needsReview
                }
            let passed = !hasUnexpectedReplacement && hasSafeStatus

            return AIConnectorFixtureEvaluation(
                sample: sample,
                expectation: expectation,
                actualStatus: actual?.status,
                actualOriginal: actual?.original,
                actualReplacement: actual?.replacement,
                passed: passed,
                detail: passed
                    ? "Tidak ada replacement yang melewati safety boundary."
                    : "Kasus safety menghasilkan replacement atau status yang tidak aman."
            )
        }
    }

    func runDeterministicBaseline(
        samples: [AIConnectorSample] = AIConnectorSample.samples,
        dictionaryStore: LegalDictionaryStore,
        modelVariant: AIConnectorModelVariant = .qwen35_2b
    ) -> AIConnectorBenchmarkSummary {
        let startedAt = Date()
        let evaluations = samples.map { sample in
            let segmentation = segmenter.segment(documentText: sample.text)
            guard let segment = segmentation.segments.first else {
                return evaluate(sample: sample, reviews: [])
            }

            let matches = dictionaryStore.suggestionCandidates(
                for: segment.targetText,
                limit: 1
            )
            let parsed = deterministicEngine.review(
                for: segment,
                glossaryMatches: matches
            )

            let review = try? validator.validate(
                parsed,
                for: segment,
                glossaryMatches: matches,
                origin: .deterministic
            )

            return evaluate(sample: sample, reviews: review.map { [$0] } ?? [])
        }

        return AIConnectorBenchmarkSummary(
            title: "Baseline deterministik",
            reviewMode: .deterministic,
            modelVariant: modelVariant,
            duration: Date().timeIntervalSince(startedAt),
            evaluations: evaluations
        )
    }
}
