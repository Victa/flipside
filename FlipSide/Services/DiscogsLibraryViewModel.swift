import Foundation
import SwiftData

@MainActor
final class DiscogsLibraryViewModel: ObservableObject {
    static let shared = DiscogsLibraryViewModel()

    struct ListState {
        var isRefreshing: Bool = false
        var errorMessage: String?
        var lastRefreshDate: Date?
    }

    struct RefreshResult {
        let successMessage: String
        let failureMessage: String?
    }

    @Published private(set) var collectionState = ListState()
    @Published private(set) var wantlistState = ListState()

    let staleInterval: TimeInterval = 15 * 60

    private let libraryService = DiscogsLibraryService.shared
    private let cache = SwiftDataLibraryCache.shared

    private init() {}

    func state(for listType: LibraryListType) -> ListState {
        switch listType {
        case .collection:
            return collectionState
        case .wantlist:
            return wantlistState
        }
    }

    func prepareState(listType: LibraryListType, modelContext: ModelContext) {
        do {
            let lastDate = try cache.lastRefreshDate(listType: listType, in: modelContext)
            updateState(listType: listType) { state in
                state.lastRefreshDate = lastDate
            }
        } catch {
            updateState(listType: listType) { state in
                state.errorMessage = error.localizedDescription
            }
        }
    }

    func refreshIfStale(listType: LibraryListType, modelContext: ModelContext) async {
        guard NetworkMonitor.shared.isConnected else {
            return
        }
        guard shouldRefresh(listType: listType, modelContext: modelContext) else {
            return
        }
        _ = await refresh(listType: listType, modelContext: modelContext)
    }

    func refresh(listType: LibraryListType, modelContext: ModelContext) async -> Result<Void, Error> {
        let username = KeychainService.shared.discogsUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !username.isEmpty else {
            let error = DiscogsLibraryService.LibraryServiceError.missingUsername
            updateState(listType: listType) { state in
                state.errorMessage = error.localizedDescription
                state.isRefreshing = false
            }
            return .failure(error)
        }

        updateState(listType: listType) { state in
            state.isRefreshing = true
            state.errorMessage = nil
        }

        do {
            let remoteItems: [LibraryRemoteItem]
            switch listType {
            case .collection:
                remoteItems = try await libraryService.fetchCollection(username: username)
            case .wantlist:
                remoteItems = try await libraryService.fetchWantlist(username: username)
            }

            let now = Date()
            try cache.replaceEntries(remoteItems, listType: listType, updatedAt: now, in: modelContext)

            updateState(listType: listType) { state in
                state.isRefreshing = false
                state.errorMessage = nil
                state.lastRefreshDate = now
            }

            return .success(())
        } catch {
            updateState(listType: listType) { state in
                state.isRefreshing = false
                state.errorMessage = error.localizedDescription
            }
            return .failure(error)
        }
    }

    func refreshAll(modelContext: ModelContext) async -> RefreshResult {
        async let collectionResult = refresh(listType: .collection, modelContext: modelContext)
        async let wantlistResult = refresh(listType: .wantlist, modelContext: modelContext)

        let collection = await collectionResult
        let wantlist = await wantlistResult
        let results = [collection, wantlist]
        let failures = results.compactMap { result -> String? in
            if case let .failure(error) = result {
                return error.localizedDescription
            }
            return nil
        }

        if failures.isEmpty {
            return RefreshResult(successMessage: "Collection and wantlist refreshed.", failureMessage: nil)
        }

        return RefreshResult(
            successMessage: "",
            failureMessage: failures.joined(separator: "\n")
        )
    }

    private func shouldRefresh(listType: LibraryListType, modelContext: ModelContext) -> Bool {
        if state(for: listType).isRefreshing {
            return false
        }

        do {
            let entries = try cache.loadEntries(listType: listType, in: modelContext)
            let lastRefresh = try cache.lastRefreshDate(listType: listType, in: modelContext)

            guard !entries.isEmpty else {
                return true
            }

            guard let lastRefresh else {
                return true
            }

            return Date().timeIntervalSince(lastRefresh) > staleInterval
        } catch {
            return true
        }
    }

    private func updateState(listType: LibraryListType, mutate: (inout ListState) -> Void) {
        switch listType {
        case .collection:
            var state = collectionState
            mutate(&state)
            collectionState = state
        case .wantlist:
            var state = wantlistState
            mutate(&state)
            wantlistState = state
        }
    }
}
