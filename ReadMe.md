# swift-guardian

A static analysis tool for Swift that detects unsafe patterns and suggests safer alternatives using AI.

## What it does

swift-guardian parses Swift source files into an Abstract Syntax Tree (AST), visits every node looking for unsafe patterns, and for each finding sends the surrounding code to Claude to generate a context-aware fix suggestion. The annotated file is written alongside the original as a `.suggested.swift` file.

**Currently detects:**
- Force unwraps — `foo!`
- Force try — `try!`
- Force casts — `as!`

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
4. **Suggest** — findings are sent to Claude via the Anthropic API with type-specific prompts — Claude is told whether it's reviewing a force unwrap, force try, or force cast, which produces more targeted suggestions
5. **Annotate** — suggestions are inserted as `// 💡` comments directly above each finding in a new `.suggested.swift` file
6. **Guard detection** — before sending to Claude, the tool checks whether the force unwrap has a nearby nil check using AST-based analysis (NilCheckVisitor). Guarded findings receive a different prompt asking Claude to refactor both the nil check and the force unwrap into proper optional binding.

## Verified fixes (`--fix`)

Suggestions are only useful if they are correct. With `--fix`, swift-guardian stops suggesting and starts remediating: every fix Claude proposes must pass verification before it is kept.

For each finding:

1. **Propose** — Claude receives a numbered excerpt around the finding and returns a drop-in replacement for exactly those lines
2. **Apply** — the replacement is spliced into an in-memory copy of the file
3. **Verify** — the patched file must pass every gate:
   - it still parses as valid Swift (SwiftParser reports no errors)
   - the original finding is gone, re-checked with the same visitors that found it
   - no new unsafe pattern appears anywhere in the file
   - optionally, a command such as `swift build` or `swift test` succeeds (`--verify-command`)
4. **Retry** — a rejected fix is sent back to Claude with the reason (for example "the fix introduced new unsafe patterns: force try (try!)"), up to `--attempts` times
5. **Keep or skip** — verified fixes become the new baseline for the next finding, so fixes never conflict; findings that never pass verification are left untouched and reported

Only verified fixes are written, to `YourFile.fixed.swift` (or over the original with `--in-place`).

```
⚠️  Found 5 unsafe pattern(s) in TestFiles/MyViewController.swift
🔧 Generating fixes and verifying each one...

  ✅ Line 14: URL(string: "https://api.example.com/user")!: fixed and verified (1 attempt)
  ✅ Line 17: try! URLSession.shared.data(from: url): fixed and verified (1 attempt)
     ↳ also resolved line 18: try! JSONDecoder().decode(User.self, from: data)
  ✅ Line 29: URL(string: urlString)!: fixed and verified (1 attempt)
     ↳ also resolved line 30: try! Data(contentsOf: url)

📝 3 verified fix(es) written to:
   /Users/eduard/Desktop/swift-guardian/TestFiles/MyViewController.fixed.swift
   Verified fixes: 3  Rejected: 0
   Unsafe patterns resolved: 5 of 5

📊 Summary
   Force unwraps : 2 (0 guarded)
   Force try     : 3
   Force casts   : 0
   Total         : 5

```

The verification loop lives in `RemediationEngine`, which depends on a `FixProvider` protocol rather than on Claude directly, so the whole find-fix-verify loop is unit tested with a stub provider.

## Architecture

```
Sources/
├── swift-guardian/
│   └── main.swift                      — entry point, wires everything together
└── SwiftGuardianCore/
    ├── Visitors/
    │   ├── ForceUnwrapVisitor.swift     — AST visitor for force unwraps
    │   ├── ForceTryVisitor.swift        — AST visitor for force try
    │   ├── ForceCastVisitor.swift       — AST visitor for force casts
    │   └── NilCheckVisitor.swift        — AST visitor for nil check detection
    ├── Remediation/
    │   ├── Analyzer.swift               — runs every visitor; shared by detection and verification
    │   ├── LinePatch.swift              — replaces a range of lines with a proposed fix
    │   ├── FixResponseParser.swift      — turns a model response into a LinePatch
    │   ├── FixVerifier.swift            — parse check, finding resolved, nothing new introduced
    │   └── RemediationEngine.swift      — propose → verify → retry loop, FixProvider protocol
    ├── Helpers/
    │   ├── Finding.swift                — value type representing a detected issue
    │   ├── ContextExtractor.swift       — extracts surrounding lines for a finding
    │   ├── SourceAnnotator.swift        — inserts suggestions and writes output file
    │   └── NilCheckDetector.swift       — detects nil checks near force unwraps
    └── Network/
        ├── APIClient.swift              — generic HTTP POST layer
        ├── ClaudeService.swift          — Anthropic API integration for suggestions
        └── ClaudeFixProvider.swift      — FixProvider that asks Claude for replacement code

Tests/
└── swift-guardianTests/
    ├── Fixtures/
    │   └── sample.swift                 — known Swift file used in fixture tests
    ├── swift_guardianTests.swift
    └── RemediationTests.swift           — patching, parsing, verification and the retry loop
```

`main.swift` only wires things together. All logic lives in `SwiftGuardianCore`, which is independently testable. Adding a new visitor means creating one file and registering it in `Analyzer.swift`; the fix verifier picks it up automatically.

## Requirements

- macOS 13+
- Swift 5.9+
- An [Anthropic API key](https://console.anthropic.com)

## Installation

```bash
git clone https://github.com/edi-stern/swift-guardian.git
cd swift-guardian
swift build
```

## Usage

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
swift run swift-guardian path/to/YourFile.swift
```

The tool writes suggestions to `YourFile.suggested.swift` in the same directory as the original.

To generate and verify fixes instead:

```bash
# keep only fixes that parse, remove the finding and add nothing new
swift run swift-guardian path/to/YourFile.swift --fix

# also require the project to build for every fix, with up to 3 attempts per finding
swift run swift-guardian path/to/YourFile.swift --verify-command "swift build" --attempts 3

# write verified fixes over the original file (use on a clean git tree)
swift run swift-guardian path/to/YourFile.swift --fix --in-place
```

`--verify-command` temporarily writes each candidate over the original file while the command runs and always restores it afterwards. Run it on a clean git working tree. `.fixed.swift` output is written next to the original, so remove it before building if the file lives inside a compiled target.

## Running tests

```bash
swift test
```

Tests cover `ContextExtractor`, `SourceAnnotator`, `ForceUnwrapVisitor`, `ForceTryVisitor`, `ForceCastVisitor`, `NilCheckDetector`, and the remediation pipeline: `LinePatch`, `FixResponseParser`, `FixVerifier` and `RemediationEngine` (with a stub fix provider).

## Extending

To add a new visitor:

1. Create `Sources/SwiftGuardianCore/YourVisitor.swift` — subclass `SyntaxVisitor`, override `visitPost` for the relevant node type
2. In `Remediation/Analyzer.swift`, instantiate it, call `.walk(tree)`, and merge its `findings` with the existing array. Detection and fix verification both use `Analyzer`, so the new rule is enforced on generated fixes too

The `SourceAnnotator` and `ClaudeService` work with any `[Finding]` — they don't know which visitor produced them.
