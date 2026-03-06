import AppKit
import Testing
@testable import MarkdownApp

@MainActor
struct MarkdownDocumentTests {
    @Test
    func readThenWriteRoundTripsDocumentText() throws {
        let document = MarkdownDocument()
        let markdown = "# Title\n\nBody"

        try document.read(from: Data(markdown.utf8), ofType: "net.daringfireball.markdown")
        let data = try document.data(ofType: "net.daringfireball.markdown")

        #expect(String(decoding: data, as: UTF8.self) == markdown)
    }

    @Test
    func updatingFileURLRefreshesWindowSubtitle() async throws {
        let document = MarkdownDocument()
        document.makeWindowControllers()

        guard let window = document.windowControllers.first?.window else {
            Issue.record("Expected a document window")
            return
        }

        #expect(window.subtitle == "Unsaved Markdown Document")

        let fileURL = URL(fileURLWithPath: "/tmp/MarkdownTests/example.md")
        document.fileURL = fileURL
        await Task.yield()

        #expect(window.subtitle == "/tmp/MarkdownTests")
        #expect(window.representedURL == fileURL)
    }
}
