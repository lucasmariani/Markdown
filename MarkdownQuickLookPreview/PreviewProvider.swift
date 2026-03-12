//
//  PreviewProvider.swift
//  MarkdownQuickLookPreview
//
//  Created by Codex on 3/12/26.
//

import Cocoa
import Markdown
import Quartz

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    override init() {
        super.init()
    }

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let markdown = try String(contentsOf: request.fileURL, encoding: .utf8)
        let html = Self.makePreviewHTML(markdown: markdown, fileURL: request.fileURL)

        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 900, height: 1200)
        ) { reply in
            reply.title = request.fileURL.lastPathComponent
            reply.stringEncoding = .utf8
            return Data(html.utf8)
        }

        return reply
    }

    private static func makePreviewHTML(markdown: String, fileURL: URL) -> String {
        let renderedHTML = HTMLFormatter.format(Document(parsing: markdown))
        let renderedHTMLLiteral = javaScriptStringLiteral(for: renderedHTML)
        let baseURLAttribute = htmlEscapedAttribute(fileURL.deletingLastPathComponent().absoluteString)

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <base href="\(baseURLAttribute)">
          <style>
            :root {
              color-scheme: light dark;
              --bg: #ffffff;
              --text: #1f2328;
              --muted: #656d76;
              --border: #d0d7de;
              --code-bg: #f6f8fa;
              --blockquote: #d0d7de;
              --link: #0969da;
            }

            @media (prefers-color-scheme: dark) {
              :root {
                --bg: #0d1117;
                --text: #e6edf3;
                --muted: #8b949e;
                --border: #30363d;
                --code-bg: #161b22;
                --blockquote: #3d444d;
                --link: #4493f8;
              }
            }

            html, body {
              margin: 0;
              padding: 0;
              min-height: 100%;
              background: var(--bg);
              color: var(--text);
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
              font-size: 15px;
              line-height: 1.55;
            }

            article {
              box-sizing: border-box;
              width: 100%;
              padding: 24px 28px 40px;
              white-space: normal;
              word-break: break-word;
            }

            h1, h2, h3, h4, h5, h6 {
              margin: 1.2em 0 0.6em;
              line-height: 1.25;
            }

            p, ul, ol, blockquote, pre, table {
              margin: 0.8em 0;
            }

            code {
              font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, Monaco, Consolas, monospace;
              font-size: 0.9em;
              background: var(--code-bg);
              padding: 0.15em 0.3em;
              border-radius: 6px;
            }

            pre {
              background: var(--code-bg);
              padding: 12px;
              border-radius: 10px;
              overflow-x: auto;
              border: 1px solid var(--border);
            }

            pre code {
              background: transparent;
              padding: 0;
              border-radius: 0;
            }

            blockquote {
              border-left: 3px solid var(--blockquote);
              margin-left: 0;
              padding-left: 12px;
              color: var(--muted);
            }

            a {
              color: var(--link);
              text-decoration: underline;
            }

            img {
              max-width: 100%;
              height: auto;
            }

            table {
              border-collapse: collapse;
              width: max-content;
              max-width: 100%;
              display: block;
              overflow-x: auto;
            }

            th, td {
              border: 1px solid var(--border);
              padding: 6px 10px;
            }

            [data-task-list="true"] {
              padding-left: 0;
            }

            [data-task-list-item="true"] {
              list-style: none;
              margin-left: 0;
            }

            [data-task-list-item="true"] > input[type="checkbox"] {
              margin: 0 0.55em 0 0;
              vertical-align: middle;
            }

            [data-task-list-item="true"] > p {
              display: inline;
              margin: 0;
            }
          </style>
        </head>
        <body>
          <article id="preview"></article>
          <script>
            (() => {
              const rawHTML = \(renderedHTMLLiteral);
              const preview = document.getElementById('preview');
              const allowedTags = new Set([
                'a', 'blockquote', 'br', 'code', 'del', 'em', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
                'hr', 'img', 'input', 'li', 'ol', 'p', 'pre', 'strong', 'table', 'tbody', 'td', 'th', 'thead', 'tr', 'ul'
              ]);
              const allowedAttributes = {
                a: new Set(['href', 'title']),
                code: new Set(['class']),
                img: new Set(['alt', 'src', 'title']),
                input: new Set(['checked', 'disabled', 'type'])
              };
              const allowedLinkSchemes = new Set(['http:', 'https:', 'mailto:']);
              const allowedImageSchemes = new Set(['data:', 'file:', 'http:', 'https:']);

              function sanitizeLinkValue(value, allowedSchemes) {
                const trimmed = (value || '').trim();
                if (!trimmed) {
                  return null;
                }

                if (
                  trimmed.startsWith('#') ||
                  trimmed.startsWith('/') ||
                  (!/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(trimmed) && !trimmed.startsWith('//'))
                ) {
                  return trimmed;
                }

                try {
                  const resolved = new URL(trimmed, document.baseURI);
                  if (allowedSchemes.has(resolved.protocol.toLowerCase())) {
                    return resolved.href;
                  }
                } catch (error) {
                  console.error('sanitizeLinkValue failed', error);
                }

                return null;
              }

              function sanitizeNode(node) {
                if (node.nodeType === Node.TEXT_NODE) {
                  return document.createTextNode(node.textContent || '');
                }

                if (node.nodeType !== Node.ELEMENT_NODE) {
                  return null;
                }

                const tag = node.tagName.toLowerCase();
                if (!allowedTags.has(tag)) {
                  const fragment = document.createDocumentFragment();
                  Array.from(node.childNodes).forEach((child) => {
                    const sanitizedChild = sanitizeNode(child);
                    if (sanitizedChild) {
                      fragment.appendChild(sanitizedChild);
                    }
                  });
                  return fragment;
                }

                const clean = document.createElement(tag);
                const allowedForTag = allowedAttributes[tag] || new Set();

                if (tag === 'input') {
                  const type = (node.getAttribute('type') || '').toLowerCase();
                  if (type !== 'checkbox' || !node.hasAttribute('disabled')) {
                    return null;
                  }

                  clean.setAttribute('type', 'checkbox');
                  clean.setAttribute('disabled', '');
                  if (node.hasAttribute('checked')) {
                    clean.setAttribute('checked', '');
                  }
                  return clean;
                }

                Array.from(node.attributes).forEach((attribute) => {
                  const name = attribute.name.toLowerCase();
                  if (!allowedForTag.has(name)) {
                    return;
                  }

                  if (tag === 'a' && name === 'href') {
                    const sanitizedHref = sanitizeLinkValue(attribute.value, allowedLinkSchemes);
                    if (sanitizedHref) {
                      clean.setAttribute('href', sanitizedHref);
                      clean.setAttribute('rel', 'noopener noreferrer');
                    }
                    return;
                  }

                  if (tag === 'img' && name === 'src') {
                    const sanitizedSrc = sanitizeLinkValue(attribute.value, allowedImageSchemes);
                    if (sanitizedSrc) {
                      clean.setAttribute('src', sanitizedSrc);
                    }
                    return;
                  }

                  clean.setAttribute(name, attribute.value);
                });

                Array.from(node.childNodes).forEach((child) => {
                  const sanitizedChild = sanitizeNode(child);
                  if (sanitizedChild) {
                    clean.appendChild(sanitizedChild);
                  }
                });

                return clean;
              }

              const parsed = new DOMParser().parseFromString(rawHTML, 'text/html');
              const fragment = document.createDocumentFragment();

              Array.from(parsed.body.childNodes).forEach((child) => {
                const sanitizedChild = sanitizeNode(child);
                if (sanitizedChild) {
                  fragment.appendChild(sanitizedChild);
                }
              });

              preview.replaceChildren(fragment);
            })();
          </script>
        </body>
        </html>
        """
    }

    private static func javaScriptStringLiteral(for string: String) -> String {
        let jsonData = try? JSONSerialization.data(withJSONObject: [string])
        let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        let literal = String(jsonString.dropFirst().dropLast())

        return literal
            .replacingOccurrences(of: "<", with: "\\u003C")
            .replacingOccurrences(of: ">", with: "\\u003E")
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private static func htmlEscapedAttribute(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
