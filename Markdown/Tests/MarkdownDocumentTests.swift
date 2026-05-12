import AppKit
import Foundation
import Testing
@testable import MarkdownApp

private final class TestScrollDocumentView: NSView {
    private let usesFlippedCoordinates: Bool

    override var isFlipped: Bool {
        usesFlippedCoordinates
    }

    init(frame: NSRect, isFlipped: Bool) {
        usesFlippedCoordinates = isFlipped
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

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
    func acceptsSystemMarkdownTypeIdentifier() throws {
        let document = MarkdownDocument()
        let markdown = "# Title\n\nBody"
        let systemMarkdownTypeIdentifier = "net.daringfireball.markdown"

        #expect(MarkdownDocument.readableTypes.contains(systemMarkdownTypeIdentifier))
        #expect(MarkdownDocument.writableTypes.contains(systemMarkdownTypeIdentifier))

        try document.read(from: Data(markdown.utf8), ofType: systemMarkdownTypeIdentifier)
        let data = try document.data(ofType: systemMarkdownTypeIdentifier)

        #expect(String(decoding: data, as: UTF8.self) == markdown)
    }

    @Test
    func appDocumentTypeDeclarationIncludesSystemMarkdownTypeIdentifier() throws {
        let systemMarkdownTypeIdentifier = "net.daringfireball.markdown"
        let infoDictionary = try #require(Bundle(for: MarkdownDocument.self).infoDictionary)
        let documentTypes = try #require(infoDictionary["CFBundleDocumentTypes"] as? [[String: Any]])
        let contentTypes = documentTypes.flatMap { documentType in
            documentType["LSItemContentTypes"] as? [String] ?? []
        }

        #expect(contentTypes.contains(systemMarkdownTypeIdentifier))
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
    func savedTextBaselineOnlyUpdatesForDocumentSaves() {
        #expect(MarkdownDocument.shouldUpdateSavedText(after: .saveOperation))
        #expect(MarkdownDocument.shouldUpdateSavedText(after: .saveAsOperation))
        #expect(MarkdownDocument.shouldUpdateSavedText(after: .autosaveInPlaceOperation))
        #expect(!MarkdownDocument.shouldUpdateSavedText(after: .saveToOperation))
        #expect(!MarkdownDocument.shouldUpdateSavedText(after: .autosaveElsewhereOperation))
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
        let shell = RenderedEditorShellHTML.standard(
            documentBaseURL: directoryURL,
            localFileResourceScheme: "markdown-local-resource"
        )

        #expect(shell.contains("<base href=\"file:///tmp/MarkdownTests%20Assets/\">"))
        #expect(shell.contains("const localFileRoot = \"file:\\/\\/\\/tmp\\/MarkdownTests%20Assets\\/\";"))
        #expect(shell.contains("const localFileResourceScheme = \"markdown-local-resource\";"))
        #expect(shell.contains("const allowedImageSchemes = new Set(['data:', 'http:', 'https:']);"))
        #expect(shell.contains("return `${localFileResourceScheme}://asset?url=${encodeURIComponent(fileURL.href)}`;"))
    }

    @Test
    func renderedShellExposesEditableMarkdownBridge() {
        let shell = RenderedEditorShellHTML.standard(
            documentBaseURL: nil,
            localFileResourceScheme: "markdown-local-resource"
        )

        #expect(shell.contains("contenteditable=\"true\""))
        #expect(shell.contains("window.applyMarkdownFormatting = (command) =>"))
        #expect(shell.contains("function serializeEditorToMarkdown()"))
        #expect(shell.contains("const blockTags = new Set"))
        #expect(shell.contains("function hasBlockChildren(element)"))
        #expect(shell.contains("function isListItemElement(element)"))
        #expect(shell.contains("function toggleCurrentBlockList(ordered)"))
        #expect(shell.contains("toggleCurrentBlockList(false);"))
        #expect(shell.contains("toggleCurrentBlockList(true);"))
        #expect(shell.contains("return serializeChildren(element);"))
        #expect(shell.contains("function rememberSelection()"))
        #expect(shell.contains("function restoreSelection()"))
        #expect(shell.contains("return trimTrailingBlankLines(serializeChildren(editor));"))
        #expect(shell.contains("function trimTrailingBlankLines(markdown)"))
        #expect(shell.contains("window.webkit?.messageHandlers?.renderedEditor"))
        #expect(shell.contains("editor.addEventListener('input', scheduleMarkdownDidChange);"))
    }

    @Test
    func emptyMarkdownListMarkersRenderAsListsWhenMarkerSpaceIsPreserved() {
        #expect(MarkdownRenderer.html(from: "- ").contains("<ul>"))
        #expect(MarkdownRenderer.html(from: "1. ").contains("<ol>"))
    }

    @Test
    func toolbarIncludesRenderedFormattingControls() throws {
        let windowController = MainWindowController()
        let toolbar = try #require(windowController.window?.toolbar)
        let defaultIdentifiers = windowController
            .toolbarDefaultItemIdentifiers(toolbar)
            .map(\.rawValue)

        #expect(defaultIdentifiers.contains("com.rianami.markdown.toolbar.blockStyle"))
        #expect(defaultIdentifiers.contains("com.rianami.markdown.toolbar.inlineFormatting"))
        #expect(defaultIdentifiers.contains("com.rianami.markdown.toolbar.listFormatting"))

        let blockItem = windowController.toolbar(
            toolbar,
            itemForItemIdentifier: NSToolbarItem.Identifier("com.rianami.markdown.toolbar.blockStyle"),
            willBeInsertedIntoToolbar: true
        )
        let inlineItem = windowController.toolbar(
            toolbar,
            itemForItemIdentifier: NSToolbarItem.Identifier("com.rianami.markdown.toolbar.inlineFormatting"),
            willBeInsertedIntoToolbar: true
        )
        let listItem = windowController.toolbar(
            toolbar,
            itemForItemIdentifier: NSToolbarItem.Identifier("com.rianami.markdown.toolbar.listFormatting"),
            willBeInsertedIntoToolbar: true
        )

        #expect(blockItem?.view is NSPopUpButton)
        #expect(inlineItem?.view is NSSegmentedControl)
        #expect(listItem?.view is NSSegmentedControl)
    }

    @Test
    func documentWindowsDefaultToRenderedMode() throws {
        let windowController = MainWindowController(initialText: "# Title")
        let toolbar = try #require(windowController.window?.toolbar)
        let modeItem = try #require(windowController.toolbar(
            toolbar,
            itemForItemIdentifier: NSToolbarItem.Identifier("com.rianami.markdown.toolbar.mode"),
            willBeInsertedIntoToolbar: true
        ))
        let modeControl = try #require(modeItem.view as? NSSegmentedControl)

        #expect(windowController.editorViewController.editorMode == .rendered)
        #expect(modeControl.selectedSegment == EditorViewController.EditorMode.rendered.rawValue)
    }

