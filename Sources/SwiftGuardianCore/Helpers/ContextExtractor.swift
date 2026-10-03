import Foundation

public enum ContextExtractor {
    public static func extract(from source: String, around line: Int, radius: Int = 3) -> String {
        let lines = source.components(separatedBy: .newlines)
        let start = max(0, line - 1 - radius)
        let end = min(lines.count - 1, line - 1 + radius)
        return lines[start...end]
            .enumerated()
            .map { "  \(start + $0.offset + 1): \($0.element)" }
            .joined(separator: "\n")
    }
}
