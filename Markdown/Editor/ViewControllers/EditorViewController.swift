//
//  EditorViewController.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import AppKit

// Keeps the AppKit document editors and the toolbar search UI in sync.
@MainActor
protocol EditorViewControllerDelegate: AnyObject {
    func editorViewController(_ controller: EditorViewController, didChangeMode mode: EditorViewController.EditorMode)
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

    private let searchController = SearchToolbarController()
    private var currentMode: EditorMode = .source
    private var sourceText: String = ""

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
        RenderedEditorController()
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
        sourceController.scrollView.isHidden = false
        renderedController.scrollView.isHidden = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sourceController.setText(sourceText)
        delegate?.editorViewController(self, didChangeMode: .source)
    }

    // MARK: - Mode Switching

    private func setMode(_ mode: EditorMode) {
        guard currentMode != mode else {
            return
        }

        guard prepareModeChange(to: mode) else {
            delegate?.editorViewController(self, didChangeMode: .source)
            return
        }

        currentMode = mode
        updateVisibleEditor(for: mode)
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

// MARK: - Menu Actions

extension EditorViewController {
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
