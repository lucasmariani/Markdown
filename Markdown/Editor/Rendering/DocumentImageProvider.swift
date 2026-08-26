//
//  DocumentImageProvider.swift
//  Markdown
//

import AppKit
import Foundation
import MarkdownEngine

/// Resolves Markdown images relative to the open document without allowing
/// `../` paths or absolute file URLs to escape the document directory.
struct DocumentImageProvider: EmbeddedImageProvider {
    let documentDirectoryURL: URL?

    func image(for reference: EmbeddedImageRequest) -> NSImage? {
        guard let imageURL = resolvedFileURL(for: reference.name) else {
            return nil
        }

        return NSImage(contentsOf: imageURL)
    }

    func fingerprint() -> AnyHashable {
        documentDirectoryURL?
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path(percentEncoded: false) ?? "no-document-directory"
    }

    func resolvedFileURL(for source: String) -> URL? {
        guard let documentDirectoryURL else {
            return nil
        }

        let rootURL = documentDirectoryURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            return nil
        }

        let candidateURL: URL
        if let absoluteURL = URL(string: trimmedSource), absoluteURL.scheme != nil {
            guard absoluteURL.isFileURL else {
                return nil
            }
            candidateURL = absoluteURL
        } else {
            let decodedSource = trimmedSource.removingPercentEncoding ?? trimmedSource
            candidateURL = URL(fileURLWithPath: decodedSource, relativeTo: rootURL)
        }

        let resolvedURL = candidateURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard Self.isDescendant(resolvedURL, of: rootURL) else {
            return nil
        }

        return resolvedURL
    }

    private static func isDescendant(_ fileURL: URL, of rootURL: URL) -> Bool {
        let rootComponents = rootURL.pathComponents
        let fileComponents = fileURL.pathComponents
        guard fileComponents.count > rootComponents.count else {
            return false
        }

        return fileComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
    }
}
