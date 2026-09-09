import CryptoKit
import Foundation

/// Extracts document context using bounded, source-backed local rules. The
/// extractor never infers jurisdiction from language alone and never stores a
/// generated explanation as evidence.
struct AIConnectorDocumentContextProfileBuilder: Sendable {
    static let allowedDocumentTypes = [
        "NDA", "DPA", "MSA", "services", "employment", "loan", "salePurchase", "unknown"
    ]
    static let allowedDomains = [
        "commercial", "privacy", "employment", "finance", "intellectualProperty", "dispute", "unknown"
    ]

    func build(
        documentText: String,
        structure: AIConnectorDocumentStructure
    ) -> AIConnectorDocumentContextProfile {
        let documentTypes = documentTypeFacts(documentText: documentText, structure: structure)
        let domains = domainFacts(documentText: documentText, structure: structure)
        let parties = factList(
            category: "party",
            values: matches(
                pattern: #"(?i)(?:selanjutnya\s+disebut|disebut\s+sebagai|disebut)\s+[“"]?([^”"\n,.;]{2,80})[”"]?"#,
                in: documentText,
                captureGroup: 1
            ) + matches(
                pattern: #"\b(?:Pihak\s+(?:Pertama|Kedua|Ketiga)|Para\s+Pihak|Borrower|Lender)\b"#,
                in: documentText
            ),
            documentText: documentText,
            structure: structure,
            confidence: .explicit
        )
        let definedTerms = factList(
            category: "defined-term",
            values: matches(
                pattern: #"["“]([^"”\n]{2,100})["”]\s+(?:(?:adalah|berarti|merupakan|didefinisikan\s+sebagai))"#,
                in: documentText,
                captureGroup: 1
            ) + matches(
                pattern: #"(?i)(?:yang\s+)?selanjutnya\s+disebut\s+[“"]([^”"]+)[”"]"#,
                in: documentText,
                captureGroup: 1
            ) + matches(
                pattern: #"["“]([^"”\n]{2,100})["”]\s+(?:atau|(?:yang\s+)?selanjutnya\s+disebut)\s+["“]([^"”\n]{2,100})["”]"#,
                in: documentText,
                captureGroup: 1
            ) + matches(
                pattern: #"["“]([^"”\n]{2,100})["”]\s+(?:atau|(?:yang\s+)?selanjutnya\s+disebut)\s+["“]([^"”\n]{2,100})["”]"#,
                in: documentText,
                captureGroup: 2
            ),
            documentText: documentText,
            structure: structure,
            confidence: .explicit
        )
        let regulations = factList(
            category: "regulation",
            values: matches(
                pattern: #"(?i)\b(?:UU|PP|Peraturan|Permen|Perpres|Kepmen|KUHPerdata|KUHP)\s*(?:No\.?\s*)?[0-9A-Za-z./ -]{0,60}"#,
                in: documentText
            ),
            documentText: documentText,
            structure: structure,
            confidence: .explicit
        )
        let dates = factList(
            category: "effective-date",
            values: matches(
                pattern: #"\b(?:[0-3]?\d\s+)?(?:Januari|Februari|Maret|April|Mei|Juni|Juli|Agustus|September|Oktober|November|Desember)\s+\d{4}\b"#,
                in: documentText
            ) + matches(
                pattern: #"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b"#,
                in: documentText
            ),
            documentText: documentText,
            structure: structure,
            confidence: .explicit
        )
        let currencies = factList(
            category: "currency",
            values: matches(
                pattern: #"(?i)\b(?:Rp\.?|IDR|USD|EUR|SGD|dolar|rupiah)\b"#,
                in: documentText
            ),
            documentText: documentText,
            structure: structure,
            confidence: .explicit
        )
        let jurisdictions = factList(
            category: "jurisdiction",
            values: matches(
                pattern: #"(?i)\b(?:hukum|jurisdiksi|pengadilan)\s+(?:di\s+)?(?:Republik\s+)?Indonesia\b|\bRepublik\s+Indonesia\b"#,
                in: documentText
            ),
            documentText: documentText,
            structure: structure,
            confidence: .explicit
        )

        let fingerprint = DocumentFingerprinting.contentSHA256(documentText)
        let needsClassification = documentTypes.filter { $0.value != "unknown" }.count != 1
            || domains.filter { $0.value != "unknown" }.isEmpty
        return AIConnectorDocumentContextProfile(
            documentTypeCandidates: documentTypes,
            legalDomains: domains,
            parties: parties,
            definedTerms: definedTerms,
            jurisdictions: jurisdictions,
            regulationReferences: regulations,
            effectiveDates: dates,
            currencies: currencies,
            sectionOutline: structure.sections,
            coverage: AIConnectorContextCoverage(
                totalUTF16Length: documentText.utf16.count,
                sampledUTF16Length: 0,
                sampledSectionIDs: [],
                evidenceIDs: []
            ),
            classificationStatus: needsClassification ? .required : .notRequired,
            sourceFingerprint: fingerprint,
            structureFingerprint: structure.fingerprint,
            extractorVersion: SelfProfileVersions.extractor,
            classifierVersion: SelfProfileVersions.classifier,
            modelCallCount: 0,
            classificationDuration: 0
        )
    }

