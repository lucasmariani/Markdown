//
//  SourceEditorController.swift
//  Markdown
//
//  Created by Lucas on 05/03/26.
//

import AppKit

@MainActor
final class SourceEditorController: NSObject, NSTextViewDelegate {
    private final class SourceTextView: NSTextView {
        var onTextFinderAction: ((NSTextFinder.Action) -> Bool)?

        override func performTextFinderAction(_ sender: Any?) {
            if let action = Self.textFinderAction(from: sender),
               onTextFinderAction?(action) == true {
                return
            }

            super.performTextFinderAction(sender)
        }

        private static func textFinderAction(from sender: Any?) -> NSTextFinder.Action? {
            let tag: Int?

            switch sender {
            case let menuItem as NSMenuItem:
                tag = menuItem.tag
            case let control as NSControl:
                tag = control.tag
            case let object as NSObject where object.responds(to: Selector(("tag"))):
                tag = object.value(forKey: "tag") as? Int
            default:
                tag = nil
            }

            guard let tag else {
                return nil
            }

            return NSTextFinder.Action(rawValue: tag)
        }
    }

    private final class TextFinderActionSender: NSObject {
        let tag: Int

        init(action: NSTextFinder.Action) {
            self.tag = action.rawValue
        }
    }

    let scrollView = NSScrollView(frame: .zero)
    private let textView = SourceTextView(frame: .zero)

    private var isUpdatingProgrammatically = false

    var onTextChanged: ((String) -> Void)?
    var onTextFinderAction: ((NSTextFinder.Action) -> Bool)? {
        didSet {
            textView.onTextFinderAction = onTextFinderAction
        }
    }

    override init() {
        super.init()
        configureTextView()
        configureScrollView()
    }

    func setText(_ text: String) {
        guard textView.string != text else {
            return
        }

        isUpdatingProgrammatically = true
        textView.string = text
        isUpdatingProgrammatically = false
    }

    func currentText() -> String {
        textView.string
    }

    func focus(in window: NSWindow?) {
        window?.makeFirstResponder(textView)
    }

    func showFindInterface(in window: NSWindow?) {
        focus(in: window)
        textView.performTextFinderAction(TextFinderActionSender(action: .showFindInterface))
    }

    func performTextFinderAction(_ action: NSTextFinder.Action, in window: NSWindow?) {
        focus(in: window)
        textView.performTextFinderAction(TextFinderActionSender(action: action))
    }

    @discardableResult
    func find(query: String, backwards: Bool) -> Bool {
        let text = textView.string as NSString
        guard text.length > 0 else {
            return false
        }

        let selection = textView.selectedRange()
        let selectionStart = min(max(selection.location, 0), text.length)
        let selectionEnd = min(selectionStart + selection.length, text.length)

        let options: NSString.CompareOptions = backwards ? [.caseInsensitive, .backwards] : [.caseInsensitive]
        let primaryRange: NSRange
        let wrappedRange: NSRange

        if backwards {
            primaryRange = NSRange(location: 0, length: selectionStart)
            wrappedRange = NSRange(location: selectionEnd, length: text.length - selectionEnd)
        } else {
            primaryRange = NSRange(location: selectionEnd, length: text.length - selectionEnd)
            wrappedRange = NSRange(location: 0, length: selectionEnd)
        }

        var match = text.range(of: query, options: options, range: primaryRange)
        if match.location == NSNotFound {
            match = text.range(of: query, options: options, range: wrappedRange)
        }

        guard match.location != NSNotFound else {
            return false
        }

        textView.setSelectedRange(match)
        textView.scrollRangeToVisible(match)
        return true
    }

    func countMatches(query: String) -> Int {
        let text = textView.string as NSString
        guard text.length > 0, !query.isEmpty else {
            return 0
        }

        var count = 0
        var searchRange = NSRange(location: 0, length: text.length)

        while searchRange.length > 0 {
            let match = text.range(of: query, options: [.caseInsensitive], range: searchRange)
            guard match.location != NSNotFound else {
                break
            }

            count += 1
            let nextLocation = match.location + max(match.length, 1)
            searchRange = NSRange(location: nextLocation, length: text.length - nextLocation)
        }

        return count
    }

    func textDidChange(_ notification: Notification) {
        guard !isUpdatingProgrammatically else {
            return
        }

        onTextChanged?(textView.string)
    }

    private func configureTextView() {
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.isIncrementalSearchingEnabled = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = .clear
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.delegate = self

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    }

    private func configureScrollView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.findBarPosition = .aboveContent
        scrollView.documentView = textView
    }
}
