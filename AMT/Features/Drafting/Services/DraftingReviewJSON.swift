import Foundation

/// Structural repair only: no text, decision, permission or source is invented.
/// A conflicting duplicate key is never repaired using first/last-key wins.
enum DraftingReviewJSON {
    struct Object {
        let root: [String: Any]
        let hasDuplicateKeys: Bool
    }

    static func object(_ raw: String) -> Object? {
        guard raw.utf8.count <= 128 * 1_024 else { return nil }
        var parser = Parser(bytes: Array(raw.utf8))
        guard let root = try? parser.value(depth: 0) as? [String: Any] else { return nil }
        parser.whitespace()
        guard parser.index == parser.bytes.count else { return nil }
        return .init(root: root, hasDuplicateKeys: parser.hasDuplicateKeys)
    }

    static func repaired(_ raw: String) -> String? {
        guard let parsed = object(raw), Set(parsed.root.keys) == ["decision", "findings"],
              let decision = parsed.root["decision"] as? String,
              ["revise", "clarify", "no_change"].contains(decision),
              var findings = parsed.root["findings"] as? [[String: Any]], findings.count <= 4 else { return nil }
        let fields: Set<String> = ["clause_id", "quote", "category", "reason", "suggested_text", "clarification_question", "substance_change", "reference_ids"]
        var changed = parsed.hasDuplicateKeys
        for i in findings.indices {
            let inactive = decision == "revise" ? "clarification_question" : "suggested_text"
            let active = decision == "revise" ? "suggested_text" : "clarification_question"
            let keys = Set(findings[i].keys)
            guard keys.isSubset(of: fields) else { return nil }
            if keys != fields {
                guard decision != "no_change", fields.subtracting(keys) == [inactive],
                      findings[i][active] is String else { return nil }
                findings[i][inactive] = NSNull()
                changed = true
            }
        }
        guard changed else { return nil }
        var root = parsed.root
        root["findings"] = findings
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private enum Failure: Error { case invalid }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var hasDuplicateKeys = false

        mutating func whitespace() {
            while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }

        mutating func consume(_ byte: UInt8) -> Bool {
            whitespace()
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        mutating func value(depth: Int) throws -> Any {
            whitespace()
            guard depth < 32, index < bytes.count else { throw Failure.invalid }
            if bytes[index] == 123 {
                index += 1
                var result: [String: Any] = [:]
                if consume(125) { return result }
                while true {
                    whitespace()
                    guard index < bytes.count, bytes[index] == 34,
                          let key = try string() as? String, consume(58) else { throw Failure.invalid }
                    let next = try value(depth: depth + 1)
                    if let previous = result[key] {
                        hasDuplicateKeys = true
                        let options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys]
                        guard try JSONSerialization.data(withJSONObject: previous, options: options)
                                == JSONSerialization.data(withJSONObject: next, options: options) else { throw Failure.invalid }
                    }
                    result[key] = next
                    if consume(125) { return result }
                    guard consume(44) else { throw Failure.invalid }
                }
            }
            if bytes[index] == 91 {
                index += 1
                var result: [Any] = []
                if consume(93) { return result }
                while true {
                    result.append(try value(depth: depth + 1))
                    if consume(93) { return result }
                    guard consume(44) else { throw Failure.invalid }
                }
            }
            if bytes[index] == 34 { return try string() }
            let start = index
            while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            guard index > start else { throw Failure.invalid }
            return try JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: [.fragmentsAllowed])
        }

        mutating func string() throws -> Any {
            let start = index
            index += 1
            var escaped = false
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 34 && !escaped {
                    return try JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: [.fragmentsAllowed])
                }
                if byte == 92 && !escaped { escaped = true } else { escaped = false }
            }
            throw Failure.invalid
        }
    }
}
