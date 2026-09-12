import Foundation

/// Performs the document-wide checks introduced in Phase 5. The detector is
/// deliberately conservative: an isolated modal word is not a finding. A
/// risk annotation requires a concrete relationship between source spans.
@MainActor
struct AIConnectorDocumentReviewDetector {
    typealias RiskReviewer = @MainActor @Sendable (
        AIConnectorRiskReviewRequest
    ) async throws -> AIConnectorRiskReviewResult

    static let version = "phase5-document-review-v1"
    static let promptVersion = "phase5-risk-review-v1"
    static let maximumModelCandidates = 8

    private struct TermDeclaration {
        let term: String
        let normalized: String
        let termRange: NSRange
        let body: String
        let bodyRange: NSRange?
        let sectionID: String?
        let aliasOf: String?
    }

    private struct InternalTarget {
        let label: String
        let range: NSRange
        let sectionID: String?
    }

    private struct Clause {
        let range: NSRange
        let text: String
        let sectionID: String?
        let party: String
        let action: String
        let object: String
        let polarity: String
        let condition: String
        let hasUnilateralNoNotice: Bool
    }

    private let contextBuilder = AIConnectorDocumentContextProfileBuilder()

    func analyze(
        documentText: String,
        structure: AIConnectorDocumentStructure,
        profile: AIConnectorDocumentContextProfile,
        mode: AIConnectorReviewMode,
        modelVariant: AIConnectorModelVariant,
        riskReviewer: RiskReviewer? = nil
    ) async -> AIConnectorDocumentReviewResult {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let local = localFindings(
            documentText: documentText,
            structure: structure,
            profile: profile
        )

        var findings = local.findings
        var modelCallCount = 0
        var fallbackCount = 0
        var riskReviewDuration: TimeInterval = 0
        var wasCancelled = false

        let candidates = findings
            .filter { $0.requiresModelReview }
            .sorted { lhs, rhs in
                let left = candidatePriority(lhs)
                let right = candidatePriority(rhs)
                if left != right { return left < right }
                if lhs.sourceRange.location != rhs.sourceRange.location {
                    return lhs.sourceRange.location < rhs.sourceRange.location
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        if mode.usesModel {
            for candidate in candidates.prefix(Self.maximumModelCandidates) {
                do {
                    try Task.checkCancellation()
                    guard let riskReviewer else {
                        fallbackCount += 1
                        findings = replace(candidate, in: findings, with: candidate.withReview(
                            origin: .deterministicFallback,
                            disposition: .uncertain
                        ))
                        continue
                    }
                    let block = structure.blocks.first {
                        NSLocationInRange(candidate.sourceRange.location, $0.sourceRange)
                            || NSIntersectionRange($0.sourceRange, candidate.sourceRange).length > 0
                    }
                    let context = block.map {
                        contextBuilder.context(for: $0, structure: structure, profile: profile)
                    }
                    let request = AIConnectorRiskReviewRequest(
                        candidateID: candidate.candidateID ?? candidate.id.uuidString,
                        ruleID: candidate.ruleID,
                        kind: candidate.kind,
                        targetText: candidate.original,
                        evidence: candidate.relatedEvidence,
                        context: context,
                        modelVariant: modelVariant
                    )
                    let reviewStartedAt = clock.now
                    modelCallCount += 1
                    let result: AIConnectorRiskReviewResult
                    do {
                        result = try await riskReviewer(request)
                    } catch {
                        riskReviewDuration += AIConnectorObservationTiming.seconds(
                            reviewStartedAt.duration(to: clock.now)
                        )
                        throw error
                    }
                    riskReviewDuration += AIConnectorObservationTiming.seconds(
                        reviewStartedAt.duration(to: clock.now)
                    )
                    guard result.candidateID == request.candidateID else {
                        throw QwenSuggestionError.contextClassificationInvalid
                    }
                    switch result.decision {
                    case .flag:
                        findings = replace(candidate, in: findings, with: candidate.withReview(
                            origin: .qwen,
                            disposition: .flagged
                        ))
                    case .dismiss:
                        findings.removeAll { $0.id == candidate.id }
                    case .uncertain:
                        findings = replace(candidate, in: findings, with: candidate.withReview(
                            origin: .deterministicFallback,
                            disposition: .uncertain
                        ))
                        fallbackCount += 1
                    }
                } catch is CancellationError {
                    wasCancelled = true
                    break
                } catch {
                    fallbackCount += 1
                    findings = replace(candidate, in: findings, with: candidate.withReview(
                        origin: .deterministicFallback,
                        disposition: .uncertain
                    ))
                }
            }
        }

        if candidates.count > Self.maximumModelCandidates {
            fallbackCount += candidates.count - Self.maximumModelCandidates
            for candidate in candidates.dropFirst(Self.maximumModelCandidates) {
                findings = replace(candidate, in: findings, with: candidate.withReview(
                    origin: .deterministicFallback,
                    disposition: .uncertain
                ))
            }
        }

        let duration = AIConnectorObservationTiming.seconds(
            startedAt.duration(to: clock.now)
        )
        let metrics = AIConnectorDocumentReviewMetrics(
            findingCount: findings.count,
            definedTermFindingCount: findings.filter { $0.kind == .definedTerm }.count,
            legalRiskFindingCount: findings.filter { $0.kind == .legalRisk }.count,
            internalReferenceFindingCount: findings.filter { $0.kind == .internalReference }.count,
            riskCandidateCount: candidates.count,
            riskModelCallCount: modelCallCount,
            riskFallbackCount: max(fallbackCount, 0),
            riskReviewDuration: riskReviewDuration,
            duration: duration,
            wasCancelled: wasCancelled
        )
        return AIConnectorDocumentReviewResult(
            findings: findings.sorted(by: sourceOrder),
            metrics: metrics
        )
    }

    private func localFindings(
        documentText: String,
        structure: AIConnectorDocumentStructure,
        profile: AIConnectorDocumentContextProfile
    ) -> (findings: [AIConnectorDocumentFinding], declarations: [TermDeclaration]) {
        let declarations = extractDeclarations(documentText: documentText, structure: structure)
        var findings = definedTermFindings(
            documentText: documentText,
            structure: structure,
            declarations: declarations
        )
        findings.append(contentsOf: internalReferenceFindings(
            documentText: documentText,
            structure: structure
        ))
        findings.append(contentsOf: riskFindings(
            documentText: documentText,
            structure: structure,
            profile: profile
        ))
        return (uniqueFindings(findings), declarations)
    }

    private func extractDeclarations(
        documentText: String,
        structure: AIConnectorDocumentStructure
    ) -> [TermDeclaration] {
        var declarations: [TermDeclaration] = []
        let explicitPattern = #"["“]([^"”\n]{2,100})["”]\s+(?:adalah|berarti|merupakan|didefinisikan\s+sebagai)\b"#
        for match in regexMatches(explicitPattern, in: documentText, captureGroup: 1) {
            let term = match.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty,
                  let full = match.fullRange,
                  let bodyRange = sentenceBodyRange(after: full, in: documentText) else {
                continue
            }
            let body = (documentText as NSString).substring(with: bodyRange)
            declarations.append(
                TermDeclaration(
                    term: term,
                    normalized: normalize(term),
                    termRange: match.range,
                    body: body,
                    bodyRange: bodyRange,
                    sectionID: sectionID(at: match.range.location, structure: structure),
                    aliasOf: nil
                )
            )
        }

        let calledPattern = #"(?i)(?:yang\s+)?selanjutnya\s+disebut\s+["“]([^"”\n]{2,100})["”]"#
        for match in regexMatches(calledPattern, in: documentText, captureGroup: 1) {
            let term = match.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            declarations.append(
                TermDeclaration(
                    term: term,
                    normalized: normalize(term),
                    termRange: match.range,
                    body: "",
                    bodyRange: match.fullRange,
                    sectionID: sectionID(at: match.range.location, structure: structure),
                    aliasOf: nil
                )
            )
        }

        let aliasPattern = #"["“]([^"”\n]{2,100})["”]\s+(?:atau|(?:yang\s+)?selanjutnya\s+disebut)\s+["“]([^"”\n]{2,100})["”]"#
        for match in regexMatches(aliasPattern, in: documentText, captureGroup: 1) {
            guard let canonicalRange = match.fullRange else { continue }
            guard let aliasRange = captureRange(
                of: canonicalRange,
                captureGroup: 2,
                pattern: aliasPattern,
                in: documentText
            ) else { continue }
            let canonical = match.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let alias = (documentText as NSString).substring(with: aliasRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !declarations.contains(where: {
                $0.normalized == normalize(canonical) && $0.aliasOf == nil
            }) {
                declarations.append(
                    TermDeclaration(
                        term: canonical,
                        normalized: normalize(canonical),
                        termRange: match.range,
                        body: "",
                        bodyRange: canonicalRange,
                        sectionID: sectionID(at: match.range.location, structure: structure),
                        aliasOf: nil
                    )
                )
            }
            if !declarations.contains(where: {
                $0.normalized == normalize(alias) && $0.aliasOf != nil
            }) {
                // The standalone “selanjutnya disebut” pass sees the alias
                // before this paired pattern. Replace that provisional
                // declaration with the explicit canonical mapping.
                declarations.removeAll {
                    $0.normalized == normalize(alias) && $0.termRange == aliasRange
                }
                declarations.append(
                    TermDeclaration(
                        term: alias,
                        normalized: normalize(alias),
                        termRange: aliasRange,
                        body: "",
                        bodyRange: canonicalRange,
                        sectionID: sectionID(at: aliasRange.location, structure: structure),
                        aliasOf: canonical
                    )
                )
            }
        }

        // A definition section may contain entries whose punctuation does not
        // match the sentence-level patterns above. It is still conservative:
        // only quoted terms are accepted, never capitalization alone.
        for block in structure.blocks where block.headingPath.contains(where: {
            $0.localizedCaseInsensitiveContains("definisi")
                || $0.localizedCaseInsensitiveContains("pengertian")
        }) {
            for match in regexMatches(#"["“]([^"”\n]{2,100})["”]"#, in: block.text, captureGroup: 1) {
                let term = match.value.trimmingCharacters(in: .whitespacesAndNewlines)
                let absoluteRange = NSRange(
                    location: block.sourceRange.location + match.range.location,
                    length: match.range.length
                )
                guard !declarations.contains(where: { $0.termRange == absoluteRange }) else {
                    continue
                }
                declarations.append(
                    TermDeclaration(
                        term: term,
                        normalized: normalize(term),
                        termRange: absoluteRange,
                        body: block.text,
                        bodyRange: block.sourceRange,
                        sectionID: block.parentSectionID,
                        aliasOf: nil
                    )
                )
            }
        }
        return declarations
    }

    private func definedTermFindings(
        documentText: String,
        structure: AIConnectorDocumentStructure,
        declarations: [TermDeclaration]
    ) -> [AIConnectorDocumentFinding] {
        var findings: [AIConnectorDocumentFinding] = []
        let grouped = Dictionary(grouping: declarations, by: \ .normalized)

        for declarationsForTerm in grouped.values {
            guard let first = declarationsForTerm.first else { continue }
            if declarationsForTerm.count > 1 {
                let bodies = Set(declarationsForTerm.map { normalize($0.body) }.filter { !$0.isEmpty })
                let related = declarationsForTerm.dropFirst().map { declaration in
                    evidence(
                        id: "declaration-\(declaration.termRange.location)",
                        range: declaration.termRange,
                        label: "Deklarasi istilah",
                        documentText: documentText,
                        sectionID: declaration.sectionID
                    )
                }
                let ruleID = bodies.count > 1
                    ? "defined-term-conflicting-definition"
                    : "defined-term-duplicate-definition"
                let title = bodies.count > 1
                    ? "Definisi istilah berpotensi bertentangan"
                    : "Deklarasi istilah berulang"
                let reason = bodies.count > 1
                    ? "Istilah \(first.term) memiliki lebih dari satu isi definisi; periksa deklarasi yang berlaku."
                    : "Istilah \(first.term) didefinisikan lebih dari sekali dengan isi yang sama."
                findings.append(makeFinding(
                    ruleID: ruleID,
                    kind: .definedTerm,
                    range: first.termRange,
                    original: substring(first.termRange, in: documentText),
                    title: title,
                    reason: reason,
                    documentText: documentText,
                    sectionID: first.sectionID,
                    requiresModelReview: bodies.count > 1,
                    evidence: related
                ))
            }

            for declaration in declarationsForTerm.dropFirst() {
                guard declaration.term != first.term else { continue }
                findings.append(makeFinding(
                    ruleID: "defined-term-case-inconsistency",
                    kind: .definedTerm,
                    range: declaration.termRange,
                    original: substring(declaration.termRange, in: documentText),
                    title: "Penulisan defined term tidak konsisten",
                    reason: "Penulisan istilah ini berbeda dari deklarasi defined term yang sudah ada.",
                    documentText: documentText,
                    sectionID: declaration.sectionID,
                    evidence: [evidence(
                        id: "canonical-\(first.termRange.location)",
                        range: first.termRange,
                        label: "Deklarasi awal",
                        documentText: documentText,
                        sectionID: first.sectionID
                    )]
                ))
            }
        }

        let declared = Set(declarations.map(\ .normalized))
        var aliases = Set<String>()
        aliases.formUnion(declarations.compactMap { $0.aliasOf }.map(normalize))
        for declaration in declarations where declaration.aliasOf != nil {
            aliases.insert(declaration.normalized)
        }

        // Case findings only attach to clear term usages. A normal language
        // word is never promoted to a defined term based on capitalization.
        for declaration in declarations {
            let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: declaration.term) + "\\b"
            for match in regexMatches(pattern, in: documentText) {
                guard match.range != declaration.termRange,
                      NSIntersectionRange(match.range, declaration.termRange).length == 0 else {
                    continue
                }
                let value = match.value
                guard value != declaration.term,
                      isClearDefinedTermUsage(
                        range: match.range,
                        value: value,
                        documentText: documentText,
                        knownTerm: declaration.term
                      ) else { continue }
                findings.append(makeFinding(
                    ruleID: "defined-term-case-inconsistency",
                    kind: .definedTerm,
                    range: match.range,
                    original: value,
                    title: "Penulisan defined term tidak konsisten",
                    reason: "Gunakan penulisan ‘\(declaration.term)’ agar istilah terdefinisi konsisten.",
                    documentText: documentText,
                    sectionID: sectionID(at: match.range.location, structure: structure),
                    evidence: [evidence(
                        id: "declaration-\(declaration.termRange.location)",
                        range: declaration.termRange,
                        label: "Deklarasi defined term",
                        documentText: documentText,
                        sectionID: declaration.sectionID
                    )]
                ))
            }
        }

        let quoted = regexMatches(#"["“]([^"”\n]{2,100})["”]"#, in: documentText, captureGroup: 1)
        for match in quoted {
            let value = match.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = normalize(value)
            guard !declared.contains(normalized),
                  !aliases.contains(normalized),
                  isContractTermUsage(
                    range: match.range,
                    value: value,
                    documentText: documentText
                  ) else { continue }
            findings.append(makeFinding(
                ruleID: "defined-term-undeclared-quoted-term",
                kind: .definedTerm,
                range: match.range,
                original: substring(match.range, in: documentText),
                title: "Istilah kontrak belum dideklarasikan",
                reason: "Istilah berpetik ini digunakan seperti defined term, tetapi deklarasinya tidak ditemukan pada dokumen.",
                documentText: documentText,
                sectionID: sectionID(at: match.range.location, structure: structure),
                disposition: .uncertain
            ))
        }
        return findings
    }

    private func internalReferenceFindings(
        documentText: String,
        structure: AIConnectorDocumentStructure
    ) -> [AIConnectorDocumentFinding] {
        let targets = internalTargets(documentText: documentText, structure: structure)
        var findings: [AIConnectorDocumentFinding] = []
        let references = regexMatches(
            #"(?i)\b(?:Pasal\s+[0-9]+[A-Za-z]?|Ayat\s+\([0-9]+\)|Lampiran\s+[A-Za-z0-9IVX.-]+|[0-9]+(?:\.[0-9]+)+|\([a-z]\))"#,
            in: documentText
        )
        for reference in references {
            let paragraph = enclosingBlock(for: reference.range, structure: structure)
            let paragraphText = paragraph.map { substring($0.sourceRange, in: documentText) } ?? ""
            if paragraphText.range(
                of: #"(?i)\b(?:UU|PP|Peraturan|Permen|Perpres|Kepmen|KUHPerdata|KUHP)\b"#,
                options: .regularExpression
            ) != nil {
                continue
            }
            let label = normalizeReferenceLabel(reference.value)
            let sameSection = targets.filter {
                normalizeReferenceLabel($0.label) == label
                    && $0.sectionID == paragraph?.parentSectionID
            }
            let matches = sameSection.isEmpty
                ? targets.filter { normalizeReferenceLabel($0.label) == label }
                : sameSection
            if matches.count == 1 { continue }

            let isMissing = matches.isEmpty
            let title = isMissing ? "Rujukan internal tidak ditemukan" : "Rujukan internal ambigu"
            let reason = isMissing
                ? "Rujukan \(reference.value) tidak ditemukan pada dokumen yang diperiksa."
                : "Rujukan \(reference.value) memiliki lebih dari satu target yang mungkin."
            findings.append(makeFinding(
                ruleID: isMissing ? "internal-reference-missing" : "internal-reference-ambiguous",
                kind: .internalReference,
                range: reference.range,
                original: substring(reference.range, in: documentText),
                title: title,
                reason: reason,
                documentText: documentText,
                sectionID: paragraph?.parentSectionID,
                disposition: .uncertain,
                evidence: matches.map {
                    evidence(
                        id: "target-\($0.range.location)",
                        range: $0.range,
                        label: "Target rujukan",
                        documentText: documentText,
                        sectionID: $0.sectionID
                    )
                }
            ))
        }
        return findings
    }

    private func riskFindings(
        documentText: String,
        structure: AIConnectorDocumentStructure,
        profile: AIConnectorDocumentContextProfile
    ) -> [AIConnectorDocumentFinding] {
        let clauses = makeClauses(documentText: documentText, structure: structure, profile: profile)
        var findings: [AIConnectorDocumentFinding] = []
        var pairKeys = Set<String>()

        for clause in clauses {
            if clause.hasUnilateralNoNotice {
                findings.append(makeFinding(
                    ruleID: "legal-risk-unilateral-termination-no-notice",
                    kind: .legalRisk,
                    range: clause.range,
                    original: clause.text,
                    title: "Pengakhiran sepihak tanpa pemberitahuan",
                    reason: "Klausul menggabungkan hak penghentian sepihak dengan frasa ‘tanpa pemberitahuan’; periksa bukti dan konteks klausulnya.",
                    documentText: documentText,
                    sectionID: clause.sectionID
                ))
            }

            if hasDanglingCondition(clause.text) {
                findings.append(makeFinding(
                    ruleID: "legal-risk-dangling-condition",
                    kind: .legalRisk,
                    range: clause.range,
                    original: clause.text,
                    title: "Kondisi atau pengecualian belum lengkap",
                    reason: "Penanda kondisi/pengecualian muncul tanpa isi yang dapat diperiksa setelahnya.",
                    documentText: documentText,
                    sectionID: clause.sectionID
                ))
            }
        }

        let grouped = Dictionary(grouping: clauses.filter {
            !$0.party.isEmpty && !$0.action.isEmpty && !$0.object.isEmpty
        }) { clause in
            "\(normalize(clause.party))|\(normalize(clause.action))|\(normalize(clause.object))"
        }
        for group in grouped.values where group.count > 1 {
            for index in group.indices {
                for otherIndex in group.indices where otherIndex > index {
                    let first = group[index]
                    let second = group[otherIndex]
                    let key = "\(first.range.location)|\(second.range.location)"
                    guard pairKeys.insert(key).inserted else { continue }
                    if first.polarity != second.polarity {
                        findings.append(makeFinding(
                            ruleID: "legal-risk-modal-negation-conflict",
                            kind: .legalRisk,
                            range: second.range,
                            original: second.text,
                            title: "Modalitas atau negasi tampak bertentangan",
                            reason: "Klausul dengan pihak, tindakan, dan objek yang sama memakai modalitas/negasi yang berlawanan.",
                            documentText: documentText,
                            sectionID: second.sectionID,
                            requiresModelReview: true,
                            evidence: [evidence(
                                id: "clause-\(first.range.location)",
                                range: first.range,
                                label: "Klausul terkait",
                                documentText: documentText,
                                sectionID: first.sectionID
                            )]
                        ))
                    } else if !first.condition.isEmpty,
                              !second.condition.isEmpty,
                              normalize(first.condition) != normalize(second.condition),
                              !isExplainedException(second.text) {
                        findings.append(makeFinding(
                            ruleID: "legal-risk-condition-exception-conflict",
                            kind: .legalRisk,
                            range: second.range,
                            original: second.text,
                            title: "Kondisi atau pengecualian berbeda",
                            reason: "Dua klausul yang tampak mengatur tindakan yang sama memiliki kondisi/pengecualian berbeda.",
                            documentText: documentText,
                            sectionID: second.sectionID,
                            requiresModelReview: true,
                            evidence: [evidence(
                                id: "clause-\(first.range.location)",
                                range: first.range,
                                label: "Klausul pembanding",
                                documentText: documentText,
                                sectionID: first.sectionID
                            )]
                        ))
                    }
                }
            }
        }
        return findings
    }

    private func makeClauses(
        documentText: String,
        structure: AIConnectorDocumentStructure,
        profile: AIConnectorDocumentContextProfile
    ) -> [Clause] {
        var clauses: [Clause] = []
        documentText.enumerateSubstrings(
            in: documentText.startIndex..<documentText.endIndex,
            options: [.bySentences, .substringNotRequired]
        ) { _, substringRange, _, _ in
            let rawRange = NSRange(substringRange, in: documentText)
            let text = substring(rawRange, in: documentText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let trimStart = text.utf16.count - text.drop(while: { $0.isWhitespace }).utf16.count
            let trimmedRange = NSRange(
                location: rawRange.location + max(0, trimStart),
                length: text.utf16.count
            )
            let party = firstParty(in: text, profile: profile)
            let action = firstMatchValue(
                #"(?i)\b(?:wajib|harus|dapat|berhak|dilarang|mengakhiri|menghentikan|melakukan|memberikan|membayar|menyampaikan|mengungkapkan|menggunakan|menjaga|memastikan)\b"#,
                in: text
            ) ?? ""
            let object = objectAfterAction(text: text, action: action)
            let polarity = polarity(of: text)
            let condition = conditionPart(of: text)
            let hasTermination = text.range(
                of: #"(?i)\b(?:mengakhiri|menghentikan|pemutusan|terminasi)\b"#,
                options: .regularExpression
            ) != nil
            let hasNoNotice = text.range(
                of: #"(?i)\btanpa\s+pemberitahuan\b"#,
                options: .regularExpression
            ) != nil
            clauses.append(
                Clause(
                    range: trimmedRange,
                    text: substring(trimmedRange, in: documentText),
                    sectionID: sectionID(at: trimmedRange.location, structure: structure),
                    party: party,
                    action: action,
                    object: object,
                    polarity: polarity,
                    condition: condition,
                    hasUnilateralNoNotice: hasTermination && hasNoNotice
                )
            )
        }
        return clauses
    }

    private func internalTargets(
        documentText: String,
        structure: AIConnectorDocumentStructure
    ) -> [InternalTarget] {
        var result: [InternalTarget] = []
        for block in structure.blocks {
            // A reference inside a paragraph is not itself a target. Only a
            // structural heading/numbered-clause label may create an index
            // entry; this prevents `Pasal 99` in “mengacu pada Pasal 99” from
            // making the missing target appear to exist.
            let leadingPatterns: [String]
            switch block.kind {
            case .heading:
                leadingPatterns = [
                    #"(?i)^\s*(Pasal\s+[0-9]+[A-Za-z]?)\b"#,
                    #"(?i)^\s*(Lampiran\s+[A-Za-z0-9IVX.-]+)\b"#
                ]
            case .numberedClause, .listItem:
                leadingPatterns = [
                    #"^\s*(?:Pasal\s+)?[0-9]+(?:\.[0-9]+)*\b"#,
                    #"^\s*(\([a-z]\))"#
                ]
            default:
                leadingPatterns = []
            }

            for pattern in leadingPatterns {
                guard let candidate = regexMatches(pattern, in: block.text).first else {
                    continue
                }
                result.append(
                    InternalTarget(
                        label: candidate.value,
                        range: NSRange(
                            location: block.sourceRange.location + candidate.range.location,
                            length: candidate.range.length
                        ),
                        sectionID: block.parentSectionID
                    )
                )
                break
            }
        }
        return result
    }

    private func makeFinding(
        ruleID: String,
        kind: AIConnectorDocumentFindingKind,
        range: NSRange,
        original: String,
        title: String,
        reason: String,
        documentText: String,
        sectionID: String?,
        disposition: AIConnectorDocumentFindingDisposition = .flagged,
        requiresModelReview: Bool = false,
        evidence: [AIConnectorFindingEvidence] = []
    ) -> AIConnectorDocumentFinding {
        let candidateID = requiresModelReview
            ? "phase5-\(ruleID)-\(range.location)"
            : nil
        let material = "\(ruleID)|\(range.location)|\(range.length)|\(original)"
        return AIConnectorDocumentFinding(
            id: AIConnectorDocumentFinding.stableID(material),
            ruleID: ruleID,
            kind: kind,
            sourceRange: range,
            original: original,
            title: title,
            reason: reason,
            origin: .deterministic,
            disposition: disposition,
            requiresModelReview: requiresModelReview,
            candidateID: candidateID,
            sectionID: sectionID,
            relatedEvidence: evidence
        )
    }

    private func evidence(
        id: String,
        range: NSRange,
        label: String,
        documentText: String,
        sectionID: String?
    ) -> AIConnectorFindingEvidence {
        AIConnectorFindingEvidence(
            id: id,
            sourceRange: range,
            original: substring(range, in: documentText),
            label: label,
            sectionID: sectionID
        )
    }

    private func replace(
        _ finding: AIConnectorDocumentFinding,
        in findings: [AIConnectorDocumentFinding],
        with replacement: AIConnectorDocumentFinding
    ) -> [AIConnectorDocumentFinding] {
        findings.map { $0.id == finding.id ? replacement : $0 }
    }

    private func uniqueFindings(
        _ findings: [AIConnectorDocumentFinding]
    ) -> [AIConnectorDocumentFinding] {
        var seen = Set<UUID>()
        return findings.filter { seen.insert($0.id).inserted }
    }

    private func candidatePriority(_ finding: AIConnectorDocumentFinding) -> Int {
        switch finding.ruleID {
        case "defined-term-conflicting-definition": return 0
        case "legal-risk-modal-negation-conflict": return 1
        case "legal-risk-condition-exception-conflict": return 2
        case "legal-risk-unilateral-termination-no-notice": return 3
        default: return 4
        }
    }

    private func sourceOrder(
        _ lhs: AIConnectorDocumentFinding,
        _ rhs: AIConnectorDocumentFinding
    ) -> Bool {
        if lhs.sourceRange.location != rhs.sourceRange.location {
            return lhs.sourceRange.location < rhs.sourceRange.location
        }
        if lhs.sourceRange.length != rhs.sourceRange.length {
            return lhs.sourceRange.length < rhs.sourceRange.length
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func sectionID(
        at location: Int,
        structure: AIConnectorDocumentStructure
    ) -> String? {
        structure.blocks.first {
            location >= $0.sourceRange.location
                && location < NSMaxRange($0.sourceRange)
        }?.parentSectionID
    }

    private func enclosingBlock(
        for range: NSRange,
        structure: AIConnectorDocumentStructure
    ) -> AIConnectorDocumentBlock? {
        structure.blocks.first {
            NSIntersectionRange($0.sourceRange, range).length > 0
        }
    }

    private func sentenceBodyRange(after fullRange: NSRange, in text: String) -> NSRange? {
        let nsText = text as NSString
        let end = min(nsText.length, NSMaxRange(fullRange) + 1)
        guard end < nsText.length else { return nil }
        var cursor = end
        while cursor < nsText.length, nsText.character(at: cursor).isWhitespaceASCII {
            cursor += 1
        }
        let start = cursor
        while cursor < nsText.length {
            let character = nsText.character(at: cursor)
            if character == 46 || character == 10 || character == 13 || character == 59 {
                break
            }
            cursor += 1
        }
        guard cursor > start else { return nil }
        return NSRange(location: start, length: cursor - start)
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .joined(separator: " ")
            .lowercased()
    }

    private func normalizeReferenceLabel(_ value: String) -> String {
        normalize(value)
            .replacingOccurrences(of: "pasal ", with: "pasal ")
    }

    private func substring(_ range: NSRange, in text: String) -> String {
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= text.utf16.count else { return "" }
        return (text as NSString).substring(with: range)
    }

    private func regexMatches(
        _ pattern: String,
        in text: String,
        captureGroup: Int? = nil
    ) -> [(value: String, range: NSRange, fullRange: NSRange?)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fullTextRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: fullTextRange).compactMap { match in
            let range = match.range(at: captureGroup ?? 0)
            guard range.location != NSNotFound else { return nil }
            return (
                value: substring(range, in: text),
                range: range,
                fullRange: captureGroup == nil ? range : match.range
            )
        }
    }

    private func captureRange(
        of fullRange: NSRange?,
        captureGroup: Int,
        pattern: String,
        in text: String
    ) -> NSRange? {
        guard let fullRange,
              let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: fullRange),
              match.range(at: captureGroup).location != NSNotFound else {
            return nil
        }
        return match.range(at: captureGroup)
    }

    private func firstMatchValue(_ pattern: String, in text: String) -> String? {
        regexMatches(pattern, in: text).first?.value
    }

    private func firstParty(
        in text: String,
        profile: AIConnectorDocumentContextProfile
    ) -> String {
        profile.parties.first {
            text.range(of: $0.value, options: .caseInsensitive) != nil
        }?.value
            ?? firstMatchValue(
                #"(?i)\b(?:Pihak\s+(?:Pertama|Kedua|Ketiga)|Para\s+Pihak|Pihak\s+[A-Z]|Perusahaan|Pemberi|Penerima)\b"#,
                in: text
            )
            ?? ""
    }

    private func objectAfterAction(text: String, action: String) -> String {
        guard !action.isEmpty,
              let range = text.range(of: action, options: .caseInsensitive) else {
            return ""
        }
        let suffix = String(text[range.upperBound...])
        let cleaned = suffix
            .replacingOccurrences(
                of: #"(?i)^(?:\s+)?(?:wajib|harus|dapat|berhak|untuk|tidak|segera)\b\s*"#,
                with: "",
                options: .regularExpression
            )
            .split { $0.isWhitespace || $0.isPunctuation }
            .prefix(8)
            .joined(separator: " ")
        return normalize(cleaned)
    }

    private func polarity(of text: String) -> String {
        if text.range(of: #"(?i)\b(?:tidak|dilarang|tanpa)\b"#, options: .regularExpression) != nil {
            return "negative"
        }
        if text.range(of: #"(?i)\b(?:dapat|berhak|boleh)\b"#, options: .regularExpression) != nil {
            return "permission"
        }
        if text.range(of: #"(?i)\b(?:wajib|harus)\b"#, options: .regularExpression) != nil {
            return "mandatory"
        }
        return "neutral"
    }

    private func conditionPart(of text: String) -> String {
        firstMatchValue(
            #"(?i)\b(?:jika|apabila|dalam hal|kecuali|sepanjang|setelah|sebelum)\b.*$"#,
            in: text
        ) ?? ""
    }

    private func hasDanglingCondition(_ text: String) -> Bool {
        text.range(
            of: #"(?i)\b(?:jika|apabila|dalam hal|kecuali|sepanjang)\s*[,;:.!?]*$"#,
            options: .regularExpression
        ) != nil
    }

    private func isExplainedException(_ text: String) -> Bool {
        text.range(
            of: #"(?i)\bkecuali\b.{0,100}\b(?:Pasal|ayat|ketentuan)\b"#,
            options: .regularExpression
        ) != nil
    }

    private func containsAny(_ text: String, patterns: [String]) -> Bool {
        patterns.contains {
            text.range(of: $0, options: .regularExpression) != nil
        }
    }

    private func isClearDefinedTermUsage(
        range: NSRange,
        value: String,
        documentText: String,
        knownTerm: String
    ) -> Bool {
        let nsText = documentText as NSString
        let beforeStart = max(0, range.location - 40)
        let before = nsText.substring(with: NSRange(location: beforeStart, length: range.location - beforeStart))
        let afterEnd = min(nsText.length, NSMaxRange(range) + 40)
        let after = nsText.substring(with: NSRange(location: NSMaxRange(range), length: afterEnd - NSMaxRange(range)))
        let quoted = (before.last == "\"" || before.last == "“")
            || (after.first == "\"" || after.first == "”")
        let contextual = before.range(of: #"(?i)(disebut|istilah|sebagaimana|yang dimaksud)"#, options: .regularExpression) != nil
            || after.range(of: #"(?i)(tersebut|ini|dimaksud)"#, options: .regularExpression) != nil
        return quoted || contextual || value.first?.isUppercase == true
            || normalize(knownTerm).contains(" ")
    }

    private func isContractTermUsage(
        range: NSRange,
        value: String,
        documentText: String
    ) -> Bool {
        guard value.first?.isUppercase == true || value.range(of: #"(?i)\b(?:Pihak|Perjanjian|Informasi|Data)\b"#, options: .regularExpression) != nil else {
            return false
        }
        let nsText = documentText as NSString
        let beforeStart = max(0, range.location - 50)
        let before = nsText.substring(with: NSRange(location: beforeStart, length: range.location - beforeStart))
        let afterEnd = min(nsText.length, NSMaxRange(range) + 50)
        let after = nsText.substring(with: NSRange(location: NSMaxRange(range), length: afterEnd - NSMaxRange(range)))
        return before.range(of: #"(?i)(disebut|istilah|sebagaimana|yang dimaksud|didefinisikan)"#, options: .regularExpression) != nil
            || after.range(of: #"(?i)(tersebut|berikut|ini|dimaksud|wajib|dapat)"#, options: .regularExpression) != nil
            || value.split(separator: " ").count > 1
    }
}

private extension unichar {
    var isWhitespaceASCII: Bool {
        self == 9 || self == 10 || self == 13 || self == 32
    }
}
