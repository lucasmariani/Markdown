//
//  MarkdownExportError.swift
//  Markdown
//

import Foundation

enum MarkdownExportError: LocalizedError, Equatable {
    case missingPandoc
    case pandocFailed(status: Int32, message: String)
    case pdfOutputMissing

    var errorDescription: String? {
        switch self {
        case .missingPandoc:
            "Pandoc is not installed or could not be found."
        case .pandocFailed:
            "Pandoc could not export the document."
        case .pdfOutputMissing:
            "Markdown did not receive a PDF from WebKit."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missingPandoc:
            "Install Pandoc with Homebrew, then try exporting again: brew install pandoc"
        case let .pandocFailed(_, message):
            message.isEmpty ? nil : message
        case .pdfOutputMissing:
            "Try exporting again, or use File > Print and choose Save as PDF."
        }
    }
}
