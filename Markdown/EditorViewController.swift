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

        configureSourceEditor()

        contentContainer.addSubview(contentSurface)
        contentSurface.addSubview(sourceScrollView)
        contentSurface.addSubview(webView)

        sourceScrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            contentSurface.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentSurface.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentSurface.topAnchor.constraint(equalTo: contentContainer.topAnchor),
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
        debugLog("viewDidLoad", details: "sourceLen=\(sourceText.count)")
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
        debugLog("textDidChange", details: "newSourceLen=\(sourceText.count)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isWebEditorReady = true
        debugLog("webViewDidFinish", details: "currentMode=\(currentMode.rawValue) pendingRefresh=\(pendingRenderedRefresh)")
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
            debugLog("jsDebug", details: String(describing: message.body))
            return
        }

        guard message.name == Self.messageName else {
            return
        }

        if isApplyingHTMLToWebView {
            debugLog("bridgeIgnored", details: "reason=isApplyingHTMLToWebView body=\(String(describing: message.body))")
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
                debugLog("bridgeIgnored", details: "reason=payloadValidationFailed payload=\(String(describing: payload))")
                return
            }
            markdown = markdownValue
        } else if let markdownValue = message.body as? String {
            markdown = markdownValue
        } else {
            debugLog("bridgeIgnored", details: "reason=unsupportedBody body=\(String(describing: message.body))")
            return
        }

        debugLog("bridgeAccepted", details: "incomingLen=\(markdown.count) mode=\(currentMode.rawValue)")
        sourceText = markdown
        hasUnsavedChanges = true

        if currentMode == .source {
            isUpdatingSourceProgrammatically = true
            sourceTextView.string = markdown
            isUpdatingSourceProgrammatically = false
            debugLog("bridgeAppliedToSourceView", details: "sourceViewLen=\(sourceTextView.string.count)")
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

        debugLog(
            "setModeBegin",
            details: "from=\(currentMode.rawValue) to=\(mode.rawValue) sourceTextLen=\(sourceText.count) sourceViewLen=\(sourceTextView.string.count)"
        )

        if mode == .rendered {
            let latestSource = sourceTextView.string
            if sourceText.isEmpty || !latestSource.isEmpty {
                sourceText = latestSource
            }
            debugLog("setModePrepareRendered", details: "latestSourceLen=\(latestSource.count) mergedSourceLen=\(sourceText.count)")
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
            debugLog("setModeSourceApplied", details: "sourceViewLen=\(sourceTextView.string.count)")
        }

        debugLog(
            "setModeEnd",
            details: "mode=\(currentMode.rawValue) sourceTextLen=\(sourceText.count) sourceViewLen=\(sourceTextView.string.count)"
        )
    }

    private func configureSourceEditor() {
        sourceTextView.isEditable = true
        sourceTextView.isSelectable = true
        sourceTextView.isRichText = false
        sourceTextView.usesFindBar = true
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

    private func loadRenderedEditorShell() {
        isWebEditorReady = false
        debugLog("loadRenderedEditorShell", details: "requested")
        webView.loadHTMLString(Self.renderedEditorShellHTML, baseURL: Bundle.main.resourceURL)
    }

    private func refreshRenderedView() {
        guard isWebEditorReady else {
            pendingRenderedRefresh = true
            debugLog("refreshDeferred", details: "sourceLen=\(sourceText.count)")
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
        debugLog("refreshBegin", details: "sourceLen=\(sourceText.count) htmlLen=\(html.count)")

        isApplyingHTMLToWebView = true
        webView.evaluateJavaScript(command) { [weak self] result, error in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.isApplyingHTMLToWebView = false
                self?.debugLog("refreshApplyFlagCleared", details: "sourceLen=\(self?.sourceText.count ?? -1)")
            }
            if let error {
                NSLog("Failed to apply rendered HTML: %@", error.localizedDescription)
                self?.debugLog("refreshError", details: error.localizedDescription)
            } else {
                let renderedPath = (result as? String) ?? "unknown"
                self?.debugLog("refreshEvaluateCompleted", details: "ok path=\(renderedPath)")
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        debugLog("webViewDidFail", details: error.localizedDescription)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        debugLog("webViewDidFailProvisional", details: error.localizedDescription)
    }

    private func debugLog(_ event: String, details: String) {
        logger.log("[\(event, privacy: .public)] \(details, privacy: .public)")
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

    private static let renderedEditorShellHTML = """
<!doctype html>
<html>
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <link rel=\"stylesheet\" href=\"RendererPrettyLights.css\">
  <style>
    :root {
      color-scheme: light dark;
      --bg: #ffffff;
      --text: #1f2328;
      --muted: #656d76;
      --border: #d0d7de;
      --code-bg: #f6f8fa;
      --blockquote: #d0d7de;
      --link: #0969da;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0d1117;
        --text: #e6edf3;
        --muted: #8b949e;
        --border: #30363d;
        --code-bg: #161b22;
        --blockquote: #3d444d;
        --link: #4493f8;
      }
    }

    html, body {
      margin: 0;
      padding: 0;
      background: var(--bg);
      color: var(--text);
      height: 100%;
      font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", Helvetica, Arial, sans-serif;
      font-size: 15px;
      line-height: 1.55;
    }

    #editor {
      box-sizing: border-box;
      min-height: 100%;
      width: 100%;
      padding: 20px 28px;
      outline: none;
      white-space: normal;
      word-break: break-word;
      caret-color: var(--text);
    }

    #editor:empty::before {
      content: \"Start writing Markdown…\";
      color: var(--muted);
      pointer-events: none;
    }

    h1, h2, h3, h4, h5, h6 {
      margin: 1.2em 0 0.6em;
      line-height: 1.25;
    }

    p, ul, ol, blockquote, pre, table {
      margin: 0.8em 0;
    }

    code {
      font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, Monaco, Consolas, monospace;
      font-size: 0.9em;
      background: var(--code-bg);
      padding: 0.15em 0.3em;
      border-radius: 6px;
    }

    pre {
      background: var(--code-bg);
      padding: 12px;
      border-radius: 10px;
      overflow-x: auto;
      border: 1px solid var(--border);
    }

    pre code {
      background: transparent;
      padding: 0;
      border-radius: 0;
    }

    blockquote {
      border-left: 3px solid var(--blockquote);
      margin-left: 0;
      padding-left: 12px;
      color: var(--muted);
    }

    a {
      color: var(--link);
      text-decoration: underline;
    }

    table {
      border-collapse: collapse;
      width: max-content;
      max-width: 100%;
      display: block;
      overflow-x: auto;
    }

    th, td {
      border: 1px solid var(--border);
      padding: 6px 10px;
    }
  </style>
</head>
<body>
  <article id=\"editor\" contenteditable=\"true\" spellcheck=\"false\"></article>
  <script src=\"RendererHighlighter.js\"></script>

  <script>
    (() => {
      const editor = document.getElementById('editor');
      let suppressNative = false;

      function postDebug(payload) {
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.markdownDebug) {
            window.webkit.messageHandlers.markdownDebug.postMessage(payload);
          }
        } catch (_) {
          // Best-effort debug logging only.
        }
      }

      function escapeText(text) {
        return text
          .replace(/\\\\/g, '\\\\\\\\')
          .replace(/([`*_{}[\\]()#+\\-.!|>])/g, '\\\\$1');
      }

      async function highlightCodeBlocks() {
        if (!window.MarkdownStarryNight || typeof window.MarkdownStarryNight.highlightCodeBlocks !== 'function') {
          postDebug({
            event: 'highlight.skip',
            reason: 'highlighterUnavailable'
          });
          return;
        }

        try {
          await window.MarkdownStarryNight.highlightCodeBlocks(editor);
          postDebug({
            event: 'highlight.done'
          });
        } catch (error) {
          postDebug({
            event: 'highlight.error',
            message: String(error)
          });
        }
      }

      function inlineMarkdown(node) {
        if (node.nodeType === Node.TEXT_NODE) {
          return escapeText(node.textContent || '');
        }

        if (node.nodeType !== Node.ELEMENT_NODE) {
          return '';
        }

        const tag = node.tagName.toLowerCase();
        const children = Array.from(node.childNodes).map(inlineMarkdown).join('');

        if (tag === 'strong' || tag === 'b') return `**${children}**`;
        if (tag === 'em' || tag === 'i') return `*${children}*`;
        if (tag === 'del' || tag === 's') return `~~${children}~~`;
        if (tag === 'code') return `\\`${node.textContent || ''}\\``;
        if (tag === 'a') {
          const href = node.getAttribute('href') || '';
          return `[${children}](${href})`;
        }
        if (tag === 'img') {
          const src = node.getAttribute('src') || '';
          const alt = node.getAttribute('alt') || '';
          return `![${escapeText(alt)}](${src})`;
        }
        if (tag === 'br') return '  \\n';

        return children;
      }

      function blockMarkdown(node) {
        if (node.nodeType === Node.TEXT_NODE) {
          const text = (node.textContent || '').trim();
          return text ? `${escapeText(text)}\\n\\n` : '';
        }

        if (node.nodeType !== Node.ELEMENT_NODE) {
          return '';
        }

        const tag = node.tagName.toLowerCase();

        if (tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6') {
          const level = Number(tag[1]);
          const content = Array.from(node.childNodes).map(inlineMarkdown).join('').trim();
          return `${'#'.repeat(level)} ${content}\\n\\n`;
        }

        if (tag === 'p') {
          const content = Array.from(node.childNodes).map(inlineMarkdown).join('').trim();
          return content ? `${content}\\n\\n` : '';
        }

        if (tag === 'blockquote') {
          const inner = Array.from(node.childNodes).map(blockMarkdown).join('').trim();
          const prefixed = inner.split('\\n').map(line => line ? `> ${line}` : '>').join('\\n');
          return `${prefixed}\\n\\n`;
        }

        if (tag === 'pre') {
          const code = node.querySelector('code');
          let language = '';
          if (code && code.className.startsWith('language-')) {
            language = code.className.replace('language-', '');
          }
          const body = (code ? code.textContent : node.textContent) || '';
          return `\\`\\`\\`${language}\\n${body.replace(/\\n+$/, '')}\\n\\`\\`\\`\\n\\n`;
        }

        if (tag === 'ul' || tag === 'ol') {
          const listItems = Array.from(node.children).filter(child => child.tagName && child.tagName.toLowerCase() === 'li');
          const rendered = listItems.map((item, index) => {
            let prefix = tag === 'ol' ? `${index + 1}. ` : '- ';

            const checkbox = item.querySelector(':scope > input[type="checkbox"]');
            if (checkbox) {
              prefix = `- [${checkbox.checked ? 'x' : ' '}] `;
            }

            const childContent = Array.from(item.childNodes)
              .filter(child => !(child.tagName && child.tagName.toLowerCase() === 'input'))
              .map(child => {
                if (child.nodeType === Node.ELEMENT_NODE) {
                  const childTag = child.tagName.toLowerCase();
                  if (childTag === 'ul' || childTag === 'ol') {
                    const nested = blockMarkdown(child).trimEnd().split('\\n').map(line => line ? `  ${line}` : '').join('\\n');
                    return `\\n${nested}`;
                  }
                }
                return inlineMarkdown(child);
              })
              .join('')
              .trim();

            return `${prefix}${childContent}`;
          }).join('\\n');

          return `${rendered}\\n\\n`;
        }

        if (tag === 'hr') {
          return `---\\n\\n`;
        }

        if (tag === 'table') {
          const rows = Array.from(node.querySelectorAll('tr')).map(tr => {
            const cells = Array.from(tr.children).map(cell => (cell.textContent || '').trim().replace(/\\|/g, '\\\\|'));
            return `| ${cells.join(' | ')} |`;
          });

          if (rows.length > 0) {
            const headerCells = Array.from(node.querySelectorAll('tr:first-child th, tr:first-child td')).length;
            if (headerCells > 0) {
              const separator = `| ${Array.from({ length: headerCells }).map(() => '---').join(' | ')} |`;
              rows.splice(1, 0, separator);
            }
          }

          return rows.length ? `${rows.join('\\n')}\\n\\n` : '';
        }

        return Array.from(node.childNodes).map(blockMarkdown).join('');
      }

      function postMarkdown(event) {
        if (suppressNative) return;
        if (event && event.isComposing) return;

        const markdown = blockMarkdown(editor).replace(/\\s+$/, '') + '\\n';
        postDebug({
          event: 'postMarkdown',
          trusted: event ? !!event.isTrusted : false,
          markdownLen: markdown.length
        });
        window.webkit.messageHandlers.markdownChanged.postMessage({
          markdown,
          reason: 'input',
          trusted: event ? !!event.isTrusted : false
        });
      }

      editor.addEventListener('input', (event) => postMarkdown(event));

      window.getMarkdown = () => blockMarkdown(editor).replace(/\\s+$/, '') + '\\n';

      window.setRenderedHTML = (html) => {
        const safeHTML = typeof html === 'string' ? html : '';
        postDebug({
          event: 'setRenderedHTML.begin',
          htmlLen: safeHTML.length
        });
        suppressNative = true;
        try {
          editor.innerHTML = safeHTML;
          highlightCodeBlocks();
        } catch (error) {
          postDebug({
            event: 'setRenderedHTML.error',
            message: String(error)
          });
          editor.innerHTML = safeHTML;
        }
        requestAnimationFrame(() => {
          requestAnimationFrame(() => {
            suppressNative = false;
            postDebug({
              event: 'setRenderedHTML.end',
              textLen: (editor.textContent || '').length
            });
          });
        });
      };
    })();
  </script>
</body>
</html>
"""
}
