import Foundation

public enum ClaudeService {
    public enum ClaudeError: Error {
        case missingAPIKey
        case noSuggestionReturned
    }

    public static func suggest(for finding: Finding, context: String) async throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] else {
            throw ClaudeError.missingAPIKey
        }
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let headers = [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01"
        ]
        let prompt = """
        You are a Swift code reviewer. The following Swift code contains a force unwrap \
        on the expression `\(finding.expression)`.

        Code context:
        \(context)

        Suggest a safer alternative. Be concise — one or two lines maximum. \
        Show only the fix, no explanation unless essential.
        """
        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 256,
            "messages": [["role": "user", "content": prompt]]
        ]
        let json = try await APIClient.post(url: url, headers: headers, body: body)
        let content = (json["content"] as? [[String: Any]])?.first
        guard let text = content?["text"] as? String else {
            throw ClaudeError.noSuggestionReturned
        }
        return text
    }
}
