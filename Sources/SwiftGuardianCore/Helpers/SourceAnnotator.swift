import Foundation

public enum SourceAnnotator {
    public static func annotate(
        source: String,
        findings: [Finding],
        suggestions: [String]
    ) -> String {
        var lines = source.components(separatedBy: .newlines)
        for (index, finding) in findings.enumerated().reversed() {
            let lineIndex = finding.line - 1
            guard lineIndex < lines.count else { continue }
            let suggestion = suggestions[index]
                .components(separatedBy: .newlines)
                .filter { !$0.hasPrefix("```") }
                .map { "// 💡 \($0)" }
                .joined(separator: "\n")
            lines.insert(suggestion, at: lineIndex)
        }
        return lines.joined(separator: "\n")
    }

    public static func write(annotatedSource: String, originalPath: String) throws {
        let outputPath = originalPath.replacingOccurrences(of: ".swift", with: ".suggested.swift")
        try annotatedSource.write(toFile: outputPath, atomically: true, encoding: .utf8)
        print("📝 Annotated file written to:\n   \(outputPath)")
    }
}
