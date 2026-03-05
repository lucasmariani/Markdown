//
//  EditorViewController.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//


import AppKit
import os
import UniformTypeIdentifiers
import WebKit

final class EditorViewController: NSViewController, NSTextViewDelegate, WKNavigationDelegate, WKScriptMessageHandler, NSMenuItemValidation {
    private enum EditorMode: Int {
        case rendered = 1
        case source = 0
    }

    private static let messageName = "markdownChanged"
    private static let debugMessageName = "markdownDebug"

    private static let preferredMarkdownType = UTType(filenameExtension: "md", conformingTo: .text) ?? .plainText

    private static let supportedMarkdownTypes: [UTType] = {
        var types: [UTType] = []
        if let md = UTType(filenameExtension: "md", conformingTo: .text) {
            types.append(md)
        }
        if let markdown = UTType(filenameExtension: "markdown", conformingTo: .text) {
            types.append(markdown)
        }
        if !types.contains(.plainText) {
            types.append(.plainText)
        }
        return types
    }()

    private lazy var modeControl: NSSegmentedControl = {
        let renderedSymbol = NSImage(
            systemSymbolName: "doc.text.image",
            accessibilityDescription: "Rendered Markdown"
        )
        let sourceSymbol = NSImage(
            systemSymbolName: "chevron.left.forwardslash.chevron.right",
            accessibilityDescription: "Source Markdown"
        )

        let control: NSSegmentedControl
        if let renderedSymbol, let sourceSymbol {
            control = NSSegmentedControl(
                images: [sourceSymbol, renderedSymbol],
                trackingMode: .selectOne,
                target: self,
                action: #selector(modeControlChanged(_:))
            )
            control.setWidth(30, forSegment: 0)
            control.setWidth(30, forSegment: 1)
            control.setToolTip("Rendered Markdown", forSegment: 1)
            control.setToolTip("Source Markdown", forSegment: 0)
        } else {
            control = NSSegmentedControl(
                labels: ["Source", "Rendered"],
                trackingMode: .selectOne,
                target: self,
                action: #selector(modeControlChanged(_:))
            )
        }

        control.segmentStyle = .separated
        control.controlSize = .small
        control.selectedSegment = EditorMode.source.rawValue
        return control
    }()
    private let sourceScrollView = NSScrollView(frame: .zero)
    private let sourceTextView = NSTextView(frame: .zero)
    private let findBarView = FindBarView()
    private var findBarHeightConstraint: NSLayoutConstraint?

    private lazy var webView: WKWebView = {
        let userContentController = WKUserContentController()
        userContentController.add(self, name: Self.messageName)
        userContentController.add(self, name: Self.debugMessageName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var currentMode: EditorMode = .source
    private var currentFileURL: URL? {
        didSet { updateWindowPresentation() }
    }

    private var sourceText: String = ""

    private var hasUnsavedChanges = false {
        didSet { updateWindowPresentation() }
    }

    private var isUpdatingSourceProgrammatically = false
    private var isApplyingHTMLToWebView = false
    private var isWebEditorReady = false
    private var pendingRenderedRefresh = false
    private var activeSearchQuery = ""
    private let logger = Logger(subsystem: "com.rianamiCorp.Markdown", category: "EditorViewController")

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.debugMessageName)
    }

    var toolbarModeControl: NSSegmentedControl {
        modeControl
    }

