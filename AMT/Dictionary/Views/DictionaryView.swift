//
//  DictionaryView.swift
//  AMT
//
//  Created by Mochammad Athar Humam Ghazanfar on 21/08/26.
//

import SwiftUI

struct DictionaryView: View {
    let dictionaryStore: LegalDictionaryStore

    @State private var searchText: String = ""
    @State private var results: [LegalDictionaryEntry] = []
    @State private var hasSearched = false

    init(dictionaryStore: LegalDictionaryStore = LegalDictionaryStore()) {
        self.dictionaryStore = dictionaryStore
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)

            VStack(spacing: 8) {
                Image(systemName: "book")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text("Lawtionary")
                    .font(.system(size: 28, weight: .medium))
            }

            HStack {
                TextField("Cari istilah atau pengertian...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit {
                        lookupWord()
                    }

                Button(action: lookupWord) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 560)

            if hasSearched {
                if results.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Istilah tidak ditemukan")
                            .font(.headline)
                        Text("Coba kata lain atau masukkan sebagian pengertiannya.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(results) { entry in
                                DictionaryEntryCard(entry: entry)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Text("Cari istilah hukum atau bagian dari pengertiannya.")
                    Text("Data awal bersifat eksperimental dan bukan nasihat hukum.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxHeight: .infinity)
            }

            if !results.isEmpty {
                Text("Menampilkan hingga 30 hasil")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func lookupWord() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            hasSearched = false
            return
        }

        results = dictionaryStore.search(query)
        hasSearched = true
    }
}

private struct DictionaryEntryCard: View {
    let entry: LegalDictionaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.term)
                .font(.headline)

            Text(entry.definition)
                .font(.body)
                .textSelection(.enabled)

            if !entry.regulation.isEmpty || !entry.regulationTitle.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    if !entry.regulation.isEmpty {
                        Text(entry.regulation)
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    if !entry.regulationTitle.isEmpty {
                        Text(entry.regulationTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let sourceURL = entry.sourceURL {
                Link(destination: sourceURL) {
                    Label("Buka sumber", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    DictionaryView(dictionaryStore: LegalDictionaryStore(entries: LegalDictionaryEntry.previewEntries))
}
