//
//  SearchBarView.swift
//  Markdown
//
//  Created by Codex on 04/03/26.
//

import AppKit

@MainActor
final class SearchBarView: NSVisualEffectView, NSSearchFieldDelegate {
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
            let fittingWidth = ceil(measuredLabelSize().width)
            reservedTrailingWidth = fittingWidth + 10
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
                    height: bounds.height > 0 ? bounds.height : 28
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

    var query: String {
        searchField.stringValue
    }

    private let searchField = CountAwareSearchField()
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let doneButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func focus(initialQuery: String?) {
        if searchField.stringValue.isEmpty, let initialQuery, !initialQuery.isEmpty {
            searchField.stringValue = initialQuery
        }
        searchField.selectText(nil)
    }

    func setMatchCount(_ count: Int?) {
        searchField.setMatchCount(count)
    }

    private func configureView() {
        material = .headerView
        blendingMode = .withinWindow
        state = .active
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Find"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.translatesAutoresizingMaskIntoConstraints = false

        previousButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous Match")
        previousButton.bezelStyle = .texturedRounded
        previousButton.isBordered = true
        previousButton.target = self
        previousButton.action = #selector(findPrevious(_:))
        previousButton.translatesAutoresizingMaskIntoConstraints = false

        nextButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next Match")
        nextButton.bezelStyle = .texturedRounded
        nextButton.isBordered = true
        nextButton.target = self
        nextButton.action = #selector(findNext(_:))
        nextButton.translatesAutoresizingMaskIntoConstraints = false

        doneButton.title = "Done"
        doneButton.bezelStyle = .texturedRounded
        doneButton.target = self
        doneButton.action = #selector(doneFinding(_:))
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(searchField)
        addSubview(previousButton)
        addSubview(nextButton)
        addSubview(doneButton)
        addSubview(separator)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 28),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),

            previousButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            previousButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 28),

            nextButton.widthAnchor.constraint(equalToConstant: 28),
            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 4),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            doneButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 10),
            doneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            doneButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        onQueryChanged?(query)
    }

    @objc private func findNext(_ sender: Any?) {
        onSearchRequested?(false)
    }

    @objc private func findPrevious(_ sender: Any?) {
        onSearchRequested?(true)
    }

    @objc private func doneFinding(_ sender: Any?) {
        onDoneRequested?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control == searchField else {
            return false
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
            commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            onSearchRequested?(backwards)
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onDoneRequested?()
            return true
        }

        return false
    }
}
