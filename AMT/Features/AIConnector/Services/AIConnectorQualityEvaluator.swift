#if DEBUG
import CryptoKit
import Foundation

nonisolated struct AIConnectorQualityEvaluator: Sendable {
    func evaluate(
        fixtures: [AIConnectorQualityFixture],
        reviews: [AIConnectorLawyerReviewRecord],
        policy: AIConnectorQualityPolicy,
        candidateManifest: AIConnectorQualityCandidateManifest,
        outputsByMode: [AIConnectorReviewMode: [String: AIConnectorQualityObservedOutput]],
        terminalStatus: AIConnectorQualityRunStatus = .completed,
        runID: UUID = UUID(),
        generatedAt: Date = Date()
    ) -> AIConnectorQualityEvaluationReport {
        let reviewByID = Dictionary(uniqueKeysWithValues: reviews.map { ($0.fixtureID, $0) })
        let approvedFixtures = fixtures.filter { fixture in
            guard let review = reviewByID[fixture.id] else { return false }
            return review.isApproved
                && review.fixtureRevision == fixture.revision
                && review.fixtureDigest == fixture.fixtureDigest
        }
        let approvedCoverage = fixtures.isEmpty
            ? 0
            : Double(approvedFixtures.count) / Double(fixtures.count)

        let modeReports = AIConnectorReviewMode.allCases.map { mode in
            evaluateMode(
                mode: mode,
                fixtures: fixtures,
                approvedFixtures: approvedFixtures,
                policy: policy,
                outputs: outputsByMode[mode] ?? [:],
                terminalStatus: terminalStatus
            )
        }

        var reasons: [String] = []
        let candidateMatchesPolicy = candidateManifest.policyID == policy.policyID
            && candidateManifest.policyRevision == policy.revision
        let candidateMatchesFixtures = candidateManifest.fixtureCatalogVersion == AIConnectorQualityFixtureCatalog.version
            && candidateManifest.fixtureManifestDigest
                == AIConnectorQualityReviewPackageService.fixtureManifestDigest(fixtures)
        if !candidateMatchesPolicy || !candidateMatchesFixtures {
            reasons.append("candidate-manifest-mismatch")
        }
        if candidateManifest.worktreeDirty {
            reasons.append("candidate-worktree-dirty")
        }
        if !policy.approved { reasons.append("policy-not-approved") }
        if !policy.isCalibrated { reasons.append("thresholds-not-calibrated") }
        if approvedFixtures.isEmpty { reasons.append("no-approved-fixtures") }
        if approvedCoverage < policy.requiredCoverageFraction {
            reasons.append("approved-coverage-below-policy")
        }

        for category in policy.requiredCategories {
            let count = approvedFixtures.filter { $0.category == category }.count
            let minimum = policy.minimumSamplesByCategory[category.rawValue] ?? 1
            if count < minimum {
                reasons.append("insufficient-samples-\(category.rawValue)")
            }
        }
        for split in policy.requiredFixtureSplits where !approvedFixtures.contains(where: { $0.split == split }) {
            reasons.append("missing-approved-split-\(split.rawValue)")
        }

        let releaseModeReport = modeReports.first { $0.mode == policy.releaseMode }
        if let releaseModeReport {
            if releaseModeReport.status == .fail { reasons.append("release-mode-threshold-failed") }
            if releaseModeReport.status == .insufficientEvidence { reasons.append("release-mode-insufficient-evidence") }
        } else {
            reasons.append("release-mode-not-run")
        }

        let allSafetyViolations = modeReports.reduce(0) { $0 + $1.safetyViolationCount }
        if allSafetyViolations > 0 { reasons.append("safety-violation") }

        let overallStatus: AIConnectorQualityGateStatus
        if allSafetyViolations > 0 || modeReports.contains(where: { $0.status == .fail }) {
            overallStatus = .fail
        } else if terminalStatus != .completed || !reasons.isEmpty {
            overallStatus = .insufficientEvidence
        } else {
            overallStatus = .pass
        }

        return AIConnectorQualityEvaluationReport(
            schemaVersion: AIConnectorQualityEvaluationReport.schemaVersion,
            generatedAt: generatedAt,
            runID: runID,
            terminalStatus: terminalStatus,
            overallStatus: overallStatus,
            statusReasons: Array(Set(reasons)).sorted(),
            candidateManifestDigest: digest(candidateManifest),
            policyID: policy.policyID,
            policyRevision: policy.revision,
            fixtureCatalogVersion: AIConnectorQualityFixtureCatalog.version,
            fixtureCount: fixtures.count,
            approvedFixtureCount: approvedFixtures.count,
            approvedCoverageFraction: approvedCoverage,
            pipelineVersion: candidateManifest.pipelineVersion,
            rulePackVersion: candidateManifest.rulePackVersion,
            corpusVersion: candidateManifest.corpusVersion,
            modes: modeReports,
            hardware: policy.hardwareProfile
        )
    }

    private func evaluateMode(
        mode: AIConnectorReviewMode,
        fixtures: [AIConnectorQualityFixture],
        approvedFixtures: [AIConnectorQualityFixture],
        policy: AIConnectorQualityPolicy,
        outputs: [String: AIConnectorQualityObservedOutput],
        terminalStatus: AIConnectorQualityRunStatus
    ) -> AIConnectorQualityModeReport {
        let summaries = AIConnectorQualityCategory.allCases.map { category in
            evaluateCategory(
                category: category,
                fixtures: approvedFixtures.filter { $0.category == category },
                outputs: outputs,
                threshold: policy.thresholdsByCategory[category.rawValue]
            )
        }
        let consideredOutputs = approvedFixtures.compactMap { outputs[$0.id] }
        let completedCount = consideredOutputs.filter { $0.complete }.count
        let coverage = approvedFixtures.isEmpty
            ? nil
            : Double(completedCount) / Double(approvedFixtures.count)
        let safety = consideredOutputs.reduce(0) { $0 + $1.safety.violationCount }
        let stageValues = Dictionary(grouping: consideredOutputs.flatMap { output in
            output.stageDurations.map { (stage: $0.key, duration: max($0.value, 0)) }
        }, by: \.stage)
        let stages = stageValues.keys.sorted().map { stage in
            let durations = stageValues[stage, default: []].map(\.duration).sorted()
            return AIConnectorQualityStageSummary(
                stage: stage,
                invocationCount: durations.count,
                medianDuration: percentile(durations, 0.5),
                p95Duration: percentile(durations, 0.95)
            )
        }
        let firstLatencies = consideredOutputs.compactMap(\.firstResultLatency).sorted()
        let totalLatencies = consideredOutputs.map { max($0.totalDuration, 0) }.sorted()
        let thresholdFailed = summaries.contains { !$0.thresholdViolations.isEmpty }
        let hasRequiredSamples = policy.requiredCategories.allSatisfy { category in
                let minimum = policy.minimumSamplesByCategory[category.rawValue] ?? 1
                return approvedFixtures.filter { $0.category == category }.count >= minimum
        }
        let status: AIConnectorQualityGateStatus
        if safety > 0 || thresholdFailed {
            status = .fail
        } else if terminalStatus != .completed || approvedFixtures.isEmpty || completedCount < approvedFixtures.count || !hasRequiredSamples {
            status = .insufficientEvidence
        } else {
            status = .pass
        }

        return AIConnectorQualityModeReport(
            mode: mode,
            status: status,
            sampleCount: approvedFixtures.count,
            completedSampleCount: completedCount,
            coverageFraction: coverage,
            safetyViolationCount: safety,
            categories: summaries,
            stages: stages,
            firstResultLatencyP50: percentile(firstLatencies, 0.5),
            totalDurationP50: percentile(totalLatencies, 0.5),
            totalDurationP95: percentile(totalLatencies, 0.95),
            reusedSegmentCount: consideredOutputs.reduce(0) { $0 + max($1.reusedSegmentCount, 0) },
            recomputedSegmentCount: consideredOutputs.reduce(0) { $0 + max($1.recomputedSegmentCount, 0) },
            modelCallCount: consideredOutputs.reduce(0) { $0 + max($1.modelCallCount, 0) },
            resourcePreparationDuration: consideredOutputs.reduce(0) { $0 + max($1.resourcePreparationDuration, 0) },
            incrementalEquivalentCount: consideredOutputs.filter { $0.incrementalEquivalentToFresh == true }.count,
            incrementalComparisonCount: consideredOutputs.filter { $0.incrementalEquivalentToFresh != nil }.count
        )
    }

    private func evaluateCategory(
        category: AIConnectorQualityCategory,
        fixtures: [AIConnectorQualityFixture],
        outputs: [String: AIConnectorQualityObservedOutput],
        threshold: AIConnectorQualityThreshold?
    ) -> AIConnectorQualityCategorySummary {
        var expectedCount = 0
        var observedCount = 0
        var truePositive = 0
        var falsePositive = 0
        var falseNegative = 0
        var exactSpanCorrect = 0
        var exactSpanTotal = 0
        var noChangeCorrect = 0
        var noChangeTotal = 0
        var hardNegativeFalsePositives = 0
        var hardNegativeTotal = 0
        var groundingCorrect = 0
        var groundingTotal = 0
        var safety = 0
        var thresholdViolations: [String] = []

        for fixture in fixtures {
            guard let output = outputs[fixture.id] else { continue }
            let expected = fixture.expected.findings
            var unmatchedExpected = expected
            expectedCount += expected.count
            observedCount += output.findings.count
            safety += output.safety.violationCount

            if fixture.expected.noChange {
                noChangeTotal += 1
                if output.findings.isEmpty { noChangeCorrect += 1 }
                if category == .hardNegative {
                    hardNegativeTotal += 1
                    if !output.findings.isEmpty { hardNegativeFalsePositives += 1 }
                }
            }

            for observed in output.findings {
                guard let expectedIndex = unmatchedExpected.firstIndex(where: {
                    finding in matches(finding, observed: observed)
                }) else {
                    falsePositive += 1
                    continue
                }
                let expectedFinding = unmatchedExpected.remove(at: expectedIndex)
               truePositive += 1
                exactSpanTotal += 1
                if expectedFinding.occurrence == observed.occurrence,
                   expectedFinding.original == observed.original,
                   expectedFinding.replacement == observed.replacement {
                    exactSpanCorrect += 1
                }
                if let expectedSourceID = expectedFinding.sourceID {
                    groundingTotal += 1
                    let expectedSource = fixture.sources.first {
                        $0.id == expectedSourceID || $0.corpusEntryID == expectedSourceID
                    }
                    let applicability = expectedSource?.applicabilityStatus.lowercased() ?? "unknown"
                    let applicabilitySupportsUse = !["unknown", "not_in_force", "not-in-force", "repealed"].contains(applicability)
                    let evidenceMatches = expectedSource?.evidenceID == nil
                        || expectedSource?.evidenceID == observed.sourceEvidenceID
                    if observed.sourceID == expectedSourceID,
                       expectedSource?.verified == true,
                       expectedSource?.isActionable == true,
                       applicabilitySupportsUse,
                       evidenceMatches,
                       observed.sourceVerified,
                       observed.sourceActionable,
                       observed.anchorValid {
                        groundingCorrect += 1
                    }
                }
            }
            falseNegative += unmatchedExpected.count
        }

        let precision = ratio(truePositive, truePositive + falsePositive)
        let recall = ratio(truePositive, truePositive + falseNegative)
        let f1 = f1(precision, recall)
        let exactAccuracy = ratio(exactSpanCorrect, exactSpanTotal)
        let noChangeAccuracy = ratio(noChangeCorrect, noChangeTotal)
        let hardNegativeRate = ratio(hardNegativeFalsePositives, hardNegativeTotal)
        let groundingRate = ratio(groundingCorrect, groundingTotal)
        if let threshold {
            if let value = threshold.minimumPrecision, let precision, precision < value { thresholdViolations.append("precision") }
            if let value = threshold.minimumRecall, let recall, recall < value { thresholdViolations.append("recall") }
            if let value = threshold.minimumF1, let f1, f1 < value { thresholdViolations.append("f1") }
            if let value = threshold.maximumHardNegativeFalsePositiveRate, let hardNegativeRate, hardNegativeRate > value { thresholdViolations.append("hard-negative-fpr") }
            if let value = threshold.minimumGroundingRate, let groundingRate, groundingRate < value { thresholdViolations.append("grounding") }
            if let value = threshold.minimumExactSpanAccuracy, let exactAccuracy, exactAccuracy < value { thresholdViolations.append("exact-span") }
        }

        return AIConnectorQualityCategorySummary(
            category: category,
            sampleCount: fixtures.count,
            completedSampleCount: fixtures.filter { outputs[$0.id] != nil }.count,
            expectedFindingCount: expectedCount,
            observedFindingCount: observedCount,
            truePositive: truePositive,
            falsePositive: falsePositive,
            falseNegative: falseNegative,
            precision: precision,
            recall: recall,
            f1: f1,
            exactSpanAccuracy: exactAccuracy,
            noChangeAccuracy: noChangeAccuracy,
            hardNegativeFalsePositiveRate: hardNegativeRate,
            groundingRate: groundingRate,
            safetyViolationCount: safety,
            thresholdViolations: thresholdViolations.sorted()
        )
    }

    private func matches(
        _ expected: AIConnectorQualityExpectedFinding,
        observed: AIConnectorQualityObservedFinding
    ) -> Bool {
        return expected.occurrence == observed.occurrence
            && expected.category == observed.category
            && expected.status == observed.status
            && expected.original == observed.original
            && expected.replacement == observed.replacement
            && (expected.classification == nil || expected.classification == observed.classification)
            && expected.readOnly == observed.readOnly
    }

    private func percentile(_ values: [TimeInterval], _ fraction: Double) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let index = min(values.count - 1, max(0, Int(ceil(fraction * Double(values.count))) - 1))
        return values[index]
    }

    private func ratio(_ numerator: Int, _ denominator: Int) -> Double? {
        denominator > 0 ? Double(numerator) / Double(denominator) : nil
    }

    private func f1(_ precision: Double?, _ recall: Double?) -> Double? {
        guard let precision, let recall, precision + recall > 0 else { return nil }
        return 2 * precision * recall / (precision + recall)
    }

    private func digest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data()
        return data.sha256Hex
    }
}

