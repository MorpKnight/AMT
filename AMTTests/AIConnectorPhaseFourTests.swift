import Foundation
import XCTest
@testable import AMT

@MainActor
final class AIConnectorPhaseFourTests: XCTestCase {
    func testStructureUsesExactUTF16RangesAndKeepsNestedSections() {
        let text = "BAB I KETENTUAN UMUM\nPasal 4 Ruang Lingkup\n1.2 Pihak Kedua menyerahkan 😀 data.\n(a) Pihak Kedua menyimpan data.\nNama\tNilai\nAli\tRp 10.000"
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let source = text as NSString

        XCTAssertGreaterThanOrEqual(structure.headingCount, 2)
        XCTAssertTrue(structure.blocks.contains { $0.kind == .tableCell })
        XCTAssertTrue(structure.blocks.allSatisfy { block in
            NSMaxRange(block.sourceRange) <= source.length
                && source.substring(with: block.sourceRange) == block.text
        })
        XCTAssertTrue(structure.blocks.contains { block in
            block.kind == .listItem && block.numberingLabel == "(a)"
        })
        XCTAssertTrue(structure.blocks.contains { block in
            block.kind == .numberedClause && block.numberingLabel == "1.2"
        })
        XCTAssertTrue(structure.sections.contains { $0.headingPath.count >= 2 })
    }

    func testSectionIDsRemainStableWhenAnotherSectionChanges() {
        let first = "BAB I\nKetentuan umum\nBAB II\nData pribadi diproses."
        let second = "BAB I\nKetentuan umum\nBAB II\nData pribadi diproses dan diamankan."
        let firstStructure = AIConnectorDocumentStructureBuilder().build(documentText: first)
        let secondStructure = AIConnectorDocumentStructureBuilder().build(documentText: second)

        XCTAssertEqual(firstStructure.sections.first?.id, secondStructure.sections.first?.id)
        XCTAssertEqual(firstStructure.sections.first?.title, "BAB I")
    }

    func testStructureAwareSegmentationDoesNotUseHeadingAsGrammarTarget() {
        let text = "BAB I\nPihak Pertama wajib menyerahkan data.\nBAB II\nPihak Kedua wajib menyimpan data."
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let profile = AIConnectorDocumentContextProfileBuilder().build(
            documentText: text,
            structure: structure
        )
        let result = LegalTextSegmenter().segment(
            documentText: text,
            structure: structure,
            profile: profile
        )
        let source = text as NSString

        XCTAssertFalse(result.segments.contains { $0.targetText == "BAB I" || $0.targetText == "BAB II" })
        XCTAssertTrue(result.segments.allSatisfy {
            source.substring(with: NSRange(location: $0.sourceLocation, length: $0.sourceLength)) == $0.targetText
        })
        XCTAssertEqual(result.segments.compactMap(\.context?.sectionID).count, result.segments.count)
        XCTAssertNotEqual(result.segments.first?.context?.sectionID, result.segments.last?.context?.sectionID)
        XCTAssertNil(result.segments.first?.previousContext)
        XCTAssertNil(result.segments.last?.nextContext)
    }

    func testLocalProfileExtractsEvidenceWithoutInferringJurisdictionFromLanguage() {
        let text = "PERJANJIAN PENGOLAHAN DATA PRIBADI\nPara Pihak sepakat.\n\"Data Pribadi\" adalah data tentang orang perseorangan.\nPerjanjian ini tunduk pada UU No. 27 Tahun 2022 dan berlaku tanggal 1 Januari 2027.\nNilai: Rp 10.000."
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let profile = AIConnectorDocumentContextProfileBuilder().build(
            documentText: text,
            structure: structure
        )

        XCTAssertTrue(profile.documentTypeCandidates.contains { $0.value == "DPA" })
        XCTAssertTrue(profile.legalDomains.contains { $0.value == "privacy" })
        XCTAssertTrue(profile.definedTerms.contains { $0.value == "Data Pribadi" })
        XCTAssertTrue(profile.regulationReferences.contains { $0.value.contains("UU") })
        XCTAssertTrue(profile.effectiveDates.contains { $0.value.contains("2027") })
        XCTAssertTrue(profile.currencies.contains { $0.value.lowercased().contains("rp") })
        XCTAssertTrue(profile.jurisdictions.isEmpty)
        XCTAssertTrue(profile.parties.contains { $0.value == "Para Pihak" })
    }

    func testContextSamplerIsBoundedAndReportsCoverage() {
        let text = String(repeating: "Pihak Kedua wajib menjaga kerahasiaan data. ", count: 500)
        let structure = AIConnectorDocumentStructureBuilder().build(documentText: text)
        let profile = AIConnectorDocumentContextProfileBuilder().build(
            documentText: text,
            structure: structure
        )
        let sample = AIConnectorDocumentContextSampler().sample(
            documentText: text,
            structure: structure,
            profile: profile
        )

        XCTAssertLessThanOrEqual(sample.text.utf16.count, AIConnectorDocumentContextSampler.maximumUTF16Length)
        XCTAssertEqual(sample.coverage.totalUTF16Length, text.utf16.count)
        XCTAssertEqual(sample.coverage.sampledUTF16Length, sample.text.utf16.count)
    }

