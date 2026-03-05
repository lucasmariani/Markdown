//
//  MarkdownDocument.swift
//  Markdown
//
//  Created by Codex on 04/03/26.
//

import AppKit

final class MarkdownDocument: NSDocument {
    private nonisolated static let markdownTypeIdentifier = "net.daringfireball.markdown"
    private static let unsavedSubtitle = "Unsaved Markdown Document"

    nonisolated(unsafe) private var textStorage = ""
    nonisolated(unsafe) private weak var editorViewController: EditorViewController?

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
        editor.setDocumentText(textStorage)
        editor.onDocumentTextDidChange = { [weak self] text in
            self?.applyEditorTextChange(text)
        }
        editorViewController = editor

        if let window = windowController.window {
            window.center()
            NSLog("[MarkdownDocument] makeWindowControllers window centered frame=%@", NSStringFromRect(window.frame))
        }
        updateWindowSubtitle()
        NSLog("[MarkdownDocument] makeWindowControllers end windowControllers=%ld", windowControllers.count)
    }

    nonisolated override func data(ofType typeName: String) throws -> Data {
        guard let data = textStorage.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        textStorage = text

        if let editor = editorViewController {
            DispatchQueue.main.async {
                editor.setDocumentText(text)
            }
        }
    }

    private func applyEditorTextChange(_ text: String) {
        guard text != textStorage else {
            return
        }
        textStorage = text
        updateChangeCount(.changeDone)
    }

    private func updateWindowSubtitle() {
        let subtitle = fileURL?.deletingLastPathComponent().path(percentEncoded: false) ?? Self.unsavedSubtitle
        for controller in windowControllers {
            controller.window?.subtitle = subtitle
        }
    }
}