    @Test
    func editorScrollPositionRoundTripsForFlippedViews() {
        let scrollView = testScrollView(isDocumentFlipped: true)
        let scrollableHeight = testScrollableHeight(in: scrollView)

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollableHeight * 0.5))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        #expect(abs(scrollView.editorScrollPosition().verticalFraction - 0.5) < 0.001)

        scrollView.applyEditorScrollPosition(EditorScrollPosition(verticalFraction: 0.75))

        #expect(abs(scrollView.contentView.bounds.minY - (scrollableHeight * 0.75)) < 0.001)
    }

    @Test
    func editorScrollPositionRoundTripsForUnflippedViews() {
        let scrollView = testScrollView(isDocumentFlipped: false)
        let scrollableHeight = testScrollableHeight(in: scrollView)

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollableHeight * 0.25))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        #expect(abs(scrollView.editorScrollPosition().verticalFraction - 0.75) < 0.001)

        scrollView.applyEditorScrollPosition(EditorScrollPosition(verticalFraction: 0.25))

        #expect(abs(scrollView.contentView.bounds.minY - (scrollableHeight * 0.75)) < 0.001)
    }

    @Test
    func editorScrollPositionClampsInvalidFractions() {
        #expect(EditorScrollPosition(verticalFraction: -0.5).verticalFraction == 0)
        #expect(EditorScrollPosition(verticalFraction: 1.5).verticalFraction == 1)
    }

    private func testScrollView(isDocumentFlipped: Bool) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.documentView = TestScrollDocumentView(
            frame: NSRect(x: 0, y: 0, width: 100, height: 1000),
            isFlipped: isDocumentFlipped
        )
        return scrollView
    }

    private func testScrollableHeight(in scrollView: NSScrollView) -> CGFloat {
        guard let documentView = scrollView.documentView else {
            return 0
        }

        return max(documentView.bounds.height - scrollView.contentView.bounds.height, 0)
    }
}
