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

    private lazy var modeControl: NSSegmentedControl = {
        let renderedSymbol = NSImage(
            systemSymbolName: "doc.text.image",
            accessibilityDescription: "Rendered Markdown"
        )
        let sourceSymbol = NSImage(
            systemSymbolName: "chevron.left.forwardslash.chevron.right",
            accessibilityDescription: "Source Markdown"
        )

        let control: NSSegmentedControl
        if let renderedSymbol, let sourceSymbol {
            control = NSSegmentedControl(
                images: [sourceSymbol, renderedSymbol],
                trackingMode: .selectOne,
                target: self,
                action: #selector(modeControlChanged(_:))
            )
            control.setWidth(30, forSegment: 0)
            control.setWidth(30, forSegment: 1)
            control.setToolTip("Rendered Markdown", forSegment: 1)
            control.setToolTip("Source Markdown", forSegment: 0)
        } else {
            control = NSSegmentedControl(
                labels: ["Source", "Rendered"],
                trackingMode: .selectOne,
                target: self,
                action: #selector(modeControlChanged(_:))
            )
        }

        control.segmentStyle = .separated
        control.controlSize = .small
        control.selectedSegment = EditorMode.source.rawValue
        return control
    }()

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

    var onDocumentTextDidChange: ((String) -> Void)?

    private var currentMode: EditorMode = .source
    private var sourceText: String = ""
    private var activeSearchQuery = ""

    var toolbarModeControl: NSSegmentedControl {
        modeControl
    }

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

        configureFindBar()

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
    }

    @objc func showRendered(_ sender: Any?) {
        setMode(.rendered)
    }

    @objc func showSource(_ sender: Any?) {
        setMode(.source)
    }

    @objc func focusSearch(_ sender: Any?) {
        showFindBar()
        findBarView.focus(initialQuery: activeSearchQuery)
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

    @objc private func modeControlChanged(_ sender: NSSegmentedControl) {
        guard let mode = EditorMode(rawValue: sender.selectedSegment) else {
            return
        }
        setMode(mode)
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
                modeControl.selectedSegment = EditorMode.source.rawValue
                return
            }
        }

        currentMode = mode
        sourceController.scrollView.isHidden = (mode == .rendered)
        renderedContainerView.isHidden = (mode == .source)
        modeControl.selectedSegment = mode.rawValue

        if mode == .rendered {
            renderedController.render(markdown: sourceText)
        } else {
            sourceController.setText(sourceText)
            sourceController.focus(in: view.window)
        }
    }

    private func configureFindBar() {
        findBarView.onQueryChanged = { [weak self] query in
            guard let self else {
                return
            }

            self.activeSearchQuery = query
            guard !query.isEmpty else {
                return
            }
            self.performSearch(query: query, backwards: false)
        }

        findBarView.onFindRequested = { [weak self] backwards in
            self?.runFind(backwards: backwards)
        }

        findBarView.onDoneRequested = { [weak self] in
            self?.hideFindBar()
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

    private func runFind(backwards: Bool) {
        let query = findBarView.query
        activeSearchQuery = query
        guard !query.isEmpty else {
            return
        }

        performSearch(query: query, backwards: backwards)
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
