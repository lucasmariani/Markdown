//
//  MainWindowController.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private enum ToolbarItemID {
        static let search = NSToolbarItem.Identifier("com.rianami.markdown.toolbar.search")
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

        window.title = "Markdown"
        window.minSize = NSSize(width: 700, height: 500)
        window.toolbarStyle = .automatic
        window.titlebarSeparatorStyle = .automatic
        window.contentViewController = editorViewController
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        window.toolbar = makeToolbar()
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        editorViewController.confirmCloseWindow()
    }

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
            let item = NSSearchToolbarItem(itemIdentifier: ToolbarItemID.search)
            item.label = "Search"
            item.paletteLabel = "Search"
            item.preferredWidthForSearchField = 220
            item.resignsFirstResponderWithCancel = true

            let searchField = item.searchField
            searchField.placeholderString = "Find"
            searchField.sendsSearchStringImmediately = true
            searchField.sendsWholeSearchString = true
            searchField.delegate = editorViewController
            searchField.target = editorViewController
            searchField.action = #selector(EditorViewController.toolbarSearchChanged(_:))

            editorViewController.attachToolbarSearchItem(item)
            return item
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
