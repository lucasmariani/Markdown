//
//  RenderedEditorShellHTML.swift
//  Markdown
//
//  Created by Lucas on 4/3/26.
//

import Foundation

enum RenderedEditorShellHTML {

    static func standard(documentBaseURL: URL?, localFileResourceScheme: String) -> String {
        let baseElement = documentBaseURL.map {
            "<base href=\"\(htmlEscapedAttribute($0.absoluteString))\">"
        } ?? ""
        let localFileRootLiteral = javaScriptStringLiteral(for: documentBaseURL?.absoluteString ?? "")
        let localFileResourceSchemeLiteral = javaScriptStringLiteral(for: localFileResourceScheme)
        let prettyLightsCSS = inlineCSSResource(named: "RendererPrettyLights")
        let highlighterJavaScript = inlineJavaScriptResource(named: "RendererHighlighter")

        return """
    <!doctype html>
    <html>
    <head>
      <meta charset=\"utf-8\">
      <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
      \(baseElement)
      <style>
        \(prettyLightsCSS)
      </style>
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
      caret-color: var(--text);
      outline: none;
    }

    #editor:focus {
      outline: none;
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
      <article id=\"editor\" contenteditable=\"true\" spellcheck=\"true\" role=\"textbox\" aria-multiline=\"true\"></article>
      <script>
        \(highlighterJavaScript)
      </script>

      <script>
        (() => {
          const editor = document.getElementById('editor');
          const localFileRoot = \(localFileRootLiteral);
          const localFileResourceScheme = \(localFileResourceSchemeLiteral);
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
          const allowedLinkSchemes = new Set(['file:', 'http:', 'https:', 'mailto:']);
          const allowedImageSchemes = new Set(['data:', 'http:', 'https:']);
          const newline = String.fromCharCode(10);
          const carriageReturn = String.fromCharCode(13);
          const tab = String.fromCharCode(9);
          const nonBreakingSpace = String.fromCharCode(160);
          const blockTags = new Set([
            'blockquote', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
            'hr', 'ol', 'p', 'pre', 'table', 'ul'
          ]);
          let isApplyingRemoteDocument = false;
          let pendingMarkdownChangeTimer = null;
          let savedSelectionRange = null;

          function isAllowedLocalFileURL(url) {
            if (!localFileRoot || url.protocol.toLowerCase() !== 'file:') {
              return false;
            }

            try {
              const root = new URL(localFileRoot);
              const rootPath = decodeURIComponent(root.pathname).replace(/\\/$/, '') + '/';
              const urlPath = decodeURIComponent(url.pathname);
              return root.protocol.toLowerCase() === 'file:' && urlPath.startsWith(rootPath);
            } catch (error) {
              console.error('isAllowedLocalFileURL failed', error);
              return false;
            }
          }

          function localResourceURL(fileURL) {
            return `${localFileResourceScheme}://asset?url=${encodeURIComponent(fileURL.href)}`;
          }

          function sanitizeLinkValue(value, allowedSchemes, options = {}) {
            const trimmed = (value || '').trim();
            if (!trimmed) {
              return null;
            }

            if (trimmed.startsWith('#')) {
              return trimmed;
            }

            try {
              const resolved = new URL(trimmed, document.baseURI);
              const protocol = resolved.protocol.toLowerCase();
              if (protocol === 'file:') {
                if (!isAllowedLocalFileURL(resolved)) {
                  return null;
                }

                return options.rewriteLocalFile ? localResourceURL(resolved) : resolved.href;
              }

              if (protocol !== 'file:' && allowedSchemes.has(protocol)) {
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
            const sanitizedSrc = sanitizeLinkValue(attribute.value, allowedImageSchemes, { rewriteLocalFile: true });
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

      function normalizeInlineText(value) {
        return (value || '')
          .split(nonBreakingSpace).join(' ')
          .split(carriageReturn).join(' ')
          .split(newline).join(' ')
          .split(tab).join(' ')
          .replace(/  +/g, ' ');
      }

      function block(markdown) {
        const trimmed = (markdown || '').trim();
        return trimmed ? trimmed + newline + newline : '';
      }

      function serializeInlineChildren(element) {
        return Array.from(element.childNodes)
          .map((child) => serializeInlineNode(child))
          .join('')
          .replace(/  +/g, ' ')
          .trim();
      }

      function serializeInlineNode(node) {
        if (node.nodeType === Node.TEXT_NODE) {
          return normalizeInlineText(node.textContent || '');
        }

        if (node.nodeType !== Node.ELEMENT_NODE) {
          return '';
        }

        const element = node;
        const tag = element.tagName.toLowerCase();

        if (tag === 'br') {
          return newline;
        }

        if (tag === 'img') {
          const alt = element.getAttribute('alt') || '';
          const src = element.getAttribute('src') || '';
          return src ? `![${alt}](${src})` : '';
        }

        if (tag === 'code' && element.closest('pre')) {
          return element.textContent || '';
        }

        const content = serializeInlineChildren(element);
        if (!content && tag !== 'a') {
          return '';
        }

        switch (tag) {
        case 'strong':
        case 'b':
          return `**${content}**`;
        case 'em':
        case 'i':
          return `*${content}*`;
        case 'code':
          return '`' + (element.textContent || '').trim() + '`';
        case 'del':
        case 's':
        case 'strike':
          return `~~${content}~~`;
        case 'a': {
          const href = element.getAttribute('href') || '';
          return href ? `[${content || href}](${href})` : content;
        }
        default:
          return content;
        }
      }

      function hasBlockChildren(element) {
        return Array.from(element.children).some((child) => (
          child instanceof HTMLElement &&
          blockTags.has(child.tagName.toLowerCase())
        ));
      }

      function isListElement(element) {
        if (!(element instanceof HTMLElement)) {
          return false;
        }

        const tag = element.tagName.toLowerCase();
        return tag === 'ul' || tag === 'ol';
      }

      function isListItemElement(element) {
        if (!(element instanceof HTMLElement)) {
          return false;
        }

        if (element.tagName.toLowerCase() === 'li') {
          return true;
        }

        return window.getComputedStyle(element).display === 'list-item';
      }

      function closestElement(startNode, predicate) {
        let element = startNode instanceof HTMLElement ? startNode : startNode?.parentElement;
        while (element && element !== editor) {
          if (predicate(element)) {
            return element;
          }

          element = element.parentElement;
        }

        return null;
      }

      function serializeChildren(element) {
        return Array.from(element.childNodes)
          .map((child) => serializeNode(child))
          .join('');
      }

      function serializeList(list, ordered, depth = 0) {
        const indent = '  '.repeat(depth);
        const items = Array.from(list.children)
          .filter((child) => isListItemElement(child))
          .map((item, index) => {
            const marker = ordered ? `${index + 1}. ` : '- ';
            const firstElement = item.firstElementChild;
            const hasTaskCheckbox = firstElement &&
              firstElement.tagName.toLowerCase() === 'input' &&
              firstElement.getAttribute('type') === 'checkbox';
            const taskPrefix = hasTaskCheckbox ? (firstElement.checked ? '[x] ' : '[ ] ') : '';
            const nestedLists = [];
            const inlineParts = [];

            Array.from(item.childNodes).forEach((child) => {
              if (child === firstElement && hasTaskCheckbox) {
                return;
              }

              if (child instanceof HTMLElement) {
                const tag = child.tagName.toLowerCase();
                if (tag === 'ul' || tag === 'ol') {
                  nestedLists.push(serializeList(child, tag === 'ol', depth + 1).trimEnd());
                  return;
                }
              }

              inlineParts.push(serializeInlineNode(child));
            });

            const itemText = inlineParts.join('').replace(/  +/g, ' ').trim();
            const nestedText = nestedLists.filter(Boolean).join(newline);
            const firstLine = `${indent}${marker}${taskPrefix}${itemText}`;
            return nestedText ? `${firstLine}${newline}${nestedText}` : firstLine;
          });

        return items.length > 0 ? items.join(newline) + newline + newline : '';
      }

      function serializeTable(table) {
        const rows = Array.from(table.querySelectorAll('tr')).map((row) => (
          Array.from(row.children).map((cell) => serializeInlineChildren(cell).trim())
        ));

        if (rows.length === 0) {
          return '';
        }

        const formattedRows = rows.map((cells) => `| ${cells.join(' | ')} |`);
        if (rows.length === 1) {
          return formattedRows[0];
        }

        const separator = `| ${rows[0].map(() => '---').join(' | ')} |`;
        return [formattedRows[0], separator, ...formattedRows.slice(1)].join(newline);
      }

      function serializeNode(node) {
        if (node.nodeType === Node.TEXT_NODE) {
          return block(normalizeInlineText(node.textContent || ''));
        }

        if (node.nodeType !== Node.ELEMENT_NODE) {
          return '';
        }

        const element = node;
        const tag = element.tagName.toLowerCase();

        if (/^h[1-6]$/.test(tag)) {
          const level = Number(tag.slice(1));
          return block(`${'#'.repeat(level)} ${serializeInlineChildren(element)}`);
        }

        switch (tag) {
        case 'p':
          return block(serializeInlineChildren(element));
        case 'blockquote': {
          const quoted = serializeChildren(element)
            .trim()
            .split(newline)
            .map((line) => `> ${line}`)
            .join(newline);
          return block(quoted);
        }
        case 'ul':
          return serializeList(element, false);
        case 'ol':
          return serializeList(element, true);
        case 'li':
          return block(`- ${serializeInlineChildren(element)}`);
        case 'pre': {
          const code = element.querySelector('code');
          const className = code?.className || '';
          const language = className
            .split(' ')
            .find((name) => name.startsWith('language-'))
            ?.slice('language-'.length) || '';
          return '```' + language + newline + (code?.textContent || element.textContent || '') + newline + '```' + newline + newline;
        }
        case 'hr':
          return '---' + newline + newline;
        case 'table':
          return block(serializeTable(element));
        case 'br':
          return newline;
        default:
          if (isListItemElement(element)) {
            return block(`- ${serializeInlineChildren(element)}`);
          }

          if (hasBlockChildren(element)) {
            return serializeChildren(element);
          }

          return block(serializeInlineChildren(element));
        }
      }

      function serializeEditorToMarkdown() {
        return trimTrailingBlankLines(serializeChildren(editor));
      }

      function trimTrailingBlankLines(markdown) {
        const lines = markdown.split(newline);
        while (lines.length > 0 && lines[lines.length - 1] === '') {
          lines.pop();
        }

        return lines.join(newline);
      }

      function postEditorMessage(payload) {
        const handler = window.webkit?.messageHandlers?.renderedEditor;
        if (handler) {
          handler.postMessage(payload);
        }
      }

      function emitMarkdownDidChange() {
        if (isApplyingRemoteDocument) {
          return;
        }

        postEditorMessage({
          type: 'markdownChanged',
          markdown: serializeEditorToMarkdown(),
        });
      }

      function scheduleMarkdownDidChange() {
        if (pendingMarkdownChangeTimer) {
          window.clearTimeout(pendingMarkdownChangeTimer);
          pendingMarkdownChangeTimer = null;
        }

        emitMarkdownDidChange();
      }

      function selectInsertedElement(element) {
        const selection = window.getSelection();
        if (!selection) {
          return;
        }

        const range = document.createRange();
        range.selectNodeContents(element);
        selection.removeAllRanges();
        selection.addRange(range);
      }

      function placeCaretAtEnd(element) {
        const selection = window.getSelection();
        if (!selection) {
          return;
        }

        const range = document.createRange();
        range.selectNodeContents(element);
        range.collapse(false);
        selection.removeAllRanges();
        selection.addRange(range);
        savedSelectionRange = range.cloneRange();
      }

      function replaceSelectionWithElement(element) {
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0) {
          editor.appendChild(element);
          selectInsertedElement(element);
          scheduleMarkdownDidChange();
          return;
        }

        const range = selection.getRangeAt(0);
        range.deleteContents();
        range.insertNode(element);
        selectInsertedElement(element);
        scheduleMarkdownDidChange();
      }

      function rememberSelection() {
        const selection = window.getSelection();
        if (
          !selection ||
          selection.rangeCount === 0 ||
          !editor.contains(selection.anchorNode) ||
          !editor.contains(selection.focusNode)
        ) {
          return;
        }

        savedSelectionRange = selection.getRangeAt(0).cloneRange();
      }

      function restoreSelection() {
        if (!savedSelectionRange) {
          return;
        }

        const selection = window.getSelection();
        if (!selection) {
          return;
        }

        selection.removeAllRanges();
        selection.addRange(savedSelectionRange);
      }

      function wrapSelectionInInlineElement(tagName, placeholder) {
        const selection = window.getSelection();
        const wrapper = document.createElement(tagName);

        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
          wrapper.textContent = placeholder;
          replaceSelectionWithElement(wrapper);
          return;
        }

        const range = selection.getRangeAt(0);
        wrapper.appendChild(range.extractContents());
        range.insertNode(wrapper);
        selectInsertedElement(wrapper);
        scheduleMarkdownDidChange();
      }

      function insertCodeBlock() {
        const selection = window.getSelection();
        const pre = document.createElement('pre');
        const code = document.createElement('code');
        code.textContent = selection && !selection.isCollapsed ? selection.toString() : 'code';
        pre.appendChild(code);
        replaceSelectionWithElement(pre);
      }

      function currentEditorRange() {
        const selection = window.getSelection();
        if (
          selection &&
          selection.rangeCount > 0 &&
          editor.contains(selection.anchorNode) &&
          editor.contains(selection.focusNode)
        ) {
          return selection.getRangeAt(0);
        }

        if (savedSelectionRange && editor.contains(savedSelectionRange.commonAncestorContainer)) {
          return savedSelectionRange;
        }

        const range = document.createRange();
        range.selectNodeContents(editor);
        range.collapse(false);
        return range;
      }

      function currentEditableBlock(range) {
        return closestElement(range.startContainer, (element) => (
          isListItemElement(element) || blockTags.has(element.tagName.toLowerCase())
        ));
      }

      function nearestParentList(element) {
        let current = element?.parentElement;
        while (current && current !== editor) {
          if (isListElement(current)) {
            return current;
          }

          current = current.parentElement;
        }

        return null;
      }

      function appendListItemContents(item, destination) {
        Array.from(item.childNodes).forEach((child) => {
          if (child instanceof HTMLElement && isListElement(child)) {
            return;
          }

          destination.appendChild(child);
        });
      }

      function unwrapList(list) {
        const fragment = document.createDocumentFragment();
        const paragraphs = [];

        Array.from(list.children)
          .filter((child) => isListItemElement(child))
          .forEach((item) => {
            const paragraph = document.createElement('p');
            appendListItemContents(item, paragraph);
            if (!paragraph.textContent.trim() && paragraph.childNodes.length === 0) {
              paragraph.appendChild(document.createElement('br'));
            }

            paragraphs.push(paragraph);
            fragment.appendChild(paragraph);
          });

        list.replaceWith(fragment);
        placeCaretAtEnd(paragraphs[0] || editor);
      }

      function ensureListItemContent(item) {
        if (!item.textContent.trim() && item.childNodes.length === 0) {
          item.appendChild(document.createElement('br'));
        }
      }

      function replaceBlockWithList(blockElement, ordered) {
        const list = document.createElement(ordered ? 'ol' : 'ul');
        const item = document.createElement('li');

        while (blockElement.firstChild) {
          item.appendChild(blockElement.firstChild);
        }

        ensureListItemContent(item);
        list.appendChild(item);
        blockElement.replaceWith(list);
        placeCaretAtEnd(item);
      }

      function insertListAtRange(range, ordered) {
        const list = document.createElement(ordered ? 'ol' : 'ul');
        const item = document.createElement('li');

        if (!range.collapsed) {
          item.appendChild(range.extractContents());
        }

        ensureListItemContent(item);
        list.appendChild(item);
        range.insertNode(list);
        placeCaretAtEnd(item);
      }

      function toggleCurrentBlockList(ordered) {
        const range = currentEditorRange();
        const currentListItem = closestElement(range.startContainer, isListItemElement);
        const parentList = nearestParentList(currentListItem);
        const targetTag = ordered ? 'ol' : 'ul';

        if (parentList) {
          if (parentList.tagName.toLowerCase() === targetTag) {
            unwrapList(parentList);
          } else {
            const replacement = document.createElement(targetTag);
            while (parentList.firstChild) {
              replacement.appendChild(parentList.firstChild);
            }

            parentList.replaceWith(replacement);
            placeCaretAtEnd(currentListItem);
          }

          scheduleMarkdownDidChange();
          return;
        }

        const blockElement = currentEditableBlock(range);
        if (blockElement) {
          replaceBlockWithList(blockElement, ordered);
        } else {
          insertListAtRange(range, ordered);
        }

        scheduleMarkdownDidChange();
      }

      function formatCurrentBlock(tagName) {
        document.execCommand('formatBlock', false, tagName);
        scheduleMarkdownDidChange();
      }

      window.applyMarkdownFormatting = (command) => {
        editor.focus();
        restoreSelection();

        switch (command) {
        case 'paragraph':
          formatCurrentBlock('p');
          break;
        case 'heading1':
          formatCurrentBlock('h1');
          break;
        case 'heading2':
          formatCurrentBlock('h2');
          break;
        case 'heading3':
          formatCurrentBlock('h3');
          break;
        case 'heading4':
          formatCurrentBlock('h4');
          break;
        case 'heading5':
          formatCurrentBlock('h5');
          break;
        case 'heading6':
          formatCurrentBlock('h6');
          break;
        case 'quote':
          formatCurrentBlock('blockquote');
          break;
        case 'codeBlock':
          insertCodeBlock();
          break;
        case 'unorderedList':
          toggleCurrentBlockList(false);
          break;
        case 'orderedList':
          toggleCurrentBlockList(true);
          break;
        case 'bold':
          document.execCommand('bold');
          scheduleMarkdownDidChange();
          break;
        case 'italic':
          document.execCommand('italic');
          scheduleMarkdownDidChange();
          break;
        case 'inlineCode':
          wrapSelectionInInlineElement('code', 'code');
          break;
        default:
          break;
        }
      };

      document.addEventListener('selectionchange', rememberSelection);
      editor.addEventListener('keyup', rememberSelection);
      editor.addEventListener('mouseup', rememberSelection);
      editor.addEventListener('input', scheduleMarkdownDidChange);
      editor.addEventListener('blur', emitMarkdownDidChange);
      editor.addEventListener('paste', (event) => {
        event.preventDefault();
        const text = event.clipboardData?.getData('text/plain') || '';
        document.execCommand('insertText', false, text);
        scheduleMarkdownDidChange();
      });
      editor.addEventListener('click', (event) => {
        const link = event.target instanceof Element ? event.target.closest('a') : null;
        if (link && !event.metaKey) {
          event.preventDefault();
        }
      });
      editor.addEventListener('keydown', (event) => {
        if (!(event.metaKey || event.ctrlKey)) {
          return;
        }

        const key = event.key.toLowerCase();
        if (key === 'b') {
          event.preventDefault();
          window.applyMarkdownFormatting('bold');
        } else if (key === 'i') {
          event.preventDefault();
          window.applyMarkdownFormatting('italic');
        }
      });

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
        isApplyingRemoteDocument = true;
        editor.replaceChildren();
        editor.appendChild(sanitizedFragment(safeHTML));
        isApplyingRemoteDocument = false;
        highlightCodeBlocks();
      };
    })();
    </script>
    </body>
    </html>
    """
    }

    private static func inlineCSSResource(named name: String) -> String {
        resourceText(named: name, extension: "css")
            .replacingOccurrences(of: "</style", with: "<\\/style", options: [.caseInsensitive])
    }

    private static func inlineJavaScriptResource(named name: String) -> String {
        resourceText(named: name, extension: "js")
            .replacingOccurrences(of: "</script", with: "<\\/script", options: [.caseInsensitive])
    }

    private static func resourceText(named name: String, extension fileExtension: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }

        return text
    }

    private static func javaScriptStringLiteral(for string: String) -> String {
        guard let data = try? JSONEncoder().encode(string),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }

        return json
    }

    private static func htmlEscapedAttribute(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