    func testContextParserRejectsUnknownEvidenceAndLabels() throws {
        let parser = AIConnectorDocumentContextClassificationParser()
        let arguments = [
            "document_type": "DPA",
            "domains": "privacy,commercial",
            "evidence_ids": "E1",
            "section_ids": "S1",
            "confidence": "inferred"
        ]
        let result = try parser.parse(
            toolCalls: [AIConnectorToolDecisionPayload(
                name: AIConnectorDocumentContextClassificationParser.toolName,
                arguments: arguments
            )],
            visibleText: "",
            allowedDocumentTypes: ["DPA"],
            allowedDomains: ["privacy", "commercial"],
            evidenceIDs: ["E1"],
            sectionIDs: ["S1"]
        )
        XCTAssertEqual(result.documentType, "DPA")
        XCTAssertEqual(result.domains, ["privacy", "commercial"])

        XCTAssertThrowsError(try parser.parse(
            toolCalls: [AIConnectorToolDecisionPayload(
                name: AIConnectorDocumentContextClassificationParser.toolName,
                arguments: arguments.merging(["evidence_ids": "E99"], uniquingKeysWith: { _, new in new })
            )],
            visibleText: "",
            allowedDocumentTypes: ["DPA"],
            allowedDomains: ["privacy", "commercial"],
            evidenceIDs: ["E1"],
            sectionIDs: ["S1"]
        )) { error in
            XCTAssertEqual(error as? AIConnectorDocumentContextClassificationError, .invalidEvidence)
        }
    }

    func testContextCoordinatorSkipsQwenInDeterministicModeAndAppliesValidClassification() async throws {
        let calls = CallBox()
        let handler: AIConnectorDocumentContextClassificationHandler = { @MainActor request, _, _ in
            calls.count += 1
            return AIConnectorDocumentContextClassificationResult(
                documentType: "DPA",
                domains: ["privacy"],
                evidenceIDs: request.evidenceIDs.isEmpty ? [] : [request.evidenceIDs[0]],
                sectionIDs: request.sectionIDs.isEmpty ? [] : [request.sectionIDs[0]],
                confidence: .inferred,
                metrics: Self.testMetrics()
            )
        }
        let service = QwenSuggestionService()
        let coordinator = AIConnectorDocumentContextCoordinator(
            service: service,
            classifier: handler
        )
        let text = "Pihak Kedua menyerahkan dokumen kepada Pihak Pertama."

        let deterministic = try await coordinator.prepare(
            documentText: text,
            structuredDocument: nil,
            mode: .deterministic,
            modelVariant: .qwen35Base4B,
            generationProfile: testProfile()
        )
        XCTAssertEqual(calls.count, 0)
        XCTAssertEqual(deterministic.profile.classificationStatus, .notRequired)

        let hybrid = try await coordinator.prepare(
            documentText: text,
            structuredDocument: nil,
            mode: .hybrid,
            modelVariant: .qwen35Base4B,
            generationProfile: testProfile()
        )
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(hybrid.profile.classificationStatus, .succeeded)
        XCTAssertTrue(hybrid.profile.documentTypeCandidates.contains { $0.origin == .qwen && $0.value == "DPA" })
    }

    func testSegmentContextFingerprintChangesCacheKey() {
        let base = AIReviewSegment(
            id: 1,
            sourceLocation: 0,
            sourceLength: 4,
            targetText: "Data",
            previousContext: nil,
            nextContext: nil,
            context: AIConnectorSegmentContext(
                sectionID: "s1",
                headingPath: ["NDA"],
                parentClause: nil,
                relevantDefinedTerms: [],
                relevantParties: [],
                sectionRegulationReferences: [],
                documentTypeCandidates: ["NDA"],
                legalDomainCandidates: ["commercial"],
                profileFingerprint: "p1",
                structureFingerprint: "structure-1"
            )
        )
        let changed = AIReviewSegment(
            id: 1,
            sourceLocation: 0,
            sourceLength: 4,
            targetText: "Data",
            previousContext: nil,
            nextContext: nil,
            context: AIConnectorSegmentContext(
                sectionID: "s2",
                headingPath: ["DPA"],
                parentClause: nil,
                relevantDefinedTerms: [],
                relevantParties: [],
                sectionRegulationReferences: [],
                documentTypeCandidates: ["DPA"],
                legalDomainCandidates: ["privacy"],
                profileFingerprint: "p2",
                structureFingerprint: "structure-2"
            )
        )
        let profile = testProfile()
        let key = { (segment: AIReviewSegment) in
            AIConnectorSegmentCache.key(from: AIConnectorCacheKeyComponents(
                segment: segment,
                reviewMode: .hybrid,
                modelVariant: .qwen35Base4B,
                generationProfile: profile,
                promptVersion: "p",
                rulePackVersion: "r",
                corpusVersion: "c",
                validatorVersion: "v",
                outputSchemaVersion: "o",
                protectionContext: .empty
            ))
        }
        XCTAssertNotEqual(key(base), key(changed))
    }

    private func testProfile() -> AIConnectorGenerationProfile {
        AIConnectorGenerationProfile(
            maxTokens: 128,
            temperature: 0,
            topP: 1,
            topK: 0,
            presencePenalty: nil,
            seed: 42
        )
    }

    private static func testMetrics() -> AIConnectorGenerationMetrics {
        AIConnectorGenerationMetrics(
            promptTokenCount: 1,
            generationTokenCount: 1,
            promptDuration: 0,
            generationDuration: 0,
            stopReason: .stop
        )
    }

    private final class CallBox: @unchecked Sendable {
        var count = 0
    }
}
