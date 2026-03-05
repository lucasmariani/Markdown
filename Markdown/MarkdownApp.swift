//
//  MarkdownApp.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import AppKit

@main
struct MarkdownApp {

    private static let appDelegate = AppDelegate()

    @MainActor
    static func main() {
        let app = NSApplication.shared

        app.setActivationPolicy(.regular)
        app.delegate = appDelegate
        app.run()
    }
}
