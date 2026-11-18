/// Why a proposed fix was not accepted.
public enum RejectionReason: Equatable, CustomStringConvertible {
    case providerError(String)
    case unparseableResponse
    case patchOutOfRange
    case unchanged
    case syntaxError
    case findingNotResolved
    case introducedFindings([FindingType])
    case verificationCommandFailed

    public var description: String {
        switch self {
        case .providerError(let message): return "the fix provider failed: \(message)"
        case .unparseableResponse: return "the response did not contain usable Swift code"
        case .patchOutOfRange: return "the patch did not fit the requested lines"
        case .unchanged: return "the code was returned unchanged"
        case .syntaxError: return "the patched file no longer parses as valid Swift"
        case .findingNotResolved: return "the unsafe pattern is still present"
        case .introducedFindings(let types):
            let names = types.map(\.displayName).joined(separator: ", ")
            return "the fix introduced new unsafe patterns: \(names)"
        case .verificationCommandFailed: return "the verification command (build or tests) failed"
        }
    }
}

public enum VerificationResult: Equatable {
    case verified
    case rejected(RejectionReason)
}

/// Checks a patched source against the original with the same rules that found the issue:
/// the file must still parse, the target finding must be gone, and nothing new may appear.
public enum FixVerifier {
    public static func verify(original: String, patched: String, target: Finding) -> VerificationResult {
        guard patched != original else { return .rejected(.unchanged) }

        if Analyzer.hasSyntaxErrors(patched) && !Analyzer.hasSyntaxErrors(original) {
            return .rejected(.syntaxError)
        }

        let before = countsByType(Analyzer.analyze(source: original))
        let after = countsByType(Analyzer.analyze(source: patched))

        let introduced = FindingType.allCases.filter { (after[$0] ?? 0) > (before[$0] ?? 0) }
        if !introduced.isEmpty { return .rejected(.introducedFindings(introduced)) }

        guard (after[target.type] ?? 0) < (before[target.type] ?? 0) else {
            return .rejected(.findingNotResolved)
        }
        return .verified
    }

    /// Counting by type (not by exact text) keeps the check stable when fixing an inner
    /// pattern changes the text of an outer one, e.g. `try! Data(contentsOf: URL(string: s)!)`.
    static func countsByType(_ findings: [Finding]) -> [FindingType: Int] {
        findings.reduce(into: [:]) { $0[$1.type, default: 0] += 1 }
    }
}