    func context(
        for block: AIConnectorDocumentBlock,
        structure: AIConnectorDocumentStructure,
        profile: AIConnectorDocumentContextProfile
    ) -> AIConnectorSegmentContext {
        let sectionFacts: ([AIConnectorContextFact]) -> [String] = { facts in
            facts.filter { fact in
                fact.sectionID == block.parentSectionID
                    || fact.evidenceRanges.contains { NSIntersectionRange($0, block.sourceRange).length > 0 }
            }.map(\.value)
        }
        let terms = profile.definedTerms.filter {
            block.text.localizedCaseInsensitiveContains($0.value)
        }.map(\.value)
        let parentClause = block.previousBlockID
            .flatMap(structure.block(for:))
            .flatMap { previous in
                previous.parentSectionID == block.parentSectionID
                    && (previous.kind == .numberedClause || previous.numberingLabel != nil)
                    ? previous.text
                    : nil
            }
        return AIConnectorSegmentContext(
            sectionID: block.parentSectionID,
            headingPath: block.headingPath,
            parentClause: parentClause,
            relevantDefinedTerms: terms,
            relevantParties: sectionFacts(profile.parties),
            sectionRegulationReferences: sectionFacts(profile.regulationReferences),
            documentTypeCandidates: profile.documentTypeCandidates.map(\.value),
            legalDomainCandidates: profile.legalDomains.map(\.value),
            profileFingerprint: profile.fingerprint,
            structureFingerprint: profile.structureFingerprint
        )
    }

    private func documentTypeFacts(
        documentText: String,
        structure: AIConnectorDocumentStructure
    ) -> [AIConnectorContextFact] {
        let rules: [(String, [String])] = [
            ("NDA", ["non-disclosure", "non disclosure", "kerahasiaan", "perjanjian kerahasiaan"]),
            ("DPA", ["data processing agreement", "data pribadi", "pelindungan data"]),
            ("MSA", ["master services agreement", "master service agreement"]),
            ("services", ["perjanjian jasa", "jasa layanan", "service agreement"]),
            ("employment", ["perjanjian kerja", "ketenagakerjaan", "employment agreement"]),
            ("loan", ["perjanjian pinjaman", "kredit", "loan agreement"]),
            ("salePurchase", ["jual beli", "sale and purchase", "purchase agreement"])
        ]
        var facts: [AIConnectorContextFact] = []
        for section in structure.sections {
            let title = section.title.lowercased()
            for (value, signals) in rules where signals.contains(where: title.contains) {
                facts.append(
                    makeFact(
                        category: "document-type",
                        value: value,
                        range: structure.block(for: section.headingBlockID)?.sourceRange ?? section.sourceRange,
                        documentText: documentText,
                        structure: structure,
                        confidence: .explicit
                    )
                )
            }
        }
        if facts.isEmpty {
            for (value, signals) in rules {
                guard let match = firstMatch(
                    signals: signals,
                    in: documentText
                ) else { continue }
                facts.append(
                    makeFact(
                        category: "document-type",
                        value: value,
                        range: match,
                        documentText: documentText,
                        structure: structure,
                        confidence: .inferred
                    )
                )
            }
        }
        return uniqueFacts(facts, fallbackValue: "unknown", category: "document-type")
    }