@MainActor
final class AIConnectorQualityRunner {
    typealias ExecutionHandler = @MainActor (
        AIConnectorReviewMode,
        AIConnectorQualityFixture
    ) async throws -> AIConnectorQualityObservedOutput

    private let evaluator: AIConnectorQualityEvaluator

    init(evaluator: AIConnectorQualityEvaluator = AIConnectorQualityEvaluator()) {
        self.evaluator = evaluator
    }

    func run(
        fixtures: [AIConnectorQualityFixture],
        reviews: [AIConnectorLawyerReviewRecord],
        policy: AIConnectorQualityPolicy,
        candidateManifest: AIConnectorQualityCandidateManifest,
        execution: @escaping ExecutionHandler,
        onProgress: @escaping @MainActor (AIConnectorReviewMode, Int, Int) -> Void = { _, _, _ in }
    ) async -> AIConnectorQualityEvaluationReport {
        var outputs: [AIConnectorReviewMode: [String: AIConnectorQualityObservedOutput]] = [:]
        var terminalStatus: AIConnectorQualityRunStatus = .completed
        for mode in AIConnectorReviewMode.allCases {
            var modeOutputs: [String: AIConnectorQualityObservedOutput] = [:]
            for (index, fixture) in fixtures.enumerated() {
                if Task.isCancelled {
                    terminalStatus = .partial
                    break
                }
                do {
                    modeOutputs[fixture.id] = try await execution(mode, fixture)
                } catch is CancellationError {
                    terminalStatus = .partial
                    break
                } catch {
                    terminalStatus = .partial
                    break
                }
                onProgress(mode, index + 1, fixtures.count)
            }
            outputs[mode] = modeOutputs
            if terminalStatus == .partial { break }
        }
        return evaluator.evaluate(
            fixtures: fixtures,
            reviews: reviews,
            policy: policy,
            candidateManifest: candidateManifest,
            outputsByMode: outputs,
            terminalStatus: terminalStatus
        )
    }
}

private extension Data {
    nonisolated var sha256Hex: String {
        CryptoKit.SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
