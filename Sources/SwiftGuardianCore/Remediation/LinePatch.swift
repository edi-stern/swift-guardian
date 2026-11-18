/// Replaces an inclusive, 1-based range of lines with new text.
public struct LinePatch: Equatable {
    public let startLine: Int
    public let endLine: Int
    public let replacement: String

    public init(startLine: Int, endLine: Int, replacement: String) {
        self.startLine = startLine
        self.endLine = endLine
        self.replacement = replacement
    }

    /// Returns the patched source, or nil when the range does not fit the source.
    public func apply(to source: String) -> String? {
        var lines = source.components(separatedBy: "\n")
        guard startLine >= 1, endLine >= startLine, endLine <= lines.count else { return nil }
        lines.replaceSubrange(
            (startLine - 1)...(endLine - 1),
            with: replacement.components(separatedBy: "\n")
        )
        return lines.joined(separator: "\n")
    }
}
