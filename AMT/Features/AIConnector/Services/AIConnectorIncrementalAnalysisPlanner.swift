import CryptoKit
import Foundation

/// Computes a conservative dependency-aware plan for a new document revision.
/// The planner never decides whether a legal statement is correct; it only
/// decides which existing results are safe to carry to the new revision.
struct AIConnectorIncrementalAnalysisPlanner: Sendable {
    func makePlan(
        previous baseline: AIConnectorAnalysisBaseline?,
        documentText: String,
        structure: AIConnectorDocumentStructure,
        segmentation: AITextSegmentationResult,
        scope: AIConnectorAnalysisRunScope,
        selectedSectionID: String? = nil,
        currentAnalysisProfile: AIConnectorAnalysisProfile? = nil,
        currentProfile: AIConnectorDocumentContextProfile? = nil
    ) -> AIConnectorAnalysisPlan {
        guard scope != .fullFresh, let baseline else {
            return .full(
                scope: scope,
                documentText: documentText,
                segmentation: segmentation
            )
        }

        guard !baseline.structure.blocks.isEmpty,
              !structure.blocks.isEmpty,
              !baseline.segmentation.segments.isEmpty,
              !segmentation.segments.isEmpty else {
            return fullPlan(
                scope: scope,
                documentText: documentText,
                segmentation: segmentation,
                reason: .ambiguousMapping
            )
        }

        let diff = textDiff(
            old: baseline.documentText,
            new: documentText
        )
        let oldBlocks = changedBlocks(
            in: baseline.structure,
            ranges: diff.oldRanges
        )
        let newBlocks = changedBlocks(
            in: structure,
            ranges: diff.newRanges
        )
        let oldBlockIDs = Set(oldBlocks.map(\.id))
        let newBlockIDs = Set(newBlocks.map(\.id))
        let changedSections = Set(
            oldBlocks.compactMap(\.parentSectionID)
                + newBlocks.compactMap(\.parentSectionID)
        )

        var reasons = Set<AIConnectorAnalysisInvalidationReason>()
        if !diff.oldRanges.isEmpty || !diff.newRanges.isEmpty {
            reasons.insert(.editedSegment)
        }

        let changedText = changedText(
            oldText: baseline.documentText,
            newText: documentText,
            oldRanges: diff.oldRanges,
            newRanges: diff.newRanges
        )
        let allChangedBlocksText = (oldBlocks + newBlocks)
            .map(\.text)
            .joined(separator: "\n")
        let dependencyText = (changedText + "\n" + allChangedBlocksText)
            .lowercased()

        if oldBlocks.contains(where: { $0.kind == .heading })
            || newBlocks.contains(where: { $0.kind == .heading }) {
            reasons.insert(.headingChanged)
        }
        if looksLikeDefinitionDependency(dependencyText) {
            reasons.insert(.definitionDependency)
        }
        if looksLikePartyDependency(dependencyText) {
            reasons.insert(.partyDependency)
        }
        if looksLikeReferenceDependency(dependencyText) {
            reasons.insert(.referenceDependency)
        }

        if let currentAnalysisProfile {
            if baseline.analysisProfile.corpusVersion != currentAnalysisProfile.corpusVersion {
                reasons.insert(.corpusChanged)
            }
            if baseline.analysisProfile.pipelineVersion != currentAnalysisProfile.pipelineVersion
                || baseline.analysisProfile.semanticModelRevision != currentAnalysisProfile.semanticModelRevision
                || baseline.analysisProfile.semanticEmbeddingSchema != currentAnalysisProfile.semanticEmbeddingSchema
                || baseline.analysisProfile.semanticRetrievalProfile != currentAnalysisProfile.semanticRetrievalProfile {
                reasons.insert(.rulePackChanged)
            }
        }

        if let currentProfile,
           let previousProfile = baseline.profile,
           profileFactsChanged(previousProfile, currentProfile) {
            reasons.insert(.profileChanged)
        }

        let mappings = makeMappings(
            oldSegments: baseline.segmentation.segments,
            newSegments: segmentation.segments,
            oldStructure: baseline.structure,
            newStructure: structure
        )
        var isAmbiguous = mappings.isAmbiguous
        if mappings.mappings.isEmpty,
           diff.oldRanges.isEmpty,
           diff.newRanges.isEmpty,
           scope == .incrementalDocument {
            isAmbiguous = true
            reasons.insert(.ambiguousMapping)
        }

        var impactedSegmentIDs = Set<Int>()
        let blockIDsToInvalidate = newBlockIDs
        impactedSegmentIDs.formUnion(
            segmentation.segments.compactMap { segment in
                let block = block(for: segment, in: structure)
                guard let block, blockIDsToInvalidate.contains(block.id) else { return nil }
                return segment.id
            }
        )

        let dependencyNeedsExpansion = reasons.contains(.definitionDependency)
            || reasons.contains(.partyDependency)
            || reasons.contains(.referenceDependency)
            || reasons.contains(.profileChanged)
            || reasons.contains(.corpusChanged)
            || reasons.contains(.rulePackChanged)

        let selectedSections = selectedSectionIDs(
            scope: scope,
            selectedSectionID: selectedSectionID,
            structure: structure
        )
        if scope == .section, selectedSections.isEmpty {
            isAmbiguous = true
            reasons.insert(.ambiguousMapping)
        }

        var dependencySectionIDs = Set<String>()
        if dependencyNeedsExpansion {
            dependencySectionIDs = structure.sectionIDs
        } else {
            dependencySectionIDs = changedSections
        }

        if scope == .section {
            if dependencyNeedsExpansion {
                impactedSegmentIDs.formUnion(segmentation.segments.map(\.id))
            } else {
                impactedSegmentIDs.formUnion(
                    segmentation.segments.compactMap { segment in
                        let sectionID = sectionID(for: segment, in: structure)
                        return selectedSections.contains(sectionID) ? segment.id : nil
                    }
                )
            }
        } else if dependencyNeedsExpansion {
            impactedSegmentIDs.formUnion(segmentation.segments.map(\.id))
        }

        // A changed sentence invalidates its same-section neighbours because
        // they are supplied as context to retrieval and model review.
        let changedSectionForContext = Set<String>(
            impactedSegmentIDs.compactMap { id in
                guard let segment = segmentation.segments.first(where: { $0.id == id }) else {
                    return nil
                }
                return sectionID(for: segment, in: structure)
            }
        )
        for contextSectionID in changedSectionForContext {
            let sameSection = segmentation.segments.filter {
                sectionID(for: $0, in: structure) == contextSectionID
            }
            for segment in sameSection where impactedSegmentIDs.contains(segment.id) {
                if let index = sameSection.firstIndex(where: { $0.id == segment.id }) {
                    if index > sameSection.startIndex {
                        impactedSegmentIDs.insert(sameSection[index - 1].id)
                    }
                    if index + 1 < sameSection.count {
                        impactedSegmentIDs.insert(sameSection[index + 1].id)
                    }
                }
            }
        }

        let mappingPairs = mappings.mappings
        let mappedOldIDs = Set(mappingPairs.map(\.oldSegmentID))
        let currentIDs = Set(segmentation.segments.map(\.id))
        let oldIDs = Set(baseline.segmentation.segments.map(\.id))
        let reusable = Set(
            mappingPairs
                .map(\.newSegmentID)
                .filter { !impactedSegmentIDs.contains($0) }
        )
        var reprocess = currentIDs.subtracting(reusable)
        let removed = oldIDs.subtracting(mappedOldIDs)

        if isAmbiguous, !dependencySectionIDs.isEmpty {
            impactedSegmentIDs.formUnion(
                segmentation.segments.compactMap { segment in
                    dependencySectionIDs.contains(sectionID(for: segment, in: structure))
                        ? segment.id
                        : nil
                }
            )
        } else if isAmbiguous {
            // We can only use a full-document fallback when no section
            // boundary can be proven. If a section is known, its members are
            // invalidated conservatively and unrelated sections stay reusable.
            reprocess = currentIDs
        }

        if reasons.isEmpty {
            reasons.insert(.editedSegment)
        }

        let requiresProfileRebuild = dependencyNeedsExpansion
            || reasons.contains(.headingChanged)
            || reasons.contains(.profileChanged)
        let requiresDocumentReview = requiresProfileRebuild
            || reasons.contains(.referenceDependency)
            || reasons.contains(.partyDependency)
            || reasons.contains(.definitionDependency)

        let plan = AIConnectorAnalysisPlan(
            changeSet: AIConnectorAnalysisChangeSet(
                scope: scope,
                oldTextFingerprint: Self.sha256(baseline.documentText),
                newTextFingerprint: Self.sha256(documentText),
                changedOldRanges: diff.oldRanges,
                changedNewRanges: diff.newRanges,
                changedOldBlockIDs: oldBlockIDs,
                changedBlockIDs: newBlockIDs,
                changedSectionIDs: changedSections,
                reasons: reasons,
                isAmbiguous: isAmbiguous
            ),
            reusableSegmentIDs: reusable,
            reprocessSegmentIDs: reprocess,
            removedSegmentIDs: removed,
            mappings: mappingPairs,
            dependencySectionIDs: dependencySectionIDs,
            requiresProfileRebuild: requiresProfileRebuild,
            requiresDocumentReview: requiresDocumentReview,
            isFullRerun: false
        )
        return plan
    }

