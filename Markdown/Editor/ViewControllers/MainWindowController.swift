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
        static let blockStyle = NSToolbarItem.Identifier("com.rianami.markdown.toolbar.blockStyle")
        static let inlineFormatting = NSToolbarItem.Identifier("com.rianami.markdown.toolbar.inlineFormatting")
        static let listFormatting = NSToolbarItem.Identifier("com.rianami.markdown.toolbar.listFormatting")
        static let search = NSToolbarItem.Identifier("com.rianami.markdown.toolbar.search")
        static let mode = NSToolbarItem.Identifier("com.rianami.markdown.toolbar.mode")
    }

    private enum WindowSizing {
        static let defaultContentSize = NSSize(width: 1000, height: 860)
        static let minimumContentSize = NSSize(width: 760, height: 680)
        static let maxHeightRatio: CGFloat = 0.9
    }

    let editorViewController = EditorViewController()
    private lazy var modeControl: NSSegmentedControl = makeModeControl()
    private lazy var blockStylePopUpButton: NSPopUpButton = makeBlockStylePopUpButton()
    private lazy var inlineFormattingControl: NSSegmentedControl = makeInlineFormattingControl()
    private lazy var listFormattingControl: NSSegmentedControl = makeListFormattingControl()

    init(initialText: String = "") {
        let window = Self.makeWindow(contentViewController: editorViewController, initialText: initialText)

        super.init(window: window)
        window.toolbar = makeToolbar()
        shouldCascadeWindows = true

        editorViewController.delegate = self
        modeControl.selectedSegment = 0
        updateFormattingControls(for: .source)

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
        let maxHeight = max(floor(frame.height * WindowSizing.maxHeightRatio), WindowSizing.minimumContentSize.height)
        let defaultWidth = max(WindowSizing.defaultContentSize.width, WindowSizing.minimumContentSize.width)
        let defaultHeight = min(WindowSizing.defaultContentSize.height, maxHeight)

        return NSSize(width: defaultWidth, height: defaultHeight)
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
        window.preservesContentDuringLiveResize = false
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.contentViewController = contentViewController
        window.setContentSize(contentSize)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.styleMask.insert(.fullSizeContentView)
        return window
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

    private func makeBlockStylePopUpButton() -> NSPopUpButton {
        let button = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 136, height: 28), pullsDown: false)
        button.target = self
        button.action = #selector(blockStyleChanged(_:))
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let styles: [(String, RenderedMarkdownFormattingCommand)] = [
            ("Paragraph", .paragraph),
            ("Heading 1", .heading1),
            ("Heading 2", .heading2),
            ("Heading 3", .heading3),
            ("Heading 4", .heading4),
            ("Heading 5", .heading5),
            ("Heading 6", .heading6),
            ("Quote", .quote),
            ("Code Block", .codeBlock),
        ]

        for (title, command) in styles {
            button.addItem(withTitle: title)
            button.lastItem?.representedObject = command.rawValue
        }

        return button
    }

    private func makeInlineFormattingControl() -> NSSegmentedControl {
        let control = NSSegmentedControl(
            images: [
                symbolImage(named: "bold", accessibilityDescription: "Bold"),
                symbolImage(named: "italic", accessibilityDescription: "Italic"),
                symbolImage(named: "curlybraces", accessibilityDescription: "Inline Code"),
            ],
            trackingMode: .momentary,
            target: self,
            action: #selector(inlineFormattingChanged(_:))
        )
        control.segmentStyle = .texturedRounded
        for index in 0..<control.segmentCount {
            control.setWidth(32, forSegment: index)
        }
        return control
    }

    private func makeListFormattingControl() -> NSSegmentedControl {
        let control = NSSegmentedControl(
            images: [
                symbolImage(named: "list.bullet", accessibilityDescription: "Bulleted List"),
                symbolImage(named: "list.number", accessibilityDescription: "Numbered List"),
            ],
            trackingMode: .momentary,
            target: self,
            action: #selector(listFormattingChanged(_:))
        )
        control.segmentStyle = .texturedRounded
        for index in 0..<control.segmentCount {
            control.setWidth(32, forSegment: index)
        }
        return control
    }

    private func symbolImage(named name: String, accessibilityDescription: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription) ?? NSImage()
    }

    private func updateFormattingControls(for mode: EditorViewController.EditorMode) {
        let isRendered = mode == .rendered
        blockStylePopUpButton.isEnabled = isRendered
        inlineFormattingControl.isEnabled = isRendered
        listFormattingControl.isEnabled = isRendered

        if !isRendered {
            blockStylePopUpButton.selectItem(at: 0)
        }
    }
}

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            ToolbarItemID.blockStyle,
            ToolbarItemID.inlineFormatting,
            ToolbarItemID.listFormatting,
            ToolbarItemID.search,
            ToolbarItemID.mode,
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemID.blockStyle,
            ToolbarItemID.inlineFormatting,
            ToolbarItemID.listFormatting,
            .flexibleSpace,
            ToolbarItemID.search,
            ToolbarItemID.mode,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarItemID.blockStyle:
            let item = NSToolbarItem(itemIdentifier: ToolbarItemID.blockStyle)
            item.label = "Block Style"
            item.paletteLabel = "Block Style"
            item.view = blockStylePopUpButton
            return item
        case ToolbarItemID.inlineFormatting:
            let item = NSToolbarItem(itemIdentifier: ToolbarItemID.inlineFormatting)
            item.label = "Inline Formatting"
            item.paletteLabel = "Inline Formatting"
            item.view = inlineFormattingControl
            return item
        case ToolbarItemID.listFormatting:
            let item = NSToolbarItem(itemIdentifier: ToolbarItemID.listFormatting)
            item.label = "Lists"
            item.paletteLabel = "Lists"
            item.view = listFormattingControl
            return item
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
        updateFormattingControls(for: mode)
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

    @objc
    private func blockStyleChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let command = RenderedMarkdownFormattingCommand(rawValue: rawValue) else {
            return
        }

        editorViewController.applyMarkdownFormatting(command)
    }

    @objc
    private func inlineFormattingChanged(_ sender: NSSegmentedControl) {
        let command: RenderedMarkdownFormattingCommand?

        switch sender.selectedSegment {
        case 0:
            command = .bold
        case 1:
            command = .italic
        case 2:
            command = .inlineCode
        default:
            command = nil
        }

        if let command {
            editorViewController.applyMarkdownFormatting(command)
        }
    }

    @objc
    private func listFormattingChanged(_ sender: NSSegmentedControl) {
        let command: RenderedMarkdownFormattingCommand?

        switch sender.selectedSegment {
        case 0:
            command = .unorderedList
        case 1:
            command = .orderedList
        default:
            command = nil
        }

        if let command {
            editorViewController.applyMarkdownFormatting(command)
        }
    }
}
