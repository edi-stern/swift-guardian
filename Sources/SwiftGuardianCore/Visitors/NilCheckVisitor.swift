import SwiftSyntax

final class NilCheckVisitor: SyntaxVisitor {
    private let variableName: String
    private(set) var isGuarded = false
    
    init(variableName: String) {
        self.variableName = variableName
        super.init(viewMode: .all)
    }
    
    // detects if let or guard let
    override func visitPost(_ node: OptionalBindingConditionSyntax) {
        if let pattern = node.pattern.as(IdentifierPatternSyntax.self) {
            if pattern.identifier.text == variableName {
                isGuarded = true
            }
        }
    }
    
    // detects if name != nil
    override func visitPost(_ node: SequenceExprSyntax) {
        let elements = node.elements
        guard elements.count == 3 else { return }
        
        let hasVariable = elements.first?.as(DeclReferenceExprSyntax.self)?.baseName.text == variableName
        let hasNil = elements.last?.as(NilLiteralExprSyntax.self) != nil
        let hasOperator = elements.dropFirst().first?.as(BinaryOperatorExprSyntax.self)?.operator.text == "!="
        
        if hasVariable && hasNil && hasOperator {
            isGuarded = true
        }
    }
}