    /// Rematerializes anchored segment results after a text edit. A result is
    /// discarded if its original occurrence cannot be proven to be the same
    /// occurrence in the new revision.
    func rematerialize(
        reviews: [AIValidatedReview],
        assessments: [AIConnectorDefinitionAssessment],
        findings: [AIConnectorDocumentFinding],
        baseline: AIConnectorAnalysisBaseline,
        plan: AIConnectorAnalysisPlan,
        newText: String,
        newSegmentation: AITextSegmentationResult
    ) -> (
        reviews: [AIValidatedReview],
        assessments: [AIConnectorDefinitionAssessment],
        findings: [AIConnectorDocumentFinding]
    ) {
        let oldSegments = Dictionary(uniqueKeysWithValues: baseline.segmentation.segments.map { ($0.id, $0) })
        let newSegments = Dictionary(uniqueKeysWithValues: newSegmentation.segments.map { ($0.id, $0) })
        let mapping = Dictionary(uniqueKeysWithValues: plan.mappings.map { ($0.oldSegmentID, $0.newSegmentID) })

        let mappedReviews = reviews.compactMap { review -> AIValidatedReview? in
            guard let anchor = review.sourceAnchor,
                  let oldSegment = oldSegments[review.segmentID],
                  let newSegmentID = mapping[review.segmentID],
                  let newSegment = newSegments[newSegmentID],
                  plan.reusableSegmentIDs.contains(newSegment.id),
                  let original = review.original,
                  anchor.isValid(for: oldSegment, original: original) else {
                return nil
            }
            let newAnchor = AIConnectorReviewAnchor(
                segmentID: newSegment.id,
                sourceRange: anchor.range,
                original: original
            )
            guard newAnchor.isValid(for: newSegment, original: original) else { return nil }
            return AIValidatedReview(
                id: review.id,
                segment: newSegment,
                status: review.status,
                category: review.category,
                original: review.original,
                replacement: review.replacement,
                reason: review.reason,
                glossaryMatch: review.glossaryMatch,
                origin: review.origin,
                ruleID: review.ruleID,
                sourceAnchor: newAnchor
            )
        }

        let mappedAssessments = assessments.compactMap { assessment -> AIConnectorDefinitionAssessment? in
            guard let newSegmentID = mapping[assessment.segment.id],
                  let newSegment = newSegments[newSegmentID],
                  plan.reusableSegmentIDs.contains(newSegment.id) else { return nil }
            return AIConnectorDefinitionAssessment(
                segment: newSegment,
                term: assessment.term,
                statementText: assessment.statementText,
                candidate: assessment.candidate,
                candidateCount: assessment.candidateCount,
                detection: assessment.detection,
                classification: assessment.classification,
                alignment: assessment.alignment,
                reason: assessment.reason,
                origin: assessment.origin,
                modelReviewed: assessment.modelReviewed,
                retrievalOrigin: assessment.retrievalOrigin,
                semanticScore: assessment.semanticScore,
                requiresHumanReview: assessment.requiresHumanReview,
                candidates: assessment.candidates
            )
        }

        let mappedFindings = findings.compactMap { finding -> AIConnectorDocumentFinding? in
            guard let primary = rematerializeRange(
                finding.sourceRange,
                original: finding.original,
                oldSegments: oldSegments,
                newSegments: newSegments,
                mapping: mapping,
                allowedSegmentIDs: plan.reusableSegmentIDs,
                newText: newText
            ) else { return nil }

            var mapped = finding
            mapped.sourceRange = primary
            mapped.relatedEvidence = []
            for evidence in finding.relatedEvidence {
                guard let range = rematerializeRange(
                    evidence.sourceRange,
                    original: evidence.original,
                    oldSegments: oldSegments,
                    newSegments: newSegments,
                    mapping: mapping,
                    allowedSegmentIDs: plan.reusableSegmentIDs,
                    newText: newText
                ) else {
                    return nil
                }
                var rematerialized = evidence
                rematerialized.sourceRange = range
                mapped.relatedEvidence.append(rematerialized)
            }
            return mapped
        }

        return (mappedReviews, mappedAssessments, mappedFindings)
    }

