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
    var isLoading: Bool = false
    var topMatches: [LegalGlossaryEntry] = []

    // MARK: - Popular Terms
    /// Array of popular legal terms displayed in the "Istilah Populer" section.
    ///
    /// TODO: [AI Team]
    /// 1. Replace this default array with real-time recommendations from your ranking or embedding model.
    /// 2. You can inject a suggestion service or async loader method here:
    ///    `func refreshPopularTerms(basedOn context: String? = nil) async { ... }`
    var popularTerms: [PopularTerm] = PopularTerm.defaultPopularTerms

    private let dictionaryStore: LegalDictionaryStore
    @ObservationIgnored private var lookupTask: Task<Void, Never>?
    @ObservationIgnored private var activeLookupID: UUID?

    init(dictionaryStore: LegalDictionaryStore = LegalDictionaryStore()) {
        self.dictionaryStore = dictionaryStore
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

    /// Executes a bounded lexical lookup across the primary dictionary and
    /// bundled legacy corpus. Semantic retrieval remains disabled until the
    /// matching model and tokenizer are available.
    func lookupTerm(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lookupTask?.cancel()
        let lookupID = UUID()
        activeLookupID = lookupID
        isLoading = true

        lookupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let ragEntries = await dictionaryStore.searchRAG(trimmed, limit: 5)
            guard !Task.isCancelled, activeLookupID == lookupID else { return }

            let glossaryEntries = ragEntries.map(makeGlossaryEntry(from:))
            topMatches = glossaryEntries

            if let first = glossaryEntries.first {
                selectedEntry = first
            } else {
                selectedEntry = LegalGlossaryEntry(
                    term: trimmed,
                    singleDefinition: "Definisi untuk kata \"\(trimmed)\" belum ditemukan dalam glosarium lokal.",
                    seeAlso: relatedTerms(count: 4, excluding: trimmed),
                    authority: .legacy,
                    corpusVersion: LegalDictionaryCorpusVersion.unspecifiedLegacy
                )
                topMatches = []
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                self.isShowingDetail = true
                self.isLoading = false
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
        return Array(fallbackTerms.filter { $0.lowercased() != currentTerm.lowercased() }.shuffled().prefix(count))
    }

    private func makeGlossaryEntry(from entry: LegalDictionaryEntry) -> LegalGlossaryEntry {
        let reference: LegalReference? = {
            guard !entry.regulation.isEmpty || !entry.regulationTitle.isEmpty || entry.sourceURL != nil else {
                return nil
            }

            return LegalReference(
                lawName: entry.regulation.isEmpty ? "Sumber hukum lokal" : entry.regulation,
                lawTitle: entry.regulationTitle.isEmpty ? nil : entry.regulationTitle,
                sourceURL: entry.sourceURL
            )
        }()

        let seeAlso = relatedTerms(count: 4, excluding: entry.term)

        return LegalGlossaryEntry(
            term: entry.term,
            singleDefinition: entry.definition,
            reference: reference,
            seeAlso: seeAlso,
            authority: entry.authority,
            corpusVersion: entry.corpusVersion
        )
    }


    /// Navigates back to the main Lawtionary search view.
    func backToHome() {
        lookupTask?.cancel()
        lookupTask = nil
        activeLookupID = nil
        isLoading = false
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isShowingDetail = false
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
