import AppKit
import Foundation
import Testing
@testable import MarkdownApp

@MainActor
struct MarkdownDocumentTests {
    @Test
    func readThenWriteRoundTripsDocumentText() throws {
        let document = MarkdownDocument()
        let markdown = "# Title\n\nBody"

        try document.read(from: Data(markdown.utf8), ofType: "public.markdown")
        let data = try document.data(ofType: "public.markdown")

        #expect(String(decoding: data, as: UTF8.self) == markdown)
    }

    @Test
    func readThenWritePreservesDetectedUTF16DocumentText() throws {
        let document = MarkdownDocument()
        let markdown = "# Title\n\nBody with café"
        let sourceData = try #require(markdown.data(using: .utf16))

        try document.read(from: sourceData, ofType: "public.markdown")
        let writtenData = try document.data(ofType: "public.markdown")

        #expect(String(data: writtenData, encoding: .utf16) == markdown)
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

    @Test
    func recoveryArtifactDetectionFindsNewestSafeSaveArtifact() throws {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directoryURL) }

        let documentURL = directoryURL.appendingPathComponent("example.md")
        let olderArtifactURL = directoryURL.appendingPathComponent("example.md.sb-old")
        let newerArtifactURL = directoryURL.appendingPathComponent("example.md.sb-new")
        let unrelatedURL = directoryURL.appendingPathComponent("example.md.backup")

        try Data("# Document".utf8).write(to: documentURL)
        try Data("older".utf8).write(to: olderArtifactURL)
        try Data("newer".utf8).write(to: newerArtifactURL)
        try Data("backup".utf8).write(to: unrelatedURL)

        let olderDate = Date(timeIntervalSinceReferenceDate: 100)
        let newerDate = Date(timeIntervalSinceReferenceDate: 200)
        try fileManager.setAttributes([.modificationDate: olderDate], ofItemAtPath: olderArtifactURL.path())
        try fileManager.setAttributes([.modificationDate: newerDate], ofItemAtPath: newerArtifactURL.path())

        let detectedURL = MarkdownDocument.recoveryArtifactURL(forDocumentAt: documentURL, fileManager: fileManager)

        #expect(detectedURL == newerArtifactURL)
    }

    @Test
    func recommendedContentSizeUsesLargerDefaultWindow() {
        let size = MainWindowController.recommendedContentSize(
            for: "",
            availableFrame: NSRect(x: 0, y: 0, width: 1600, height: 1200)
        )

        #expect(size == NSSize(width: 1000, height: 860))
    }

    @Test
    func recommendedContentSizeIgnoresDocumentTextForWidth() {
        let availableFrame = NSRect(x: 0, y: 0, width: 1600, height: 1200)
        let narrow = MainWindowController.recommendedContentSize(for: "", availableFrame: availableFrame)
        let wide = MainWindowController.recommendedContentSize(
            for: String(repeating: "W", count: 220),
            availableFrame: availableFrame
        )

        #expect(narrow.width == 1000)
        #expect(wide.width == 1000)
        #expect(wide.height == narrow.height)
    }

    @Test
    func renderedShellUsesDocumentDirectoryForRelativeAssets() {
        let directoryURL = URL(fileURLWithPath: "/tmp/MarkdownTests Assets/", isDirectory: true)
        let shell = RenderedEditorShellHTML.standard(documentBaseURL: directoryURL)

        #expect(shell.contains("<base href=\"file:///tmp/MarkdownTests%20Assets/\">"))
        #expect(shell.contains("const localFileRoot = \"file:\\/\\/\\/tmp\\/MarkdownTests%20Assets\\/\";"))
        #expect(shell.contains("const allowedImageSchemes = new Set(['data:', 'file:', 'http:', 'https:']);"))
    }
}