    private func fullPlan(
        scope: AIConnectorAnalysisRunScope,
        documentText: String,
        segmentation: AITextSegmentationResult,
        reason: AIConnectorAnalysisInvalidationReason
    ) -> AIConnectorAnalysisPlan {
        let ids = Set(segmentation.segments.map(\.id))
        let changeSet = AIConnectorAnalysisChangeSet(
            scope: scope,
            oldTextFingerprint: nil,
            newTextFingerprint: Self.sha256(documentText),
            changedOldRanges: [],
            changedNewRanges: [],
            changedOldBlockIDs: [],
            changedBlockIDs: [],
            changedSectionIDs: [],
            reasons: [reason, .fullRerun],
            isAmbiguous: true
        )
        return AIConnectorAnalysisPlan(
            changeSet: changeSet,
            reusableSegmentIDs: [],
            reprocessSegmentIDs: ids,
            removedSegmentIDs: [],
            mappings: [],
            dependencySectionIDs: [],
            requiresProfileRebuild: true,
            requiresDocumentReview: true,
            isFullRerun: true
        )
    }

    private func makeMappings(
        oldSegments: [AIReviewSegment],
        newSegments: [AIReviewSegment],
        oldStructure: AIConnectorDocumentStructure,
        newStructure: AIConnectorDocumentStructure
    ) -> MappingResult {
        let oldDescriptors = descriptors(
            for: oldSegments,
            structure: oldStructure
        )
        let newDescriptors = descriptors(
            for: newSegments,
            structure: newStructure
        )
        var oldGroups: [SegmentKey: [SegmentDescriptor]] = [:]
        var newGroups: [SegmentKey: [SegmentDescriptor]] = [:]
        for descriptor in oldDescriptors { oldGroups[descriptor.key, default: []].append(descriptor) }
        for descriptor in newDescriptors { newGroups[descriptor.key, default: []].append(descriptor) }

        var mappings: [AIConnectorSegmentMapping] = []
        var ambiguous = false
        for key in Set(oldGroups.keys).union(newGroups.keys) {
            let oldGroup = oldGroups[key, default: []].sorted { $0.segment.id < $1.segment.id }
            let newGroup = newGroups[key, default: []].sorted { $0.segment.id < $1.segment.id }
            guard !oldGroup.isEmpty, !newGroup.isEmpty else { continue }
            if oldGroup.count != newGroup.count {
                ambiguous = true
                continue
            }
            for (old, new) in zip(oldGroup, newGroup) {
                mappings.append(
                    AIConnectorSegmentMapping(
                        oldSegmentID: old.segment.id,
                        newSegmentID: new.segment.id
                    )
                )
            }
        }
        return MappingResult(mappings: mappings, isAmbiguous: ambiguous)
    }

