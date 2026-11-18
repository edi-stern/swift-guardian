import Testing
import Foundation
@testable import SwiftGuardianCore

// MARK: - Helpers

/// Returns canned responses in order and records the feedback it receives.
final class StubFixProvider: FixProvider {
    private var responses: [String]
    private(set) var feedbacks: [String?] = []

    init(_ responses: [String]) {
        self.responses = responses
    }

    func proposeFix(
        for finding: Finding,
        excerpt: String,
        range: ClosedRange<Int>,
        feedback: String?
    ) async throws -> String {
        feedbacks.append(feedback)
        return responses.isEmpty ? "" : responses.removeFirst()
    }
}

struct ProviderFailure: Error {}

final class FailingFixProvider: FixProvider {
    func proposeFix(
        for finding: Finding,
        excerpt: String,
        range: ClosedRange<Int>,
        feedback: String?
    ) async throws -> String {
        throw ProviderFailure()
    }
}

let optionalSource = "let a: Int? = 1\nlet b = a!"

func firstFinding(in source: String) throws -> Finding {
    try #require(Analyzer.analyze(source: source).first)
}

// MARK: - LinePatch

@Suite("LinePatch")
struct LinePatchTests {

    @Test func replacesSingleLine() {
        let patch = LinePatch(startLine: 2, endLine: 2, replacement: "x")
        #expect(patch.apply(to: "a\nb\nc") == "a\nx\nc")
    }

    @Test func replacementCanChangeLineCount() {
        let patch = LinePatch(startLine: 2, endLine: 2, replacement: "x\ny")
        #expect(patch.apply(to: "a\nb\nc") == "a\nx\ny\nc")
    }

    @Test func rejectsRangeOutsideSource() {
        let patch = LinePatch(startLine: 3, endLine: 4, replacement: "x")
        #expect(patch.apply(to: "a\nb\nc") == nil)
    }
}

// MARK: - FixResponseParser

@Suite("FixResponseParser")
struct FixResponseParserTests {

    @Test func extractsFencedCode() {
        let response = "Here is the fix:\n```swift\nlet b = a ?? 0\n```\nDone."
        let patch = FixResponseParser.parse(response, range: 2...2)
        #expect(patch?.replacement == "let b = a ?? 0")
    }

    @Test func stripsEchoedLineNumbersButKeepsIndentation() {
        let response = "```swift\n  2:     let b = a ?? 0\n```"
        let patch = FixResponseParser.parse(response, range: 2...2)
        #expect(patch?.replacement == "    let b = a ?? 0")
    }

    @Test func returnsNilForEmptyResponse() {
        #expect(FixResponseParser.parse("```swift\n```", range: 1...1) == nil)
    }
}

// MARK: - FixVerifier

@Suite("FixVerifier")
struct FixVerifierTests {

    @Test func acceptsFixThatRemovesTheFinding() throws {
        let target = try firstFinding(in: optionalSource)
        let patched = "let a: Int? = 1\nlet b = a ?? 0"
        #expect(FixVerifier.verify(original: optionalSource, patched: patched, target: target) == .verified)
    }

    @Test func rejectsUnchangedCode() throws {
        let target = try firstFinding(in: optionalSource)
        #expect(FixVerifier.verify(original: optionalSource, patched: optionalSource, target: target)
                == .rejected(.unchanged))
    }

    @Test func rejectsInvalidSwift() throws {
        let target = try firstFinding(in: optionalSource)
        let patched = "let a: Int? = 1\nlet b = (a ?? 0"
        #expect(FixVerifier.verify(original: optionalSource, patched: patched, target: target)
                == .rejected(.syntaxError))
    }

    @Test func rejectsFixThatKeepsThePattern() throws {
        let target = try firstFinding(in: optionalSource)
        let patched = "let a: Int? = 1\nlet b = a! // reviewed"
        #expect(FixVerifier.verify(original: optionalSource, patched: patched, target: target)
                == .rejected(.findingNotResolved))
    }

    @Test func rejectsFixThatIntroducesAnotherUnsafePattern() throws {
        let target = try firstFinding(in: optionalSource)
        let patched = "let a: Int? = 1\nlet b = try! compute(a ?? 0)"
        #expect(FixVerifier.verify(original: optionalSource, patched: patched, target: target)
                == .rejected(.introducedFindings([.forceTry])))
    }

    @Test func fixingAnInnerPatternDoesNotCountAsNewOuterFinding() throws {
        let source = "let d = try! Data(contentsOf: URL(string: s)!)"
        let target = try #require(Analyzer.analyze(source: source).first { $0.type == .forceUnwrap })
        let patched = "let d = try! Data(contentsOf: url)"
        #expect(FixVerifier.verify(original: source, patched: patched, target: target) == .verified)
    }
}

// MARK: - RemediationEngine

@Suite("RemediationEngine")
struct RemediationEngineTests {

    @Test func appliesVerifiedFix() async {
        let engine = RemediationEngine(provider: StubFixProvider(["let b = a ?? 0"]), contextRadius: 0)
        let report = await engine.run(source: optionalSource)
        #expect(report.verifiedCount == 1)
        #expect(report.fixedSource == "let a: Int? = 1\nlet b = a ?? 0")
    }

