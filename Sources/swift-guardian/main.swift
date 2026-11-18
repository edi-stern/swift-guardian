import SwiftGuardianCore
import SwiftSyntax
import SwiftParser
import Foundation

// MARK: - Functions

func analyzeFile(_ path: String) async -> [Finding] {
    do {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        return Analyzer.analyze(source: source, fileName: path)
    } catch {
        print("❌ Error reading \(path): \(error.localizedDescription)")
        return []
    }
}

/// Builds the optional build/test gate: writes the candidate source over the file, runs the
/// command, and always restores the original contents afterwards.
func makeCommandCheck(command: String, filePath: String, original: String) -> (String) async -> Bool {
    return { patched in
        do {
            try patched.write(toFile: filePath, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        defer { try? original.write(toFile: filePath, atomically: true, encoding: .utf8) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
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

let usage = """
Usage: swift-guardian <path-to-swift-file-or-directory> [options]

Options (single file only):
  --fix                     Generate fixes with Claude and keep only the ones that pass verification
  --verify-command "<cmd>"  Also require this command (e.g. "swift build") to succeed for each fix; implies --fix
  --attempts <n>            Attempts per finding, with feedback on each rejection (default 2)
  --in-place                Overwrite the original file instead of writing <name>.fixed.swift
"""

let arguments = Array(CommandLine.arguments.dropFirst())

func optionValue(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

let verifyCommand = optionValue("--verify-command")
let fixMode = arguments.contains("--fix") || verifyCommand != nil
let inPlace = arguments.contains("--in-place")
let maxAttempts = optionValue("--attempts").flatMap { Int($0) } ?? 2
let optionValueIndices = Set(["--verify-command", "--attempts"].compactMap { name in
    arguments.firstIndex(of: name).map { $0 + 1 }
})

guard let inputPath = arguments.enumerated().first(where: { item in
    !item.element.hasPrefix("--") && !optionValueIndices.contains(item.offset)
})?.element else {
    print(usage)
    exit(1)
}

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
    if fixMode {
        print("ℹ️  --fix works on a single file; showing a report for the directory instead.\n")
    }
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
    // MARK: - Single file mode
    let filePath = files[0]
    let source = try String(contentsOfFile: filePath, encoding: .utf8)
    let findings = allFindings.map { $0.finding }

    if fixMode {
        // MARK: Verified remediation: propose, verify, retry, keep only what passes
        print("⚠️  Found \(findings.count) unsafe pattern(s) in \(filePath)")
        let gateNote = verifyCommand.map { " (gate: `" + $0 + "`)" } ?? ""
        print("🔧 Generating fixes and verifying each one\(gateNote)...\n")

        let engine = RemediationEngine(
            provider: ClaudeFixProvider(),
            maxAttempts: maxAttempts,
            externalCheck: verifyCommand.map { makeCommandCheck(command: $0, filePath: filePath, original: source) }
        )
        let report = await engine.run(source: source, fileName: filePath)

        for outcome in report.outcomes {
            let f = outcome.finding
            let tries = outcome.attempts == 1 ? "1 attempt" : "\(outcome.attempts) attempts"
            switch outcome.result {
            case .verified:
                print("  ✅ Line \(f.line): \(f.expression): fixed and verified (\(tries))")
                for extra in outcome.alsoResolved {
                    print("     ↳ also resolved line \(extra.line): \(extra.expression)")
                }
            case .rejected(let reason):
                print("  ❌ Line \(f.line): \(f.expression): rejected after \(tries): \(reason)")
            }
        }

        if report.verifiedCount > 0 {
            let outputPath = inPlace
                ? filePath
                : URL(fileURLWithPath: filePath).deletingPathExtension().appendingPathExtension("fixed.swift").path
            try report.fixedSource.write(toFile: outputPath, atomically: true, encoding: .utf8)
            print("\n📝 \(report.verifiedCount) verified fix(es) written to:\n   \(outputPath)")
        } else {
            print("\nNo fix passed verification; the file was left unchanged.")
        }
        let resolvedCount = findings.count - report.remainingFindings.count
        print("   Verified fixes: \(report.verifiedCount)  Rejected: \(report.rejectedCount)")
        print("   Unsafe patterns resolved: \(resolvedCount) of \(findings.count)\n")
    } else {

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
}

// MARK: - Summary

let updatedForSummary = allFindings.map { $0.finding }
let totalUnwraps = updatedForSummary.filter { $0.type == .forceUnwrap }.count
let guardedUnwraps = updatedForSummary.filter { $0.type == .forceUnwrap && $0.isGuarded }.count
let totalTries = updatedForSummary.filter { $0.type == .forceTry }.count
let totalCasts = updatedForSummary.filter { $0.type == .forceCast }.count

let summaryTitle = (fixMode && !isDirectory) ? "📊 Found (before fixes)" : "📊 Summary"
print("""
\(summaryTitle)
   Force unwraps : \(totalUnwraps) (\(guardedUnwraps) guarded)
   Force try     : \(totalTries)
   Force casts   : \(totalCasts)
   Total         : \(allFindings.count)
""")
