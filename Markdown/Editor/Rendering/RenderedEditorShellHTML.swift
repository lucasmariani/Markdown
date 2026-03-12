//
//  RenderedEditorShellHTML.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import Foundation

enum RenderedEditorShellHTML {

    static let standard = """
<!doctype html>
<html>
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <link rel=\"stylesheet\" href=\"RendererPrettyLights.css\">
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
      background: transparent;
      color: var(--text);
      height: 100%;
      overflow: hidden;
      font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", Helvetica, Arial, sans-serif;
      font-size: 15px;
      line-height: 1.55;
    }

    #editor {
      box-sizing: border-box;
      min-height: 100%;
      width: 100%;
      padding: 20px 28px;
      white-space: normal;
      word-break: break-word;
      background: transparent;
      user-select: text;
      -webkit-user-select: text;
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
      cursor: pointer;
    }

    [data-task-list-item="true"] > p {
      display: inline;
      margin: 0;
    }

  </style>
</head>
<body>
  <article id=\"editor\"></article>
  <script src=\"RendererHighlighter.js\"></script>

  <script>
    (() => {
      const editor = document.getElementById('editor');
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
      const allowedImageSchemes = new Set(['data:', 'http:', 'https:']);

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

        if (tag === 'li') {
          const firstElementChild = clean.firstElementChild;
          if (
            firstElementChild &&
            firstElementChild.tagName.toLowerCase() === 'input' &&
            firstElementChild.getAttribute('type') === 'checkbox'
          ) {
            clean.setAttribute('data-task-list-item', 'true');
          }
        }

        if (tag === 'ul' || tag === 'ol') {
          const hasTaskListItems = Array.from(clean.children).some((child) => (
            child instanceof HTMLElement &&
            child.getAttribute('data-task-list-item') === 'true'
          ));

          if (hasTaskListItems) {
            clean.setAttribute('data-task-list', 'true');
          }
        }

        return clean;
      }

      function sanitizedFragment(html) {
        const template = document.createElement('template');
        template.innerHTML = html;

        const fragment = document.createDocumentFragment();
        Array.from(template.content.childNodes).forEach((child) => {
          const sanitizedChild = sanitizeNode(child);
          if (sanitizedChild) {
            fragment.appendChild(sanitizedChild);
          }
        });

        return fragment;
      }

      async function highlightCodeBlocks() {
        if (!window.MarkdownStarryNight || typeof window.MarkdownStarryNight.highlightCodeBlocks !== 'function') {
          return;
        }

        try {
          await window.MarkdownStarryNight.highlightCodeBlocks(editor);
        } catch (error) {
          console.error('highlightCodeBlocks failed', error);
        }
      }

      window.setRenderedDocument = (payload) => {
        const safeHTML = typeof payload === 'string'
          ? payload
          : (typeof payload?.html === 'string' ? payload.html : '');
        editor.replaceChildren();
        editor.appendChild(sanitizedFragment(safeHTML));
        highlightCodeBlocks();
      };
    })();
  </script>
</body>
</html>
"""
}
