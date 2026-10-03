public struct Finding {
    public let line: Int
    public let column: Int
    public let expression: String
    public let type: FindingType
}

public enum FindingType {
    case forceUnwrap
    case forceTry
    case forceCast
}
