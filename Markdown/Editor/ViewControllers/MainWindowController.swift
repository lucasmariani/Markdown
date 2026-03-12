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

    let editorViewController = EditorViewController()
    private lazy var modeControl: NSSegmentedControl = makeModeControl()

    init() {
        let window = Self.makeWindow(contentViewController: editorViewController)

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

    private static func makeWindow(contentViewController: NSViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 100, height: 100)
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.contentViewController = contentViewController
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
