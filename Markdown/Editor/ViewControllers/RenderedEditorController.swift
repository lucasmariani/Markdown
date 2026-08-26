//
//  RenderedEditorController.swift
//  Markdown
//

import AppKit
import MarkdownEngine
import MarkdownEngineCodeBlocks
import Observation
import SwiftUI

enum RenderedMarkdownFormattingCommand: String {
    case paragraph
    case heading1
    case heading2
    case heading3
    case heading4
    case heading5
    case heading6
    case quote
    case codeBlock
    case unorderedList
    case orderedList
    case bold
    case italic
    case inlineCode
}

private struct RenderedEditorBus {
    let applyBold: Notification.Name
    let applyItalic: Notification.Name
    let applyHeading: Notification.Name
    let applyInlineCode: Notification.Name
    let applyBlockquote: Notification.Name
    let applyUnorderedList: Notification.Name
    let applyOrderedList: Notification.Name
    let applyCodeBlock: Notification.Name
    let findQuery: Notification.Name
    let findResults: Notification.Name
    let clearFindHighlights: Notification.Name

    init(identifier: UUID = UUID()) {
        let prefix = "com.rianami.markdown.rendered-editor.\(identifier.uuidString)"
        applyBold = Notification.Name("\(prefix).format.bold")
        applyItalic = Notification.Name("\(prefix).format.italic")
        applyHeading = Notification.Name("\(prefix).format.heading")
        applyInlineCode = Notification.Name("\(prefix).format.inline-code")
        applyBlockquote = Notification.Name("\(prefix).format.blockquote")
        applyUnorderedList = Notification.Name("\(prefix).format.unordered-list")
        applyOrderedList = Notification.Name("\(prefix).format.ordered-list")
        applyCodeBlock = Notification.Name("\(prefix).format.code-block")
        findQuery = Notification.Name("\(prefix).find.query")
        findResults = Notification.Name("\(prefix).find.results")
        clearFindHighlights = Notification.Name("\(prefix).find.clear")
    }

    var engineBus: MarkdownEditorBus {
        MarkdownEditorBus(
            applyBoldRequest: applyBold,
            applyItalicRequest: applyItalic,
            applyHeadingRequest: applyHeading,
            applyInlineCodeRequest: applyInlineCode,
            applyBlockquoteRequest: applyBlockquote,
            applyUnorderedListRequest: applyUnorderedList,
            applyOrderedListRequest: applyOrderedList,
            applyCodeBlockRequest: applyCodeBlock,
            findClearHighlights: clearFindHighlights,
            findQuery: findQuery,
            findResults: findResults
        )
    }
}

@MainActor
@Observable
private final class RenderedEditorState {
    var markdown: String {
        didSet {
            guard markdown != oldValue, !isApplyingDocumentText else {
                return
            }
            onMarkdownChanged?(markdown)
        }
    }

    var configuration: MarkdownEditorConfiguration
    var documentIdentifier: String

    @ObservationIgnored var onMarkdownChanged: ((String) -> Void)?
    @ObservationIgnored private var isApplyingDocumentText = false

    init(
        markdown: String = "",
        configuration: MarkdownEditorConfiguration,
        documentIdentifier: String
    ) {
        self.markdown = markdown
        self.configuration = configuration
        self.documentIdentifier = documentIdentifier
    }

    func applyDocumentText(_ text: String) {
        guard markdown != text else {
            return
        }

        isApplyingDocumentText = true
        markdown = text
        isApplyingDocumentText = false
    }
}

private struct RenderedEditorView: View {
    @Bindable var state: RenderedEditorState

    var body: some View {
        NativeTextViewWrapper(
            text: $state.markdown,
            configuration: state.configuration,
            fontName: "SF Pro",
            fontSize: 15,
            documentId: state.documentIdentifier
        )
    }
}

@MainActor
final class RenderedEditorController: NSObject {
    private let bus: RenderedEditorBus
    private let unsavedDocumentIdentifier: String
    private let syntaxHighlighter: HighlighterSwiftBridge
    private let state: RenderedEditorState
    private lazy var hostingView = NSHostingView(rootView: RenderedEditorView(state: state))
    private var documentDirectoryURL: URL?

    private var currentSearchQuery = ""
    private var currentSearchIndex = 0
    private var latestSearchCount = 0

    var onMarkdownChanged: ((String) -> Void)? {
        get { state.onMarkdownChanged }
        set { state.onMarkdownChanged = newValue }
    }

    var view: NSView {
        hostingView
    }

    override init() {
        let bus = RenderedEditorBus()
        let unsavedDocumentIdentifier = "unsaved-\(UUID().uuidString)"
        let syntaxHighlighter = HighlighterSwiftBridge()
        var configuration = MarkdownEditorConfiguration.default
        configuration.extensions = [StrikethroughExtension()]
        configuration.textInsets = TextInsets(horizontal: 28, vertical: 20)

        configuration.services = MarkdownEditorServices(
            images: DocumentImageProvider(documentDirectoryURL: nil),
            syntaxHighlighter: syntaxHighlighter,
            bus: bus.engineBus
        )

        state = RenderedEditorState(
            configuration: configuration,
            documentIdentifier: unsavedDocumentIdentifier
        )

        self.bus = bus
        self.unsavedDocumentIdentifier = unsavedDocumentIdentifier
        self.syntaxHighlighter = syntaxHighlighter
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFindResults(_:)),
            name: bus.findResults,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @discardableResult
    func ensureView() -> Bool {
        _ = hostingView
        return true
    }

    func render(markdown: String) {
        state.applyDocumentText(markdown)
    }

