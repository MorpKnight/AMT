//
//  DictionaryViewModel.swift
//  AMT
//
//  Created by Antigravity on 2026/08/27.
//

import Foundation
import SwiftUI
import Observation
import CoreServices

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

        // 1. Check curated Indonesian legal glossary first
        let key = trimmed.lowercased()
        if let entry = PopularTerm.sampleGlossaryEntries[key] {
            self.selectedEntry = entry
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isShowingDetail = true
                self.isLoading = false
            }
            return
        }

        // 2. Lookup via macOS CoreServices DCSCopyTextDefinition (system dictionary fallback)
        let range = CFRangeMake(0, trimmed.count)
        if let result = DCSCopyTextDefinition(nil, trimmed as CFString, range) {
            let definitionString = result.takeRetainedValue() as String
            self.selectedEntry = LegalGlossaryEntry(
                term: trimmed,
                singleDefinition: definitionString,
                reference: LegalReference(lawName: "Kamus Sistem macOS", institution: nil)
            )
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isShowingDetail = true
                self.isLoading = false
            }
            return
        }

        // 3. Fallback when term is not found
        //
        // TODO: [AI Team]
        // You can hook into your Qwen / MLX LLM model here to generate on-the-fly legal definition:
        //
        // Task {
        //     let prompt = "Jelaskan definisi hukum singkat untuk istilah: \(trimmed)"
        //     let generatedDefinition = try await qwenService.review(text: prompt, ...)
        //     self.selectedEntry = LegalGlossaryEntry(term: trimmed, singleDefinition: generatedDefinition)
        // }
        self.selectedEntry = LegalGlossaryEntry(
            term: trimmed,
            singleDefinition: "Definisi untuk kata \"\(trimmed)\" belum ditemukan dalam glosarium lokal.",
            reference: LegalReference(lawName: "Lawtionary", institution: nil)
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isShowingDetail = true
            self.isLoading = false
        }
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
