//
//  MainWindowController.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import AppKit

final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private enum ToolbarItemID {
        static let mode = NSToolbarItem.Identifier("com.rianami.markdown.toolbar.mode")
    }

    let editorViewController = EditorViewController()

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
            let control = editorViewController.toolbarModeControl

            item.label = "Mode"
            item.paletteLabel = "Mode"
            item.view = control

            return item
        default:
            return nil
        }
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "MarkdownMainToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        return toolbar
    }
}
