//
//  MarkdownLauncher.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import AppKit

@main
struct MarkdownLauncher {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}
