import Foundation

/// Turns a model response into a `LinePatch` for a known line range.
public enum FixResponseParser {
    public static func parse(_ response: String, range: ClosedRange<Int>) -> LinePatch? {
        var code = extractCodeBlock(from: response) ?? response
        code = stripLineNumbers(from: code)
        code = code.trimmingCharacters(in: .newlines)
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return LinePatch(startLine: range.lowerBound, endLine: range.upperBound, replacement: code)
    }

    /// Content of the first ``` fenced block, if any.
    static func extractCodeBlock(from text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let open = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }) else {
            return nil
        }
        let rest = lines[(open + 1)...]
        guard let close = rest.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }) else {
            return rest.joined(separator: "\n")
        }
        return lines[(open + 1)..<close].joined(separator: "\n")
    }

    /// Removes "  12: " prefixes when the model echoes the numbered excerpt.
    /// Only applied when every non-empty line carries such a prefix.
    static func stripLineNumbers(from code: String) -> String {
        let lines = code.components(separatedBy: "\n")
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonEmpty.isEmpty, nonEmpty.allSatisfy({ codeAfterLineNumber($0) != nil }) else { return code }
        return lines.map { codeAfterLineNumber($0) ?? $0 }.joined(separator: "\n")
    }

    /// For "  12: let x = 1" returns "let x = 1"; nil when the line has no number prefix.
    static func codeAfterLineNumber(_ line: String) -> String? {
        let afterIndent = line.drop(while: { $0 == " " || $0 == "\t" })
        let digits = afterIndent.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        let afterDigits = afterIndent.dropFirst(digits.count)
        guard afterDigits.first == ":" else { return nil }
        let code = afterDigits.dropFirst()
        return String(code.first == " " ? code.dropFirst() : code)
    }
}
