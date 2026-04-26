# Markdown

`Markdown` is a very basic, native document-based macOS 26+ app for opening, editing, previewing, and saving Markdown files.

## What It Does

- Opens `.md` and `.markdown` files as standard `NSDocument` documents.
- Provides a source editing mode for plain-text Markdown editing.
- Provides a rendered preview mode for reading formatted Markdown.
- Supports in-app search while editing documents.
- Uses autosave-in-place and native macOS document version history.
- Restores previously open documents on relaunch when possible.

When working in Xcode and the Swift programing language:

## Xcode MCP
Use the `DocumentationSearch` MCP command from "xcode" to search for the latest Apple developer documentation for Apple frameworks. The tool runs locally, and gives compact results very quickly. It often has more detailed and newer information than your training data.

Key new terms that you are unlikely to know about and you MUST ALWAYS search for if referenced are:

- Liquid Glass - this is a new design system.
- FoundationModels - this is a new machine learning framework using on-device models, with new macros for structured generation of types.
- SwiftUI is always evolving, particularly around things you may have previously used with view representables. Don't assume you know the latest way of doing anything.

There will be new APIs and frameworks beyond your training data, so use `DocumentationSearch` liberally.

If you can't find an implementation of something mentioned in the project, then assume it is new API that you haven't heard of, and use the `DocumentationSearch` tool to find details.

- Always prefer xcode MCP to XcodeBuildMCP, except when running tests.

## Code Style Guidelines for Xcode and Swift

- **Naming**: PascalCase for types, camelCase for properties/methods
- **Properties**: Use `@State private var` for SwiftUI state, `let` for constants
- **Structure**: Conform views to `View` protocol, define UI in `body` property
- **Types**: Leverage Swift's strong type system, avoid force unwrapping
- **Architecture**: Follow SwiftUI patterns with clear separation of concerns. Avoid using the Combine framework and instead prefer to use Swift's async and await versions of APIs instead.
- **Comments**: Add descriptive comments for complex logic or non-obvious code
- **Testing** Use the Testing framework for unit test and XCUIAutomation framework for UI tests (https://developer.apple.com/documentation/testing/)

## Validating your work in Xcode

When validating work and experimenting with ideas in Xcode, you have a number of tools at your disposal, each for specific kinds of situations:


- `BuildProject` - Build the project in Xcode. Fully compiles and assembles binaries and resources using Xcode's build system. You can use this to check that work compiles and builds correctly. An extremely powerful tool, but builds can take a long time.

- `XcodeRefreshCodeIssuesInFile` - A fast way to get "live" diagnostics from Xcode about many compiler errors you would normally see in Swift files. While you won't learn about build errors in other files or problems with things like linking, you will often be able to see if types are incorrect/unresolvable, if you have hallucinated/mistyped APIs, or if you've forgotten to import something. Use this to quickly verify your work, since it's not allowed to take more than a couple seconds to run.

- `ExecuteSnippet` - A fast, lightweight tool that runs new code in the context of a given file, sort of like a special Swift REPL environment. This is often much faster than unit tests or full runs, but code executed here is only temporary. Use this to try out a new idea or see how a piece of code in the project works.

## Other rules for XCode and Swift

- Always use the XcodeBuildMCP CLI to build the test scheme and run unit tests and UI tests, unless specifically asked. Some skills have information regarding how to use this CLI.
- Concurrency rules for all changes:
  - Keep Swift 6 strict concurrency on (`SWIFT_STRICT_CONCURRENCY = complete`) and default actor isolation as nonisolated for new code unless a type must be `@MainActor`.
  - Avoid `@unchecked Sendable` in production code; prefer explicit `Sendable` types and DTO snapshots when crossing actor boundaries.
  - Do not pass non-Sendable types across concurrency domains; convert to `Data`/value types first.
  - Actor-bound APIs must be awaited from nonisolated contexts; do not reach into actor state synchronously.
  - There are more information on concurrency in docs/CONCURRENCY_NOTES.md.
- 'traitCollectionDidChange' was deprecated in iOS 17.0: Use the trait change registration APIs declared in the UITraitChangeObservable protocol.