    func setDocumentURL(_ documentURL: URL?) {
        state.documentIdentifier = documentURL?
            .standardizedFileURL
            .path(percentEncoded: false) ?? unsavedDocumentIdentifier

        let baseURL = documentURL?.deletingLastPathComponent()
        guard documentDirectoryURL?.standardizedFileURL != baseURL?.standardizedFileURL else {
            return
        }

        documentDirectoryURL = baseURL
        var configuration = state.configuration
        configuration.services = MarkdownEditorServices(
            images: DocumentImageProvider(documentDirectoryURL: baseURL),
            syntaxHighlighter: syntaxHighlighter,
            bus: bus.engineBus
        )
        state.configuration = configuration
    }

    func applyFormatting(_ command: RenderedMarkdownFormattingCommand) {
        let center = NotificationCenter.default

        switch command {
        case .paragraph:
            applyParagraphStyle()
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            let level = switch command {
            case .heading1: 1
            case .heading2: 2
            case .heading3: 3
            case .heading4: 4
            case .heading5: 5
            case .heading6: 6
            default: 1
            }
            center.post(name: bus.applyHeading, object: nil, userInfo: ["level": level])
        case .quote:
            center.post(name: bus.applyBlockquote, object: nil)
        case .codeBlock:
            center.post(name: bus.applyCodeBlock, object: nil)
        case .unorderedList:
            center.post(name: bus.applyUnorderedList, object: nil)
        case .orderedList:
            center.post(name: bus.applyOrderedList, object: nil)
        case .bold:
            center.post(name: bus.applyBold, object: nil)
        case .italic:
            center.post(name: bus.applyItalic, object: nil)
        case .inlineCode:
            center.post(name: bus.applyInlineCode, object: nil)
        }
    }

    func find(query: String, backwards: Bool) {
        let count = countMatches(query: query)
        guard count > 0 else {
            currentSearchQuery = query
            currentSearchIndex = 0
            postFindQuery(query: query, index: 0)
            return
        }

        if currentSearchQuery != query {
            currentSearchQuery = query
            currentSearchIndex = backwards ? count - 1 : 0
        } else if backwards {
            currentSearchIndex = (currentSearchIndex - 1 + count) % count
        } else {
            currentSearchIndex = (currentSearchIndex + 1) % count
        }

        postFindQuery(query: query, index: currentSearchIndex)
    }

    func countMatches(query: String, completion: @escaping (Int) -> Void) {
        let count = countMatches(query: query)
        latestSearchCount = count
        completion(count)
    }

    func clearSearchResults() {
        currentSearchQuery = ""
        currentSearchIndex = 0
        latestSearchCount = 0
        NotificationCenter.default.post(name: bus.clearFindHighlights, object: nil)
    }

    func focus(in window: NSWindow?) {
        guard let window else {
            return
        }

        if let textView = editorTextView {
            window.makeFirstResponder(textView)
            return
        }

        DispatchQueue.main.async { [weak self, weak window] in
            guard let textView = self?.editorTextView else {
                return
            }
            window?.makeFirstResponder(textView)
        }
    }

    func scrollPosition() -> EditorScrollPosition {
        editorScrollView?.editorScrollPosition() ?? EditorScrollPosition(verticalFraction: 0)
    }

    func applyScrollPosition(_ position: EditorScrollPosition) {
        editorScrollView?.applyEditorScrollPosition(position)
    }

    private var editorTextView: NSTextView? {
        hostingView.firstDescendant(of: NSTextView.self)
    }

    private var editorScrollView: NSScrollView? {
        hostingView.firstDescendant(of: NSScrollView.self)
    }

    private func applyParagraphStyle() {
        guard let textView = editorTextView else {
            return
        }

        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let lineRange = text.lineRange(for: selection)
        let line = text.substring(with: lineRange)
        let headingPrefixLength = line.prefix { $0 == "#" }.count
        guard (1...6).contains(headingPrefixLength),
              line.dropFirst(headingPrefixLength).first == " " else {
            return
        }

        let prefixRange = NSRange(location: lineRange.location, length: headingPrefixLength + 1)
        guard textView.shouldChangeText(in: prefixRange, replacementString: "") else {
            return
        }

        textView.replaceCharacters(in: prefixRange, with: "")
        textView.didChangeText()
        let removedBeforeSelection = min(prefixRange.length, max(selection.location - prefixRange.location, 0))
        textView.setSelectedRange(NSRange(
            location: selection.location - removedBeforeSelection,
            length: selection.length
        ))
    }

    private func countMatches(query: String) -> Int {
        guard !query.isEmpty, let textView = editorTextView else {
            return 0
        }

        let text = textView.string as NSString
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var searchRange = NSRange(location: 0, length: text.length)
        var count = 0

        while searchRange.length > 0 {
            let match = text.range(of: query, options: options, range: searchRange)
            guard match.location != NSNotFound else {
                break
            }

            count += 1
            let nextLocation = match.location + max(match.length, 1)
            searchRange = NSRange(location: nextLocation, length: text.length - nextLocation)
        }

        return count
    }

    private func postFindQuery(query: String, index: Int) {
        NotificationCenter.default.post(
            name: bus.findQuery,
            object: nil,
            userInfo: ["query": query, "currentIndex": index]
        )
    }

    @objc private func handleFindResults(_ notification: Notification) {
        guard let count = notification.userInfo?["count"] as? Int else {
            return
        }
        latestSearchCount = count
        if count == 0 {
            currentSearchIndex = 0
        } else {
            currentSearchIndex = min(currentSearchIndex, count - 1)
        }
    }
}

private extension NSView {
    func firstDescendant<ViewType: NSView>(of type: ViewType.Type) -> ViewType? {
        if let match = self as? ViewType {
            return match
        }

        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }

        return nil
    }
}
