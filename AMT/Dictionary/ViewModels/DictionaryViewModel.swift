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

    // MARK: - Popular Terms
    /// Array of popular legal terms displayed in the "Istilah Populer" section.
    ///
    /// TODO: [AI Team]
    /// 1. Replace this default array with real-time recommendations from your ranking or embedding model.
    /// 2. You can inject a suggestion service or async loader method here:
    ///    `func refreshPopularTerms(basedOn context: String? = nil) async { ... }`
    var popularTerms: [PopularTerm] = PopularTerm.defaultPopularTerms

    private let dictionaryStore: LegalDictionaryStore

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

    /// Executes the legal term lookup with animated transition to Detail View (Option B).
    func lookupTerm(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true

        if let entry = dictionaryStore.search(trimmed, limit: 1).first {
            selectedEntry = makeGlossaryEntry(from: entry)
        } else {
            selectedEntry = LegalGlossaryEntry(
                term: trimmed,
                singleDefinition: "Definisi untuk kata \"\(trimmed)\" belum ditemukan dalam glosarium lokal."
            )
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            self.isShowingDetail = true
            self.isLoading = false
        }
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

        return LegalGlossaryEntry(
            term: entry.term,
            singleDefinition: entry.definition,
            reference: reference
        )
    }

    /// Navigates back to the main Lawtionary search view.
    func backToHome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isShowingDetail = false
            self.selectedEntry = nil
        }
    }

    /// Clears current search and returns to the home view.
    func clearSearch() {
        searchText = ""
        backToHome()
    }
}
