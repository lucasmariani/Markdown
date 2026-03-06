//
//  AppDelegate.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import AppKit

@MainActor
private protocol LaunchSessionDocumentControlling: AnyObject {
    var openDocumentURLs: [URL] { get }
    func presentOpenPanel()
    func reopenDocument(at url: URL, completion: @escaping (Bool) -> Void)
}

extension NSDocumentController: LaunchSessionDocumentControlling {
    var openDocumentURLs: [URL] {
        documents.compactMap(\.fileURL)
    }

    func presentOpenPanel() {
        openDocument(nil)
    }

    func reopenDocument(at url: URL, completion: @escaping (Bool) -> Void) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()

        openDocument(withContentsOf: url, display: true) { document, alreadyOpen, error in
            let didOpen = document != nil || alreadyOpen

            if let markdownDocument = document as? MarkdownDocument, didStartAccessing {
                markdownDocument.adoptSecurityScopedURL(url)
            } else if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }

            if let error {
                NSLog("[AppDelegate] failed to reopen %@: %@", url.path(percentEncoded: false), error.localizedDescription)
            }

            completion(didOpen)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let documentController: any LaunchSessionDocumentControlling
    private let launchSessionStore: LaunchSessionStore
    private var hasPerformedInitialLaunchAction = false

    override init() {
        self.documentController = NSDocumentController.shared
        self.launchSessionStore = .shared
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[AppDelegate] didFinishLaunching")
        configureMainMenu()
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self] in
            self?.performInitialLaunchActionIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        performInitialLaunchActionIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        launchSessionStore.saveOpenDocumentSession(urls: documentController.openDocumentURLs)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, documentController.openDocumentURLs.isEmpty else {
            return false
        }

        documentController.presentOpenPanel()
        return true
    }

    private func performInitialLaunchActionIfNeeded() {
        guard !hasPerformedInitialLaunchAction else {
            return
        }

        let action = DocumentLaunchPolicy.actionForLaunch(
            existingDocumentURLs: documentController.openDocumentURLs,
            previousSessionURLs: launchSessionStore.restoredDocumentURLs()
        )

        hasPerformedInitialLaunchAction = true

        switch action {
        case .none:
            return
        case .openPanel:
            documentController.presentOpenPanel()
        case let .reopen(urls):
            reopenDocuments(urls)
        }
    }

    private func reopenDocuments(_ urls: [URL]) {
        guard !urls.isEmpty else {
            documentController.presentOpenPanel()
            return
        }

        var remainingCount = urls.count
        var reopenedAnyDocument = false

        for url in urls {
            documentController.reopenDocument(at: url) { [weak self] didOpen in
                guard let self else {
                    return
                }

                reopenedAnyDocument = reopenedAnyDocument || didOpen
                remainingCount -= 1

                guard remainingCount == 0 else {
                    return
                }

                if !reopenedAnyDocument && self.documentController.openDocumentURLs.isEmpty {
                    self.documentController.presentOpenPanel()
                }
            }
        }
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let aboutItem = appMenu.addItem(withTitle: "About Markdown", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        aboutItem.target = nil
        appMenu.addItem(NSMenuItem.separator())
        let servicesMenuItem = NSMenuItem()
        appMenu.addItem(servicesMenuItem)
        let servicesMenu = NSMenu(title: "Services")
        servicesMenuItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Markdown", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h").target = nil
        let hideOthersItem = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = nil
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "").target = nil

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Markdown", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        let newItem = fileMenu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        newItem.target = nil

        let openItem = fileMenu.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        openItem.target = nil
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(NSMenuItem.separator())

        let saveItem = fileMenu.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        saveItem.keyEquivalentModifierMask = [.command]
        saveItem.target = nil

        let saveAsItem = fileMenu.addItem(withTitle: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        saveAsItem.target = nil

        let exportItem = fileMenu.addItem(withTitle: "Export…", action: #selector(NSDocument.saveTo(_:)), keyEquivalent: "")
        exportItem.target = nil

        let saveAllItem = fileMenu.addItem(withTitle: "Save All", action: #selector(NSDocumentController.saveAllDocuments(_:)), keyEquivalent: "S")
        saveAllItem.keyEquivalentModifierMask = [.command, .option]
        saveAllItem.target = nil

        let revertToMenuItem = NSMenuItem(title: "Revert To", action: nil, keyEquivalent: "")
        fileMenu.addItem(revertToMenuItem)
        let revertToMenu = NSMenu(title: "Revert To")
        revertToMenuItem.submenu = revertToMenu

        let revertToSavedItem = revertToMenu.addItem(withTitle: "Last Saved", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        revertToSavedItem.target = nil

        revertToMenu.addItem(NSMenuItem.separator())
        let browseVersionsItem = revertToMenu.addItem(withTitle: "Browse All Versions…", action: #selector(NSDocument.browseVersions(_:)), keyEquivalent: "")
        browseVersionsItem.target = nil

        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Print…", action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "p").target = nil

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        let undoItem = editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        undoItem.keyEquivalentModifierMask = [.command]

        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]

        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x").target = nil
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c").target = nil
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v").target = nil

        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a").target = nil

        editMenu.addItem(NSMenuItem.separator())
        let findItem = editMenu.addItem(withTitle: "Find…", action: #selector(EditorViewController.focusSearch(_:)), keyEquivalent: "f")
        findItem.keyEquivalentModifierMask = [.command]
        findItem.target = nil
        editMenu.addItem(withTitle: "Find Next", action: #selector(EditorViewController.findNext(_:)), keyEquivalent: "g").target = nil
        let findPreviousItem = editMenu.addItem(withTitle: "Find Previous", action: #selector(EditorViewController.findPrevious(_:)), keyEquivalent: "G")
        findPreviousItem.keyEquivalentModifierMask = [.command, .shift]
        findPreviousItem.target = nil

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        viewMenu.addItem(withTitle: "Rendered", action: #selector(EditorViewController.showRendered(_:)), keyEquivalent: "1").target = nil
        viewMenu.addItem(withTitle: "Source", action: #selector(EditorViewController.showSource(_:)), keyEquivalent: "2").target = nil

        NSApp.mainMenu = mainMenu
    }
}
