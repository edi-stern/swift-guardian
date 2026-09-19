# swift-guardian

A static analysis tool for Swift that detects unsafe patterns and suggests safer alternatives using AI.

## What it does

swift-guardian parses Swift source files into an Abstract Syntax Tree (AST), visits every node looking for unsafe patterns, and for each finding sends the surrounding code to Claude to generate a context-aware fix suggestion. The annotated file is written alongside the original as a `.suggested.swift` file.

**Currently detects:**
- Force unwraps — `foo!`
- Force try — `try!`

**Example output:**

```
⚠️  Found 2 force unwrap(s) in ViewModel.swift

  Line 71, Col 74: pageSize!
  68:     isLoading = true
  69:     defer { isLoading = false }
  70:
  71:     let page = repository.fetchPage(offset: currentOffset, pageSize: pageSize!)
  72:     displayedUsers.append(contentsOf: page)
  73:     currentOffset += pageSize!

  💡 Asking Claude for a fix...
  ✅ Suggestion:
guard let pageSize else { return }
let page = repository.fetchPage(offset: currentOffset, pageSize: pageSize)

📝 Annotated file written to: ViewModel.suggested.swift
```

## How it works

1. **Parse** — Apple's [SwiftSyntax](https://github.com/apple/swift-syntax) library parses the Swift source file into an AST
2. **Visit** — `SyntaxVisitor` subclasses walk every node in the tree, recording findings when they encounter `ForceUnwrapExprSyntax` or `TryExprSyntax` with an exclamation mark token
3. **Contextualise** — for each finding, the surrounding lines are extracted to give Claude enough context to understand the code
4. **Suggest** — findings are sent to Claude via the Anthropic API, which returns a concise, context-aware fix
5. **Annotate** — suggestions are inserted as `// 💡` comments directly above each finding in a new `.suggested.swift` file

## Architecture

```
Sources/
├── swift-guardian/
│   └── main.swift              — entry point, wires everything together
└── SwiftGuardianCore/
    ├── Finding.swift            — value type representing a detected issue
    ├── ForceUnwrapVisitor.swift — AST visitor for force unwraps
    ├── ForceTryVisitor.swift    — AST visitor for force try
    ├── ContextExtractor.swift   — extracts surrounding lines for a finding
    ├── APIClient.swift          — generic HTTP POST layer
    ├── ClaudeService.swift      — Anthropic API integration and prompt
    └── SourceAnnotator.swift    — inserts suggestions and writes output file

Tests/
└── swift-guardianTests/
    ├── Fixtures/
    │   └── sample.swift         — known Swift file used in fixture tests
    └── swift_guardianTests.swift
```

`main.swift` only wires things together. All logic lives in `SwiftGuardianCore`, which is independently testable. Adding a new visitor means creating one file and adding two lines to `main.swift`.

## Requirements

- macOS 13+
- Swift 5.9+
- An [Anthropic API key](https://console.anthropic.com)

## Installation

```bash
git clone https://github.com/yourusername/swift-guardian.git
cd swift-guardian
swift build
```

## Usage

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
swift run swift-guardian path/to/YourFile.swift
```

The tool writes suggestions to `YourFile.suggested.swift` in the same directory as the original.

## Running tests

```bash
swift test
```

14 tests covering `ContextExtractor`, `SourceAnnotator`, `ForceUnwrapVisitor`, and `ForceTryVisitor`.

## Extending

To add a new visitor:

1. Create `Sources/SwiftGuardianCore/YourVisitor.swift` — subclass `SyntaxVisitor`, override `visitPost` for the relevant node type
2. In `main.swift`, instantiate it, call `.walk(tree)`, and merge its `findings` with the existing array

The `SourceAnnotator` and `ClaudeService` work with any `[Finding]` — they don't know which visitor produced them.

## What I learned

Building this taught me how static analysis tools actually work under the hood. SwiftLint, SonarQube, and similar tools all operate on the same principle — parse source into an AST, visit specific node types, report findings. The difference between a linter and a compiler is largely what you do with the tree once you have it.

The interesting engineering problem was understanding what context to send to Claude. The expression alone (`pageSize!`) tells the model almost nothing. The surrounding lines reveal the type, the usage pattern, and the intended fix. Getting that context window right is what makes the suggestions useful rather than generic.

The next step is interprocedural analysis — following a value across function boundaries to understand whether a force unwrap is truly unsafe or whether the caller has already guaranteed non-nil. That's the kind of analysis SonarQube and similar tools do, and it requires a control flow graph rather than a simple AST walk.
