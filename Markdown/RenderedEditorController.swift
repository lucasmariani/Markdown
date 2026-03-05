//
//  RenderedEditorController.swift
//  Markdown
//
//  Created by Codex on 05/03/26.
//

import AppKit
import WebKit

final class RenderedEditorController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private enum Message {
        static let markdownChanged = "markdownChanged"
        static let markdownDebug = "markdownDebug"
    }

    private let containerView: NSView
    private var webView: WKWebView?

    private var latestMarkdown = ""
    private var isReady = false
    private var isApplyingRenderedHTML = false
    private var pendingRefresh = false

    var onMarkdownInput: ((String) -> Void)?

    init(containerView: NSView) {
        self.containerView = containerView
        super.init()
    }

    deinit {
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

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground")

        containerView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

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
}
