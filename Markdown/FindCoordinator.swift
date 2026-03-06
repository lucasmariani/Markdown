//
//  FindCoordinator.swift
//  Markdown
//
//  Created by Codex on 05/03/26.
//

import AppKit

@MainActor
final class FindCoordinator {
    private let findBarView: SearchBarView
    private(set) var activeQuery = ""

    var onSearchRequested: ((String, Bool) -> Void)?
    var onSearchCleared: (() -> Void)?
    var onDoneRequested: (() -> Void)?

    init(findBarView: SearchBarView) {
        self.findBarView = findBarView
        configureCallbacks()
    }

    func focusSearch() {
        findBarView.focus(initialQuery: activeQuery)
    }

    private func configureCallbacks() {
        findBarView.onQueryChanged = { [weak self] query in
            guard let self else {
                return
            }

            self.activeQuery = query
            guard !query.isEmpty else {
                self.onSearchCleared?()
                return
            }

            self.onSearchRequested?(query, false)
        }

        findBarView.onFindRequested = { [weak self] backwards in
            guard let self else {
                return
            }

            let query = self.findBarView.query
            self.activeQuery = query
            guard !query.isEmpty else {
                return
            }

            self.onSearchRequested?(query, backwards)
        }

        findBarView.onDoneRequested = { [weak self] in
            self?.onDoneRequested?()
        }
    }
}
