import SwiftSyntax

public final class ForceTryVisitor: SyntaxVisitor {
    public private(set) var findings: [Finding] = []
    private let locationConverter: SourceLocationConverter

    public init(locationConverter: SourceLocationConverter) {
        self.locationConverter = locationConverter
        super.init(viewMode: .all)
    }

    override public func visitPost(_ node: TryExprSyntax) {
        guard node.questionOrExclamationMark?.tokenKind == .exclamationMark else { return }
        let location = node.startLocation(converter: locationConverter)
        findings.append(Finding(
            line: location.line,
            column: location.column,
            expression: node.trimmedDescription
        ))
    }
}
