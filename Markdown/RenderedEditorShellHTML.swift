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
      font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", Helvetica, Arial, sans-serif;
      font-size: 15px;
      line-height: 1.55;
    }

    #editor {
      box-sizing: border-box;
      min-height: 100%;
      width: 100%;
      padding: 20px 28px;
      outline: none;
      white-space: normal;
      word-break: break-word;
      caret-color: var(--text);
      background: transparent;
    }

    #editor:empty::before {
      content: \"\";
      color: var(--muted);
      pointer-events: none;
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
  </style>
</head>
<body>
  <article id=\"editor\" contenteditable=\"true\" spellcheck=\"false\"></article>
  <script src=\"RendererHighlighter.js\"></script>

  <script>
    (() => {
      const editor = document.getElementById('editor');
      let suppressNative = false;

      function postDebug(payload) {
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.markdownDebug) {
            window.webkit.messageHandlers.markdownDebug.postMessage(payload);
          }
        } catch (_) {
          // Best-effort debug logging only.
        }
      }

      function escapeText(text) {
        return text
          .replace(/\\\\/g, '\\\\\\\\')
          .replace(/([`*_{}[\\]()#+\\-.!|>])/g, '\\\\$1');
      }

      async function highlightCodeBlocks() {
        if (!window.MarkdownStarryNight || typeof window.MarkdownStarryNight.highlightCodeBlocks !== 'function') {
          postDebug({
            event: 'highlight.skip',
            reason: 'highlighterUnavailable'
          });
          return;
        }

        try {
          await window.MarkdownStarryNight.highlightCodeBlocks(editor);
          postDebug({
            event: 'highlight.done'
          });
        } catch (error) {
          postDebug({
            event: 'highlight.error',
            message: String(error)
          });
        }
      }

      function inlineMarkdown(node) {
        if (node.nodeType === Node.TEXT_NODE) {
          return escapeText(node.textContent || '');
        }

        if (node.nodeType !== Node.ELEMENT_NODE) {
          return '';
        }

        const tag = node.tagName.toLowerCase();
        const children = Array.from(node.childNodes).map(inlineMarkdown).join('');

        if (tag === 'strong' || tag === 'b') return `**${children}**`;
        if (tag === 'em' || tag === 'i') return `*${children}*`;
        if (tag === 'del' || tag === 's') return `~~${children}~~`;
        if (tag === 'code') return `\\`${node.textContent || ''}\\``;
        if (tag === 'a') {
          const href = node.getAttribute('href') || '';
          return `[${children}](${href})`;
        }
        if (tag === 'img') {
          const src = node.getAttribute('src') || '';
          const alt = node.getAttribute('alt') || '';
          return `![${escapeText(alt)}](${src})`;
        }
        if (tag === 'br') return '  \\n';

        return children;
      }

      function blockMarkdown(node) {
        if (node.nodeType === Node.TEXT_NODE) {
          const text = (node.textContent || '').trim();
          return text ? `${escapeText(text)}\\n\\n` : '';
        }

        if (node.nodeType !== Node.ELEMENT_NODE) {
          return '';
        }

        const tag = node.tagName.toLowerCase();

        if (tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6') {
          const level = Number(tag[1]);
          const content = Array.from(node.childNodes).map(inlineMarkdown).join('').trim();
          return `${'#'.repeat(level)} ${content}\\n\\n`;
        }

        if (tag === 'p') {
          const content = Array.from(node.childNodes).map(inlineMarkdown).join('').trim();
          return content ? `${content}\\n\\n` : '';
        }

        if (tag === 'blockquote') {
          const inner = Array.from(node.childNodes).map(blockMarkdown).join('').trim();
          const prefixed = inner.split('\\n').map(line => line ? `> ${line}` : '>').join('\\n');
          return `${prefixed}\\n\\n`;
        }

        if (tag === 'pre') {
          const code = node.querySelector('code');
          let language = '';
          if (code && code.className.startsWith('language-')) {
            language = code.className.replace('language-', '');
          }
          const body = (code ? code.textContent : node.textContent) || '';
          return `\\`\\`\\`${language}\\n${body.replace(/\\n+$/, '')}\\n\\`\\`\\`\\n\\n`;
        }

        if (tag === 'ul' || tag === 'ol') {
          const listItems = Array.from(node.children).filter(child => child.tagName && child.tagName.toLowerCase() === 'li');
          const rendered = listItems.map((item, index) => {
            let prefix = tag === 'ol' ? `${index + 1}. ` : '- ';

            const checkbox = item.querySelector(':scope > input[type="checkbox"]');
            if (checkbox) {
              prefix = `- [${checkbox.checked ? 'x' : ' '}] `;
            }

            const childContent = Array.from(item.childNodes)
              .filter(child => !(child.tagName && child.tagName.toLowerCase() === 'input'))
              .map(child => {
                if (child.nodeType === Node.ELEMENT_NODE) {
                  const childTag = child.tagName.toLowerCase();
                  if (childTag === 'ul' || childTag === 'ol') {
                    const nested = blockMarkdown(child).trimEnd().split('\\n').map(line => line ? `  ${line}` : '').join('\\n');
                    return `\\n${nested}`;
                  }
                }
                return inlineMarkdown(child);
              })
              .join('')
              .trim();

            return `${prefix}${childContent}`;
          }).join('\\n');

          return `${rendered}\\n\\n`;
        }

        if (tag === 'hr') {
          return `---\\n\\n`;
        }

        if (tag === 'table') {
          const rows = Array.from(node.querySelectorAll('tr')).map(tr => {
            const cells = Array.from(tr.children).map(cell => (cell.textContent || '').trim().replace(/\\|/g, '\\\\|'));
            return `| ${cells.join(' | ')} |`;
          });

          if (rows.length > 0) {
            const headerCells = Array.from(node.querySelectorAll('tr:first-child th, tr:first-child td')).length;
            if (headerCells > 0) {
              const separator = `| ${Array.from({ length: headerCells }).map(() => '---').join(' | ')} |`;
              rows.splice(1, 0, separator);
            }
          }

          return rows.length ? `${rows.join('\\n')}\\n\\n` : '';
        }

        return Array.from(node.childNodes).map(blockMarkdown).join('');
      }

      function postMarkdown(event) {
        if (suppressNative) return;
        if (event && event.isComposing) return;

        const markdown = blockMarkdown(editor).replace(/\\s+$/, '') + '\\n';
        postDebug({
          event: 'postMarkdown',
          trusted: event ? !!event.isTrusted : false,
          markdownLen: markdown.length
        });
        window.webkit.messageHandlers.markdownChanged.postMessage({
          markdown,
          reason: 'input',
          trusted: event ? !!event.isTrusted : false
        });
      }

      editor.addEventListener('input', (event) => postMarkdown(event));

      window.getMarkdown = () => blockMarkdown(editor).replace(/\\s+$/, '') + '\\n';

      window.performEditorUndo = () => {
        editor.focus();
        document.execCommand('undo');
      };

      window.performEditorRedo = () => {
        editor.focus();
        document.execCommand('redo');
      };

      window.setRenderedHTML = (html) => {
        const safeHTML = typeof html === 'string' ? html : '';
        postDebug({
          event: 'setRenderedHTML.begin',
          htmlLen: safeHTML.length
        });
        suppressNative = true;
        try {
          editor.innerHTML = safeHTML;
          highlightCodeBlocks();
        } catch (error) {
          postDebug({
            event: 'setRenderedHTML.error',
            message: String(error)
          });
          editor.innerHTML = safeHTML;
        }
        requestAnimationFrame(() => {
          requestAnimationFrame(() => {
            suppressNative = false;
            postDebug({
              event: 'setRenderedHTML.end',
              textLen: (editor.textContent || '').length
            });
          });
        });
      };
    })();
  </script>
</body>
</html>
"""
}
