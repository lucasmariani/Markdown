//
//  MarkdownExportHTML.swift
//  Markdown
//

import Foundation

enum MarkdownExportHTML {
    static func document(markdown: String, title: String, documentBaseURL: URL?, css: String = pdfCSS) -> String {
        let baseElement = documentBaseURL.map {
            "<base href=\"\(htmlEscapedAttribute($0.absoluteString))\">"
        } ?? ""
        let renderedHTML = MarkdownRenderer.html(from: markdown)

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset=\"utf-8\">
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
          <title>\(htmlEscapedText(title))</title>
          \(baseElement)
          <style>
        \(css)
          </style>
        </head>
        <body>
          <article class=\"markdown-export\">
        \(renderedHTML)
          </article>
        </body>
        </html>
        """
    }

    static let sharedCSS = """
        :root {
          color-scheme: light;
          --bg: #ffffff;
          --text: #1f2328;
          --muted: #656d76;
          --border: #d0d7de;
          --code-bg: #f6f8fa;
          --blockquote: #d0d7de;
          --link: #0969da;
        }

        @page {
          margin: 0.65in;
        }

        html {
          background: var(--bg);
          color: var(--text);
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
          font-size: 12pt;
          line-height: 1.5;
        }

        body {
          margin: 0;
          background: var(--bg);
          color: var(--text);
        }

        .markdown-export {
          box-sizing: border-box;
          max-width: 100%;
        }

        h1, h2, h3, h4, h5, h6 {
          break-after: avoid;
          line-height: 1.25;
          margin: 1.35em 0 0.6em;
        }

        h1 {
          font-size: 2em;
          border-bottom: 1px solid var(--border);
          padding-bottom: 0.25em;
        }

        h2 {
          font-size: 1.45em;
          border-bottom: 1px solid var(--border);
          padding-bottom: 0.2em;
        }

        h3 {
          font-size: 1.18em;
        }

        p, ul, ol, blockquote, pre, table {
          margin: 0.85em 0;
        }

        a {
          color: var(--link);
          text-decoration: underline;
        }

        blockquote {
          border-left: 3px solid var(--blockquote);
          color: var(--muted);
          margin-left: 0;
          padding-left: 12px;
        }

        code, pre, kbd, samp {
          font-family: "SF Mono", SFMono-Regular, ui-monospace, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
          font-variant-ligatures: none;
        }

        code {
          background: var(--code-bg);
          border-radius: 4px;
          font-size: 0.9em;
          padding: 0.12em 0.28em;
        }

        pre {
          background: var(--code-bg);
          border: 1px solid var(--border);
          border-radius: 6px;
          box-sizing: border-box;
          break-inside: avoid;
          font-size: 8.75pt;
          line-height: 1.35;
          overflow-x: auto;
          padding: 10px 12px;
          tab-size: 4;
          white-space: pre;
        }

        pre code {
          background: transparent;
          border-radius: 0;
          font-size: inherit;
          padding: 0;
          white-space: inherit;
        }

        table {
          border-collapse: collapse;
          display: block;
          max-width: 100%;
          overflow-x: auto;
          width: max-content;
        }

        th, td {
          border: 1px solid var(--border);
          padding: 6px 10px;
          vertical-align: top;
        }

        img {
          height: auto;
          max-width: 100%;
        }

        hr {
          border: 0;
          border-top: 1px solid var(--border);
          margin: 1.5em 0;
        }
        """

    static let pdfCSS = sharedCSS + """

        .markdown-export {
          padding: 0.65in;
        }
        """

    static let epubCSS = sharedCSS + """

        body {
          padding: 0;
        }

        .markdown-export {
          max-width: none;
        }
        """

    private static func htmlEscapedText(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func htmlEscapedAttribute(_ string: String) -> String {
        htmlEscapedText(string)
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