    @Test func retriesWithFeedbackAfterRejection() async {
        let provider = StubFixProvider(["let b = a!", "let b = a ?? 0"])
        let engine = RemediationEngine(provider: provider, maxAttempts: 2, contextRadius: 0)
        let report = await engine.run(source: optionalSource)
        #expect(report.outcomes.first?.attempts == 2)
        #expect(report.outcomes.first?.result == .verified)
        #expect(provider.feedbacks.first == .some(nil))
        #expect(provider.feedbacks.last??.contains("rejected") == true)
    }

    @Test func leavesFileUnchangedWhenNoFixPasses() async {
        let bad = "let b = try! compute(a ?? 0)"
        let engine = RemediationEngine(provider: StubFixProvider([bad, bad]), maxAttempts: 2, contextRadius: 0)
        let report = await engine.run(source: optionalSource)
        #expect(report.verifiedCount == 0)
        #expect(report.fixedSource == optionalSource)
        #expect(report.outcomes.first?.result == .rejected(.introducedFindings([.forceTry])))
    }

    @Test func externalCheckCanRejectAFix() async {
        let engine = RemediationEngine(
            provider: StubFixProvider(["let b = a ?? 0"]),
            maxAttempts: 1,
            contextRadius: 0,
            externalCheck: { _ in false }
        )
        let report = await engine.run(source: optionalSource)
        #expect(report.outcomes.first?.result == .rejected(.verificationCommandFailed))
        #expect(report.fixedSource == optionalSource)
    }

    @Test func fixesSeveralFindingsInSequence() async {
        let source = "let a: Int? = 1\nlet b = a!\nlet c = a!"
        let engine = RemediationEngine(
            provider: StubFixProvider(["let b = a ?? 0", "let c = a ?? 0"]),
            contextRadius: 0
        )
        let report = await engine.run(source: source)
        #expect(report.verifiedCount == 2)
        #expect(Analyzer.analyze(source: report.fixedSource).isEmpty)
    }

    @Test func skipsRejectedFindingAndMovesOn() async {
        let source = "let a: Int? = 1\nlet b = a!\nlet c = a!"
        let engine = RemediationEngine(
            provider: StubFixProvider(["let b = a!", "let c = a ?? 0"]),
            maxAttempts: 1,
            contextRadius: 0
        )
        let report = await engine.run(source: source)
        #expect(report.outcomes.count == 2)
        #expect(report.verifiedCount == 1)
        #expect(report.fixedSource == "let a: Int? = 1\nlet b = a!\nlet c = a ?? 0")
    }

    @Test func reportsProviderErrors() async {
        let engine = RemediationEngine(provider: FailingFixProvider(), contextRadius: 0)
        let report = await engine.run(source: optionalSource)
        guard case .rejected(.providerError)? = report.outcomes.first?.result else {
            Issue.record("Expected a provider error")
            return
        }
        #expect(report.fixedSource == optionalSource)
    }
}

// MARK: - ClaudeFixProvider response parsing

@Suite("ClaudeFixProvider")
struct ClaudeFixProviderTests {

    @Test func readsTextAfterNonTextBlocks() throws {
        let json: [String: Any] = [
            "content": [
                ["type": "thinking", "thinking": "..."],
                ["type": "text", "text": "```swift\nlet b = a ?? 0\n```"]
            ]
        ]
        #expect(try ClaudeFixProvider.text(from: json).contains("a ?? 0"))
    }

    @Test func explainsResponsesWithoutText() {
        let json: [String: Any] = ["content": [["type": "thinking"]], "stop_reason": "max_tokens"]
        #expect(throws: ClaudeFixProviderError.self) {
            try ClaudeFixProvider.text(from: json)
        }
    }
}

// MARK: - Side-effect fixes

@Suite("Side-effect fixes")
struct SideEffectFixTests {

    @Test func reportsFindingsRemovedByAWiderFix() async {
        let source = "let a: Int? = 1\nlet b = a!\nlet c = try! f(b)"
        let wider = "let a: Int? = 1\nguard let b = a, let c = try? f(b) else { return }"
        let engine = RemediationEngine(provider: StubFixProvider([wider]), contextRadius: 1)
        let report = await engine.run(source: source)
        #expect(report.outcomes.count == 1)
        #expect(report.outcomes.first?.alsoResolved.map(\.type) == [.forceTry])
        #expect(report.remainingFindings.isEmpty)
    }
}

// MARK: - Original line numbers

@Suite("Original line numbers")
struct OriginalLineTests {

    @Test func reportsLinesFromTheOriginalFile() async {
        let source = "let a: Int? = 1\nlet b = a!\nlet z = 0\nlet c = a!"
        let engine = RemediationEngine(
            provider: StubFixProvider([
                "guard let x = a else { return }\nlet b = x",  // line 2 grows by one line
                "let c = a ?? 0"                              // was line 4, now line 5
            ]),
            contextRadius: 0
        )
        let report = await engine.run(source: source)
        #expect(report.outcomes.map(\.finding.line) == [2, 4])
        #expect(report.verifiedCount == 2)
    }

    @Test func lineBeforeAPatchIsUnchanged() {
        let patch = LinePatch(startLine: 5, endLine: 5, replacement: "a\nb\nc")
        #expect(RemediationEngine.originalLine(of: 3, through: [patch]) == 3)
        #expect(RemediationEngine.originalLine(of: 8, through: [patch]) == 6)
    }
}
