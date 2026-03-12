//
//  LaunchSession.swift
//  Markdown
//
//  Created by Lucas on 06/03/26.
//

import Foundation

enum DocumentLaunchAction: Equatable {
    case none
    case openPanel
    case reopen(urls: [URL])
}

enum DocumentLaunchPolicy {
    static func actionForLaunch(existingDocumentURLs: [URL], previousSessionURLs: [URL]) -> DocumentLaunchAction {
        if !existingDocumentURLs.isEmpty {
            return .none
        }

        let uniqueSessionURLs = uniqueURLs(previousSessionURLs)
        if uniqueSessionURLs.isEmpty {
            return .openPanel
        }

        return .reopen(urls: uniqueSessionURLs)
    }

    static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var unique: [URL] = []

        for url in urls {
            let key = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
            if seen.insert(key).inserted {
                unique.append(url)
            }
        }

        return unique
    }
}

@MainActor
final class LaunchSessionStore {
    static let shared = LaunchSessionStore(userDefaults: .standard)

    private enum Keys {
        static let openDocumentBookmarks = "LaunchSession.openDocumentBookmarks"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func saveOpenDocumentSession(urls: [URL]) {
        let uniqueURLs = DocumentLaunchPolicy.uniqueURLs(urls)
        let bookmarks = uniqueURLs.compactMap(makeBookmarkData(for:))
        userDefaults.set(bookmarks, forKey: Keys.openDocumentBookmarks)
    }

    func restoredDocumentURLs() -> [URL] {
        guard let bookmarks = userDefaults.array(forKey: Keys.openDocumentBookmarks) as? [Data] else {
            return []
        }

        var refreshedBookmarks: [Data] = []
        var urls: [URL] = []

        for bookmark in bookmarks {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                continue
            }

            urls.append(url)

            if isStale, let refreshedBookmark = makeBookmarkData(for: url) {
                refreshedBookmarks.append(refreshedBookmark)
            } else {
                refreshedBookmarks.append(bookmark)
            }
        }

        if refreshedBookmarks.count != bookmarks.count || refreshedBookmarks != bookmarks {
            userDefaults.set(refreshedBookmarks, forKey: Keys.openDocumentBookmarks)
        }

        return DocumentLaunchPolicy.uniqueURLs(urls)
    }

    private func makeBookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
