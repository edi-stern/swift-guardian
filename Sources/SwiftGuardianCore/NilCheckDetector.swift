public enum NilCheckDetector {
    public static func isGuarded(expression: String, context: String) -> Bool {
        let variableName = extractVariableName(from: expression)
        guard !variableName.isEmpty else { return false }
        
        let lines = context.split(separator: "\n")
        return lines.contains { line in
            line.contains(variableName) &&
            (line.contains("!= nil") || line.contains("== nil") ||
             line.contains("if let") || line.contains("guard let"))
        }
    }
    
    private static func extractVariableName(from expression: String) -> String{
        expression
            .replacingOccurrences(of: "!", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
