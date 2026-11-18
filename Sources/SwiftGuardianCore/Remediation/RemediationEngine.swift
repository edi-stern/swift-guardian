/// Anything that can propose replacement code for a range of lines (Claude in the CLI,
/// a stub in tests).
public protocol FixProvider {
    /// - Parameters:
    ///   - excerpt: the lines in `range`, numbered as "  12: code".
    ///   - feedback: why the previous attempt was rejected, if this is a retry.
    func proposeFix(
        for finding: Finding,
        excerpt: String,
        range: ClosedRange<Int>,
        feedback: String?
    ) async throws -> String
}

public struct RemediationOutcome {
    /// The finding, with its line number as it was in the original file.
    public var finding: Finding
    public let result: VerificationResult
    public let attempts: Int
    public let patch: LinePatch?
    /// Other findings the accepted fix removed as a side effect.
    public var alsoResolved: [Finding] = []
}

public struct RemediationReport {
    public let originalSource: String
    public let fixedSource: String
    public let outcomes: [RemediationOutcome]

    public var verifiedCount: Int { outcomes.filter { $0.result == .verified }.count }
    public var rejectedCount: Int { outcomes.count - verifiedCount }
    public var remainingFindings: [Finding] { Analyzer.analyze(source: fixedSource) }
}

/// Find, fix, verify, retry. Only fixes that pass verification are kept; each accepted fix
/// becomes the baseline for the next finding, so fixes never conflict with each other.
public struct RemediationEngine {
    public let provider: any FixProvider
    public let maxAttempts: Int
    public let contextRadius: Int
    /// Optional extra gate, e.g. writing the file and running `swift build`.
    public let externalCheck: ((String) async -> Bool)?

    public init(
        provider: any FixProvider,
        maxAttempts: Int = 2,
        contextRadius: Int = 3,
        externalCheck: ((String) async -> Bool)? = nil
    ) {
        self.provider = provider
        self.maxAttempts = max(1, maxAttempts)
        self.contextRadius = max(0, contextRadius)
        self.externalCheck = externalCheck
    }

    public func run(source: String, fileName: String = "input.swift") async -> RemediationReport {
        var current = source
        var outcomes: [RemediationOutcome] = []
        // Accepted patches in order, used to report line numbers from the original file.
        var applied: [LinePatch] = []
        // Rejected findings stay in the file; skip that many occurrences of each signature.
        var skipped: [String: Int] = [:]
        let iterationLimit = Analyzer.analyze(source: source, fileName: fileName).count * 2 + 10

        for _ in 0..<iterationLimit {
            guard let target = nextTarget(in: current, fileName: fileName, skipping: skipped) else { break }

            var outcome = await remediate(target, in: current)
            outcome.finding = Self.mapToOriginal(target, through: applied)

            if outcome.result == .verified, let patch = outcome.patch, let patched = patch.apply(to: current) {
                outcome.alsoResolved = Self.sideEffectFixes(before: current, after: patched, target: target)
                    .map { Self.mapToOriginal($0, through: applied) }
                outcomes.append(outcome)
                applied.append(patch)
                current = patched
            } else {
                outcomes.append(outcome)
                skipped[Self.signature(of: target), default: 0] += 1
            }
        }

        return RemediationReport(originalSource: source, fixedSource: current, outcomes: outcomes)
    }

    func remediate(_ target: Finding, in source: String) async -> RemediationOutcome {
        let lineCount = source.components(separatedBy: "\n").count
        let range = max(1, target.line - contextRadius)...min(lineCount, target.line + contextRadius)
        let excerpt = Self.numberedExcerpt(of: source, range: range)

        var feedback: String?
        var lastResult = VerificationResult.rejected(.unparseableResponse)
        var lastPatch: LinePatch?

        for attempt in 1...maxAttempts {
            let response: String
            do {
                response = try await provider.proposeFix(
                    for: target, excerpt: excerpt, range: range, feedback: feedback
                )
            } catch {
                return RemediationOutcome(
                    finding: target,
                    result: .rejected(.providerError(String(describing: error))),
                    attempts: attempt,
                    patch: nil
                )
            }

            if let patch = FixResponseParser.parse(response, range: range) {
                lastPatch = patch
                if let patched = patch.apply(to: source) {
                    lastResult = FixVerifier.verify(original: source, patched: patched, target: target)
                    if lastResult == .verified, let check = externalCheck, !(await check(patched)) {
                        lastResult = .rejected(.verificationCommandFailed)
                    }
                } else {
                    lastResult = .rejected(.patchOutOfRange)
                }
            } else {
                lastPatch = nil
                lastResult = .rejected(.unparseableResponse)
            }

            if lastResult == .verified {
                return RemediationOutcome(finding: target, result: .verified, attempts: attempt, patch: lastPatch)
            }
            if case .rejected(let reason) = lastResult {
                feedback = "Your previous fix was rejected because \(reason). Propose a different fix."
            }
        }
        return RemediationOutcome(finding: target, result: lastResult, attempts: maxAttempts, patch: lastPatch)
    }

    func nextTarget(in source: String, fileName: String, skipping skipped: [String: Int]) -> Finding? {
        var seen: [String: Int] = [:]
        for finding in Analyzer.analyze(source: source, fileName: fileName) {
            let key = Self.signature(of: finding)
            let index = seen[key, default: 0]
            seen[key] = index + 1
            if index >= skipped[key, default: 0] { return finding }
        }
        return nil
    }

    /// Maps a line in the partially fixed file back to the original file by undoing the
    /// line shifts of each accepted patch, newest first.
    static func originalLine(of line: Int, through applied: [LinePatch]) -> Int {
        applied.reversed().reduce(line) { current, patch in
            let replacedCount = patch.endLine - patch.startLine + 1
            let insertedCount = patch.replacement.components(separatedBy: "\n").count
            if current < patch.startLine { return current }
            if current >= patch.startLine + insertedCount {
                return current - (insertedCount - replacedCount)
            }
            // Inside code written by an earlier fix: point at the matching original line.
            return patch.startLine + min(current - patch.startLine, replacedCount - 1)
        }
    }

    static func mapToOriginal(_ finding: Finding, through applied: [LinePatch]) -> Finding {
        Finding(
            line: originalLine(of: finding.line, through: applied),
            column: finding.column,
            expression: finding.expression,
            type: finding.type,
            isGuarded: finding.isGuarded
        )
    }

    /// Findings present before but not after, excluding one occurrence of the target.
    static func sideEffectFixes(before: String, after: String, target: Finding) -> [Finding] {
        var remaining = Analyzer.analyze(source: after).map(signature(of:))
        var targetPending = true
        return Analyzer.analyze(source: before).filter { finding in
            let key = signature(of: finding)
            if let index = remaining.firstIndex(of: key) {
                remaining.remove(at: index)
                return false
            }
            if targetPending && key == signature(of: target) {
                targetPending = false
                return false
            }
            return true
        }
    }

    static func signature(of finding: Finding) -> String {
        "\(finding.type.displayName):\(finding.expression)"
    }

    static func numberedExcerpt(of source: String, range: ClosedRange<Int>) -> String {
        let lines = source.components(separatedBy: "\n")
        return range.map { "  \($0): \(lines[$0 - 1])" }.joined(separator: "\n")
    }
}
