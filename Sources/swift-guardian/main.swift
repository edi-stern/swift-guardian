import SwiftGuardianCore
import SwiftSyntax
import SwiftParser
import Foundation

// MARK: - Entry point

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift-guardian <path-to-swift-file>")
    exit(1)
}

let filePath = CommandLine.arguments[1]

guard FileManager.default.fileExists(atPath: filePath) else {
    print("❌ File not found: \(filePath)")
    exit(1)
}

let source = try String(contentsOfFile: filePath, encoding: .utf8)

// MARK: - Parse

let tree = Parser.parse(source: source)
let converter = SourceLocationConverter(fileName: filePath, tree: tree)
let unwrapVisitor = ForceUnwrapVisitor(locationConverter: converter)
unwrapVisitor.walk(tree)

let tryVisitor = ForceTryVisitor(locationConverter: converter)
tryVisitor.walk(tree)

let findings = (unwrapVisitor.findings + tryVisitor.findings)
    .sorted { $0.line < $1.line }

// MARK: - Report

guard !unwrapVisitor.findings.isEmpty || !tryVisitor.findings.isEmpty else {
    print("✅ No force unwraps found in \(filePath)")
    exit(0)
}

print("⚠️  Found \(findings.count) force unwrap(s) in \(filePath)\n")

// MARK: - Suggest

var suggestions: [String] = []

for finding in findings {
    let context = ContextExtractor.extract(from: source, around: finding.line)

    print("  Line \(finding.line), Col \(finding.column): \(finding.expression)")
    print(context)
    print("\n  💡 Asking Claude for a fix...")

    do {
        let suggestion = try await ClaudeService.suggest(for: finding, context: context)
        suggestions.append(suggestion)
        print("  ✅ Suggestion:\n\(suggestion)\n")
    } catch {
        suggestions.append("Could not generate suggestion")
        print("  ❌ Error: \(error.localizedDescription)\n")
    }
}

// MARK: - Annotate

let annotated = SourceAnnotator.annotate(
    source: source,
    findings: findings,
    suggestions: suggestions
)

try SourceAnnotator.write(annotatedSource: annotated, originalPath: filePath)
