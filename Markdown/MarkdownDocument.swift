//
//  MarkdownDocument.swift
//  Markdown
//
//  Created by Codex on 04/03/26.
//

import AppKit
import Synchronization

@MainActor
final class MarkdownDocument: NSDocument {
    private nonisolated static let markdownTypeIdentifier = "net.daringfireball.markdown"
    private static let unsavedSubtitle = "Unsaved Markdown Document"

    private let textStorage = Mutex("")
    private weak var editorViewController: EditorViewController?

    override var fileURL: URL? {
        didSet {
            MainActor.assumeIsolated {
                updateWindowSubtitle()
            }
        }
    }

    nonisolated override class var autosavesInPlace: Bool {
        true
    }

    nonisolated override class var readableTypes: [String] {
        [markdownTypeIdentifier]
    }

    nonisolated override class var writableTypes: [String] {
        [markdownTypeIdentifier]
    }

    override func makeWindowControllers() {
        NSLog("[MarkdownDocument] makeWindowControllers begin")
        let windowController = MainWindowController()
        addWindowController(windowController)

        let editor = windowController.editorViewController
        editor.setDocumentText(storedText())
        editor.onDocumentTextDidChange = { [weak self] text in
            self?.applyEditorTextChange(text)
        }
        editorViewController = editor

        updateWindowSubtitle()
        NSLog("[MarkdownDocument] makeWindowControllers end windowControllers=%ld", windowControllers.count)
    }

    override func data(ofType typeName: String) throws -> Data {
        let snapshot = currentTextSnapshot()
        guard let data = snapshot.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        setStoredText(text)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.editorViewController?.setDocumentText(text)
        }
    }

    private func applyEditorTextChange(_ text: String) {
        guard text != storedText() else {
            return
        }
        setStoredText(text)
        updateChangeCount(.changeDone)
    }

    private func currentTextSnapshot() -> String {
        let snapshot = editorViewController?.documentTextSnapshot() ?? storedText()
        setStoredText(snapshot)
        return snapshot
    }

    private func updateWindowSubtitle() {
        let subtitle = fileURL
            .map { ($0.path(percentEncoded: false) as NSString).deletingLastPathComponent }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.unsavedSubtitle
        for controller in windowControllers {
            controller.window?.representedURL = fileURL
            controller.window?.subtitle = subtitle
        }
    }

    nonisolated private func storedText() -> String {
        textStorage.withLock { $0 }
    }

    nonisolated private func setStoredText(_ text: String) {
        textStorage.withLock { value in
            value = text
        }
    }
}
