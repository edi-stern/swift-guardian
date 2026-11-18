import SwiftSyntax
import SwiftParser

/// Runs every detector over a source string. Shared by the CLI and by the
/// fix verifier, so a fix is checked with exactly the same rules that found the issue.
public enum Analyzer {
    public static func analyze(source: String, fileName: String = "input.swift") -> [Finding] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: fileName, tree: tree)

        let unwrapVisitor = ForceUnwrapVisitor(locationConverter: converter)
        unwrapVisitor.walk(tree)

        let tryVisitor = ForceTryVisitor(locationConverter: converter)
        tryVisitor.walk(tree)

        let castVisitor = ForceCastVisitor(locationConverter: converter)
        castVisitor.walk(tree)

        return (unwrapVisitor.findings + tryVisitor.findings + castVisitor.findings)
            .sorted { ($0.line, $0.column) < ($1.line, $1.column) }
    }

    /// True when SwiftParser had to recover from invalid syntax.
    public static func hasSyntaxErrors(_ source: String) -> Bool {
        Parser.parse(source: source).hasError
    }
}
