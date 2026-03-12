//
//  SearchToolbarController.swift
//  Markdown
//
//  Created by Lucas on 04/03/26.
//

import AppKit

@MainActor
final class SearchToolbarController: NSObject {
    private enum Metrics {
        static let preferredWidth: CGFloat = 110
        static let fallbackHeight: CGFloat = 28
    }

    // Keeps the match count inside a standard NSSearchField so the toolbar item
    // still uses native AppKit expansion and compression behavior.
    private final class CountAwareSearchField: NSSearchField {
        private let countLabel = NSTextField(labelWithString: "")
        private var reservedTrailingWidth: CGFloat = 0

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            configureCountLabel()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var searchTextBounds: NSRect {
            adjustedSearchTextBounds(super.searchTextBounds)
        }

        func setMatchCount(_ count: Int?) {
            guard let count else {
                countLabel.stringValue = ""
                countLabel.isHidden = true
                reservedTrailingWidth = 0
                needsLayout = true
                needsDisplay = true
                return
            }

            countLabel.stringValue = count == 1 ? "1 match" : "\(count) matches"
            countLabel.isHidden = false
            reservedTrailingWidth = ceil(measuredLabelSize().width) + 10
            needsDisplay = true
            needsLayout = true
        }

        override func layout() {
            super.layout()

            guard !countLabel.isHidden else {
                return
            }

            let cancelRect = cancelButtonBounds
            let availableMaxX = max(cancelRect.minX - 6, 0)
            let labelSize = measuredLabelSize()
            let width = min(ceil(labelSize.width), max(availableMaxX - 8, 0))
            let x = max(availableMaxX - width, 8)
            let height = ceil(labelSize.height)
            let y = floor((bounds.height - height) * 0.5)
            countLabel.frame = NSRect(x: x, y: y, width: width, height: height)
        }

        private func configureCountLabel() {
            countLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            countLabel.textColor = .secondaryLabelColor
            countLabel.alignment = .right
            countLabel.lineBreakMode = .byTruncatingHead
            countLabel.maximumNumberOfLines = 1
            countLabel.translatesAutoresizingMaskIntoConstraints = true
            countLabel.isHidden = true
            addSubview(countLabel)
        }

        private func measuredLabelSize() -> NSSize {
            if let cell = countLabel.cell {
                return cell.cellSize(forBounds: NSRect(
                    x: 0,
                    y: 0,
                    width: CGFloat.greatestFiniteMagnitude,
                    height: bounds.height > 0 ? bounds.height : Metrics.fallbackHeight
                ))
            }

            return countLabel.fittingSize
        }

        private func adjustedSearchTextBounds(_ rect: NSRect) -> NSRect {
            guard reservedTrailingWidth > 0 else {
                return rect
            }

            var adjustedRect = rect
            adjustedRect.size.width = max(0, adjustedRect.width - reservedTrailingWidth)
            return adjustedRect
        }
    }

    var onQueryChanged: ((String) -> Void)?
    var onSearchRequested: ((Bool) -> Void)?
    var onDoneRequested: (() -> Void)?

    var toolbarItem: NSSearchToolbarItem {
        searchToolbarItem
    }

    var query: String {
        searchField.stringValue
    }

    var isExpanded: Bool {
        isSearchInteractionActive
    }

    private let searchField = CountAwareSearchField(frame: .zero)
    private let searchToolbarItem = NSSearchToolbarItem(itemIdentifier: NSToolbarItem.Identifier("com.rianami.markdown.toolbar.search"))
    private var isSearchInteractionActive = false

    override init() {
        super.init()
        configureSearchField()
        configureToolbarItem()
    }

    // MARK: - Public API

    func focus(initialQuery: String?) {
        if searchField.stringValue.isEmpty, let initialQuery, !initialQuery.isEmpty {
            searchField.stringValue = initialQuery
        }

        isSearchInteractionActive = true
        searchToolbarItem.beginSearchInteraction()

        Task { @MainActor [weak self] in
            self?.searchField.selectText(nil)
        }
    }

    func collapse() {
        guard isSearchInteractionActive else {
            return
        }

        isSearchInteractionActive = false
        searchToolbarItem.endSearchInteraction()
    }

    func setMatchCount(_ count: Int?) {
        searchField.setMatchCount(count)
    }
}

// MARK: - Setup

private extension SearchToolbarController {
    func configureToolbarItem() {
        searchToolbarItem.label = "Search"
        searchToolbarItem.paletteLabel = "Search"
        searchToolbarItem.toolTip = "Search"
        searchToolbarItem.preferredWidthForSearchField = Metrics.preferredWidth
        searchToolbarItem.resignsFirstResponderWithCancel = true
        searchToolbarItem.searchField = searchField
    }

    func configureSearchField() {
        searchField.placeholderString = "Search"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
    }
}

// MARK: - NSSearchFieldDelegate

extension SearchToolbarController: NSSearchFieldDelegate {
    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        onQueryChanged?(query)
    }

    func searchFieldDidStartSearching(_ sender: NSSearchField) {
        isSearchInteractionActive = true
    }

    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        collapseIfPossible()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        collapseIfPossible()
    }
}

// MARK: - Helpers

private extension SearchToolbarController {
    func collapseIfPossible() {
        guard query.isEmpty, isSearchInteractionActive else {
            return
        }

        // beginSearchInteraction() keeps the toolbar item expanded until the app
        // explicitly ends the interaction, so we collapse when editing ends and
        // the field is both blank and no longer first responder.
        let currentEditor = searchField.currentEditor()
        guard searchField.window?.firstResponder !== currentEditor else {
            return
        }

        collapse()
    }
}
