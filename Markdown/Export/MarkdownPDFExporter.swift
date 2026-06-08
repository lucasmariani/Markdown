//
//  MarkdownPDFExporter.swift
//  Markdown
//

import AppKit
import WebKit

@MainActor
enum MarkdownPDFExporter {
    fileprivate enum Timeout {
        static let pageLoadNanoseconds: UInt64 = 30_000_000_000
        static let javaScriptNanoseconds: UInt64 = 15_000_000_000
        static let pdfPageNanoseconds: UInt64 = 60_000_000_000
    }

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

        let evaluator = JavaScriptEvaluationRequest(timeoutNanoseconds: Timeout.javaScriptNanoseconds)
        return try await evaluator.evaluateHeight(script, in: webView, fallbackHeight: webView.frame.height)
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
        let request = PDFDataRequest(timeoutNanoseconds: Timeout.pdfPageNanoseconds)
        return try await request.createPDF(from: webView, configuration: configuration)
    }
}

@MainActor
private final class ExportWebViewLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutWorkItem: DispatchWorkItem?

    func load(html: String, baseURL: URL?, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                self?.finish(throwing: MarkdownExportError.pdfTimedOut(step: "loading the document for PDF export"))
            }
            self.timeoutWorkItem = timeoutWorkItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(Int(MarkdownPDFExporter.Timeout.pageLoadNanoseconds / 1_000_000)),
                execute: timeoutWorkItem
            )
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(throwing: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(throwing: error)
    }

    private func finish() {
        guard let continuation else {
            return
        }

        self.continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        continuation.resume()
    }

    private func finish(throwing error: Error) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        continuation.resume(throwing: error)
    }
}

@MainActor
private final class JavaScriptEvaluationRequest {
    private let timeoutNanoseconds: UInt64
    private var continuation: CheckedContinuation<CGFloat, Error>?
    private var timeoutWorkItem: DispatchWorkItem?

    init(timeoutNanoseconds: UInt64) {
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func evaluateHeight(_ script: String, in webView: WKWebView, fallbackHeight: CGFloat) async throws -> CGFloat {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let timeoutNanoseconds = self.timeoutNanoseconds
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                self?.finish(throwing: MarkdownExportError.pdfTimedOut(step: "measuring the document for PDF export"))
            }
            self.timeoutWorkItem = timeoutWorkItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(Int(timeoutNanoseconds / 1_000_000)),
                execute: timeoutWorkItem
            )

            webView.evaluateJavaScript(script) { [weak self] value, error in
                Task { @MainActor in
                    if let error {
                        self?.finish(throwing: error)
                    } else if let number = value as? NSNumber {
                        self?.finish(returning: CGFloat(truncating: number))
                    } else {
                        self?.finish(returning: fallbackHeight)
                    }
                }
            }
        }
    }

    private func finish(returning height: CGFloat) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        continuation.resume(returning: height)
    }

    private func finish(throwing error: Error) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        continuation.resume(throwing: error)
    }
}

@MainActor
private final class PDFDataRequest {
    private let timeoutNanoseconds: UInt64
    private var continuation: CheckedContinuation<Data, Error>?
    private var timeoutWorkItem: DispatchWorkItem?

    init(timeoutNanoseconds: UInt64) {
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func createPDF(from webView: WKWebView, configuration: WKPDFConfiguration) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let timeoutNanoseconds = self.timeoutNanoseconds
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                self?.finish(throwing: MarkdownExportError.pdfTimedOut(step: "creating a PDF page"))
            }
            self.timeoutWorkItem = timeoutWorkItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(Int(timeoutNanoseconds / 1_000_000)),
                execute: timeoutWorkItem
            )

            webView.createPDF(configuration: configuration) { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case let .success(data):
                        self?.finish(returning: data)
                    case let .failure(error):
                        self?.finish(throwing: error)
                    }
                }
            }
        }
    }

    private func finish(returning data: Data) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        continuation.resume(returning: data)
    }

    private func finish(throwing error: Error) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        continuation.resume(throwing: error)
    }
}
