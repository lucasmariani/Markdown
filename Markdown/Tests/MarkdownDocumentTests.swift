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
}