    private func descriptors(
        for segments: [AIReviewSegment],
        structure: AIConnectorDocumentStructure
    ) -> [SegmentDescriptor] {
        var occurrence: [SegmentKey: Int] = [:]
        return segments.map { segment in
            let block = block(for: segment, in: structure)
            let key = SegmentKey(
                sectionID: block?.parentSectionID,
                blockID: block?.id,
                normalizedText: normalize(segment.targetText)
            )
            let currentOccurrence = occurrence[key, default: 0]
            occurrence[key] = currentOccurrence + 1
            return SegmentDescriptor(
                segment: segment,
                key: key,
                occurrence: currentOccurrence
            )
        }
    }

    private func selectedSectionIDs(
        scope: AIConnectorAnalysisRunScope,
        selectedSectionID: String?,
        structure: AIConnectorDocumentStructure
    ) -> Set<String> {
        guard scope == .section,
              let selectedSectionID,
              structure.section(for: selectedSectionID) != nil else { return [] }
        return Set(structure.sections.compactMap { section in
            isDescendantOrSelf(section, of: selectedSectionID, in: structure)
                ? section.id
                : nil
        })
    }

    private func isDescendantOrSelf(
        _ section: AIConnectorDocumentSection,
        of ancestorID: String,
        in structure: AIConnectorDocumentStructure
    ) -> Bool {
        var current: AIConnectorDocumentSection? = section
        while let value = current {
            if value.id == ancestorID { return true }
            current = structure.section(for: value.parentSectionID)
        }
        return false
    }

