//
//  EditorViewController.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import AppKit

@MainActor
final class EditorViewController: NSViewController, NSMenuItemValidation {
    private enum EditorMode: Int {
        case rendered = 1
        case source = 0
    }

    var onDocumentTextDidChange: ((String) -> Void)?
    var onModeChanged: ((Bool) -> Void)?

    private let searchBarView = SearchBarView()
    private var currentMode: EditorMode = .source
    private var sourceText: String = ""
    private var findBarHeightConstraint: NSLayoutConstraint?

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

    private lazy var findCoordinator: SearchCoordinator = {
        let coordinator = SearchCoordinator(searchBarView: searchBarView)
        coordinator.onSearchRequested = { [weak self] query, backwards in
            self?.performSearch(query: query, backwards: backwards)
        }
        coordinator.onSearchCleared = { [weak self] in
            self?.clearSearch()
        }
        coordinator.onDoneRequested = { [weak self] in
            self?.hideFindBar()
        }
        return coordinator
    }()

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

    override func loadView() {
        let contentContainer = NSView()

        let contentSurface = NSVisualEffectView()
        contentSurface.material = .contentBackground
        contentSurface.blendingMode = .withinWindow
        contentSurface.state = .active
        contentSurface.translatesAutoresizingMaskIntoConstraints = false

        _ = findCoordinator

        contentContainer.addSubview(searchBarView)
        contentContainer.addSubview(contentSurface)
        contentSurface.addSubview(sourceController.scrollView)
        contentSurface.addSubview(renderedController.scrollView)

        sourceController.scrollView.translatesAutoresizingMaskIntoConstraints = false
        renderedController.scrollView.translatesAutoresizingMaskIntoConstraints = false

        let safeArea = contentContainer.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            searchBarView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            searchBarView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            searchBarView.topAnchor.constraint(equalTo: safeArea.topAnchor),

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

        let findBarHeight = searchBarView.heightAnchor.constraint(equalToConstant: 0)
        findBarHeight.isActive = true
        findBarHeightConstraint = findBarHeight

        self.view = contentContainer
        sourceController.scrollView.isHidden = false
        renderedController.scrollView.isHidden = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sourceController.setText(sourceText)
        onModeChanged?(false)
    }

    @objc func showRendered(_ sender: Any?) {
        setMode(.rendered)
    }

    @objc func showSource(_ sender: Any?) {
        setMode(.source)
    }

    @objc func focusSearch(_ sender: Any?) {
        showFindBar()
        findCoordinator.focusSearch()
    }

    @objc func findNext(_ sender: Any?) {
        showFindBar()
        performSearch(query: searchBarView.query, backwards: false)
    }

    @objc func findPrevious(_ sender: Any?) {
        showFindBar()
        performSearch(query: searchBarView.query, backwards: true)
    }

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

    private func setMode(_ mode: EditorMode) {
        guard currentMode != mode else {
            return
        }

        if mode == .rendered {
            let latestSource = sourceController.currentText()
            if sourceText.isEmpty || !latestSource.isEmpty {
                sourceText = latestSource
            }

            guard renderedController.ensureWebView() else {
                onModeChanged?(false)
                return
            }
        }

        currentMode = mode
        sourceController.scrollView.isHidden = (mode == .rendered)
        renderedController.scrollView.isHidden = (mode == .source)
        onModeChanged?(mode == .rendered)

        if mode == .rendered {
            renderedController.render(markdown: sourceText)
            renderedController.focus(in: view.window)
        } else {
            sourceController.setText(sourceText)
            sourceController.focus(in: view.window)
        }

        if !searchBarView.isHidden {
            updateSearchMatchCount(for: searchBarView.query)
        }
    }

    private func showFindBar() {
        searchBarView.isHidden = false
        findBarHeightConstraint?.constant = 40
        view.layoutSubtreeIfNeeded()
        updateSearchMatchCount(for: searchBarView.query)
    }

    private func hideFindBar() {
        if currentMode == .source {
            sourceController.focus(in: view.window)
        } else {
            renderedController.focus(in: view.window)
        }

        findBarHeightConstraint?.constant = 0
        view.layoutSubtreeIfNeeded()
        searchBarView.isHidden = true
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
        searchBarView.setMatchCount(nil)

        if currentMode == .rendered {
            renderedController.clearSearchResults()
        }
    }

    private func handleSourceTextChanged(_ text: String) {
        sourceText = text
        onDocumentTextDidChange?(sourceText)

        if currentMode == .source, !searchBarView.isHidden {
            updateSearchMatchCount(for: searchBarView.query)
        }
    }

    private func handleSourceTextFinderAction(_ action: NSTextFinder.Action) -> Bool {
        switch action {
        case .showFindInterface:
            showFindBar()
            findCoordinator.focusSearch()
            return true
        case .nextMatch:
            showFindBar()
            performSearch(query: searchBarView.query, backwards: false)
            return true
        case .previousMatch:
            showFindBar()
            performSearch(query: searchBarView.query, backwards: true)
            return true
        case .hideFindInterface:
            hideFindBar()
            return true
        default:
            return false
        }
    }

    private func updateSearchMatchCount(for query: String) {
        guard !query.isEmpty else {
            searchBarView.setMatchCount(nil)
            return
        }

        if currentMode == .source {
            searchBarView.setMatchCount(sourceController.countMatches(query: query))
            return
        }

        renderedController.countMatches(query: query) { [weak self] count in
            guard let self, self.currentMode == .rendered, self.searchBarView.query == query else {
                return
            }

            self.searchBarView.setMatchCount(count)
        }
    }
}
