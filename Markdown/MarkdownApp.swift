//
//  AppDelegate.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()

        let controller = MainWindowController()
        self.windowController = controller
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.orderFrontRegardless()

        connectMenuTargets(to: controller.editorViewController)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        return windowController?.editorViewController.openDocument(at: url) ?? false
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: "About Markdown", action: nil, keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Markdown", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        fileMenu.addItem(withTitle: "New", action: #selector(EditorViewController.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open…", action: #selector(EditorViewController.openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())

        let saveItem = fileMenu.addItem(withTitle: "Save", action: #selector(EditorViewController.saveDocument(_:)), keyEquivalent: "s")
        saveItem.keyEquivalentModifierMask = [.command]

        let saveAsItem = fileMenu.addItem(withTitle: "Save As…", action: #selector(EditorViewController.saveDocumentAs(_:)), keyEquivalent: "S")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        let undoItem = editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        undoItem.keyEquivalentModifierMask = [.command]

        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]

        editMenu.addItem(NSMenuItem.separator())

        let cutItem = editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        cutItem.target = nil

        let copyItem = editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        copyItem.target = nil

        let pasteItem = editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        pasteItem.target = nil

        editMenu.addItem(NSMenuItem.separator())

        let selectAllItem = editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        selectAllItem.target = nil

        editMenu.addItem(NSMenuItem.separator())

        let findItem = editMenu.addItem(withTitle: "Find…", action: #selector(EditorViewController.focusSearch(_:)), keyEquivalent: "f")
        findItem.keyEquivalentModifierMask = [.command]

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        viewMenu.addItem(withTitle: "Rendered", action: #selector(EditorViewController.showRendered(_:)), keyEquivalent: "1")
        viewMenu.addItem(withTitle: "Source", action: #selector(EditorViewController.showSource(_:)), keyEquivalent: "2")

        NSApp.mainMenu = mainMenu
    }

    private func connectMenuTargets(to editorViewController: EditorViewController) {
        guard let mainMenu = NSApp.mainMenu else {
            return
        }

        let editorActions: Set<Selector> = [
            #selector(EditorViewController.newDocument(_:)),
            #selector(EditorViewController.openDocument(_:)),
            #selector(EditorViewController.saveDocument(_:)),
            #selector(EditorViewController.saveDocumentAs(_:)),
            #selector(EditorViewController.showRendered(_:)),
            #selector(EditorViewController.showSource(_:)),
            #selector(EditorViewController.focusSearch(_:)),
        ]

        for item in mainMenu.allItemsRecursively where item.action != #selector(NSApplication.terminate(_:)) {
            if let action = item.action, editorActions.contains(action) {
                item.target = editorViewController
            } else {
                item.target = nil
            }
        }
    }
}

private extension NSMenu {
    var allItemsRecursively: [NSMenuItem] {
        var result: [NSMenuItem] = []

        for item in items {
            result.append(item)
            if let submenu = item.submenu {
                result.append(contentsOf: submenu.allItemsRecursively)
            }
        }

        return result
    }
}
