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

let forceCastVisitor = ForceCastVisitor(locationConverter: converter)
forceCastVisitor.walk(tree)

let findings = (unwrapVisitor.findings + tryVisitor.findings + forceCastVisitor.findings)
    .sorted { $0.line < $1.line }

// MARK: - Report

guard !findings.isEmpty else {
    print("✅ No unsafe patterns found in \(filePath)")
    exit(0)
}

print("⚠️  Found \(findings.count) unsafe patterns(s) in \(filePath)\n")

// MARK: - Suggest

var suggestions: [String] = []
var updatedFindings: [Finding] = []

for finding in findings {
    let context = ContextExtractor.extract(
        from: source,
        around: finding.line
    )
    let guardedFinding = finding.update(
        isGuarded: NilCheckDetector
            .isGuarded(
            expression: finding.expression,
            source: source,
            around: finding.line
        )
    )
    updatedFindings.append(guardedFinding)

    print("  Line \(guardedFinding.line), Col \(guardedFinding.column): \(guardedFinding.expression)")
    
    if guardedFinding.isGuarded {
        print("  ⚠️  Note: a nil check was detected nearby")
    }
    print(context)
    print("\n  💡 Asking Claude for a fix...")
    
    do {
        let suggestion = try await ClaudeService.suggest(for: guardedFinding, context: context)
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
    findings: updatedFindings,
    suggestions: suggestions
)

try SourceAnnotator.write(annotatedSource: annotated, originalPath: filePath)

// MARK: - Summary
let totalUnwraps = updatedFindings.filter { $0.type == .forceUnwrap }.count
let guardedUnwraps = updatedFindings.filter { $0.type == .forceUnwrap && $0.isGuarded }.count
let totalTries = updatedFindings.filter { $0.type == .forceTry }.count
let totalCasts = updatedFindings.filter { $0.type == .forceCast }.count

print("""
📊 Summary
   Force unwraps : \(totalUnwraps) (\(guardedUnwraps) guarded)
   Force try     : \(totalTries)
   Force casts   : \(totalCasts)
   Total         : \(findings.count)
""")