    private func changedBlocks(
        in structure: AIConnectorDocumentStructure,
        ranges: [NSRange]
    ) -> [AIConnectorDocumentBlock] {
        guard !ranges.isEmpty else { return [] }
        return structure.blocks.filter { block in
            ranges.contains { range in
                if range.length == 0 {
                    return range.location >= block.sourceRange.location
                        && range.location <= NSMaxRange(block.sourceRange)
                }
                return NSIntersectionRange(block.sourceRange, range).length > 0
            }
        }
    }

    private func block(
        for segment: AIReviewSegment,
        in structure: AIConnectorDocumentStructure
    ) -> AIConnectorDocumentBlock? {
        structure.blocks.first { block in
            segment.sourceLocation >= block.sourceRange.location
                && NSMaxRange(NSRange(location: segment.sourceLocation, length: segment.sourceLength))
                    <= NSMaxRange(block.sourceRange)
        }
    }

    private func sectionID(
        for segment: AIReviewSegment,
        in structure: AIConnectorDocumentStructure
    ) -> String {
        block(for: segment, in: structure)?.parentSectionID ?? "root"
    }

    private func rematerializeRange(
        _ oldRange: NSRange,
        original: String,
        oldSegments: [Int: AIReviewSegment],
        newSegments: [Int: AIReviewSegment],
        mapping: [Int: Int],
        allowedSegmentIDs: Set<Int>,
        newText: String
    ) -> NSRange? {
        guard let oldSegment = oldSegments.values.first(where: { segment in
            oldRange.location >= segment.sourceLocation
                && NSMaxRange(oldRange) <= segment.sourceLocation + segment.sourceLength
        }),
        let newSegmentID = mapping[oldSegment.id],
        let newSegment = newSegments[newSegmentID],
        allowedSegmentIDs.contains(newSegmentID) else { return nil }

        let localLocation = oldRange.location - oldSegment.sourceLocation
        let newRange = NSRange(
            location: newSegment.sourceLocation + localLocation,
            length: oldRange.length
        )
        guard newRange.location >= 0,
              NSMaxRange(newRange) <= newText.utf16.count,
              (newText as NSString).substring(with: newRange) == original else {
            return nil
        }
        return newRange
    }

