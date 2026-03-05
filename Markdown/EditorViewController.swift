//
//  EditorViewController.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import AppKit

final class EditorViewController: NSViewController, NSTextViewDelegate, NSMenuItemValidation {
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

    private let sourceScrollView = NSScrollView(frame: .zero)
    private let sourceTextView = NSTextView(frame: .zero)
    private let renderedContainerView = NSView(frame: .zero)
    private let findBarView = FindBarView()

    private var findBarHeightConstraint: NSLayoutConstraint?

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
    private var isUpdatingSourceProgrammatically = false

    var toolbarModeControl: NSSegmentedControl {
        modeControl
    }

    func setDocumentText(_ text: String) {
        sourceText = text

        isUpdatingSourceProgrammatically = true
        sourceTextView.string = text
        isUpdatingSourceProgrammatically = false

        if currentMode == .rendered {
            renderedController.render(markdown: sourceText)
        }
    }

    func documentTextSnapshot() -> String {
        if currentMode == .source {
            sourceText = sourceTextView.string
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
        configureSourceEditor()

        contentContainer.addSubview(findBarView)
        contentContainer.addSubview(contentSurface)
        contentSurface.addSubview(sourceScrollView)
        contentSurface.addSubview(renderedContainerView)

        sourceScrollView.translatesAutoresizingMaskIntoConstraints = false
        renderedContainerView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            findBarView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            findBarView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            findBarView.topAnchor.constraint(equalTo: contentContainer.topAnchor),

            contentSurface.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentSurface.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentSurface.topAnchor.constraint(equalTo: findBarView.bottomAnchor),
            contentSurface.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            sourceScrollView.leadingAnchor.constraint(equalTo: contentSurface.leadingAnchor),
            sourceScrollView.trailingAnchor.constraint(equalTo: contentSurface.trailingAnchor),
            sourceScrollView.topAnchor.constraint(equalTo: contentSurface.topAnchor),
            sourceScrollView.bottomAnchor.constraint(equalTo: contentSurface.bottomAnchor),

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
        sourceScrollView.isHidden = false
        renderedContainerView.isHidden = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sourceTextView.string = sourceText
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

    func textDidChange(_ notification: Notification) {
        guard !isUpdatingSourceProgrammatically else {
            return
        }

        sourceText = sourceTextView.string
        onDocumentTextDidChange?(sourceText)
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
            let latestSource = sourceTextView.string
            if sourceText.isEmpty || !latestSource.isEmpty {
                sourceText = latestSource
            }

            guard renderedController.ensureWebView() else {
                modeControl.selectedSegment = EditorMode.source.rawValue
                return
            }
        }

        currentMode = mode
        sourceScrollView.isHidden = (mode == .rendered)
        renderedContainerView.isHidden = (mode == .source)
        modeControl.selectedSegment = mode.rawValue

        if mode == .rendered {
            renderedController.render(markdown: sourceText)
        } else {
            isUpdatingSourceProgrammatically = true
            sourceTextView.string = sourceText
            isUpdatingSourceProgrammatically = false
            view.window?.makeFirstResponder(sourceTextView)
        }
    }

    private func configureSourceEditor() {
        sourceTextView.isEditable = true
        sourceTextView.isSelectable = true
        sourceTextView.isRichText = false
        sourceTextView.allowsUndo = true
        sourceTextView.usesFindBar = false
        sourceTextView.usesFontPanel = false
        sourceTextView.isAutomaticQuoteSubstitutionEnabled = false
        sourceTextView.isAutomaticDashSubstitutionEnabled = false
        sourceTextView.isAutomaticTextReplacementEnabled = false
        sourceTextView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        sourceTextView.backgroundColor = .clear
        sourceTextView.insertionPointColor = .labelColor
        sourceTextView.textContainerInset = NSSize(width: 18, height: 16)
        sourceTextView.delegate = self

        sourceTextView.isVerticallyResizable = true
        sourceTextView.isHorizontallyResizable = false
        sourceTextView.autoresizingMask = [.width]
        sourceTextView.textContainer?.widthTracksTextView = true
        sourceTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        sourceScrollView.hasVerticalScroller = true
        sourceScrollView.hasHorizontalScroller = false
        sourceScrollView.borderType = .noBorder
        sourceScrollView.autohidesScrollers = true
        sourceScrollView.drawsBackground = false
        sourceScrollView.scrollerStyle = .overlay
        sourceScrollView.documentView = sourceTextView
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
            view.window?.makeFirstResponder(sourceTextView)
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
            _ = performSourceSearch(query: query, backwards: backwards)
        }
    }

    @discardableResult
    private func performSourceSearch(query: String, backwards: Bool) -> Bool {
        let text = sourceTextView.string as NSString
        guard text.length > 0 else {
            return false
        }

        let selection = sourceTextView.selectedRange()
        let selectionStart = min(max(selection.location, 0), text.length)
        let selectionEnd = min(selectionStart + selection.length, text.length)

        let options: NSString.CompareOptions = backwards ? [.caseInsensitive, .backwards] : [.caseInsensitive]
        let primaryRange: NSRange
        let wrappedRange: NSRange

        if backwards {
            primaryRange = NSRange(location: 0, length: selectionStart)
            wrappedRange = NSRange(location: selectionEnd, length: text.length - selectionEnd)
        } else {
            primaryRange = NSRange(location: selectionEnd, length: text.length - selectionEnd)
            wrappedRange = NSRange(location: 0, length: selectionEnd)
        }

        var match = text.range(of: query, options: options, range: primaryRange)
        if match.location == NSNotFound {
            match = text.range(of: query, options: options, range: wrappedRange)
        }

        guard match.location != NSNotFound else {
            return false
        }

        sourceTextView.setSelectedRange(match)
        sourceTextView.scrollRangeToVisible(match)
        return true
    }

    private func handleRenderedMarkdownInput(_ markdown: String) {
        sourceText = markdown
        onDocumentTextDidChange?(sourceText)

        if currentMode == .source {
            isUpdatingSourceProgrammatically = true
            sourceTextView.string = markdown
            isUpdatingSourceProgrammatically = false
        }
    }
}
