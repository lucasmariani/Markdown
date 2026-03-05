//
//  EditorViewController.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import AppKit

final class EditorViewController: NSViewController, NSMenuItemValidation {
    private enum EditorMode: Int {
        case rendered = 1
        case source = 0
    }

    private let renderedContainerView = NSView(frame: .zero)
    private let findBarView = FindBarView()

    private var findBarHeightConstraint: NSLayoutConstraint?

    private lazy var sourceController: SourceEditorController = {
        let controller = SourceEditorController()
        controller.onTextChanged = { [weak self] text in
            self?.handleSourceTextChanged(text)
        }
        return controller
    }()

    private lazy var renderedController: RenderedEditorController = {
        let controller = RenderedEditorController(containerView: renderedContainerView)
        controller.onMarkdownInput = { [weak self] markdown in
            self?.handleRenderedMarkdownInput(markdown)
        }
        return controller
    }()

    private lazy var findCoordinator: FindCoordinator = {
        let coordinator = FindCoordinator(findBarView: findBarView)
        coordinator.onSearchRequested = { [weak self] query, backwards in
            self?.performSearch(query: query, backwards: backwards)
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
        let rootView = NSVisualEffectView()
        rootView.material = .windowBackground
        rootView.blendingMode = .behindWindow
        rootView.state = .active
        rootView.translatesAutoresizingMaskIntoConstraints = false

        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        let contentSurface = NSVisualEffectView()
        contentSurface.material = .contentBackground
        contentSurface.blendingMode = .withinWindow
        contentSurface.state = .active
        contentSurface.translatesAutoresizingMaskIntoConstraints = false

        _ = findCoordinator

        contentContainer.addSubview(findBarView)
        contentContainer.addSubview(contentSurface)
        contentSurface.addSubview(sourceController.scrollView)
        contentSurface.addSubview(renderedContainerView)

        sourceController.scrollView.translatesAutoresizingMaskIntoConstraints = false
        renderedContainerView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            findBarView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            findBarView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            findBarView.topAnchor.constraint(equalTo: contentContainer.topAnchor),

            contentSurface.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentSurface.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentSurface.topAnchor.constraint(equalTo: findBarView.bottomAnchor),
            contentSurface.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            sourceController.scrollView.leadingAnchor.constraint(equalTo: contentSurface.leadingAnchor),
            sourceController.scrollView.trailingAnchor.constraint(equalTo: contentSurface.trailingAnchor),
            sourceController.scrollView.topAnchor.constraint(equalTo: contentSurface.topAnchor),
            sourceController.scrollView.bottomAnchor.constraint(equalTo: contentSurface.bottomAnchor),

            renderedContainerView.leadingAnchor.constraint(equalTo: contentSurface.leadingAnchor),
            renderedContainerView.trailingAnchor.constraint(equalTo: contentSurface.trailingAnchor),
            renderedContainerView.topAnchor.constraint(equalTo: contentSurface.topAnchor),
            renderedContainerView.bottomAnchor.constraint(equalTo: contentSurface.bottomAnchor),
        ])

        let findBarHeight = findBarView.heightAnchor.constraint(equalToConstant: 0)
        findBarHeight.isActive = true
        findBarHeightConstraint = findBarHeight

        rootView.addSubview(contentContainer)
        let cornerAdaptiveGuide = rootView.layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))

        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: cornerAdaptiveGuide.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: cornerAdaptiveGuide.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: cornerAdaptiveGuide.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: cornerAdaptiveGuide.bottomAnchor),
        ])

        self.view = rootView
        sourceController.scrollView.isHidden = false
        renderedContainerView.isHidden = true
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
        renderedContainerView.isHidden = (mode == .source)
        onModeChanged?(mode == .rendered)

        if mode == .rendered {
            renderedController.render(markdown: sourceText)
        } else {
            sourceController.setText(sourceText)
            sourceController.focus(in: view.window)
        }
    }

    private func showFindBar() {
        findBarView.isHidden = false
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
        findBarView.isHidden = true
    }

    private func performSearch(query: String, backwards: Bool) {
        if currentMode == .rendered {
            renderedController.find(query: query, backwards: backwards)
        } else {
            _ = sourceController.find(query: query, backwards: backwards)
        }
    }

    private func handleRenderedMarkdownInput(_ markdown: String) {
        sourceText = markdown
        onDocumentTextDidChange?(sourceText)

        if currentMode == .source {
            sourceController.setText(markdown)
        }
    }

    private func handleSourceTextChanged(_ text: String) {
        sourceText = text
        onDocumentTextDidChange?(sourceText)
    }
}
