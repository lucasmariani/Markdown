//
//  MarkdownDocument.swift
//  Markdown
//
//  Created by Lucas on 04/03/26.
//

import AppKit
import Synchronization

@MainActor
final class MarkdownDocument: NSDocument {
    private nonisolated static let markdownTypeIdentifier = "public.markdown"
    private static let unsavedSubtitle = "Unsaved Markdown Document"

    private let textStorage = Mutex("")
    private let securityScopedURLStorage = Mutex<URL?>(nil)
    private weak var editorViewController: EditorViewController?
    private var hasPresentedRecoveryArtifactAlert = false

    override var fileURL: URL? {
        didSet {
            MainActor.assumeIsolated {
                updateWindowSubtitle()
                presentRecoveryArtifactAlertIfNeeded()
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
        presentRecoveryArtifactAlertIfNeeded()
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

    nonisolated func beginSecurityScopedAccess(to url: URL) {
        guard currentSecurityScopedURL()?.standardizedFileURL != url.standardizedFileURL else {
            return
        }

        endSecurityScopedAccess()

        guard url.startAccessingSecurityScopedResource() else {
            return
        }

        securityScopedURLStorage.withLock { value in
            value = url
        }
    }

    nonisolated func adoptSecurityScopedURL(_ url: URL) {
        guard currentSecurityScopedURL()?.standardizedFileURL != url.standardizedFileURL else {
            return
        }

        endSecurityScopedAccess()
        securityScopedURLStorage.withLock { value in
            value = url
        }
    }

    nonisolated private func currentSecurityScopedURL() -> URL? {
        securityScopedURLStorage.withLock { $0 }
    }

    private func presentRecoveryArtifactAlertIfNeeded() {
        guard !hasPresentedRecoveryArtifactAlert,
              let fileURL,
              let artifactURL = Self.recoveryArtifactURL(forDocumentAt: fileURL),
              let window = windowControllers.first?.window else {
            return
        }

        hasPresentedRecoveryArtifactAlert = true

        let alert = NSAlert()
        alert.messageText = "Interrupted Save File Found"
        alert.informativeText = """
        Markdown found a temporary save file left beside this document after an interrupted save. \
        The original document opened normally. You can reveal the temporary file in Finder to inspect or remove it.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reveal in Finder")
        alert.addButton(withTitle: "Ignore")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else {
                return
            }

            NSWorkspace.shared.activateFileViewerSelecting([artifactURL])
        }
    }

    nonisolated static func recoveryArtifactURL(
        forDocumentAt documentURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let documentName = documentURL.lastPathComponent
        guard let siblingURLs = try? fileManager.contentsOfDirectory(
            at: documentURL.deletingLastPathComponent(),
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let artifactURLs = siblingURLs.filter { candidateURL in
            guard candidateURL != documentURL else {
                return false
            }

            let candidateName = candidateURL.lastPathComponent
            return candidateName.hasPrefix("\(documentName).sb-")
        }

        return artifactURLs.max { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    nonisolated private func endSecurityScopedAccess() {
        let url = securityScopedURLStorage.withLock { value -> URL? in
            let currentURL = value
            value = nil
            return currentURL
        }

        guard let url else {
            return
        }

        url.stopAccessingSecurityScopedResource()
    }

    deinit {
        endSecurityScopedAccess()
    }
}
