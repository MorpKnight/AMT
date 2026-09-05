import CryptoKit
import Accelerate
import Foundation

nonisolated enum LegalCorpusStoreError: Error, Equatable, LocalizedError, Sendable {
    case missingResource(String)
    case invalidManifest(String)
    case invalidData(String)
    case hashMismatch(String)
    case countMismatch(String)
    case foreignKeyViolation(String)
    case embeddingMismatch(String)

    var errorDescription: String? {
        switch self {
        case let .missingResource(name):
            "Resource corpus hukum tidak ditemukan: \(name)."
        case let .invalidManifest(detail):
            "Manifest corpus hukum tidak valid: \(detail)."
        case let .invalidData(name):
            "Data corpus hukum tidak dapat dibaca: \(name)."
        case let .hashMismatch(name):
            "Hash corpus hukum tidak sesuai: \(name)."
        case let .countMismatch(detail):
            "Jumlah record corpus hukum tidak sesuai: \(detail)."
        case let .foreignKeyViolation(detail):
            "Referensi corpus hukum tidak dapat di-resolve: \(detail)."
        case let .embeddingMismatch(detail):
            "Embedding corpus hukum tidak sesuai: \(detail)."
        }
    }
}

/// Immutable, version-checked view of the bundled legal knowledge pack.
///
/// This type owns no model and performs no network access. It is deliberately
/// safe to copy into the dictionary, suggestion pipeline, and read-only local
/// tools. Semantic inference is provided separately by ``LegalSemanticRetriever``.
nonisolated struct LegalCorpusStore: Sendable {
    static let expectedSchemaVersion = "amt-legal-corpus-v2"

    let manifest: LegalCorpusManifest
    let concepts: [LegalConcept]
    let primaryRecords: [LegalDictionaryPrimaryRecord]
    let termGroups: [LegalDictionaryTermGroup]
    let alternatives: [LegalDictionaryAlternative]
    let regulations: [LegalRegulation]
    let relations: [LegalRegulationRelation]
    let sourcePassages: [LegalSourcePassage]
    let embeddings: [Float]

    private let regulationByID: [String: LegalRegulation]
    private let passageByID: [String: LegalSourcePassage]
    private let relationByReferenceID: [String: [LegalRegulationRelation]]
    private let primaryByTermID: [String: LegalDictionaryPrimaryRecord]
    private let termGroupByID: [String: LegalDictionaryTermGroup]
    private let alternativesByTermID: [String: [LegalDictionaryAlternative]]

    init(bundle: Bundle = .main) throws {
        // Xcode's synchronized resource group flattens this directory in the
        // final app bundle. Keep the namespaced lookup for bundles that retain
        // subdirectories, then support the flattened layout as well.
        guard let manifestURL = bundle.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: "legal_corpus"
        ) ?? bundle.url(forResource: "manifest", withExtension: "json") else {
            throw LegalCorpusStoreError.missingResource("legal_corpus/manifest.json")
        }

        try self.init(directory: manifestURL.deletingLastPathComponent())
    }

    init(directory: URL) throws {
        let decoder = JSONDecoder()
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw LegalCorpusStoreError.missingResource(manifestURL.path)
        }

        let loadedManifest: LegalCorpusManifest
        do {
            let manifestData = try Data(contentsOf: manifestURL)
            loadedManifest = try decoder.decode(LegalCorpusManifest.self, from: manifestData)
        } catch let error as LegalCorpusStoreError {
            throw error
        } catch {
            throw LegalCorpusStoreError.invalidManifest(error.localizedDescription)
        }

        guard loadedManifest.schemaVersion == Self.expectedSchemaVersion else {
            throw LegalCorpusStoreError.invalidManifest(
                "schema \(loadedManifest.schemaVersion) tidak didukung"
            )
        }
        guard loadedManifest.embedding.dimension > 0,
              loadedManifest.embedding.dimension == 384,
              loadedManifest.embedding.normalized else {
            throw LegalCorpusStoreError.invalidManifest("konfigurasi embedding")
        }
        let retrieval = loadedManifest.retrieval
        guard retrieval.rrfK > 0,
              retrieval.lexicalTopK > 0,
              retrieval.semanticTopK > 0,
              (1...3).contains(retrieval.suggestionCandidateLimit),
              retrieval.suggestionMinimumSpanTokens > 0,
              retrieval.suggestionMaximumSpanTokens
                >= retrieval.suggestionMinimumSpanTokens,
              (0...1).contains(retrieval.suggestionMinimumKeywordCoverage),
              (-1...1).contains(retrieval.suggestionSemanticThreshold),
              retrieval.suggestionTopOneMargin >= 0 else {
            throw LegalCorpusStoreError.invalidManifest("parameter retrieval")
        }

        let resourceNames = Set(loadedManifest.files.values)
        guard resourceNames.count == loadedManifest.files.count else {
            throw LegalCorpusStoreError.invalidManifest("nama file berulang")
        }
        guard let expectedHashes = loadedManifest.filesSHA256 else {
            throw LegalCorpusStoreError.invalidManifest("files_sha256 tidak tersedia")
        }
        guard Set(expectedHashes.keys) == resourceNames else {
            throw LegalCorpusStoreError.invalidManifest("daftar hash file tidak sesuai")
        }

        for fileName in resourceNames {
            guard !fileName.isEmpty,
                  URL(fileURLWithPath: fileName).lastPathComponent == fileName else {
                throw LegalCorpusStoreError.invalidManifest("nama file tidak aman")
            }
            let fileURL = directory.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw LegalCorpusStoreError.missingResource(fileName)
            }
            guard let expectedHash = expectedHashes[fileName] else {
                throw LegalCorpusStoreError.invalidManifest("hash untuk \(fileName) hilang")
            }
            let actualHash = Self.sha256(fileURL: fileURL)
            guard actualHash == expectedHash else {
                throw LegalCorpusStoreError.hashMismatch(fileName)
            }
        }

        func resourceName(_ key: String) throws -> String {
            guard let name = loadedManifest.files[key] else {
                throw LegalCorpusStoreError.invalidManifest("file \(key) hilang")
            }
            return name
        }

        let loadedConcepts: [LegalConcept]
        let loadedPrimaryRecords: [LegalDictionaryPrimaryRecord]
        let loadedTermGroups: [LegalDictionaryTermGroup]
        let loadedAlternatives: [LegalDictionaryAlternative]
        let loadedRegulations: [LegalRegulation]
        let loadedRelations: [LegalRegulationRelation]
        let loadedSourcePassages: [LegalSourcePassage]
        do {
            loadedConcepts = try Self.decode(
                [LegalConcept].self,
                from: directory.appendingPathComponent(try resourceName("concepts"))
            )
            loadedPrimaryRecords = try Self.decode(
                [LegalDictionaryPrimaryRecord].self,
                from: directory.appendingPathComponent(try resourceName("dictionary_primary"))
            )
            loadedTermGroups = try Self.decode(
                [LegalDictionaryTermGroup].self,
                from: directory.appendingPathComponent(try resourceName("dictionary_terms"))
            )
            loadedAlternatives = try Self.decode(
                [LegalDictionaryAlternative].self,
                from: directory.appendingPathComponent(try resourceName("dictionary_alternatives"))
            )
            loadedRegulations = try Self.decode(
                [LegalRegulation].self,
                from: directory.appendingPathComponent(try resourceName("regulations"))
            )
            loadedRelations = try Self.decode(
                [LegalRegulationRelation].self,
                from: directory.appendingPathComponent(try resourceName("relations"))
            )
            loadedSourcePassages = try Self.decode(
                [LegalSourcePassage].self,
                from: directory.appendingPathComponent(try resourceName("source_passages"))
            )
        } catch let error as LegalCorpusStoreError {
            throw error
        } catch {
            throw LegalCorpusStoreError.invalidData(error.localizedDescription)
        }

        guard loadedConcepts.count == loadedManifest.conceptCount,
              loadedPrimaryRecords.count == loadedManifest.termGroupCount,
              loadedTermGroups.count == loadedManifest.termGroupCount,
              loadedAlternatives.count == loadedManifest.alternativeCount,
              loadedRegulations.count == loadedManifest.regulationCount,
              loadedRelations.count == loadedManifest.relationCount,
              loadedSourcePassages.count == loadedManifest.sourcePassageCount else {
            throw LegalCorpusStoreError.countMismatch(
                "concepts=\(loadedConcepts.count)/\(loadedManifest.conceptCount), "
                    + "primary=\(loadedPrimaryRecords.count)/\(loadedManifest.termGroupCount), "
                    + "terms=\(loadedTermGroups.count)/\(loadedManifest.termGroupCount), "
                    + "alternatives=\(loadedAlternatives.count)/\(loadedManifest.alternativeCount), "
                    + "regulations=\(loadedRegulations.count)/\(loadedManifest.regulationCount), "
                    + "relations=\(loadedRelations.count)/\(loadedManifest.relationCount), "
                    + "passages=\(loadedSourcePassages.count)/\(loadedManifest.sourcePassageCount)"
            )
        }

        let sortedConceptIDs = loadedConcepts.map(\.recordID).sorted()
        guard loadedConcepts.map(\.recordID) == sortedConceptIDs,
              sortedConceptIDs.allSatisfy({ !$0.isEmpty }),
              Set(sortedConceptIDs).count == loadedConcepts.count else {
            throw LegalCorpusStoreError.invalidData("urutan atau ID konsep tidak stabil")
        }
        let conceptOrderMaterial = loadedConcepts
            .map(\.recordID)
            .joined(separator: "\n")
        let conceptOrderSHA256 = SHA256.hash(data: Data(conceptOrderMaterial.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard loadedManifest.embedding.conceptOrderSHA256 == conceptOrderSHA256 else {
            throw LegalCorpusStoreError.embeddingMismatch(
                "hash urutan konsep tidak sesuai"
            )
        }

        let regulationsByID = Dictionary(grouping: loadedRegulations, by: \.referenceID)
        let passagesByID = Dictionary(grouping: loadedSourcePassages, by: \.passageID)
        guard regulationsByID.values.allSatisfy({ $0.count == 1 }),
              passagesByID.values.allSatisfy({ $0.count == 1 }),
              loadedRegulations.allSatisfy({ !$0.referenceID.isEmpty }),
              loadedSourcePassages.allSatisfy({ !$0.passageID.isEmpty }) else {
            throw LegalCorpusStoreError.foreignKeyViolation("ID regulasi atau passage duplikat")
        }
        let loadedRegulationByID = regulationsByID.compactMapValues(\.first)
        let loadedPassageByID = passagesByID.compactMapValues(\.first)

        let primaryRecordsByID = Dictionary(grouping: loadedPrimaryRecords, by: \.termGroupID)
        let termGroupsByID = Dictionary(grouping: loadedTermGroups, by: \.termGroupID)
        let alternativesByDefinitionID = Dictionary(grouping: loadedAlternatives, by: \.definitionID)
        guard primaryRecordsByID.values.allSatisfy({ $0.count == 1 }),
              termGroupsByID.values.allSatisfy({ $0.count == 1 }),
              alternativesByDefinitionID.values.allSatisfy({ $0.count == 1 }),
              loadedPrimaryRecords.allSatisfy({ !$0.termGroupID.isEmpty }),
              loadedTermGroups.allSatisfy({ !$0.termGroupID.isEmpty }),
              loadedAlternatives.allSatisfy({ !$0.definitionID.isEmpty }) else {
            throw LegalCorpusStoreError.foreignKeyViolation(
                "ID primary, term group, atau alternative duplikat"
            )
        }

        let loadedConceptByID = Dictionary(uniqueKeysWithValues: loadedConcepts.map { ($0.recordID, $0) })
        for primary in loadedPrimaryRecords where primary.primaryAvailable {
            guard primary.selectionStatus == "selected",
                  let primaryDefinitionID = primary.primaryDefinitionID,
                  let primaryDefinition = primary.primaryDefinition,
                  !primaryDefinition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let concept = loadedConceptByID[primary.termGroupID],
                  concept.definition == primaryDefinition,
                  concept.recordID == primary.termGroupID else {
                throw LegalCorpusStoreError.foreignKeyViolation(
                    "primary \(primary.termGroupID)"
                )
            }
            guard !primaryDefinitionID.isEmpty else {
                throw LegalCorpusStoreError.foreignKeyViolation(
                    "primary definition \(primary.termGroupID)"
                )
            }
            for referenceID in primary.primaryReferenceIDs {
                guard loadedRegulationByID[referenceID] != nil else {
                    throw LegalCorpusStoreError.foreignKeyViolation(
                        "primary \(primary.termGroupID) → \(referenceID)"
                    )
                }
            }
        }
        for termGroup in loadedTermGroups {
            guard primaryRecordsByID[termGroup.termGroupID] != nil else {
                throw LegalCorpusStoreError.foreignKeyViolation(
                    "term group \(termGroup.termGroupID) → primary"
                )
            }
        }
        for alternative in loadedAlternatives {
            guard termGroupsByID[alternative.termGroupID] != nil else {
                throw LegalCorpusStoreError.foreignKeyViolation(
                    "alternative \(alternative.definitionID) → \(alternative.termGroupID)"
                )
            }
            for evidence in alternative.evidence {
                guard loadedRegulationByID[evidence.regulationID] != nil else {
                    throw LegalCorpusStoreError.foreignKeyViolation(
                        "alternative evidence \(evidence.evidenceID)"
                    )
                }
            }
        }

        let relationIDs = loadedRelations.map(\.relationID)
        guard relationIDs.allSatisfy({ !$0.isEmpty }),
              Set(relationIDs).count == relationIDs.count else {
            throw LegalCorpusStoreError.foreignKeyViolation(
                "ID relation regulasi duplikat atau kosong"
            )
        }

        var relationIndex: [String: [LegalRegulationRelation]] = [:]
        for relation in loadedRelations {
            guard loadedRegulationByID[relation.sourceReferenceID] != nil,
                  loadedRegulationByID[relation.targetReferenceID] != nil else {
                throw LegalCorpusStoreError.foreignKeyViolation(
                    "relation \(relation.relationID)"
                )
            }
            relationIndex[relation.sourceReferenceID, default: []].append(relation)
            relationIndex[relation.targetReferenceID, default: []].append(relation)
        }

        for concept in loadedConcepts {
            for evidence in concept.evidence {
                guard loadedRegulationByID[evidence.referenceID] != nil,
                      !evidence.referenceID.isEmpty,
                      !evidence.passageID.isEmpty,
                      let passage = loadedPassageByID[evidence.passageID],
                      passage.referenceID == evidence.referenceID,
                      passage.conceptIDs.contains(concept.recordID) else {
                    throw LegalCorpusStoreError.foreignKeyViolation(
                        "evidence \(evidence.passageID)"
                    )
                }
            }

            guard concept.actionable == (concept.actionableEvidence != nil) else {
                throw LegalCorpusStoreError.foreignKeyViolation(
                    "flag actionable \(concept.recordID)"
                )
            }
            if let actionableEvidence = concept.actionableEvidence {
                guard concept.evidence.contains(actionableEvidence),
                      let regulation = loadedRegulationByID[actionableEvidence.referenceID],
                      let passage = loadedPassageByID[actionableEvidence.passageID],
                      passage.referenceID == actionableEvidence.referenceID,
                      passage.conceptIDs.contains(concept.recordID),
                      regulation.applicabilityStatus == .inForce,
                      actionableEvidence.verificationStatus?.isAcceptedEvidence == true,
                      actionableEvidence.officialDetailURL != nil,
                      actionableEvidence.officialDocumentURL != nil,
                      !actionableEvidence.matchedDefinitionText
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !passage.text
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw LegalCorpusStoreError.foreignKeyViolation(
                        "actionable evidence \(concept.recordID)"
                    )
                }
            }
        }

        let conceptIDs = Set(loadedConcepts.map(\.recordID))
        for passage in loadedSourcePassages {
            guard loadedRegulationByID[passage.referenceID] != nil else {
                throw LegalCorpusStoreError.foreignKeyViolation(
                    "passage \(passage.passageID) → \(passage.referenceID)"
                )
            }
            for conceptID in passage.conceptIDs {
                guard conceptIDs.contains(conceptID) else {
                    throw LegalCorpusStoreError.foreignKeyViolation(
                        "passage \(passage.passageID) → \(conceptID)"
                    )
                }
            }
        }

        guard loadedConcepts.filter(\.actionable).count
                == loadedManifest.actionableConceptCount else {
            throw LegalCorpusStoreError.countMismatch(
                "actionable concepts tidak sesuai"
            )
        }

        let embeddingURL = directory.appendingPathComponent(try resourceName("embeddings"))
        let embeddingData: Data
        do {
            embeddingData = try Data(contentsOf: embeddingURL)
        } catch {
            throw LegalCorpusStoreError.invalidData("definition_embeddings.f16")
        }
        let expectedByteCount = loadedConcepts.count
            * loadedManifest.embedding.dimension
            * MemoryLayout<UInt16>.size
        guard embeddingData.count == expectedByteCount else {
            throw LegalCorpusStoreError.embeddingMismatch(
                "byte count \(embeddingData.count), expected \(expectedByteCount)"
            )
        }
        let loadedEmbeddings = Self.decodeFloat16(embeddingData)
        guard loadedEmbeddings.count == loadedConcepts.count * loadedManifest.embedding.dimension else {
            throw LegalCorpusStoreError.embeddingMismatch("jumlah vector")
        }
        let dimension = loadedManifest.embedding.dimension
        for row in loadedConcepts.indices {
            let offset = row * dimension
            var squaredNorm = 0.0
            for column in 0..<dimension {
                let value = loadedEmbeddings[offset + column]
                guard value.isFinite else {
                    throw LegalCorpusStoreError.embeddingMismatch(
                        "vector \(row) memiliki nilai non-finite"
                    )
                }
                squaredNorm += Double(value) * Double(value)
            }
            let norm = squaredNorm.squareRoot()
            guard abs(norm - 1.0) <= 0.02 else {
                throw LegalCorpusStoreError.embeddingMismatch(
                    "vector \(row) tidak ternormalisasi"
                )
            }
        }

        var contextualAlternativeIndex: [String: [LegalDictionaryAlternative]] = [:]
        for alternative in loadedAlternatives
            where alternative.termSelectionStatus == "selected"
                && alternative.definitionRole == "alternative" {
            contextualAlternativeIndex[alternative.termGroupID, default: []].append(alternative)
        }
        for termGroupID in contextualAlternativeIndex.keys {
            contextualAlternativeIndex[termGroupID]?.sort {
                if $0.definitionIndex != $1.definitionIndex {
                    return $0.definitionIndex < $1.definitionIndex
                }
                return $0.definitionID < $1.definitionID
            }
        }

        self.manifest = loadedManifest
        self.concepts = loadedConcepts
        self.primaryRecords = loadedPrimaryRecords
        self.termGroups = loadedTermGroups
        self.alternatives = loadedAlternatives
        self.regulations = loadedRegulations
        self.relations = loadedRelations
        self.sourcePassages = loadedSourcePassages
        self.embeddings = loadedEmbeddings
        self.regulationByID = loadedRegulationByID
        self.passageByID = loadedPassageByID
        self.relationByReferenceID = relationIndex
        self.primaryByTermID = Dictionary(
            uniqueKeysWithValues: loadedPrimaryRecords.map { ($0.termGroupID, $0) }
        )
        self.termGroupByID = Dictionary(
            uniqueKeysWithValues: loadedTermGroups.map { ($0.termGroupID, $0) }
        )
        self.alternativesByTermID = contextualAlternativeIndex
    }

    func concept(id: String) -> LegalConcept? {
        concepts.first { $0.recordID == id }
    }

    func primaryRecord(forTermGroupID termGroupID: String) -> LegalDictionaryPrimaryRecord? {
        primaryByTermID[termGroupID]
    }

    func termGroup(for term: String) -> LegalDictionaryTermGroup? {
        let normalizedTerm = Self.normalizeTerm(term)
        guard !normalizedTerm.isEmpty else { return nil }
        return termGroups.first {
            Self.normalizeTerm($0.termNormalized) == normalizedTerm
                || Self.normalizeTerm($0.term) == normalizedTerm
        }
    }

    func alternatives(for term: String) -> [LegalDictionaryAlternative] {
        guard let termGroup = termGroup(for: term) else { return [] }
        return alternativesByTermID[termGroup.termGroupID] ?? []
    }

    func regulation(id: String) -> LegalRegulation? {
        regulationByID[id]
    }

    func sourcePassage(id: String) -> LegalSourcePassage? {
        passageByID[id]
    }

    func relations(for referenceID: String) -> [LegalRegulationRelation] {
        relationByReferenceID[referenceID] ?? []
    }

    /// Converts the selected-primary projection into the existing dictionary
    /// façade. Contextual alternatives stay outside the search index and are
    /// resolved separately by the dictionary presentation layer.
    func dictionaryEntries() -> [LegalDictionaryEntry] {
        concepts.map { concept in
            let evidence = concept.actionableEvidence ?? concept.evidence.first
            let reference = concept.references.first {
                $0.referenceID == evidence?.referenceID
            } ?? concept.references.first
            let regulation = evidence.flatMap { regulationByID[$0.referenceID] }
                ?? reference.flatMap { regulationByID[$0.referenceID] }

            let status = regulation?.applicabilityStatus
                ?? reference?.officialStatusCode
                ?? .unknown
            let isActionable = concept.actionable
                && status == .inForce
                && evidence?.officialDetailURL != nil
                && evidence?.officialDocumentURL != nil
            let hasVerifiedEvidence = concept.evidence.contains { evidence in
                evidence.verificationStatus?.isAcceptedEvidence == true
            }

            return LegalDictionaryEntry(
                id: concept.recordID,
                term: concept.term,
                definition: concept.definition,
                regulation: regulation?.referenceName
                    ?? reference?.displayName
                    ?? "",
                regulationTitle: regulation?.officialTitle
                    ?? evidence?.regulationTitle
                    ?? reference?.officialTitle
                    ?? "",
                sourceURL: evidence?.officialDetailURL ?? reference?.officialDetailURL,
                officialDocumentURL: evidence?.officialDocumentURL
                    ?? regulation?.officialDocumentURL
                    ?? reference?.officialDocumentURL,
                sources: concept.sources,
                sourceURLs: concept.sourceURLs,
                referenceID: evidence?.referenceID ?? reference?.referenceID,
                authority: hasVerifiedEvidence ? .verified : .legacy,
                corpusVersion: manifest.corpusVersion,
                applicabilityStatus: status,
                sourcePassageID: evidence?.passageID,
                articleLocator: evidence?.articleLocator,
                pageStart: evidence?.pageStart,
                pageEnd: evidence?.pageEnd,
                isActionable: isActionable
            )
        }
    }

    func semanticMatches(
        for queryVector: [Float],
        limit: Int
    ) -> [LegalRetrievalMatch] {
        guard limit > 0,
              queryVector.count == manifest.embedding.dimension else {
            return []
        }

        let dimension = manifest.embedding.dimension
        let ranked = concepts.indices.map { index in
            let offset = index * dimension
            var score: Float = 0
            queryVector.withUnsafeBufferPointer { queryBuffer in
                embeddings.withUnsafeBufferPointer { embeddingBuffer in
                    guard let queryBase = queryBuffer.baseAddress,
                          let embeddingBase = embeddingBuffer.baseAddress else {
                        return
                    }
                    vDSP_dotpr(
                        queryBase,
                        1,
                        embeddingBase.advanced(by: offset),
                        1,
                        &score,
                        vDSP_Length(dimension)
                    )
                }
            }
            let evidence = concepts[index].actionableEvidence ?? concepts[index].evidence.first
            return (index: index, score: score, evidence: evidence)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return concepts[lhs.index].recordID < concepts[rhs.index].recordID
        }

        return ranked.prefix(limit).enumerated().map { rank, item in
            let concept = concepts[item.index]
            return LegalRetrievalMatch(
                concept: concept,
                evidence: item.evidence,
                lexicalScore: nil,
                semanticScore: item.score,
                fusionScore: nil,
                rank: rank + 1,
                origin: .semantic,
                isActionable: concept.actionable
            )
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            throw LegalCorpusStoreError.invalidData(url.lastPathComponent)
        }
    }

    private static func normalizeTerm(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private static func sha256(fileURL: URL) -> String {
        guard let data = try? Data(contentsOf: fileURL) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func decodeFloat16(_ data: Data) -> [Float] {
        let bytes = [UInt8](data)
        var result: [Float] = []
        result.reserveCapacity(bytes.count / 2)

        var index = 0
        while index + 1 < bytes.count {
            let bits = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
            result.append(float32(fromFloat16Bits: bits))
            index += 2
        }
        return result
    }

    /// Converts an IEEE-754 binary16 value without relying on the availability
    /// of Float16(bitPattern:) on a particular macOS architecture/toolchain.
    private static func float32(fromFloat16Bits bits: UInt16) -> Float {
        let sign = UInt32(bits & 0x8000) << 16
        let exponent = UInt32((bits & 0x7C00) >> 10)
        let fraction = UInt32(bits & 0x03FF)

        let floatBits: UInt32
        switch exponent {
        case 0:
            if fraction == 0 {
                floatBits = sign
            } else {
                var normalizedFraction = fraction
                var normalizedExponent: Int32 = -14
                while (normalizedFraction & 0x0400) == 0 {
                    normalizedFraction <<= 1
                    normalizedExponent -= 1
                }
                normalizedFraction &= 0x03FF
                let singleExponent = UInt32(normalizedExponent + 127)
                floatBits = sign
                    | (singleExponent << 23)
                    | (normalizedFraction << 13)
            }
        case 0x1F:
            floatBits = sign | 0x7F800000 | (fraction << 13)
        default:
            let singleExponent = exponent + (127 - 15)
            floatBits = sign | (singleExponent << 23) | (fraction << 13)
        }

        return Float(bitPattern: floatBits)
    }
}
