//
//  RenderedEditorController.swift
//  Markdown
//
//  Created by Codex on 05/03/26.
//

import AppKit
import WebKit

private final class RenderedWebView: WKWebView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        if let scrollView = enclosingScrollView {
            scrollView.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class RenderedEditorController: NSObject, WKNavigationDelegate {
    let scrollView = NSScrollView(frame: .zero)
    private let documentContainerView = FlippedDocumentView(frame: .zero)
    private var webView: WKWebView?
    private var pendingHeightRefreshWorkItem: DispatchWorkItem?

    private var latestMarkdown = ""
    private var isReady = false
    private var pendingRefresh = false

    override init() {
        super.init()
        configureScrollView()
    }

    @discardableResult
    func ensureWebView() -> Bool {
        if webView != nil {
            return true
        }

        let configuration = WKWebViewConfiguration()

        let webView = RenderedWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.frame = documentContainerView.bounds

        documentContainerView.addSubview(webView)
        layoutDocumentContainer(minimumHeight: max(scrollView.contentView.bounds.height, 1))

        self.webView = webView
        loadShell()
        return true
    }

    func render(markdown: String) {
        latestMarkdown = markdown
        guard let webView else {
            pendingRefresh = true
            return
        }

        guard isReady else {
            pendingRefresh = true
            loadShell()
            return
        }

        let html = MarkdownRenderer.html(from: markdown)
        let htmlLiteral = javaScriptStringLiteral(html)
        let command = """
        (() => {
          if (typeof window.setRenderedDocument === 'function') {
            try {
              window.setRenderedDocument(\(htmlLiteral));
              return 'setRenderedDocument';
            } catch (error) {
              console.error('setRenderedDocument failed', error);
            }
          }

          const editor = document.getElementById('editor');
          if (editor) {
            editor.innerHTML = \(htmlLiteral);
            return 'fallbackInnerHTML';
          }

        throw new Error('rendered editor element not found');
        })()
        """

        webView.evaluateJavaScript(command) { [weak self] _, error in
            if let error {
                NSLog("Failed to apply rendered HTML: %@", error.localizedDescription)
            }

            self?.scheduleHeightRefresh(after: 0.25)
        }
    }

    func find(query: String, backwards: Bool) {
        guard isReady, let webView else {
            return
        }

        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(query, configuration: configuration) { _ in }
    }

    func clearSearchResults() {
        guard isReady else {
            return
        }

        render(markdown: latestMarkdown)
    }

    func focus(in window: NSWindow?) {
        guard let webView else {
            return
        }
        window?.makeFirstResponder(webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        scheduleHeightRefresh()
        if pendingRefresh {
            pendingRefresh = false
            render(markdown: latestMarkdown)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated else {
            decisionHandler(.allow)
            return
        }

        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    private func loadShell() {
        guard let webView else {
            return
        }

        isReady = false
        layoutDocumentContainer(minimumHeight: max(scrollView.contentView.bounds.height, 1))
        webView.loadHTMLString(RenderedEditorShellHTML.standard, baseURL: Bundle.main.resourceURL)
    }

    private func javaScriptStringLiteral(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json
    }

    private func configureScrollView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true
        scrollView.postsFrameChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(containerGeometryDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(containerGeometryDidChange),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(containerGeometryDidChange),
            name: NSView.frameDidChangeNotification,
            object: scrollView
        )

        scrollView.documentView = documentContainerView
    }

    @objc
    private func containerGeometryDidChange(_ notification: Notification) {
        layoutDocumentContainer(minimumHeight: documentContainerView.frame.height)
        scheduleHeightRefresh()
    }

    private func scheduleHeightRefresh(after delay: TimeInterval = 0.05) {
        pendingHeightRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshDocumentHeight()
        }
        pendingHeightRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func refreshDocumentHeight() {
        guard isReady, let webView else {
            return
        }

        let script = """
        (() => {
          const editor = document.getElementById('editor');
          const body = document.body;
          const doc = document.documentElement;
          if (editor) {
            void editor.offsetWidth;
          }

          window.dispatchEvent(new Event('resize'));
          return Math.max(
            editor ? editor.scrollHeight : 0,
            editor ? editor.offsetHeight : 0,
            editor ? Math.ceil(editor.getBoundingClientRect().height) : 0,
            body ? body.scrollHeight : 0,
            body ? body.offsetHeight : 0,
            body ? body.clientHeight : 0,
            doc ? doc.scrollHeight : 0,
            doc ? doc.offsetHeight : 0,
            doc ? doc.clientHeight : 0
          );
        })()
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else {
                return
            }

            if let error {
                NSLog("Failed to measure rendered content height: %@", error.localizedDescription)
                return
            }

            guard let value = result as? NSNumber else {
                return
            }

            let height = CGFloat(truncating: value)
            self.layoutDocumentContainer(minimumHeight: height)
        }
    }

    private func layoutDocumentContainer(minimumHeight: CGFloat) {
        let width = max(scrollView.contentView.bounds.width, 1)
        let height = max(minimumHeight, scrollView.contentView.bounds.height, 1)
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        let widthChanged = abs(documentContainerView.frame.width - frame.width) > .ulpOfOne

        if documentContainerView.frame != frame {
            documentContainerView.frame = frame
            documentContainerView.needsDisplay = true
        }

        webView?.frame = documentContainerView.bounds
        webView?.needsDisplay = true

        if widthChanged {
            scheduleHeightRefresh(after: 0.15)
        }
    }
}
