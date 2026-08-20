//
//  AMTDocument.swift
//  AMT
//
//  Created by Giovan Christoffel Sihombing on 2026/08/20.
//

import SwiftUI
import UniformTypeIdentifiers

nonisolated struct AMTDocument: FileDocument {
    var text: String

    init(text: String = "Hello, world!") {
        self.text = text
    }

    static let readableContentTypes = [
        UTType(importedAs: "com.example.plain-text")
    ]

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8)!
        return .init(regularFileWithContents: data)
    }
}
