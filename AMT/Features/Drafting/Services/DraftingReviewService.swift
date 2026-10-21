import CryptoKit
import Foundation

/// One document owns this service/cache. The generation closure uses the shared
/// application scheduler; local routes never prepare or load a model.
@MainActor
final class DraftingReviewService {
    typealias Generator = @MainActor @Sendable (DraftingReview.PreparedRequest, AIConnectorModelVariant) async throws -> QwenReviewResult

    private let generate: Generator
    private var cache = AIConnectorAnalysisLRUCache<DraftingReview.Result>(capacity: 256, maximumCost: 8 * 1_024 * 1_024)
    private var cacheEpoch = 0

    init(generator: @escaping Generator) { generate = generator }

    convenience init(service: QwenSuggestionService) {
        self.init { prepared, variant in
            try await service.reviewDrafting(prepared: prepared, modelVariant: variant)
        }
    }

    func clearCache() {
        cacheEpoch += 1
        cache.removeAll()
    }

    func review(_ input: DraftingReview.Request, modelVariant: AIConnectorModelVariant = .qwen35Base4B,
                fullFresh: Bool = true, allowsInference: Bool = true) async -> DraftingReview.Result {
        var route: DraftingReview.Route = .preflight
        var modelCalls = 0
        var formatRepairs = 0
        func result(_ status: DraftingReview.Status, failures: [String], response: DraftingReview.Response? = nil,
                    anchors: [DraftingReview.Anchor] = [], metrics: AIConnectorGenerationMetrics? = nil) -> DraftingReview.Result {
            .init(status: status, route: route, response: response, failures: failures, anchors: anchors,
                  documentRevision: input.documentRevision, modelCallCount: modelCalls, cacheHit: false, generationMetrics: metrics, formatRepairCount: formatRepairs)
        }
        do {
            try Task.checkCancellation()
            // Full input and policy bind cached validated results, so a cache hit
            // avoids rebuilding document protection and dependency closure.
            let key = try cacheKey(input, modelVariant: modelVariant, allowsInference: allowsInference)
            if !fullFresh, let prior = cache[key] {
                try Task.checkCancellation()
                return .init(status: prior.status, route: prior.route, response: prior.response, failures: prior.failures,
                             anchors: prior.anchors, documentRevision: prior.documentRevision, modelCallCount: 0,
                             cacheHit: true, generationMetrics: nil)
            }
            let preflight = DraftingReviewPreparation.validateAndPrepare(input)
            guard preflight.failures.isEmpty, var prepared = preflight.prepared else {
                return result(.incomplete, failures: preflight.failures)
            }
            if let literal = DraftingLiteralRouter.requestWithLiteralPermission(prepared) {
                prepared = .init(request: literal, definitions: prepared.definitions, references: prepared.references,
                                 protectionContext: prepared.protectionContext)
            }
            let epoch = cacheEpoch
            let validation: DraftingReviewValidator.Validation
            var metrics: AIConnectorGenerationMetrics?
            if let response = DraftingLiteralRouter.response(prepared) {
                route = .literal
                validation = DraftingReviewValidator.validate(response, prepared: prepared)
            } else {
                guard allowsInference else { return result(.incomplete, failures: ["modelReviewRequired"]) }
                route = .model
                modelCalls = 1
                let generated = try await generate(prepared, modelVariant)
                try Task.checkCancellation()
                metrics = generated.metrics
                if generated.metrics.stopReason == .cancelled { throw CancellationError() }
                guard generated.metrics.stopReason == .stop, !generated.containsReasoningMarkers else {
                    return result(.incomplete, failures: ["incompleteGeneration"], metrics: metrics)
                }
                if let repaired = DraftingReviewJSON.repaired(generated.output) {
                    formatRepairs = 1
                    validation = DraftingReviewValidator.parse(repaired, prepared: prepared)
                } else {
                    validation = DraftingReviewValidator.parse(generated.output, prepared: prepared)
                }
            }
            try Task.checkCancellation()
            guard validation.failures.isEmpty, let response = validation.response else {
                return result(.incomplete, failures: validation.failures, metrics: metrics)
            }
            let completed = result(.complete, failures: [], response: response, anchors: validation.anchors, metrics: metrics)
            // Pressure/reset while inference awaits must not repopulate an evicted cache.
            if cacheEpoch == epoch { cache[key] = completed }
            return completed
        } catch is CancellationError {
            return result(.cancelled, failures: ["cancelled"])
        } catch is AIConnectorInputBudgetError {
            return result(.incomplete, failures: ["requiredEvidenceTooLong"])
        } catch {
            return result(.incomplete, failures: ["generationFailed"])
        }
    }

    private func cacheKey(_ request: DraftingReview.Request, modelVariant: AIConnectorModelVariant, allowsInference: Bool) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var material = try encoder.encode(request)
        material.append(Data((DraftingReview.policyVersion + "|" + DraftingReviewPrompt.instructions + "|"
                              + modelVariant.modelID + "|" + modelVariant.revision + "|greedy-768-seed42|"
                              + String(allowsInference)).utf8))
        return SHA256.hash(data: material).map { String(format: "%02x", $0) }.joined()
    }
}
