//
//  MarkdownPDFExporter.swift
//  Markdown
//

import AppKit
import WebKit

@MainActor
enum MarkdownPDFExporter {
    private enum Page {
        static let paperSize = NSSize(width: 612, height: 792)
    }

    static func export(markdown: String, title: String, documentBaseURL: URL?, to outputURL: URL) async throws {
        let html = MarkdownExportHTML.document(
            markdown: markdown,
            title: title,
            documentBaseURL: documentBaseURL
        )
        let webView = WKWebView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: Page.paperSize.width,
                height: Page.paperSize.height
            )
        )
        let loader = ExportWebViewLoader()
        webView.navigationDelegate = loader

        try await loader.load(html: html, baseURL: documentBaseURL ?? Bundle.main.resourceURL, in: webView)
        let contentHeight = try await measuredContentHeight(in: webView)
        webView.frame.size.height = max(contentHeight, webView.frame.height)

        let configuration = WKPDFConfiguration()
        configuration.rect = NSRect(
            x: 0,
            y: 0,
            width: Page.paperSize.width,
            height: webView.frame.height
        )
        let data = try await pdfData(from: webView, configuration: configuration)
        guard !data.isEmpty else {
            throw MarkdownExportError.pdfOutputMissing
        }

        try data.write(to: outputURL, options: [.atomic])
    }

    private static func measuredContentHeight(in webView: WKWebView) async throws -> CGFloat {
        let script = """
        (() => {
          const body = document.body;
          const doc = document.documentElement;
          return Math.max(
            body ? body.scrollHeight : 0,
            body ? body.offsetHeight : 0,
            doc ? doc.scrollHeight : 0,
            doc ? doc.offsetHeight : 0
          );
        })()
        """

        let result = try await webView.evaluateJavaScript(script)
        if let number = result as? NSNumber {
            return CGFloat(truncating: number)
        }

        return webView.frame.height
    }

    private static func pdfData(from webView: WKWebView, configuration: WKPDFConfiguration) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: configuration) { result in
                continuation.resume(with: result)
            }
        }
    }
}

@MainActor
private final class ExportWebViewLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(html: String, baseURL: URL?, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(with: .success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<Void, Error>) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        continuation.resume(with: result)
    }
}
