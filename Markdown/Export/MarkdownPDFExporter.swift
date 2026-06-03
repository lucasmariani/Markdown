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
        static let margin: CGFloat = 46.8

        static var contentSize: NSSize {
            NSSize(
                width: paperSize.width - (margin * 2),
                height: paperSize.height - (margin * 2)
            )
        }
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
                width: Page.contentSize.width,
                height: Page.contentSize.height
            )
        )
        let loader = ExportWebViewLoader()
        webView.navigationDelegate = loader

        try await loader.load(html: html, baseURL: documentBaseURL ?? Bundle.main.resourceURL, in: webView)
        let contentHeight = try await measuredContentHeight(in: webView)
        let totalContentHeight = max(ceil(contentHeight), Page.contentSize.height)
        webView.frame.size.height = totalContentHeight
        webView.layoutSubtreeIfNeeded()

        let pageData = try await capturePageData(from: webView, totalContentHeight: totalContentHeight)
        try writePaginatedPDF(pageData, to: outputURL)
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw MarkdownExportError.pdfOutputMissing
        }
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

    private static func capturePageData(from webView: WKWebView, totalContentHeight: CGFloat) async throws -> [Data] {
        var pages: [Data] = []
        var yOffset: CGFloat = 0

        while yOffset < totalContentHeight {
            let remainingHeight = totalContentHeight - yOffset
            let pageHeight = min(Page.contentSize.height, remainingHeight)
            let configuration = WKPDFConfiguration()
            configuration.rect = NSRect(
                x: 0,
                y: yOffset,
                width: Page.contentSize.width,
                height: pageHeight
            )

            let data = try await pdfData(from: webView, configuration: configuration)
            guard !data.isEmpty else {
                throw MarkdownExportError.pdfOutputMissing
            }

            pages.append(data)
            yOffset += pageHeight
        }

        return pages
    }

    private static func writePaginatedPDF(_ pages: [Data], to outputURL: URL) throws {
        guard !pages.isEmpty else {
            throw MarkdownExportError.pdfOutputMissing
        }

        let temporaryURL = outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(origin: .zero, size: Page.paperSize)
        let context = CGContext(temporaryURL as CFURL, mediaBox: &mediaBox, nil)
        guard let context else {
            throw MarkdownExportError.pdfOutputMissing
        }
        var didClosePDF = false
        var didMovePDF = false
        defer {
            if !didClosePDF {
                context.closePDF()
            }
            if !didMovePDF {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        for pageData in pages {
            guard let provider = CGDataProvider(data: pageData as CFData),
                  let document = CGPDFDocument(provider),
                  let sourcePage = document.page(at: 1) else {
                throw MarkdownExportError.pdfOutputMissing
            }

            let sourceBox = sourcePage.getBoxRect(.mediaBox)
            let topAlignedY = Page.paperSize.height - Page.margin - min(sourceBox.height, Page.contentSize.height)

            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: Page.margin - sourceBox.minX, y: topAlignedY - sourceBox.minY)
            context.drawPDFPage(sourcePage)
            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        didClosePDF = true

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        didMovePDF = true
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
