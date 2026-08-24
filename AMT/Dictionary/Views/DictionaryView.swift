//
//  DictionaryView.swift
//  AMT
//
//  Created by Mochammad Athar Humam Ghazanfar on 21/08/26.
//

import Foundation
import SwiftUI

struct DictionaryView: View {
    @State private var searchText: String = ""
    @State private var definition: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Dictionary")
                    .font(Font.title.bold())
                Spacer()
            }
            .padding()

            Divider()

            // Search bar
            HStack {
                TextField("Cari kata...", text: $searchText)
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
            .padding(16)
            .glassEffect()
            .padding()

            // Hasil definisi
            ScrollView {
                Text(definition)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            Spacer()
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    func lookupWord() {
        guard !searchText.isEmpty else {
            definition = ""
            return
        }

        let range = CFRangeMake(0, searchText.count)
        if let result = DCSCopyTextDefinition(nil, searchText as CFString, range) {
            definition = result.takeRetainedValue() as String
        } else {
            definition = "Kata \"\(searchText)\" tidak ditemukan."
        }
    }
}

#Preview {
    DictionaryView()
}
