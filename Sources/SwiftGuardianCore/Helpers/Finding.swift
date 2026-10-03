public struct Finding {
    public let line: Int
    public let column: Int
    public let expression: String
    public let type: FindingType
    public let isGuarded: Bool
    
    public init(line: Int, column: Int, expression: String, type: FindingType, isGuarded: Bool = false) {
        self.line = line
        self.column = column
        self.expression = expression
        self.type = type
        self.isGuarded = isGuarded
    }
    
    public func update(isGuarded: Bool) -> Finding {
        .init(line: line, column: column, expression: expression, type: type, isGuarded: isGuarded)
    }
}

public enum FindingType {
    case forceUnwrap
    case forceTry
    case forceCast
}
