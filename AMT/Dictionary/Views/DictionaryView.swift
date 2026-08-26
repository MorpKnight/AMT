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
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "book")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text("Lawtionary")
                    .font(.system(size: 28, weight: .medium))
            }

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
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 480)

            if !definition.isEmpty {
                ScrollView {
                    Text(definition)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
