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

        for item in mainMenu.allItemsRecursively where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = editorViewController
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
