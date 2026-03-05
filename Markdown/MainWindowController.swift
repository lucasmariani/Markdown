//
//  MainWindowController.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import AppKit

final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private enum ToolbarItemID {
        static let source = NSToolbarItem.Identifier("com.rianami.markdown.toolbar.source")
        static let rendered = NSToolbarItem.Identifier("com.rianami.markdown.toolbar.rendered")
    }

    let editorViewController = EditorViewController()
    private lazy var sourceModeButton: NSButton = makeModeButton(
        symbolName: "chevron.left.forwardslash.chevron.right",
        action: #selector(EditorViewController.showSource(_:)),
        toolTip: "Source Markdown"
    )
    private lazy var renderedModeButton: NSButton = makeModeButton(
        symbolName: "doc.text.image",
        action: #selector(EditorViewController.showRendered(_:)),
        toolTip: "Rendered Markdown"
    )

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 700, height: 500)
        window.toolbarStyle = .automatic
        window.titlebarSeparatorStyle = .automatic
        window.contentViewController = editorViewController
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.toolbar = makeToolbar()
        shouldCascadeWindows = true

        editorViewController.onModeChanged = { [weak self] isRendered in
            self?.sourceModeButton.state = isRendered ? .off : .on
            self?.renderedModeButton.state = isRendered ? .on : .off
        }
        sourceModeButton.state = .on
        renderedModeButton.state = .off

        NSLog("[MainWindowController] initialized window=%@", String(describing: window))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ToolbarItemID.source, ToolbarItemID.rendered]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ToolbarItemID.source, ToolbarItemID.rendered]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarItemID.source:
            let item = NSToolbarItem(itemIdentifier: ToolbarItemID.source)
            item.label = "Source"
            item.paletteLabel = "Source"
            item.view = sourceModeButton
            return item
        case ToolbarItemID.rendered:
            let item = NSToolbarItem(itemIdentifier: ToolbarItemID.rendered)
            item.label = "Rendered"
            item.paletteLabel = "Rendered"
            item.view = renderedModeButton
            return item
        default:
            return nil
        }
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "MarkdownMainToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        return toolbar
    }

    private func makeModeButton(symbolName: String, action: Selector, toolTip: String) -> NSButton {
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: toolTip
        ) ?? NSImage()
        let button = NSButton(image: image, target: editorViewController, action: action)
        button.setButtonType(.toggle)
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.toolTip = toolTip
        return button
    }
}
