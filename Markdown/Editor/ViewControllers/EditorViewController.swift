//
//  EditorViewController.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import AppKit
import PDFKit
import UniformTypeIdentifiers

// Keeps the AppKit document editors and the toolbar search UI in sync.
@MainActor
protocol EditorViewControllerDelegate: AnyObject {
    func editorViewController(_ controller: EditorViewController, didChangeMode mode: EditorViewController.EditorMode)
}

struct EditorScrollPosition: Equatable {
    let verticalFraction: CGFloat

    init(verticalFraction: CGFloat) {
        self.verticalFraction = min(max(verticalFraction, 0), 1)
    }
}

@MainActor
final class EditorViewController: NSViewController {
    // The segmented toolbar control uses these raw values directly.
    enum EditorMode: Int {
        case rendered = 1
        case source = 0
    }

    // The document remains the owner of persisted text.
    var onDocumentTextDidChange: ((String) -> Void)?
    weak var delegate: EditorViewControllerDelegate?

    lazy private(set) var searchControllerToolbarItem = searchController.toolbarItem
    var editorMode: EditorMode { currentMode }

    private let searchController = SearchToolbarController()
    private var currentMode: EditorMode = .rendered
    private var sourceText: String = ""
    private var documentURL: URL?
    private var documentBaseURL: URL?
    private var activePrintJobs: [MarkdownPrintJob] = []

    private lazy var sourceController: SourceEditorController = {
        let controller = SourceEditorController()
        controller.onTextChanged = { [weak self] text in
            self?.handleSourceTextChanged(text)
        }
        controller.onTextFinderAction = { [weak self] action in
            self?.handleSourceTextFinderAction(action) ?? false
        }
        return controller
    }()

    private lazy var renderedController: RenderedEditorController = {
        let controller = RenderedEditorController()
        controller.onMarkdownChanged = { [weak self] markdown in
            self?.handleRenderedMarkdownChanged(markdown)
        }
        return controller
    }()

    private lazy var searchCoordinator: SearchCoordinator = {
        let coordinator = SearchCoordinator(searchController: searchController)
        coordinator.onSearchRequested = { [weak self] query, backwards in
            self?.performSearch(query: query, backwards: backwards)
        }
        coordinator.onSearchCleared = { [weak self] in
            self?.clearSearch()
        }
        coordinator.onDoneRequested = { [weak self] in
            self?.unfocusSearchItem()
        }
        return coordinator
    }()

    // MARK: - Document API

    func setDocumentText(_ text: String) {
        sourceText = text
        sourceController.setText(text)

        if currentMode == .rendered {
            renderedController.render(markdown: sourceText)
        }
    }

    func documentTextSnapshot() -> String {
        if currentMode == .source {
            sourceText = sourceController.currentText()
        }
        return sourceText
    }

    func setDocumentURL(_ fileURL: URL?) {
        documentURL = fileURL
        let baseURL = fileURL?.deletingLastPathComponent()
        guard documentBaseURL?.standardizedFileURL != baseURL?.standardizedFileURL else {
            return
        }

        documentBaseURL = baseURL
        renderedController.setDocumentBaseURL(baseURL)
    }

    // MARK: - NSViewController

    override func loadView() {
        let contentContainer = NSView()
        let contentSurface = makeContentSurface()

        _ = searchCoordinator

        contentContainer.addSubview(contentSurface)
        contentSurface.addSubview(sourceController.scrollView)
        contentSurface.addSubview(renderedController.scrollView)

        sourceController.scrollView.translatesAutoresizingMaskIntoConstraints = false
        renderedController.scrollView.translatesAutoresizingMaskIntoConstraints = false

        installConstraints(in: contentContainer, contentSurface: contentSurface)

        self.view = contentContainer
        sourceController.scrollView.isHidden = (currentMode == .rendered)
        renderedController.scrollView.isHidden = (currentMode == .source)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sourceController.setText(sourceText)
        if currentMode == .rendered {
            _ = renderedController.ensureWebView()
        }
        updateVisibleEditor(for: currentMode)
        delegate?.editorViewController(self, didChangeMode: currentMode)
    }

    // MARK: - Mode Switching

    private func setMode(_ mode: EditorMode) {
        guard currentMode != mode else {
            return
        }

        let previousScrollPosition = scrollPosition(for: currentMode)
        guard prepareModeChange(to: mode) else {
            delegate?.editorViewController(self, didChangeMode: .source)
            return
        }

        currentMode = mode
        updateVisibleEditor(for: mode)
        restoreScrollPosition(previousScrollPosition, for: mode)
        delegate?.editorViewController(self, didChangeMode: mode)
        refreshSearchCountIfNeeded()
    }

    // MARK: - Search

