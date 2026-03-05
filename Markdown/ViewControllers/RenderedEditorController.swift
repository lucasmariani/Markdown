//
//  RenderedEditorController.swift
//  Markdown
//
//  Created by Codex on 05/03/26.
//

import AppKit
import WebKit

private final class RenderedWebView: WKWebView {
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

final class RenderedEditorController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private enum Message {
        static let markdownChanged = "markdownChanged"
        static let markdownDebug = "markdownDebug"
    }

    let scrollView = NSScrollView(frame: .zero)
    private let documentContainerView = FlippedDocumentView(frame: .zero)
    private var webView: WKWebView?
    private var pendingHeightRefreshWorkItem: DispatchWorkItem?

    private var latestMarkdown = ""
    private var isReady = false
    private var isApplyingRenderedHTML = false
    private var pendingRefresh = false

    var onMarkdownInput: ((String) -> Void)?

    override init() {
        super.init()
        configureScrollView()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        pendingHeightRefreshWorkItem?.cancel()
        if let userContentController = webView?.configuration.userContentController {
            userContentController.removeScriptMessageHandler(forName: Message.markdownChanged)
            userContentController.removeScriptMessageHandler(forName: Message.markdownDebug)
        }
    }

    @discardableResult
    func ensureWebView() -> Bool {
        if webView != nil {
            return true
        }

        let userContentController = WKUserContentController()
        userContentController.add(self, name: Message.markdownChanged)
        userContentController.add(self, name: Message.markdownDebug)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController

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

        isApplyingRenderedHTML = true
        webView.evaluateJavaScript(command) { [weak self] _, error in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.isApplyingRenderedHTML = false
            }

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

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == Message.markdownDebug {
            return
        }

        guard message.name == Message.markdownChanged else {
            return
        }

        if isApplyingRenderedHTML {
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

        onMarkdownInput?(markdown)
    }

    private func loadShell() {
        guard let webView else {
            return
        }

        isReady = false
        layoutDocumentContainer(minimumHeight: max(scrollView.contentView.bounds.height, 1))
        webView.loadHTMLString(RenderedEditorShellHTML.standard, baseURL: Bundle.main.resourceURL)
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

    private func configureScrollView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        scrollView.documentView = documentContainerView
    }

    @objc
    private func contentViewBoundsDidChange(_ notification: Notification) {
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

        if documentContainerView.frame != frame {
            documentContainerView.frame = frame
        }

        webView?.frame = documentContainerView.bounds
    }
}
