import Foundation
import Testing
@testable import MarkdownApp

struct DocumentLaunchPolicyTests {
    @Test
    func existingOpenDocumentsSuppressLaunchAction() {
        let existingURL = URL(fileURLWithPath: "/tmp/MarkdownTests/already-open.md")
        let previousSessionURL = URL(fileURLWithPath: "/tmp/MarkdownTests/previous-session.md")

        let action = DocumentLaunchPolicy.actionForLaunch(
            existingDocumentURLs: [existingURL],
            previousSessionURLs: [previousSessionURL]
        )

        #expect(action == .none)
    }

    @Test
    func previousSessionDocumentsAreRestoredWithoutDuplicates() {
        let documentURL = URL(fileURLWithPath: "/tmp/MarkdownTests/restored.md")
        let duplicateURL = URL(fileURLWithPath: "/tmp/MarkdownTests/./restored.md")

        let action = DocumentLaunchPolicy.actionForLaunch(
            existingDocumentURLs: [],
            previousSessionURLs: [documentURL, duplicateURL]
        )

        #expect(action == .reopen(urls: [documentURL]))
    }

    @Test
    func launchWithoutPreviousSessionOpensDocumentPicker() {
        let action = DocumentLaunchPolicy.actionForLaunch(
            existingDocumentURLs: [],
            previousSessionURLs: []
        )

        #expect(action == .openPanel)
    }
}
