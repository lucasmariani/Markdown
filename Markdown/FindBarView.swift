//
//  FindBarView.swift
//  Markdown
//
//  Created by Codex on 04/03/26.
//

import AppKit

final class FindBarView: NSVisualEffectView, NSSearchFieldDelegate {
    var onQueryChanged: ((String) -> Void)?
    var onFindRequested: ((Bool) -> Void)?
    var onDoneRequested: (() -> Void)?

    var query: String {
        searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let searchField = NSSearchField()
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
        searchField.sendsWholeSearchString = true
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

            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 4),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 28),

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
        onFindRequested?(false)
    }

    @objc private func findPrevious(_ sender: Any?) {
        onFindRequested?(true)
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
            onFindRequested?(backwards)
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onDoneRequested?()
            return true
        }

        return false
    }
}
