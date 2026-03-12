//
//  MainWindowController.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import AppKit

@MainActor
final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private enum ToolbarItemID {
        static let mode = NSToolbarItem.Identifier("com.rianami.markdown.toolbar.mode")
    }

    let editorViewController = EditorViewController()
    private lazy var modeControl: NSSegmentedControl = makeModeControl()

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
        window.titlebarAppearsTransparent = false

        window.styleMask.insert(.fullSizeContentView)

        super.init(window: window)
        window.toolbar = makeToolbar()
        shouldCascadeWindows = true

        editorViewController.onModeChanged = { [weak self] isRendered in
            self?.modeControl.selectedSegment = isRendered ? 1 : 0
        }
        modeControl.selectedSegment = 0

        NSLog("[MainWindowController] initialized window=%@", String(describing: window))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ToolbarItemID.mode]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ToolbarItemID.mode]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
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

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "MarkdownMainToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        return toolbar
    }

    @objc
    private func modeControlChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 1:
            editorViewController.showRendered(sender)
        default:
            editorViewController.showSource(sender)
        }
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
