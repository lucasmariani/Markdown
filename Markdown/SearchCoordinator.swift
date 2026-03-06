//
//  SearchCoordinator.swift
//  Markdown
//
//  Created by Codex on 05/03/26.
//

import AppKit

@MainActor
final class SearchCoordinator {
    private let searchBarView: SearchBarView
    private(set) var activeQuery = ""

    var onSearchRequested: ((String, Bool) -> Void)?
    var onSearchCleared: (() -> Void)?
    var onDoneRequested: (() -> Void)?

    init(searchBarView: SearchBarView) {
        self.searchBarView = searchBarView
        configureCallbacks()
    }

    func focusSearch() {
        searchBarView.focus(initialQuery: activeQuery)
    }

    private func configureCallbacks() {
        searchBarView.onQueryChanged = { [weak self] query in
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

        searchBarView.onSearchRequested = { [weak self] backwards in
            guard let self else {
                return
            }

            let query = self.searchBarView.query
            self.activeQuery = query
            guard !query.isEmpty else {
                return
            }

            self.onSearchRequested?(query, backwards)
        }

        searchBarView.onDoneRequested = { [weak self] in
            self?.onDoneRequested?()
        }
    }
}