    override func loadView() {
        let rootView = NSVisualEffectView()
        rootView.material = .windowBackground
        rootView.blendingMode = .behindWindow
        rootView.state = .active
        rootView.translatesAutoresizingMaskIntoConstraints = false

        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        let contentSurface = NSVisualEffectView()
        contentSurface.material = .contentBackground
        contentSurface.blendingMode = .withinWindow
        contentSurface.state = .active
        contentSurface.translatesAutoresizingMaskIntoConstraints = false

        configureFindBar()

        configureSourceEditor()

        contentContainer.addSubview(findBarView)
        contentContainer.addSubview(contentSurface)
        contentSurface.addSubview(sourceScrollView)
        contentSurface.addSubview(webView)

        sourceScrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            findBarView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            findBarView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            findBarView.topAnchor.constraint(equalTo: contentContainer.topAnchor),

            contentSurface.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentSurface.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentSurface.topAnchor.constraint(equalTo: findBarView.bottomAnchor),
            contentSurface.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            sourceScrollView.leadingAnchor.constraint(equalTo: contentSurface.leadingAnchor),
            sourceScrollView.trailingAnchor.constraint(equalTo: contentSurface.trailingAnchor),
            sourceScrollView.topAnchor.constraint(equalTo: contentSurface.topAnchor),
            sourceScrollView.bottomAnchor.constraint(equalTo: contentSurface.bottomAnchor),

            webView.leadingAnchor.constraint(equalTo: contentSurface.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentSurface.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentSurface.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentSurface.bottomAnchor),
        ])
        let findBarHeight = findBarView.heightAnchor.constraint(equalToConstant: 0)
        findBarHeight.isActive = true
        findBarHeightConstraint = findBarHeight

        rootView.addSubview(contentContainer)

        let cornerAdaptiveGuide = rootView.layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))

        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: cornerAdaptiveGuide.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: cornerAdaptiveGuide.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: cornerAdaptiveGuide.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: cornerAdaptiveGuide.bottomAnchor),
        ])

        self.view = rootView

        sourceScrollView.isHidden = false
        webView.isHidden = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        sourceTextView.string = sourceText
        loadRenderedEditorShell()
        updateWindowPresentation()
    }

    @objc func newDocument(_ sender: Any?) {
        guard confirmDiscardChangesIfNeeded() else {
            return
        }

        sourceText = ""
        currentFileURL = nil
        hasUnsavedChanges = false

        isUpdatingSourceProgrammatically = true
        sourceTextView.string = sourceText
        isUpdatingSourceProgrammatically = false

        if currentMode == .rendered {
            refreshRenderedView()
        }
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.supportedMarkdownTypes
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        _ = openDocument(at: url)
    }

    @discardableResult
    func openDocument(at url: URL) -> Bool {
        guard confirmDiscardChangesIfNeeded() else {
            return false
        }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            sourceText = text
            currentFileURL = url
            hasUnsavedChanges = false

            isUpdatingSourceProgrammatically = true
            sourceTextView.string = text
            isUpdatingSourceProgrammatically = false

            if currentMode == .rendered {
                refreshRenderedView()
            }

            return true
        } catch {
            presentError(error)
            return false
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        _ = saveDocumentSynchronously()
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        _ = saveDocumentAsSynchronously()
    }

    @objc func showRendered(_ sender: Any?) {
        setMode(.rendered)
    }

    @objc func showSource(_ sender: Any?) {
        setMode(.source)
    }

    @objc func focusSearch(_ sender: Any?) {
        showFindBar()
        findBarView.focus(initialQuery: activeSearchQuery)
    }

    func confirmCloseWindow() -> Bool {
        confirmDiscardChangesIfNeeded()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(showRendered(_:)):
            menuItem.state = currentMode == .rendered ? .on : .off
            return true
        case #selector(showSource(_:)):
            menuItem.state = currentMode == .source ? .on : .off
            return true
        default:
            return true
        }
    }

    func textDidChange(_ notification: Notification) {
        guard !isUpdatingSourceProgrammatically else {
            return
        }

        sourceText = sourceTextView.string
        hasUnsavedChanges = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isWebEditorReady = true
        if pendingRenderedRefresh || currentMode == .rendered {
            refreshRenderedView()
            pendingRenderedRefresh = false
        }

        if currentMode == .rendered {
            sourceScrollView.isHidden = true
            webView.isHidden = false
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == Self.debugMessageName {
            return
        }

        guard message.name == Self.messageName else {
            return
        }

        if isApplyingHTMLToWebView {
            return
        }

        let markdown: String
        if let payload = message.body as? [String: Any] {
            guard
                let reason = payload["reason"] as? String,
                reason == "input",
                let trusted = payload["trusted"] as? Bool,
                trusted,
                let markdownValue = payload["markdown"] as? String
            else {
                return
            }
            markdown = markdownValue
        } else if let markdownValue = message.body as? String {
            markdown = markdownValue
        } else {
            return
        }

        sourceText = markdown
        hasUnsavedChanges = true

        if currentMode == .source {
            isUpdatingSourceProgrammatically = true
            sourceTextView.string = markdown
            isUpdatingSourceProgrammatically = false
        }
    }

    @objc private func modeControlChanged(_ sender: NSSegmentedControl) {
        guard let mode = EditorMode(rawValue: sender.selectedSegment) else {
            return
        }
        setMode(mode)
    }

    private func setMode(_ mode: EditorMode) {
        guard currentMode != mode else {
            return
        }

        if mode == .rendered {
            let latestSource = sourceTextView.string
            if sourceText.isEmpty || !latestSource.isEmpty {
                sourceText = latestSource
            }
        }

        currentMode = mode

        if mode == .rendered && !isWebEditorReady {
            sourceScrollView.isHidden = false
            webView.isHidden = true
        } else {
            sourceScrollView.isHidden = mode == .rendered
            webView.isHidden = mode == .source
        }
        modeControl.selectedSegment = mode.rawValue

        if mode == .rendered {
            refreshRenderedView()
        } else {
            isUpdatingSourceProgrammatically = true
            sourceTextView.string = sourceText
            isUpdatingSourceProgrammatically = false
            view.window?.makeFirstResponder(sourceTextView)
        }
    }

    private func configureSourceEditor() {
        sourceTextView.isEditable = true
        sourceTextView.isSelectable = true
        sourceTextView.isRichText = false
        sourceTextView.allowsUndo = true
        sourceTextView.usesFindBar = false
        sourceTextView.usesFontPanel = false
        sourceTextView.isAutomaticQuoteSubstitutionEnabled = false
        sourceTextView.isAutomaticDashSubstitutionEnabled = false
        sourceTextView.isAutomaticTextReplacementEnabled = false
        sourceTextView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        sourceTextView.backgroundColor = .clear
        sourceTextView.insertionPointColor = .labelColor
        sourceTextView.textContainerInset = NSSize(width: 18, height: 16)
        sourceTextView.delegate = self

        sourceTextView.isVerticallyResizable = true
        sourceTextView.isHorizontallyResizable = false
        sourceTextView.autoresizingMask = [.width]
        sourceTextView.textContainer?.widthTracksTextView = true
        sourceTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        sourceScrollView.hasVerticalScroller = true
        sourceScrollView.hasHorizontalScroller = false
        sourceScrollView.borderType = .noBorder
        sourceScrollView.autohidesScrollers = true
        sourceScrollView.drawsBackground = false
        sourceScrollView.scrollerStyle = .overlay
        sourceScrollView.documentView = sourceTextView

        webView.setValue(false, forKey: "drawsBackground")
    }

    private func configureFindBar() {
        findBarView.onQueryChanged = { [weak self] query in
            guard let self else { return }
            self.activeSearchQuery = query
            guard !query.isEmpty else { return }
            self.performSearch(query: query, backwards: false)
        }

        findBarView.onFindRequested = { [weak self] backwards in
            self?.runFind(backwards: backwards)
        }

        findBarView.onDoneRequested = { [weak self] in
            self?.hideFindBar()
        }
    }

    private func showFindBar() {
        findBarView.isHidden = false
        findBarHeightConstraint?.constant = 40
        view.layoutSubtreeIfNeeded()
    }

    private func hideFindBar() {
        view.window?.makeFirstResponder(currentMode == .source ? sourceTextView : webView)
        findBarHeightConstraint?.constant = 0
        view.layoutSubtreeIfNeeded()
        findBarView.isHidden = true
    }

    private func runFind(backwards: Bool) {
        let query = findBarView.query
        activeSearchQuery = query
        guard !query.isEmpty else {
            return
        }
        performSearch(query: query, backwards: backwards)
    }

    private func performSearch(query: String, backwards: Bool) {
        if currentMode == .rendered {
            performRenderedSearch(query: query, backwards: backwards)
        } else {
            _ = performSourceSearch(query: query, backwards: backwards)
        }
    }

    private func performRenderedSearch(query: String, backwards: Bool) {
        guard isWebEditorReady else {
            return
        }

        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true

        webView.find(query, configuration: configuration) { [weak self] result in
            
        }
    }

    @discardableResult
    private func performSourceSearch(query: String, backwards: Bool) -> Bool {
        let text = sourceTextView.string as NSString
        guard text.length > 0 else {
            return false
        }

        let selection = sourceTextView.selectedRange()
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

        sourceTextView.setSelectedRange(match)
        sourceTextView.scrollRangeToVisible(match)
        return true
    }

    private func loadRenderedEditorShell() {
        isWebEditorReady = false
        webView.loadHTMLString(RenderedEditorShellHTML.standard, baseURL: Bundle.main.resourceURL)
    }

    private func refreshRenderedView() {
        guard isWebEditorReady else {
            pendingRenderedRefresh = true
            loadRenderedEditorShell()
            return
        }

        let html = MarkdownRenderer.html(from: sourceText)
        let htmlLiteral = javaScriptStringLiteral(for: html)
        let command = """
        (() => {
          const renderedHTML = \(htmlLiteral);
          if (typeof window.setRenderedHTML === 'function') {
            try {
              window.setRenderedHTML(renderedHTML);
              return 'setRenderedHTML';
            } catch (error) {
              console.error('setRenderedHTML failed', error);
            }
          }
        
          const editor = document.getElementById('editor');
          if (editor) {
            editor.innerHTML = renderedHTML;
            return 'fallbackInnerHTML';
          }
        
          throw new Error('rendered editor element not found');
        })()
        """

        isApplyingHTMLToWebView = true
        webView.evaluateJavaScript(command) { [weak self] result, error in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.isApplyingHTMLToWebView = false
            }
            if let error {
                NSLog("Failed to apply rendered HTML: %@", error.localizedDescription)
            } else {
                let renderedPath = (result as? String) ?? "unknown"
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        return
    }

    private func updateWindowPresentation() {
        let title = currentFileURL?.lastPathComponent ?? "Untitled.md"
        let subtitle = currentFileURL?.deletingLastPathComponent().path(percentEncoded: false) ?? "Unsaved Markdown Document"

        guard let window = view.window else {
            return
        }

        window.title = title
        window.subtitle = subtitle
        window.isDocumentEdited = hasUnsavedChanges
    }

    private func confirmDiscardChangesIfNeeded() -> Bool {
        guard hasUnsavedChanges else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Do you want to save changes to this document?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveDocumentSynchronously()
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    private func saveDocumentSynchronously() -> Bool {
        if currentMode == .source {
            sourceText = sourceTextView.string
        }

        if let url = currentFileURL {
            do {
                try writeCurrentDocument(to: url)
                return true
            } catch {
                presentError(error)
                return false
            }
        }

        return saveDocumentAsSynchronously()
    }

    private func saveDocumentAsSynchronously() -> Bool {
        if currentMode == .source {
            sourceText = sourceTextView.string
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.preferredMarkdownType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "Untitled.md"

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        do {
            try writeCurrentDocument(to: url)
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    private func writeCurrentDocument(to url: URL) throws {
        let normalized = sourceText.replacingOccurrences(of: "\r\n", with: "\n")
        try normalized.write(to: url, atomically: true, encoding: .utf8)

        currentFileURL = url
        hasUnsavedChanges = false
    }

    private func javaScriptStringLiteral(for value: String) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
            let jsonArray = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }

        return String(jsonArray.dropFirst().dropLast())
    }

}
