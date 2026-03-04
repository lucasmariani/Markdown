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