    private func focusOnSearchItem() {
        searchCoordinator.focusSearch()
        updateSearchMatchCount(for: searchController.query)
    }

    private func unfocusSearchItem() {
        focusActiveEditor()
        searchController.collapse()
    }

    private func performSearch(query: String, backwards: Bool) {
        updateSearchMatchCount(for: query)

        if currentMode == .rendered {
            renderedController.find(query: query, backwards: backwards)
        } else {
            sourceController.find(query: query, backwards: backwards)
        }
    }

    private func clearSearch() {
        searchController.setMatchCount(nil)

        if currentMode == .rendered {
            renderedController.clearSearchResults()
        }
    }

    private func handleSourceTextChanged(_ text: String) {
        sourceText = text
        onDocumentTextDidChange?(sourceText)

        if currentMode == .source, searchController.isExpanded {
            updateSearchMatchCount(for: searchController.query)
        }
    }

    private func handleRenderedMarkdownChanged(_ markdown: String) {
        sourceText = markdown
        onDocumentTextDidChange?(sourceText)

        if currentMode == .rendered, searchController.isExpanded {
            updateSearchMatchCount(for: searchController.query)
        }
    }

    private func handleSourceTextFinderAction(_ action: NSTextFinder.Action) -> Bool {
        switch action {
        case .showFindInterface:
            focusOnSearchItem()
            return true
        case .nextMatch:
            focusOnSearchItem()
            performSearch(query: searchController.query, backwards: false)
            return true
        case .previousMatch:
            focusOnSearchItem()
            performSearch(query: searchController.query, backwards: true)
            return true
        case .hideFindInterface:
            unfocusSearchItem()
            return true
        default:
            return false
        }
    }

    private func updateSearchMatchCount(for query: String) {
        guard !query.isEmpty else {
            searchController.setMatchCount(nil)
            return
        }

        if currentMode == .source {
            searchController.setMatchCount(sourceController.countMatches(query: query))
            return
        }

        renderedController.countMatches(query: query) { [weak self] count in
            guard let self, self.currentMode == .rendered, self.searchController.query == query else {
                return
            }

            self.searchController.setMatchCount(count)
        }
    }

    // MARK: - Layout

    private func makeContentSurface() -> NSVisualEffectView {
        let contentSurface = NSVisualEffectView()
        contentSurface.material = .contentBackground
        contentSurface.blendingMode = .withinWindow
        contentSurface.state = .active
        contentSurface.translatesAutoresizingMaskIntoConstraints = false
        return contentSurface
    }

    private func installConstraints(in contentContainer: NSView, contentSurface: NSView) {
        let safeArea = contentContainer.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            contentSurface.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            contentSurface.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            contentSurface.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            contentSurface.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),

            sourceController.scrollView.leadingAnchor.constraint(equalTo: contentSurface.leadingAnchor),
            sourceController.scrollView.trailingAnchor.constraint(equalTo: contentSurface.trailingAnchor),
            sourceController.scrollView.topAnchor.constraint(equalTo: contentSurface.topAnchor),
            sourceController.scrollView.bottomAnchor.constraint(equalTo: contentSurface.bottomAnchor),

            renderedController.scrollView.leadingAnchor.constraint(equalTo: contentSurface.leadingAnchor),
            renderedController.scrollView.trailingAnchor.constraint(equalTo: contentSurface.trailingAnchor),
            renderedController.scrollView.topAnchor.constraint(equalTo: contentSurface.topAnchor),
            renderedController.scrollView.bottomAnchor.constraint(equalTo: contentSurface.bottomAnchor),
        ])
    }

    // MARK: - Helpers

    private func prepareModeChange(to mode: EditorMode) -> Bool {
        guard mode == .rendered else {
            return true
        }

        let latestSource = sourceController.currentText()
        if sourceText.isEmpty || !latestSource.isEmpty {
            sourceText = latestSource
        }

        return renderedController.ensureWebView()
    }

    private func updateVisibleEditor(for mode: EditorMode) {
        sourceController.scrollView.isHidden = (mode == .rendered)
        renderedController.scrollView.isHidden = (mode == .source)

        switch mode {
        case .rendered:
            renderedController.render(markdown: sourceText)
            renderedController.focus(in: view.window)
        case .source:
            sourceController.setText(sourceText)
            sourceController.focus(in: view.window)
        }
    }

    private func scrollPosition(for mode: EditorMode) -> EditorScrollPosition {
        switch mode {
        case .source:
            sourceController.scrollView.editorScrollPosition()
        case .rendered:
            renderedController.scrollView.editorScrollPosition()
        }
    }

    private func restoreScrollPosition(_ position: EditorScrollPosition, for mode: EditorMode) {
        applyScrollPosition(position, for: mode)

        DispatchQueue.main.async { [weak self] in
            self?.applyScrollPosition(position, for: mode)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard self?.currentMode == mode else {
                return
            }

            self?.applyScrollPosition(position, for: mode)
        }
    }

    private func applyScrollPosition(_ position: EditorScrollPosition, for mode: EditorMode) {
        switch mode {
        case .source:
            sourceController.scrollView.applyEditorScrollPosition(position)
        case .rendered:
            renderedController.scrollView.applyEditorScrollPosition(position)
        }
    }

    private func focusActiveEditor() {
        switch currentMode {
        case .source:
            sourceController.focus(in: view.window)
        case .rendered:
            renderedController.focus(in: view.window)
        }
    }

    private func refreshSearchCountIfNeeded() {
        guard searchController.isExpanded else {
            return
        }

        updateSearchMatchCount(for: searchController.query)
    }
}

