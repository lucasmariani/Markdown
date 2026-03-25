//
//  MainWindowController.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import AppKit

@MainActor
final class MainWindowController: NSWindowController {
    private enum ToolbarItemID {
        static let search = NSToolbarItem.Identifier("com.rianami.markdown.toolbar.search")
        static let mode = NSToolbarItem.Identifier("com.rianami.markdown.toolbar.mode")
    }

    private enum WindowSizing {
        static let defaultContentSize = NSSize(width: 1120, height: 860)
        static let minimumContentSize = NSSize(width: 760, height: 680)
        static let maxWidthRatio: CGFloat = 0.85
        static let maxHeightRatio: CGFloat = 0.9
        static let horizontalPadding: CGFloat = 72
        static let measuredLineLimit = 400
        static let tabReplacement = "    "
    }

    let editorViewController = EditorViewController()
    private lazy var modeControl: NSSegmentedControl = makeModeControl()

    init(initialText: String = "") {
        let window = Self.makeWindow(contentViewController: editorViewController, initialText: initialText)

        super.init(window: window)
        window.toolbar = makeToolbar()
        shouldCascadeWindows = true

        editorViewController.delegate = self
        modeControl.selectedSegment = 0

        NSLog("[MainWindowController] initialized window=%@", String(describing: window))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private

    static func recommendedContentSize(
        for initialText: String,
        availableFrame: NSRect? = NSScreen.main?.visibleFrame
    ) -> NSSize {
        let frame = availableFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 960)
        let maxWidth = max(floor(frame.width * WindowSizing.maxWidthRatio), WindowSizing.minimumContentSize.width)
        let maxHeight = max(floor(frame.height * WindowSizing.maxHeightRatio), WindowSizing.minimumContentSize.height)
        let defaultWidth = min(WindowSizing.defaultContentSize.width, maxWidth)
        let defaultHeight = min(WindowSizing.defaultContentSize.height, maxHeight)
        let estimatedWidth = min(estimatedContentWidth(for: initialText), maxWidth)
        let width = max(defaultWidth, estimatedWidth)

        return NSSize(width: width, height: defaultHeight)
    }

    private static func makeWindow(contentViewController: NSViewController, initialText: String) -> NSWindow {
        let contentSize = recommendedContentSize(for: initialText)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = WindowSizing.minimumContentSize
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.contentViewController = contentViewController
        window.setContentSize(contentSize)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.styleMask.insert(.fullSizeContentView)
        return window
    }

    private static func estimatedContentWidth(for text: String) -> CGFloat {
        let longestLineWidth = text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .prefix(WindowSizing.measuredLineLimit)
            .reduce(CGFloat.zero) { currentMax, line in
                max(currentMax, measuredLineWidth(String(line)))
            }

        guard longestLineWidth > 0 else {
            return WindowSizing.defaultContentSize.width
        }

        return ceil(longestLineWidth + WindowSizing.horizontalPadding)
    }

    private static func measuredLineWidth(_ line: String) -> CGFloat {
        let expandedLine = line.replacingOccurrences(of: "\t", with: WindowSizing.tabReplacement)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        return (expandedLine as NSString).size(withAttributes: [.font: font]).width
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "MarkdownMainToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        return toolbar
    }

    private func makeModeControl() -> NSSegmentedControl {
        let sourceImage = NSImage(
            systemSymbolName: "chevron.left.forwardslash.chevron.right",
            accessibilityDescription: "Source Markdown"
        ) ?? NSImage()
        let renderedImage = NSImage(
            systemSymbolName: "doc.text.image",
            accessibilityDescription: "Rendered Markdown"
        ) ?? NSImage()

        let control = NSSegmentedControl(
            images: [sourceImage, renderedImage],
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeControlChanged(_:))
        )
        control.segmentStyle = .texturedRounded
        control.setWidth(32, forSegment: 0)
        control.setWidth(32, forSegment: 1)
        return control
    }
}

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ToolbarItemID.search, ToolbarItemID.mode]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ToolbarItemID.search, ToolbarItemID.mode]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarItemID.search:
            return editorViewController.searchControllerToolbarItem
        case ToolbarItemID.mode:
            let item = NSToolbarItem(itemIdentifier: ToolbarItemID.mode)
            item.label = "Editor Mode"
            item.paletteLabel = "Editor Mode"
            item.view = modeControl
            return item
        default:
            return nil
        }
    }
}

// MARK: - EditorViewControllerDelegate

extension MainWindowController: EditorViewControllerDelegate {
    func editorViewController(_ controller: EditorViewController, didChangeMode mode: EditorViewController.EditorMode) {
        modeControl.selectedSegment = mode == .rendered ? 1 : 0
    }
}

// MARK: - Actions

extension MainWindowController {
    @objc
    private func modeControlChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 1:
            editorViewController.showRendered(sender)
        default:
            editorViewController.showSource(sender)
        }
    }
}