    private func domainFacts(
        documentText: String,
        structure: AIConnectorDocumentStructure
    ) -> [AIConnectorContextFact] {
        let rules: [(String, [String])] = [
            ("privacy", ["data pribadi", "pelindungan data", "privasi", "data processing"]),
            ("employment", ["ketenagakerjaan", "karyawan", "perjanjian kerja", "upah"]),
            ("finance", ["pinjaman", "kredit", "bunga", "jaminan"]),
            ("intellectualProperty", ["hak cipta", "merek", "paten", "kekayaan intelektual"]),
            ("dispute", ["sengketa", "arbitrase", "gugatan", "pengadilan"]),
            ("commercial", ["perjanjian", "jasa", "jual beli", "kerja sama"])
        ]
        var facts: [AIConnectorContextFact] = []
        for (value, signals) in rules {
            guard let match = firstMatch(signals: signals, in: documentText) else { continue }
            let explicit = structure.sections.contains {
                $0.title.range(of: signals.joined(separator: "|"), options: [.regularExpression, .caseInsensitive]) != nil
            }
            facts.append(
                makeFact(
                    category: "domain",
                    value: value,
                    range: match,
                    documentText: documentText,
                    structure: structure,
                    confidence: explicit ? .explicit : .inferred
                )
            )
        }
        return uniqueFacts(facts, fallbackValue: "unknown", category: "domain")
    }

    private func factList(
        category: String,
        values: [String],
        documentText: String,
        structure: AIConnectorDocumentStructure,
        confidence: AIConnectorDocumentContextConfidence
    ) -> [AIConnectorContextFact] {
        var facts: [AIConnectorContextFact] = []
        var used = Set<String>()
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.utf16.count >= 2,
                  used.insert(normalized.lowercased()).inserted,
                  let range = firstRange(of: normalized, in: documentText) else {
                continue
            }
            facts.append(
                makeFact(
                    category: category,
                    value: normalized,
                    range: range,
                    documentText: documentText,
                    structure: structure,
                    confidence: confidence
                )
            )
        }
        return facts
    }

    private func uniqueFacts(
        _ facts: [AIConnectorContextFact],
        fallbackValue: String,
        category: String
    ) -> [AIConnectorContextFact] {
        var result: [AIConnectorContextFact] = []
        var seen = Set<String>()
        for fact in facts where seen.insert(fact.value.lowercased()).inserted {
            result.append(fact)
        }
        if result.isEmpty {
            result.append(
                AIConnectorContextFact(
                    id: "\(category)-unknown",
                    value: fallbackValue,
                    confidence: .unknown
                )
            )
        }
        return result
    }

    private func makeFact(
        category: String,
        value: String,
        range: NSRange,
        documentText: String,
        structure: AIConnectorDocumentStructure,
        confidence: AIConnectorDocumentContextConfidence
    ) -> AIConnectorContextFact {
        let section = structure.sections.last {
            NSIntersectionRange($0.sourceRange, range).length > 0
        }
        let material = "\(category)|\(value)|\(range.location)|\(range.length)"
        let digest = SHA256.hash(data: Data(material.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        _ = documentText
        return AIConnectorContextFact(
            id: "\(category)-\(digest)",
            value: value,
            confidence: confidence,
            evidenceRanges: [range],
            sectionID: section?.id
        )
    }

    private func matches(
        pattern: String,
        in text: String,
        captureGroup: Int? = nil
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            let resultRange = match.range(at: captureGroup ?? 0)
            guard resultRange.location != NSNotFound,
                  let swiftRange = Range(resultRange, in: text) else { return nil }
            return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func firstRange(of value: String, in text: String) -> NSRange? {
        let range = (text as NSString).range(of: value, options: .caseInsensitive)
        return range.location == NSNotFound ? nil : range
    }

    private func firstMatch(signals: [String], in text: String) -> NSRange? {
        signals.compactMap { firstRange(of: $0, in: text) }
            .sorted { $0.location < $1.location }
            .first
    }

    private enum SelfProfileVersions {
        static let extractor = AIConnectorDocumentContextProfile.extractorVersion
        static let classifier = AIConnectorDocumentContextProfile.classifierVersion
    }
}
