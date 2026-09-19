import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftGuardianCore

// MARK: - Helpers

func makeUnwrapVisitor(source: String) -> ForceUnwrapVisitor {
    let tree = Parser.parse(source: source)
    let converter = SourceLocationConverter(fileName: "test.swift", tree: tree)
    let visitor = ForceUnwrapVisitor(locationConverter: converter)
    visitor.walk(tree)
    return visitor
}

func makeTryVisitor(source: String) -> ForceTryVisitor {
    let tree = Parser.parse(source: source)
    let converter = SourceLocationConverter(fileName: "test.swift", tree: tree)
    let visitor = ForceTryVisitor(locationConverter: converter)
    visitor.walk(tree)
    return visitor
}

func fixtureSource(_ name: String) throws -> String {
    let url = Bundle.module.url(
        forResource: name,
        withExtension: "swift",
        subdirectory: "Fixtures"
    )!
    return try String(contentsOf: url, encoding: .utf8)
}

// MARK: - ContextExtractor

@Suite("ContextExtractor")
struct ContextExtractorTests {

    @Test func extractsCorrectLines() {
        let source = "line1\nline2\nline3\nline4\nline5\nline6\nline7"
        let result = ContextExtractor.extract(from: source, around: 4, radius: 2)
        #expect(result.contains("line2"))
        #expect(result.contains("line3"))
        #expect(result.contains("line4"))
        #expect(result.contains("line5"))
        #expect(result.contains("line6"))
        #expect(!result.contains("line1"))
        #expect(!result.contains("line7"))
    }

    @Test func handlesStartOfFile() {
        let source = "line1\nline2\nline3\nline4\nline5"
        let result = ContextExtractor.extract(from: source, around: 1, radius: 3)
        #expect(result.contains("line1"))
        #expect(result.contains("line4"))
    }

    @Test func handlesEndOfFile() {
        let source = "line1\nline2\nline3\nline4\nline5"
        let result = ContextExtractor.extract(from: source, around: 5, radius: 3)
        #expect(result.contains("line5"))
        #expect(!result.contains("line1"))
    }
}

// MARK: - SourceAnnotator

@Suite("SourceAnnotator")
struct SourceAnnotatorTests {

    @Test func insertsSuggestionAboveFinding() {
        let source = "let a = 1\nlet b = foo!\nlet c = 3"
        let finding = Finding(line: 2, column: 9, expression: "foo!")
        let result = SourceAnnotator.annotate(
            source: source,
            findings: [finding],
            suggestions: ["let b = foo ?? defaultValue"]
        )
        let lines = result.components(separatedBy: .newlines)
        let commentIndex = lines.firstIndex(where: { $0.contains("💡") })!
        let findingIndex = lines.firstIndex(where: { $0.contains("foo!") })!
        #expect(commentIndex < findingIndex)
    }

    @Test func stripsMarkdownFences() {
        let source = "let a = 1\nlet b = foo!\nlet c = 3"
        let finding = Finding(line: 2, column: 9, expression: "foo!")
        let result = SourceAnnotator.annotate(
            source: source,
            findings: [finding],
            suggestions: ["```swift\nlet b = foo ?? defaultValue\n```"]
        )
        #expect(!result.contains("```"))
        #expect(result.contains("let b = foo ?? defaultValue"))
    }

    @Test func multiplesFindingsInsertedInOrder() {
        let source = "let a = foo!\nlet b = 2\nlet c = bar!"
        let findings = [
            Finding(line: 1, column: 9, expression: "foo!"),
            Finding(line: 3, column: 9, expression: "bar!")
        ]
        let result = SourceAnnotator.annotate(
            source: source,
            findings: findings,
            suggestions: ["fix for foo", "fix for bar"]
        )
        let fooIndex = result.range(of: "fix for foo")!.lowerBound
        let barIndex = result.range(of: "fix for bar")!.lowerBound
        #expect(fooIndex < barIndex)
    }
}

// MARK: - ForceUnwrapVisitor

@Suite("ForceUnwrapVisitor")
struct ForceUnwrapVisitorTests {

    @Test func detectsForceUnwrap() {
        let source = "let a: String? = nil\nlet b = a!"
        let visitor = makeUnwrapVisitor(source: source)
        #expect(visitor.findings.count == 1)
        #expect(visitor.findings[0].line == 2)
        #expect(visitor.findings[0].expression == "a!")
    }

    @Test func ignoresSafeUnwrap() {
        let source = "let a: String? = nil\nlet b = a ?? \"default\""
        let visitor = makeUnwrapVisitor(source: source)
        #expect(visitor.findings.count == 0)
    }

    @Test func detectsMultipleUnwraps() {
        let source = "let a = foo!\nlet b = bar!\nlet c = baz ?? \"\""
        let visitor = makeUnwrapVisitor(source: source)
        #expect(visitor.findings.count == 2)
    }
}

// MARK: - ForceTryVisitor

@Suite("ForceTryVisitor")
struct ForceTryVisitorTests {

    @Test func detectsForceTry() {
        let source = "let data = try! Data(contentsOf: url)"
        let visitor = makeTryVisitor(source: source)
        #expect(visitor.findings.count == 1)
        #expect(visitor.findings[0].line == 1)
    }

    @Test func ignoresSafeTry() {
        let source = "let data = try? Data(contentsOf: url)"
        let visitor = makeTryVisitor(source: source)
        #expect(visitor.findings.count == 0)
    }

    @Test func ignoresPlainTry() {
        let source = "func f() throws {}\nlet x = try f()"
        let visitor = makeTryVisitor(source: source)
        #expect(visitor.findings.count == 0)
    }
}

// MARK: - Fixture

@Suite("Fixture")
struct FixtureTests {

    @Test func detectsKnownFindingsInSampleFile() throws {
        let source = try fixtureSource("sample")
        let unwrapVisitor = makeUnwrapVisitor(source: source)
        let tryVisitor = makeTryVisitor(source: source)
        let findings = (unwrapVisitor.findings + tryVisitor.findings)
            .sorted { $0.line < $1.line }
        #expect(findings.count == 3)
    }
}