    private func profileFactsChanged(
        _ old: AIConnectorDocumentContextProfile,
        _ new: AIConnectorDocumentContextProfile
    ) -> Bool {
        localFactValues(old.documentTypeCandidates) != localFactValues(new.documentTypeCandidates)
            || localFactValues(old.legalDomains) != localFactValues(new.legalDomains)
            || localFactValues(old.parties) != localFactValues(new.parties)
            || localFactValues(old.definedTerms) != localFactValues(new.definedTerms)
            || localFactValues(old.jurisdictions) != localFactValues(new.jurisdictions)
            || localFactValues(old.regulationReferences) != localFactValues(new.regulationReferences)
    }

    private func localFactValues(_ facts: [AIConnectorContextFact]) -> [String] {
        facts
            .filter { $0.origin != .qwen }
            .map(\.value)
            .sorted()
    }

    private func changedText(
        oldText: String,
        newText: String,
        oldRanges: [NSRange],
        newRanges: [NSRange]
    ) -> String {
        let oldPart = oldRanges.map { safeSubstring(oldText, range: $0) }.joined(separator: " ")
        let newPart = newRanges.map { safeSubstring(newText, range: $0) }.joined(separator: " ")
        return oldPart + "\n" + newPart
    }

    private func safeSubstring(_ text: String, range: NSRange) -> String {
        guard range.location >= 0,
              range.length >= 0,
              range.location <= text.utf16.count,
              range.length <= text.utf16.count - range.location else { return "" }
        return (text as NSString).substring(with: range)
    }

    private func textDiff(old: String, new: String) -> TextDiff {
        guard old != new else {
            return TextDiff(oldRanges: [], newRanges: [])
        }
        let oldUnits = Array(old.utf16)
        let newUnits = Array(new.utf16)
        var prefix = 0
        while prefix < oldUnits.count,
              prefix < newUnits.count,
              oldUnits[prefix] == newUnits[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < oldUnits.count - prefix,
              suffix < newUnits.count - prefix,
              oldUnits[oldUnits.count - suffix - 1]
                == newUnits[newUnits.count - suffix - 1] {
            suffix += 1
        }

        let oldLength = max(0, oldUnits.count - prefix - suffix)
        let newLength = max(0, newUnits.count - prefix - suffix)
        return TextDiff(
            oldRanges: [NSRange(location: prefix, length: oldLength)],
            newRanges: [NSRange(location: prefix, length: newLength)]
        )
    }

    private func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func looksLikeDefinitionDependency(_ text: String) -> Bool {
        text.contains(" adalah ") && (text.contains("\"") || text.contains("“") || text.contains("‘"))
            || text.contains(" selanjutnya disebut ")
            || text.contains(" berarti ")
    }

    private func looksLikePartyDependency(_ text: String) -> Bool {
        text.contains("para pihak") || text.contains(" pihak ")
            || text.contains("pemberi") || text.contains("penerima")
    }

    private func looksLikeReferenceDependency(_ text: String) -> Bool {
        text.contains("pasal ") || text.contains("uu no") || text.contains("pp no")
            || text.contains("lampiran") || text.contains("peraturan")
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private struct SegmentKey: Hashable {
        let sectionID: String?
        let blockID: String?
        let normalizedText: String
    }

    private struct SegmentDescriptor {
        let segment: AIReviewSegment
        let key: SegmentKey
        let occurrence: Int
    }

    private struct MappingResult {
        let mappings: [AIConnectorSegmentMapping]
        let isAmbiguous: Bool
    }

    private struct TextDiff {
        let oldRanges: [NSRange]
        let newRanges: [NSRange]
    }
}
