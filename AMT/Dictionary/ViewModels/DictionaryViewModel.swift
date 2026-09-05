//
//  DictionaryViewModel.swift
//  AMT
//
//  Created by Antigravity on 2026/08/27.
//

import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class DictionaryViewModel {
    var searchText: String = ""
    var selectedEntry: LegalGlossaryEntry? = nil
    var isShowingDetail: Bool = false
    var isNotFound: Bool = false
    var isLoading: Bool = false
    var semanticProgress: Double?
    var topMatches: [LegalGlossaryEntry] = []

    // MARK: - Popular Terms
    /// Array of popular legal terms displayed in the "Istilah Populer" section.
    var popularTerms: [PopularTerm] = []

    var corpusSummary: LegalDictionaryCorpusSummary {
        dictionaryStore.corpusSummary
    }

    private let dictionaryStore: LegalDictionaryStore
    @ObservationIgnored private var lookupTask: Task<Void, Never>?
    @ObservationIgnored private var activeLookupID: UUID?

    init(dictionaryStore: LegalDictionaryStore = LegalDictionaryStore()) {
        self.dictionaryStore = dictionaryStore
        self.popularTerms = PopularTerm.randomPopularTerms(count: 3, from: dictionaryStore.entries)
    }

    /// Refreshes the popular terms section with 3 random terms.
    func refreshPopularTerms() {
        popularTerms = PopularTerm.randomPopularTerms(count: 3, from: dictionaryStore.entries)
    }

    // MARK: - Search & Lookup Actions

    /// Triggered when the user clicks one of the "Istilah Populer" or "Lihat Juga" chips.
    func selectPopularTerm(_ term: PopularTerm) {
        searchText = term.name
        lookupTerm(term.name)
    }

    /// Triggered when the user submits from the search field.
    func lookupCurrentText() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lookupTerm(trimmed)
    }

    /// Executes an exact-term lookup or a hybrid reverse lookup. The semantic
    /// model is loaded lazily only when the query is not an exact/prefix term.
    func lookupTerm(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lookupTask?.cancel()
        let lookupID = UUID()
        activeLookupID = lookupID
        isLoading = true
        isNotFound = false
        semanticProgress = nil

        lookupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let ragEntries = await dictionaryStore.searchRAG(
                trimmed,
                limit: 5,
                semanticProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.activeLookupID == lookupID,
                              !Task.isCancelled else { return }
                        self.semanticProgress = min(max(progress, 0), 1)
                    }
                }
            )
            guard !Task.isCancelled, activeLookupID == lookupID else { return }

            var seenTerms: Set<String> = []
            let glossaryEntries = ragEntries.compactMap { entry -> LegalGlossaryEntry? in
                let normalizedTerm = entry.term
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard seenTerms.insert(normalizedTerm).inserted else { return nil }
                return self.makeGlossaryEntry(forTerm: entry.term)
            }
            topMatches = glossaryEntries
            selectedEntry = glossaryEntries.first

            withAnimation(.easeInOut(duration: 0.2)) {
                self.isShowingDetail = !glossaryEntries.isEmpty
                self.isNotFound = glossaryEntries.isEmpty
                self.isLoading = false
                self.semanticProgress = nil
            }
            activeLookupID = nil
            lookupTask = nil
        }
    }

    func selectMatch(_ entry: LegalGlossaryEntry) {
        withAnimation(.easeInOut(duration: 0.15)) {
            self.selectedEntry = entry
        }
    }

    func regulation(for referenceID: String) -> LegalRegulation? {
        dictionaryStore.regulation(id: referenceID)
    }

    private func relatedTerms(count: Int = 4, excluding currentTerm: String) -> [String] {
        let related = dictionaryStore.relatedTerms(excluding: currentTerm, limit: count)
        if !related.isEmpty { return related }

        let fallbackTerms = [
            "Jaksa Agung",
            "Jabatan Fungsional",
            "Jabatan Struktural",
            "Jabatan Pimpinan Tinggi",
            "Pengendali Data Pribadi",
            "Hak Cipta",
            "Bursa Efek",
            "Badan Hukum"
        ]
        return Array(
            fallbackTerms
                .filter {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare(currentTerm.trimmingCharacters(in: .whitespacesAndNewlines))
                        != .orderedSame
                }
                .prefix(count)
        )
    }

    private func makeGlossaryEntry(forTerm term: String) -> LegalGlossaryEntry {
        let termEntries = dictionaryStore.entries(forTerm: term)
        let entries = termEntries.isEmpty
            ? dictionaryStore.search(term, limit: 1)
            : termEntries
        let canonicalTerm = entries.first?.term ?? term
        let termGroup = dictionaryStore.termGroup(forTerm: canonicalTerm)

        let definitions = entries.enumerated().map { index, entry in
            let resolvedReferences = dictionaryStore.references(for: entry)
            let primaryReference = resolvedReferences.first ?? makeReference(from: entry)
            return DefinitionItem(
                id: index + 1,
                text: entry.definition,
                reference: primaryReference,
                additionalReferences: Array(resolvedReferences.dropFirst()),
                sources: entry.sources,
                sourceURLs: entry.sourceURLs,
                role: .primary,
                attributionStatus: dictionaryStore
                    .primaryRecord(forTerm: canonicalTerm)?
                    .primaryAttributionStatus
                    ?? primaryReference?.attributionStatus,
                selectionStatus: termGroup?.selectionStatus,
                selectionReason: termGroup?.selectionReason,
                verificationStatus: primaryReference?.verificationStatus,
                isActionable: entry.isActionable
            )
        }
        let contextualAlternatives = dictionaryStore
            .alternatives(forTerm: canonicalTerm)
            .enumerated()
            .map { index, alternative in
                let resolvedReferences = dictionaryStore.references(for: alternative)
                let reference = resolvedReferences.first {
                    $0.isDefinitionAuthority
                } ?? resolvedReferences.first
                let alternativeSourceURLs = alternative.sourceURLs.isEmpty
                    ? alternative.sourceURL.map { [$0] } ?? []
                    : alternative.sourceURLs
                return DefinitionItem(
                    id: index + 1,
                    text: alternative.definition,
                    reference: reference,
                    additionalReferences: Array(resolvedReferences.dropFirst()),
                    sources: alternative.source.isEmpty ? [] : [alternative.source],
                    sourceURLs: alternativeSourceURLs,
                    role: .alternative,
                    attributionStatus: alternative.attributionStatus,
                    selectionStatus: alternative.selectionStatus,
                    selectionReason: alternative.selectionReason,
                    verificationStatus: resolvedReferences
                        .compactMap(\.verificationStatus)
                        .first,
                    isActionable: alternative.isActionable
                )
            }
        let authority = entries.contains { $0.authority == .verified }
            ? LegalDictionaryEntryAuthority.verified
            : .legacy
        let applicabilityStatus: LegalCorpusApplicabilityStatus
        if entries.contains(where: { $0.applicabilityStatus == .inForce }) {
            applicabilityStatus = .inForce
        } else if entries.contains(where: { $0.applicabilityStatus == .notInForce }) {
            applicabilityStatus = .notInForce
        } else {
            applicabilityStatus = .unknown
        }
        var referenceIDs = entries
            .flatMap(dictionaryStore.references(for:))
            .compactMap(\.referenceID)
        referenceIDs.append(contentsOf: contextualAlternatives
            .flatMap(\.allReferences)
            .compactMap(\.referenceID))
        let relations = dictionaryStore.regulationRelations(for: referenceIDs)

        return LegalGlossaryEntry(
            term: canonicalTerm,
            definitions: definitions,
            seeAlso: relatedTerms(count: 4, excluding: canonicalTerm),
            authority: authority,
            corpusVersion: entries.first?.corpusVersion
                ?? LegalDictionaryCorpusVersion.unspecifiedLegacy,
            applicabilityStatus: applicabilityStatus,
            isActionable: entries.contains(where: { $0.isActionable }),
            regulationRelations: relations,
            contextualAlternatives: contextualAlternatives,
            selectionStatus: termGroup?.selectionStatus,
            selectionReason: termGroup?.selectionReason
        )
    }

    private func makeReference(from entry: LegalDictionaryEntry) -> LegalReference? {
        guard !entry.regulation.isEmpty
                || !entry.regulationTitle.isEmpty
                || entry.sourceURL != nil
                || entry.officialDocumentURL != nil else {
            return nil
        }

        return LegalReference(
            lawName: entry.regulation.isEmpty ? "Sumber hukum lokal" : entry.regulation,
            lawTitle: entry.regulationTitle.isEmpty ? nil : entry.regulationTitle,
            sourceURL: entry.sourceURL,
            officialDocumentURL: entry.officialDocumentURL,
            referenceID: entry.referenceID,
            applicabilityStatus: entry.applicabilityStatus,
            articleLocator: entry.articleLocator,
            pageStart: entry.pageStart,
            pageEnd: entry.pageEnd,
            sourcePassageID: entry.sourcePassageID,
            attributionStatus: entry.referenceID == nil ? nil : "explicit_reference",
            isDefinitionAuthority: entry.referenceID != nil
        )
    }


    /// Navigates back to the main Lawtionary search view.
    func backToHome() {
        lookupTask?.cancel()
        lookupTask = nil
        activeLookupID = nil
        isLoading = false
        semanticProgress = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isShowingDetail = false
            self.isNotFound = false
            self.selectedEntry = nil
        }
    }

    /// Clears current search and returns to the home view.
    func clearSearch() {
        lookupTask?.cancel()
        searchText = ""
        backToHome()
    }
}
