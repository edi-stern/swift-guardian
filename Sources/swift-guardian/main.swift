import SwiftGuardianCore
import SwiftSyntax
import SwiftParser
import Foundation

// MARK: - Functions

func analyzeFile(_ path: String) async -> [Finding] {
    do {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: path, tree: tree)

        let unwrapVisitor = ForceUnwrapVisitor(locationConverter: converter)
        unwrapVisitor.walk(tree)

        let tryVisitor = ForceTryVisitor(locationConverter: converter)
        tryVisitor.walk(tree)

        let forceCastVisitor = ForceCastVisitor(locationConverter: converter)
        forceCastVisitor.walk(tree)

        return (unwrapVisitor.findings + tryVisitor.findings + forceCastVisitor.findings)
            .sorted { $0.line < $1.line }
    } catch {
        print("❌ Error reading \(path): \(error.localizedDescription)")
        return []
    }
}

func swiftFiles(at path: String) -> [String] {
    var isDirectory: ObjCBool = false
    FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)

    if !isDirectory.boolValue {
        return [path]
    }

    guard let enumerator = FileManager.default.enumerator(atPath: path) else {
        return []
    }

    var files: [String] = []
    while let file = enumerator.nextObject() as? String {
        if file.hasSuffix(".swift") {
            files.append(path + "/" + file)
        }
    }
    return files
}

// MARK: - Entry point

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift-guardian <path-to-swift-file-or-directory>")
    exit(1)
}

let inputPath = CommandLine.arguments[1]

guard FileManager.default.fileExists(atPath: inputPath) else {
    print("❌ Path not found: \(inputPath)")
    exit(1)
}

let files = swiftFiles(at: inputPath)
let isDirectory = files.count > 1

// MARK: - Analyse

var allFindings: [(file: String, finding: Finding)] = []

for file in files {
    let findings = await analyzeFile(file)
    for finding in findings {
        allFindings.append((file: file, finding: finding))
    }
}

guard !allFindings.isEmpty else {
    print("✅ No unsafe patterns found in \(inputPath)")
    exit(0)
}

// MARK: - Directory mode: report only, no Claude suggestions

if isDirectory {
    print("⚠️  Found \(allFindings.count) unsafe pattern(s) across \(files.count) files\n")
    var currentFile = ""
    for item in allFindings {
        if item.file != currentFile {
            currentFile = item.file
            print("\n📄 \(currentFile)")
        }
        let f = item.finding
        let guardedNote = f.isGuarded ? " [guarded]" : ""
        print("   Line \(f.line), Col \(f.column): \(f.expression)\(guardedNote)")
    }
} else {
    // MARK: - Single file mode: full analysis with Claude suggestions
    let filePath = files[0]
    let source = try String(contentsOfFile: filePath, encoding: .utf8)
    let findings = allFindings.map { $0.finding }

    print("⚠️  Found \(findings.count) unsafe pattern(s) in \(filePath)\n")

    var suggestions: [String] = []
    var updatedFindings: [Finding] = []

    for finding in findings {
        let context = ContextExtractor.extract(from: source, around: finding.line)
        let guardedFinding = finding.update(
            isGuarded: NilCheckDetector.isGuarded(
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

    let annotated = SourceAnnotator.annotate(
        source: source,
        findings: updatedFindings,
        suggestions: suggestions
    )
    try SourceAnnotator.write(annotatedSource: annotated, originalPath: filePath)
}

// MARK: - Summary

let updatedForSummary = allFindings.map { $0.finding }
let totalUnwraps = updatedForSummary.filter { $0.type == .forceUnwrap }.count
let guardedUnwraps = updatedForSummary.filter { $0.type == .forceUnwrap && $0.isGuarded }.count
let totalTries = updatedForSummary.filter { $0.type == .forceTry }.count
let totalCasts = updatedForSummary.filter { $0.type == .forceCast }.count

print("""
📊 Summary
   Force unwraps : \(totalUnwraps) (\(guardedUnwraps) guarded)
   Force try     : \(totalTries)
   Force casts   : \(totalCasts)
   Total         : \(allFindings.count)
""")
