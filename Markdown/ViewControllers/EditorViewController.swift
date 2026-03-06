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

    private let searchBarView = SearchBarView()

    private var findBarHeightConstraint: NSLayoutConstraint?

    private lazy var sourceController: SourceEditorController = {
        let controller = SourceEditorController()
        controller.onTextChanged = { [weak self] text in
            self?.handleSourceTextChanged(text)
        }
        return controller
    }()

    private lazy var renderedController: RenderedEditorController = {
        RenderedEditorController()
    }()

    private lazy var findCoordinator: FindCoordinator = {
        let coordinator = FindCoordinator(findBarView: searchBarView)
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

    var onDocumentTextDidChange: ((String) -> Void)?
    var onModeChanged: ((Bool) -> Void)?

    private var currentMode: EditorMode = .source
    private var sourceText: String = ""

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
//        let rootView = NSVisualEffectView()
//        rootView.material = .underWindowBackground
//        rootView.state = .active
//        rootView.translatesAutoresizingMaskIntoConstraints = false

        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

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

        NSLayoutConstraint.activate([
            searchBarView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            searchBarView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            searchBarView.topAnchor.constraint(equalTo: contentContainer.topAnchor),

            contentSurface.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentSurface.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentSurface.topAnchor.constraint(equalTo: searchBarView.bottomAnchor),
            contentSurface.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

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

//        rootView.addSubview(contentContainer)
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
        guard currentMode == .rendered else {
            sourceController.showFindInterface(in: view.window)
            return
        }

        showFindBar()
        findCoordinator.focusSearch()
    }

    @objc func findNext(_ sender: Any?) {
        guard currentMode == .rendered else {
            sourceController.performTextFinderAction(.nextMatch, in: view.window)
            return
        }

        showFindBar()
        performSearch(query: searchBarView.query, backwards: false)
    }

    @objc func findPrevious(_ sender: Any?) {
        guard currentMode == .rendered else {
            sourceController.performTextFinderAction(.previousMatch, in: view.window)
            return
        }

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
    }

    private func showFindBar() {
        searchBarView.isHidden = false
        findBarHeightConstraint?.constant = 40
        view.layoutSubtreeIfNeeded()
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
        if currentMode == .rendered {
            renderedController.find(query: query, backwards: backwards)
        }
    }

    private func clearSearch() {
        if currentMode == .rendered {
            renderedController.clearSearchResults()
        }
    }

    private func handleSourceTextChanged(_ text: String) {
        sourceText = text
        onDocumentTextDidChange?(sourceText)
    }
}
