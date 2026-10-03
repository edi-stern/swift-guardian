import SwiftSyntax
import SwiftParser
import Foundation

public enum NilCheckDetector {
    public static func isGuarded(
        expression: String,
        source: String,
        around line: Int,
        radius: Int = 3
    ) -> Bool {
        let variableName = extractVariableName(from: expression)
        guard !variableName.isEmpty else { return false }

        let lines = source.components(separatedBy: "\n")
        let start = max(0, line - 1 - radius)
        let end = min(lines.count - 1, line - 1 + radius)
        let contextSource = lines[start...end].joined(separator: "\n")

        let wrappedSource = "func __context__() {\n\(contextSource)\n}"
        let tree = Parser.parse(source: wrappedSource)
        let visitor = NilCheckVisitor(variableName: variableName)
        visitor.walk(tree)
        return visitor.isGuarded
    }
    
    private static func extractVariableName(from expression: String) -> String{
        expression
            .replacingOccurrences(of: "!", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
