import Foundation

typealias AIConnectorDocumentContextClassificationHandler = @MainActor @Sendable (
    AIConnectorDocumentContextClassificationRequest,
    @escaping @Sendable (Double) -> Void,
    @escaping @MainActor @Sendable (Int) -> Void
) async throws -> AIConnectorDocumentContextClassificationResult

/// Prepares the structure/profile boundary before the review queue starts.
/// Local extraction remains useful when classification is unavailable.
@MainActor
final class AIConnectorDocumentContextCoordinator {
    private let service: QwenSuggestionService
    private let structureBuilder = AIConnectorDocumentStructureBuilder()
    private let profileBuilder = AIConnectorDocumentContextProfileBuilder()
    private let classifier: AIConnectorDocumentContextClassificationHandler?

    init(
        service: QwenSuggestionService,
        classifier: AIConnectorDocumentContextClassificationHandler? = nil
    ) {
        self.service = service
        self.classifier = classifier
    }

    func prepare(
        documentText: String,
        structuredDocument: StructuredDocument?,
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        generationProfile: AIConnectorGenerationProfile,
        downloadProgress: @escaping @Sendable (Double) -> Void = { _ in },
        generationProgress: @escaping @MainActor @Sendable (Int) -> Void = { _ in },
        stage: @escaping @MainActor @Sendable (AIConnectorDocumentContextPreparationStage) -> Void = { _ in }
    ) async throws -> AIConnectorDocumentContextPreparation {
        let clock = ContinuousClock()
        let startedAt = clock.now
        stage(.structure)
        let structureStartedAt = clock.now
        let structure = structureBuilder.build(
            documentText: documentText,
            structuredDocument: structuredDocument
        )
        let structureDuration = Self.seconds(structureStartedAt.duration(to: clock.now))
        stage(.extraction)
        let extractionStartedAt = clock.now
        var profile = profileBuilder.build(
            documentText: documentText,
            structure: structure
        )
        let sample = AIConnectorDocumentContextSampler().sample(
            documentText: documentText,
            structure: structure,
            profile: profile
        )
        profile = profile.withCoverage(sample.coverage)
        let extractionDuration = Self.seconds(extractionStartedAt.duration(to: clock.now))

        var classificationDuration = 0.0
        if mode.usesModel, profile.requiresClassification {
            stage(.classification)
            let request = AIConnectorDocumentContextClassificationRequest(
                sampledText: sample.text,
                evidenceIDs: sample.evidenceIDs,
                sectionIDs: sample.sectionIDs,
                allowedDocumentTypes: AIConnectorDocumentContextProfileBuilder.allowedDocumentTypes,
                allowedDomains: AIConnectorDocumentContextProfileBuilder.allowedDomains,
                modelVariant: modelVariant,
                generationProfile: generationProfile
            )
            let classificationStartedAt = clock.now
            do {
                let result = try await classify(
                    request,
                    downloadProgress: downloadProgress,
                    generationProgress: generationProgress
                )
                classificationDuration = Self.seconds(
                    classificationStartedAt.duration(to: clock.now)
                )
                profile = profile.withClassification(
                    documentTypes: makeClassifiedFacts(
                        category: "document-type",
                        values: result.documentType
                            .map { $0 == "unknown" ? [] : [$0] } ?? [],
                        confidence: result.confidence,
                        sectionIDs: result.sectionIDs,
                        structure: structure
                    ),
                    domains: makeClassifiedFacts(
                        category: "domain",
                        values: result.domains.filter { $0 != "unknown" },
                        confidence: result.confidence,
                        sectionIDs: result.sectionIDs,
                        structure: structure
                    ),
                    status: .succeeded,
                    modelCallCount: 1,
                    duration: classificationDuration
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                classificationDuration = Self.seconds(
                    classificationStartedAt.duration(to: clock.now)
                )
                profile = profile.withClassification(
                    documentTypes: [],
                    domains: [],
                    status: .fallback,
                    modelCallCount: 1,
                    duration: classificationDuration
                )
            }
        } else if profile.requiresClassification {
            profile = profile.withClassification(
                documentTypes: [],
                domains: [],
                status: .notRequired,
                modelCallCount: 0,
                duration: 0
            )
        }

        stage(.segmentation)
        let segmentationStartedAt = clock.now
        let segmentation = LegalTextSegmenter().segment(
            documentText: documentText,
            structure: structure,
            profile: profile
        )
        let segmentationDuration = Self.seconds(segmentationStartedAt.duration(to: clock.now))
        let preparationDuration = Self.seconds(startedAt.duration(to: clock.now))
        return AIConnectorDocumentContextPreparation(
            structure: structure,
            profile: profile,
            segmentation: segmentation,
            structureDuration: structureDuration,
            extractionDuration: extractionDuration,
            segmentationDuration: segmentationDuration,
            preparationDuration: preparationDuration,
            classificationDuration: classificationDuration,
            cacheKey: Self.cacheKey(
                documentText: documentText,
                structure: structure,
                modelVariant: modelVariant,
                mode: mode
            )
        )
    }

    private func classify(
        _ request: AIConnectorDocumentContextClassificationRequest,
        downloadProgress: @escaping @Sendable (Double) -> Void,
        generationProgress: @escaping @MainActor @Sendable (Int) -> Void
    ) async throws -> AIConnectorDocumentContextClassificationResult {
        if let classifier {
            return try await classifier(request, downloadProgress, generationProgress)
        }
        return try await service.reviewDocumentContext(
            request: request,
            downloadProgress: downloadProgress,
            generationProgress: generationProgress
        )
    }

    private func makeClassifiedFacts(
        category: String,
        values: [String],
        confidence: AIConnectorDocumentContextConfidence,
        sectionIDs: [String],
        structure: AIConnectorDocumentStructure
    ) -> [AIConnectorContextFact] {
        values.enumerated().map { index, value in
            let sectionID = sectionIDs.indices.contains(index) ? sectionIDs[index] : sectionIDs.first
            let range = structure.section(for: sectionID)?.sourceRange
            return AIConnectorContextFact(
                id: "qwen-\(category)-\(index)-\(value)",
                value: value,
                origin: .qwen,
                confidence: confidence,
                evidenceRanges: range.map { [$0] } ?? [],
                sectionID: sectionID
            )
        }
    }

    private static func cacheKey(
        documentText: String,
        structure: AIConnectorDocumentStructure,
        modelVariant: AIConnectorModelVariant,
        mode: AIConnectorReviewMode
    ) -> String {
        [
            DocumentFingerprinting.contentSHA256(documentText),
            structure.fingerprint,
            AIConnectorDocumentContextProfile.extractorVersion,
            AIConnectorDocumentContextProfile.classifierVersion,
            modelVariant.rawValue,
            mode.rawValue
        ].joined(separator: "|")
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

enum AIConnectorDocumentContextPreparationStage: String, Sendable {
    case structure
    case extraction
    case classification
    case segmentation
}

struct AIConnectorDocumentContextSample: Sendable {
    let text: String
    let evidenceIDs: [String]
    let sectionIDs: [String]
    let coverage: AIConnectorContextCoverage
}

struct AIConnectorDocumentContextSampler: Sendable {
    /// Conservative UTF-16 cap. It leaves headroom below the 2,048-token
    /// classification input limit for tokenizers with larger tokenization.
    static let maximumUTF16Length = 7_000

    func sample(
        documentText: String,
        structure: AIConnectorDocumentStructure,
        profile: AIConnectorDocumentContextProfile
    ) -> AIConnectorDocumentContextSample {
        var parts: [String] = []
        var evidenceIDs: [String] = []
        var sectionIDs: [String] = []
        var length = 0
        var counter = 0

        func append(_ label: String, _ value: String, sectionID: String?) {
            guard length < Self.maximumUTF16Length else { return }
            let line = "[\(label)] \(value.trimmingCharacters(in: .whitespacesAndNewlines))"
            let separatorLength = parts.isEmpty ? 0 : 1
            let available = Self.maximumUTF16Length - length - separatorLength
            guard available > 0 else { return }
            let clipped: String
            if line.utf16.count > available {
                clipped = available == 1
                    ? "…"
                    : String(line.prefix(available - 1)) + "…"
            } else {
                clipped = line
            }
            guard !clipped.isEmpty else { return }
            parts.append(clipped)
            length += clipped.utf16.count + separatorLength
            evidenceIDs.append(label)
            if let sectionID, !sectionIDs.contains(sectionID) { sectionIDs.append(sectionID) }
        }

        for section in profile.sectionOutline {
            append("S\(counter)", section.title, sectionID: section.id)
            counter += 1
        }
        let evidenceRanges = profile.definedTerms + profile.parties + profile.regulationReferences
        for fact in evidenceRanges {
            guard let range = fact.evidenceRanges.first,
                  range.location >= 0,
                  NSMaxRange(range) <= (documentText as NSString).length else { continue }
            append(
                "E\(counter)",
                (documentText as NSString).substring(with: range),
                sectionID: fact.sectionID
            )
            counter += 1
        }

        let step = max(1, structure.blocks.count / 8)
        for index in Swift.stride(from: 0, to: structure.blocks.count, by: step) {
            let block = structure.blocks[index]
            guard block.kind != AIConnectorDocumentBlockKind.heading,
                  NSMaxRange(block.sourceRange) <= (documentText as NSString).length else { continue }
            append(
                "B\(counter)",
                (documentText as NSString).substring(with: block.sourceRange),
                sectionID: block.parentSectionID
            )
            counter += 1
        }

        let sampledText = parts.joined(separator: "\n")
        return AIConnectorDocumentContextSample(
            text: sampledText,
            evidenceIDs: evidenceIDs,
            sectionIDs: sectionIDs,
            coverage: AIConnectorContextCoverage(
                totalUTF16Length: documentText.utf16.count,
                sampledUTF16Length: sampledText.utf16.count,
                sampledSectionIDs: sectionIDs,
                evidenceIDs: evidenceIDs
            )
        )
    }
}
