import Foundation

public enum ClaudeService {
    public enum ClaudeError: Error {
        case missingAPIKey
        case noSuggestionReturned
    }
    
    private enum Constants {
        static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    }

    public static func suggest(for finding: Finding, context: String) async throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] else {
            throw ClaudeError.missingAPIKey
        }
        let url = Constants.apiURL
        let headers = [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "prompt-caching-2024-07-31"
        ]
        
        let typeDescription: String
        let suggestion: String

        switch finding.type {
        case .forceUnwrap:
            typeDescription = "force unwrap (!)"
            suggestion = "Use optional binding (if let / guard let), nil coalescing (??), or make the value non-optional if it's always set."
        case .forceTry:
            typeDescription = "force try (try!)"
            suggestion = "Use do-catch to handle the error, or try? to convert to an optional."
        case .forceCast:
            typeDescription = "force cast (as!)"
            suggestion = "Use conditional cast (as?) with a fallback, or guard against the wrong type before casting."
        }

        let guardedNote = finding.isGuarded ?
            "Note: a nil check for this value was detected nearby. Suggest how to refactor to eliminate both the nil check and the force unwrap using proper optional binding." :
            ""

        let prompt = """
        The following Swift code contains a \(typeDescription) on the expression `\(finding.expression)`.

        Code context:
        \(context)

        \(guardedNote)
        \(suggestion)
        """
        
        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 256,
            "system": [
                [
                    "type": "text",
                    "text": "You are a Swift code reviewer. When shown Swift code containing an unsafe pattern, suggest a safer alternative. Be concise — one or two lines maximum. Show only the fix, no explanation unless essential.",
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]
        
        let json = try await APIClient.post(url: url, headers: headers, body: body)
        let content = (json["content"] as? [[String: Any]])?.first
        guard let text = content?["text"] as? String else {
            throw ClaudeError.noSuggestionReturned
        }
        return text
    }
}