@MainActor
extension NSScrollView {
    func editorScrollPosition() -> EditorScrollPosition {
        guard let documentView else {
            return EditorScrollPosition(verticalFraction: 0)
        }

        let visibleRect = contentView.bounds
        let scrollableHeight = max(documentView.bounds.height - visibleRect.height, 0)
        guard scrollableHeight > 0 else {
            return EditorScrollPosition(verticalFraction: 0)
        }

        if let verticalScroller {
            return EditorScrollPosition(verticalFraction: CGFloat(verticalScroller.doubleValue))
        }

        let visualTopOffset = documentView.isFlipped
            ? visibleRect.minY
            : scrollableHeight - visibleRect.minY
        return EditorScrollPosition(verticalFraction: visualTopOffset / scrollableHeight)
    }

    func applyEditorScrollPosition(_ position: EditorScrollPosition) {
        guard let documentView else {
            return
        }

        let visibleRect = contentView.bounds
        let scrollableHeight = max(documentView.bounds.height - visibleRect.height, 0)
        guard scrollableHeight > 0 else {
            return
        }

        let visualTopOffset = scrollableHeight * position.verticalFraction
        let originY = documentView.isFlipped
            ? visualTopOffset
            : scrollableHeight - visualTopOffset
        let boundedOriginY = min(max(originY, 0), scrollableHeight)
        contentView.scroll(to: NSPoint(x: visibleRect.minX, y: boundedOriginY))
        reflectScrolledClipView(contentView)
    }
}

// MARK: - Menu Actions

extension EditorViewController {
    private enum ExportFormat {
        case pdf
        case epub

        var panelTitle: String {
            switch self {
            case .pdf:
                "Export as PDF"
            case .epub:
                "Export as EPUB"
            }
        }

        var fileExtension: String {
            switch self {
            case .pdf:
                "pdf"
            case .epub:
                "epub"
            }
        }

        var contentType: UTType {
            switch self {
            case .pdf:
                .pdf
            case .epub:
                UTType(filenameExtension: "epub") ?? .data
            }
        }
    }

    @objc func showRendered(_ sender: Any?) {
        setMode(.rendered)
    }

    @objc func showSource(_ sender: Any?) {
        setMode(.source)
    }

    @objc func focusSearch(_ sender: Any?) {
        focusOnSearchItem()
    }

    @objc func findNext(_ sender: Any?) {
        focusOnSearchItem()
        performSearch(query: searchController.query, backwards: false)
    }

    @objc func findPrevious(_ sender: Any?) {
        focusOnSearchItem()
        performSearch(query: searchController.query, backwards: true)
    }

    @objc func exportPDF(_ sender: Any?) {
        presentExportPanel(for: .pdf)
    }

    @objc func exportEPUB(_ sender: Any?) {
        presentExportPanel(for: .epub)
    }

    @objc func printDocument(_ sender: Any?) {
        printCurrentDocument(presentingWindow: view.window)
    }

    func applyMarkdownFormatting(_ command: RenderedMarkdownFormattingCommand) {
        guard currentMode == .rendered else {
            return
        }

        renderedController.applyFormatting(command)
    }

