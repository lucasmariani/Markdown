//
//  RenderedEditorController.swift
//  Markdown
//
//  Created by Lucas on 05/03/26.
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
        webView.find(query, configuration: configuration) { [weak self] result in
            guard let self, result.matchFound else {
                return
            }

            self.scrollCurrentMatchIntoView()
        }
    }

    func countMatches(query: String, completion: @escaping (Int) -> Void) {
        guard isReady, let webView, !query.isEmpty else {
            completion(0)
            return
        }

        let queryLiteral = javaScriptStringLiteral(query)
        let script = """
        (() => {
          const query = \(queryLiteral);
          if (!query) {
            return 0;
          }

          const editor = document.getElementById('editor');
          const haystack = (editor?.innerText ?? document.body?.innerText ?? '').toLocaleLowerCase();
          const needle = query.toLocaleLowerCase();

          let count = 0;
          let indexStep = Math.max(needle.length, 1);
          let searchIndex = 0;
          for (let index = haystack.indexOf(needle, searchIndex); index !== -1; index = haystack.indexOf(needle, index + indexStep)) {
            count += 1;
          }

          return count;
        })()
        """

        webView.evaluateJavaScript(script) { result, error in
            if let error {
                NSLog("Failed to count rendered search results: %@", error.localizedDescription)
                completion(0)
                return
            }

            completion((result as? NSNumber).map { Int(truncating: $0) } ?? 0)
        }
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

    private func scrollCurrentMatchIntoView() {
        guard let webView else {
            return
        }

        let script = """
        (() => {
          const selection = window.getSelection();
          if (!selection || selection.rangeCount === 0) {
            return null;
          }

          const range = selection.getRangeAt(0);
          const rect = range.getBoundingClientRect();
          if (!rect || (rect.width === 0 && rect.height === 0)) {
            return null;
          }

          return {
            x: rect.left + window.scrollX,
            y: rect.top + window.scrollY,
            width: rect.width,
            height: rect.height
          };
        })()
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else {
                return
            }

            if let error {
                NSLog("Failed to locate rendered search result: %@", error.localizedDescription)
                return
            }

            guard let matchRect = self.domRect(from: result) else {
                return
            }

            let visibleHeight = self.scrollView.contentView.bounds.height
            let inset = max((visibleHeight - matchRect.height) * 0.5, 24)
            self.documentContainerView.scrollToVisible(matchRect.insetBy(dx: 0, dy: -inset))
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }

    private func domRect(from result: Any?) -> NSRect? {
        guard let dictionary = result as? [String: Any],
              let x = dictionary["x"] as? Double,
              let y = dictionary["y"] as? Double,
              let width = dictionary["width"] as? Double,
              let height = dictionary["height"] as? Double,
              let webView else {
            return nil
        }

        let rectInWebView = NSRect(x: x, y: y, width: width, height: max(height, 1))
        return documentContainerView.convert(rectInWebView, from: webView)
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
