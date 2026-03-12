//
//  SearchCoordinator.swift
//  Markdown
//
//  Created by Lucas on 05/03/26.
//

import AppKit

@MainActor
final class SearchCoordinator {
    private let searchController: SearchToolbarController
    private(set) var activeQuery = ""

    var onSearchRequested: ((String, Bool) -> Void)?
    var onSearchCleared: (() -> Void)?
    var onDoneRequested: (() -> Void)?

    init(searchController: SearchToolbarController) {
        self.searchController = searchController
        configureCallbacks()
    }

    // MARK: - Public API

    func focusSearch() {
        searchController.focus(initialQuery: activeQuery)
    }
}

// MARK: - Private

private extension SearchCoordinator {
    func configureCallbacks() {
        searchController.onQueryChanged = { [weak self] query in
            self?.handleQueryChanged(query)
        }

        searchController.onSearchRequested = { [weak self] backwards in
            self?.handleSearchRequest(backwards: backwards)
        }

        searchController.onDoneRequested = { [weak self] in
            self?.onDoneRequested?()
        }
    }

    func handleQueryChanged(_ query: String) {
        activeQuery = query

        guard !query.isEmpty else {
            onSearchCleared?()
            return
        }

        onSearchRequested?(query, false)
    }

    func handleSearchRequest(backwards: Bool) {
        let query = searchController.query
        activeQuery = query

        guard !query.isEmpty else {
            return
        }

        onSearchRequested?(query, backwards)
    }
}
