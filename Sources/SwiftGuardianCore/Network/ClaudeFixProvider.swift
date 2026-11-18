import Foundation

/// Asks Claude for a drop-in replacement of a numbered range of lines.
public struct ClaudeFixProvider: FixProvider {
    public let model: String

    public init(model: String = ProcessInfo.processInfo.environment["SWIFT_GUARDIAN_MODEL"] ?? "claude-haiku-5-5") {
        self.model = model
    }

    public func proposeFix(
        for finding: Finding,
        excerpt: String,
        range: ClosedRange<Int>,
        feedback: String?
    ) async throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] else {
            throw ClaudeService.ClaudeError.missingAPIKey
        }

        let system = """
        You are a Swift refactoring tool. You receive a numbered excerpt of a Swift file and one \
        unsafe pattern inside it. Reply with ONLY the replacement for every line of the excerpt, \
        as Swift code in a single ```swift block, without line numbers and without explanation. \
        Keep the original indentation and behaviour, change only what is needed to remove the \
        unsafe pattern, and never introduce force unwraps (!), try! or as!. Lines outside the \
        excerpt cannot be changed, so the replacement must compile in place.
        """

        var prompt = """
        Unsafe pattern: \(finding.type.displayName) on `\(finding.expression)` at line \(finding.line).
        Rewrite lines \(range.lowerBound)-\(range.upperBound):

        \(excerpt)
        """
        if let feedback {
            prompt += "\n\n\(feedback)"
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": system,
            "messages": [["role": "user", "content": prompt]]
        ]
        let headers = [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01"
        ]

        let url = URL(string: "https://api.anthropic.com/v1/messages")
        guard let url else { throw ClaudeService.ClaudeError.noSuggestionReturned }
        let json = try await APIClient.post(url: url, headers: headers, body: body)
        return try Self.text(from: json)
    }

    /// Joins every text block. Newer models can return other block types (for example
    /// thinking) before the text, so the first block is not always the answer.
    static func text(from json: [String: Any]) throws -> String {
        let blocks = json["content"] as? [[String: Any]] ?? []
        let texts = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }
        guard !texts.isEmpty else {
            throw ClaudeFixProviderError.noTextInResponse(
                stopReason: json["stop_reason"] as? String,
                blockTypes: blocks.compactMap { $0["type"] as? String }
            )
        }
        return texts.joined(separator: "\n")
    }
}

public enum ClaudeFixProviderError: Error, CustomStringConvertible {
    case noTextInResponse(stopReason: String?, blockTypes: [String])

    public var description: String {
        switch self {
        case .noTextInResponse(let stopReason, let blockTypes):
            let types = blockTypes.isEmpty ? "none" : blockTypes.joined(separator: ", ")
            return "no text in Claude's response (stop_reason: \(stopReason ?? "unknown"), blocks: \(types))"
        }
    }
}
