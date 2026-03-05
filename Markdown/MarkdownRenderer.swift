//
//  MarkdownRenderer.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import Foundation
import Markdown

enum MarkdownRenderer {
    static func html(from markdown: String) -> String {
        let document = Document(parsing: markdown)
        return HTMLFormatter.format(document)
    }
}