    private func presentExportPanel(for format: ExportFormat) {
        let panel = NSSavePanel()
        panel.title = format.panelTitle
        panel.nameFieldStringValue = defaultExportFilename(for: format)
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard let window = view.window else {
            let response = panel.runModal()
            guard response == .OK, let outputURL = panel.url else {
                return
            }

            export(format: format, to: outputURL, presentingWindow: nil)
            return
        }

        panel.beginSheetModal(for: window) { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, response == .OK, let outputURL = panel.url else {
                    return
                }

                self.export(format: format, to: outputURL, presentingWindow: window)
            }
        }
    }

    private func export(format: ExportFormat, to outputURL: URL, presentingWindow: NSWindow?) {
        let markdown = documentTextSnapshot()
        let title = defaultExportTitle()
        let baseURL = documentBaseURL

        Task { @MainActor [weak self] in
            do {
                switch format {
                case .pdf:
                    try await MarkdownPDFExporter.export(
                        markdown: markdown,
                        title: title,
                        documentBaseURL: baseURL,
                        to: outputURL
                    )
                case .epub:
                    try await PandocEPUBExporter.export(
                        markdown: markdown,
                        title: title,
                        documentBaseURL: baseURL,
                        to: outputURL
                    )
                }
            } catch {
                self?.presentExportError(error, for: format, window: presentingWindow)
            }
        }
    }

    private func printCurrentDocument(presentingWindow: NSWindow?) {
        let markdown = documentTextSnapshot()
        let title = defaultExportTitle()
        let baseURL = documentBaseURL

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let job = try await MarkdownPrintJob.make(
                    markdown: markdown,
                    title: title,
                    documentBaseURL: baseURL
                )
                try runPrintJob(job, presentingWindow: presentingWindow)
            } catch {
                presentPrintError(error, window: presentingWindow)
            }
        }
    }

    private func runPrintJob(_ job: MarkdownPrintJob, presentingWindow: NSWindow?) throws {
        activePrintJobs.append(job)
        job.setCompletion { [weak self, weak job] in
            guard let job else {
                return
            }

            self?.activePrintJobs.removeAll { $0 === job }
        }

        do {
            try job.run(presentingWindow: presentingWindow)
        } catch {
            activePrintJobs.removeAll { $0 === job }
            job.cleanUp()
            throw error
        }
    }

    private func presentExportError(_ error: Error, for format: ExportFormat, window: NSWindow?) {
        let alert = NSAlert(error: error)
        alert.messageText = "\(format.panelTitle) Failed"

        if let recoverySuggestion = (error as? LocalizedError)?.recoverySuggestion,
           !recoverySuggestion.isEmpty {
            alert.informativeText = recoverySuggestion
        }

        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentPrintError(_ error: Error, window: NSWindow?) {
        let alert = NSAlert(error: error)
        alert.messageText = "Print Failed"

        if let recoverySuggestion = (error as? LocalizedError)?.recoverySuggestion,
           !recoverySuggestion.isEmpty {
            alert.informativeText = recoverySuggestion
        }

        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func defaultExportFilename(for format: ExportFormat) -> String {
        "\(defaultExportTitle()).\(format.fileExtension)"
    }

    private func defaultExportTitle() -> String {
        documentURL?
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "Untitled"
    }
}

@MainActor
private final class MarkdownPrintJob: NSObject {
    private let directoryURL: URL
    private let document: PDFDocument
    private var completion: (() -> Void)?

    static func make(markdown: String, title: String, documentBaseURL: URL?) async throws -> MarkdownPrintJob {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownPrint-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        do {
            let outputURL = directoryURL
                .appendingPathComponent(safeFilenameComponent(for: title))
                .appendingPathExtension("pdf")
            try await MarkdownPDFExporter.export(
                markdown: markdown,
                title: title,
                documentBaseURL: documentBaseURL,
                to: outputURL
            )
            guard let document = PDFDocument(url: outputURL) else {
                throw MarkdownExportError.pdfOutputMissing
            }

            return MarkdownPrintJob(directoryURL: directoryURL, document: document)
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }
    }

    private init(directoryURL: URL, document: PDFDocument) {
        self.directoryURL = directoryURL
        self.document = document
    }

    func setCompletion(_ completion: @escaping () -> Void) {
        self.completion = completion
    }

    func run(presentingWindow window: NSWindow?) throws {
        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false

        guard let operation = document.printOperation(
            for: printInfo,
            scalingMode: .pageScaleToFit,
            autoRotate: true
        ) else {
            throw MarkdownExportError.printUnavailable
        }

        operation.showsPrintPanel = true
        operation.showsProgressPanel = true

        if let window {
            operation.runModal(
                for: window,
                delegate: self,
                didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        } else {
            _ = operation.run()
            finish()
        }
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    @objc private func printOperationDidRun(
        _ printOperation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        finish()
    }

    private func finish() {
        cleanUp()
        completion?()
        completion = nil
    }

    private static func safeFilenameComponent(for title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = title
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.nilIfEmpty ?? "Untitled"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - NSMenuItemValidation

extension EditorViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(showRendered(_:)):
            menuItem.state = currentMode == .rendered ? .on : .off
            return true
        case #selector(showSource(_:)):
            menuItem.state = currentMode == .source ? .on : .off
            return true
        default:
            return true
        }
    }
}
