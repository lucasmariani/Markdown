//
//  PandocEPUBExporter.swift
//  Markdown
//

import Foundation

enum PandocEPUBExporter {
    static func export(markdown: String, title: String, documentBaseURL: URL?, to outputURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try exportSynchronously(
                markdown: markdown,
                title: title,
                documentBaseURL: documentBaseURL,
                to: outputURL
            )
        }.value
    }

    static func pandocExecutableURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        for directory in executableSearchDirectories(environment: environment) {
            let candidateURL = directory.appendingPathComponent("pandoc")
            if FileManager.default.isExecutableFile(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }

    static func arguments(title: String, cssURL: URL, documentBaseURL: URL?, outputURL: URL) -> [String] {
        var arguments = [
            "--from", "gfm+raw_html",
            "--to", "epub3",
            "--standalone",
            "--toc",
            "--wrap=preserve",
            "--metadata", "title=\(title)",
            "--css", cssURL.path,
            "--output", outputURL.path,
        ]

        if let documentBaseURL {
            arguments.append(contentsOf: ["--resource-path", documentBaseURL.path])
        }

        arguments.append("-")
        return arguments
    }

    private static func exportSynchronously(
        markdown: String,
        title: String,
        documentBaseURL: URL?,
        to outputURL: URL
    ) throws {
        guard let pandocURL = pandocExecutableURL() else {
            throw MarkdownExportError.missingPandoc
        }

        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let cssURL = temporaryDirectoryURL.appendingPathComponent("markdown-export.css")
        try MarkdownExportHTML.epubCSS.write(to: cssURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = pandocURL
        process.arguments = arguments(
            title: title,
            cssURL: cssURL,
            documentBaseURL: documentBaseURL,
            outputURL: outputURL
        )
        process.currentDirectoryURL = documentBaseURL

        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(Data(markdown.utf8))
        inputPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw MarkdownExportError.pandocFailed(status: process.terminationStatus, message: message)
        }
    }

    private static func executableSearchDirectories(environment: [String: String]) -> [URL] {
        let pathDirectories = environment["PATH", default: ""]
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        let commonDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/opt/local/bin",
            "/nix/var/nix/profiles/default/bin",
        ]
        let directories = pathDirectories + commonDirectories

        return Array(OrderedSet(directories)).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}

private struct OrderedSet<Element: Hashable>: Sequence {
    private var values: [Element] = []

    init(_ elements: [Element]) {
        var seen = Set<Element>()
        for element in elements where !seen.contains(element) {
            seen.insert(element)
            values.append(element)
        }
    }

    func makeIterator() -> Array<Element>.Iterator {
        values.makeIterator()
    }
}
