//
//  MarkdownExportError.swift
//  Markdown
//

import Foundation

enum MarkdownExportError: LocalizedError, Equatable {
    case missingPandoc
    case pandocFailed(status: Int32, message: String)
    case pdfOutputMissing
    case pdfTimedOut(step: String)
    case printUnavailable

    var errorDescription: String? {
        switch self {
        case .missingPandoc:
            "Pandoc is not installed or could not be found."
        case .pandocFailed:
            "Pandoc could not export the document."
        case .pdfOutputMissing:
            "Markdown did not receive a PDF from WebKit."
        case let .pdfTimedOut(step):
            "Markdown timed out while \(step)."
        case .printUnavailable:
            "Markdown could not create a print operation."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missingPandoc:
            "Install Pandoc with Homebrew, then try exporting again: brew install pandoc"
        case let .pandocFailed(_, message):
            message.isEmpty ? nil : message
        case .pdfOutputMissing:
            "Try exporting again after relaunching Markdown."
        case .pdfTimedOut:
            "Try again after relaunching Markdown. If this keeps happening, export a shorter section of the document."
        case .printUnavailable:
            "Use File > Export as PDF, then print the PDF from Preview."
        }
    }
}
