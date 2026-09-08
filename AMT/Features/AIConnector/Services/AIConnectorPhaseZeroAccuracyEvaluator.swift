import Foundation

/// Computes provisional fixture accuracy from in-memory segment results. It
/// consumes raw spans only inside this evaluator and emits count-only DTOs.
struct AIConnectorPhaseZeroAccuracyEvaluator: Sendable {
    private struct FindingKey: Hashable {
        let status: AIReviewStatus
        let category: AIReviewCategory
        let original: String
        let replacement: String
    }

    private struct Counters {
        var fixtureCount = 0
        var expectedFindingCount = 0
        var actualFindingCount = 0
        var truePositive = 0
        var falsePositive = 0
        var falseNegative = 0
        var exactSpanCorrectCount = 0
        var exactSpanTotalCount = 0
        var noChangeCorrectCount = 0
        var noChangeTotalCount = 0
        var safetyViolationCount = 0
        var modelOriginResultCount = 0
        var fallbackOriginResultCount = 0

        mutating func add(
            fixture: AIConnectorPhaseZeroFixture,
            result: AIConnectorSegmentResult?
        ) {
            fixtureCount += 1
            let actualFindings = result?.reviews.filter {
                $0.status != .noSuggestion
            } ?? []
            let actualKeyedFindings = actualFindings.compactMap { review -> (key: FindingKey, origin: AIReviewOrigin)? in
                guard review.status != .noSuggestion,
                      let original = review.original,
                      let replacement = review.replacement,
                      !original.isEmpty,
                      !replacement.isEmpty else {
                    return nil
                }
                return (
                    key: FindingKey(
                        status: review.status,
                        category: review.category,
                        original: original,
                        replacement: replacement
                    ),
                    origin: review.origin
                )
            }
            if fixture.category != .definition {
                actualFindingCount += actualFindings.count
            }
            expectedFindingCount += expectedFindingCount(for: fixture.expected)

            var expectedKeys: [FindingKey] = []
            switch fixture.expected {
            case let .findings(expected):
                expectedKeys = expected.map {
                    FindingKey(
                        status: $0.status,
                        category: $0.category,
                        original: $0.original,
                        replacement: $0.replacement
                    )
                }
            case let .definition(expected):
                let actual = result?.definitionAssessment
                if actual != nil {
                    actualFindingCount += 1
                }
                let matches = actual?.classification == expected.classification
                    && actual?.alignment == expected.alignment
                if matches {
                    truePositive += 1
                    exactSpanCorrectCount += 1
                } else {
                    falseNegative += 1
                    if actual != nil {
                        falsePositive += 1
                    }
                }
                exactSpanTotalCount += 1
            case .noChange:
                if actualFindings.isEmpty {
                    noChangeCorrectCount += 1
                } else {
                    falsePositive += actualFindings.count
                }
                noChangeTotalCount += 1
            }

            if !expectedKeys.isEmpty {
                var unmatchedActual = actualKeyedFindings
                for expected in expectedKeys {
                    if let index = unmatchedActual.firstIndex(where: { $0.key == expected }) {
                        truePositive += 1
                        exactSpanCorrectCount += 1
                        unmatchedActual.remove(at: index)
                    } else {
                        falseNegative += 1
                    }
                }
                falsePositive += unmatchedActual.count
                falsePositive += actualFindings.count - actualKeyedFindings.count
                exactSpanTotalCount += expectedKeys.count
            }

            if let result,
               result.outputWasTruncated
                || result.reasoningMarkerDetected
                || result.sourceClaimDetected {
                safetyViolationCount += 1
            }
            modelOriginResultCount += actualFindings.filter {
                $0.origin == .qwen || $0.origin == .qwenRepaired
            }.count
            fallbackOriginResultCount += actualFindings.filter {
                $0.origin == .deterministicFallback
            }.count
        }

        private func expectedFindingCount(
            for expectation: AIConnectorPhaseZeroFixtureExpectation
        ) -> Int {
            switch expectation {
            case let .findings(findings):
                findings.count
            case .definition:
                1
            case .noChange:
                0
            }
        }
    }

    func summaries(
        fixtures: [AIConnectorPhaseZeroFixture],
        resultsByFixtureID: [String: AIConnectorSegmentResult]
    ) -> [AIConnectorAccuracySummary] {
        let reviewStatus = fixtures.allSatisfy {
            $0.reviewStatus == .approved
        } ? AIConnectorFixtureReviewStatus.approved : .pendingLawyerReview

        var all = Counters()
        var byCategory: [AIConnectorPhaseZeroFixtureCategory: Counters] = [:]
        for fixture in fixtures {
            let result = resultsByFixtureID[fixture.id]
            all.add(fixture: fixture, result: result)
            var categoryCounters = byCategory[fixture.category] ?? Counters()
            categoryCounters.add(fixture: fixture, result: result)
            byCategory[fixture.category] = categoryCounters
        }

        var summaries = [summary(
            scope: "all",
            counters: all,
            reviewStatus: reviewStatus
        )]
        for category in AIConnectorPhaseZeroFixtureCategory.allCases {
            guard let counters = byCategory[category] else { continue }
            summaries.append(
                summary(
                    scope: category.rawValue,
                    counters: counters,
                    reviewStatus: reviewStatus
                )
            )
        }
        return summaries
    }

    private func summary(
        scope: String,
        counters: Counters,
        reviewStatus: AIConnectorFixtureReviewStatus
    ) -> AIConnectorAccuracySummary {
        AIConnectorAccuracySummary(
            scope: scope,
            fixtureCount: counters.fixtureCount,
            expectedFindingCount: counters.expectedFindingCount,
            actualFindingCount: counters.actualFindingCount,
            truePositive: counters.truePositive,
            falsePositive: counters.falsePositive,
            falseNegative: counters.falseNegative,
            exactSpanCorrectCount: counters.exactSpanCorrectCount,
            exactSpanTotalCount: counters.exactSpanTotalCount,
            noChangeCorrectCount: counters.noChangeCorrectCount,
            noChangeTotalCount: counters.noChangeTotalCount,
            safetyViolationCount: counters.safetyViolationCount,
            modelOriginResultCount: counters.modelOriginResultCount,
            fallbackOriginResultCount: counters.fallbackOriginResultCount,
            reviewStatus: reviewStatus
        )
    }
}
