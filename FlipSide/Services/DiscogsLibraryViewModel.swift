import Foundation
import SwiftData

@MainActor
final class DiscogsLibraryViewModel: ObservableObject {
    static let shared = DiscogsLibraryViewModel()

    struct ListState {
        var isRefreshing: Bool = false
        var errorMessage: String?
        var lastRefreshDate: Date?
        var itemsLoadedCount: Int = 0
        var estimatedTotalCount: Int?
        var pagesLoaded: Int = 0
        var totalPages: Int = 0
        var isInitialPageLoaded: Bool = false
        var isBackgroundRefreshing: Bool = false
        var syncSessionId: UUID?
    }

    struct RefreshResult {
        let successMessage: String
        let failureMessage: String?
    }

    @Published private(set) var collectionState = ListState()
    @Published private(set) var wantlistState = ListState()

    let staleInterval: TimeInterval = 15 * 60
    let incrementalLibrarySyncEnabled = true

    private let libraryService = DiscogsLibraryService.shared
    private let cache = SwiftDataLibraryCache.shared

    private var activeSyncSessionId: UUID?

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
            let loadedCount = try cache.loadEntries(listType: listType, in: modelContext).count
            updateState(listType: listType) { state in
                state.lastRefreshDate = lastDate
                if !state.isRefreshing && !state.isBackgroundRefreshing {
                    state.itemsLoadedCount = loadedCount
                }
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
        if incrementalLibrarySyncEnabled {
            let sessionId = UUID()
            activeSyncSessionId = sessionId
            return await refreshIncremental(
                listType: listType,
                modelContext: modelContext,
                sessionId: sessionId,
                onFirstPage: {}
            )
        }

        guard DiscogsAuthService.shared.isConnected else {
            let error = DiscogsLibraryService.LibraryServiceError.notConnected
            updateState(listType: listType) { state in
                state.errorMessage = error.localizedDescription
                state.isRefreshing = false
            }
            return .failure(error)
        }

        let username = DiscogsAuthService.shared.connectedUsername() ?? ""
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

    func refreshIncremental(
        listType: LibraryListType,
        modelContext: ModelContext,
        sessionId: UUID,
        onFirstPage: @escaping @MainActor () -> Void
    ) async -> Result<Void, Error> {
        guard DiscogsAuthService.shared.isConnected else {
            let error = DiscogsLibraryService.LibraryServiceError.notConnected
            updateState(listType: listType) { state in
                state.errorMessage = error.localizedDescription
                state.isRefreshing = false
                state.isBackgroundRefreshing = false
            }
            return .failure(error)
        }

        let username = DiscogsAuthService.shared.connectedUsername() ?? ""
        guard !username.isEmpty else {
            let error = DiscogsLibraryService.LibraryServiceError.missingUsername
            updateState(listType: listType) { state in
                state.errorMessage = error.localizedDescription
                state.isRefreshing = false
                state.isBackgroundRefreshing = false
            }
            return .failure(error)
        }

        cache.beginIncrementalSync(listType: listType, syncId: sessionId, in: modelContext)

        updateState(listType: listType) { state in
            state.isRefreshing = true
            state.isBackgroundRefreshing = true
            state.errorMessage = nil
            state.itemsLoadedCount = 0
            state.estimatedTotalCount = nil
            state.pagesLoaded = 0
            state.totalPages = 0
            state.isInitialPageLoaded = false
            state.syncSessionId = sessionId
        }

        var didReceiveFirstPage = false

        do {
            let summary = try await libraryService.syncListPaged(listType: listType, username: username) { items, chunk in
                guard self.isSessionActive(sessionId) else {
                    throw CancellationError()
                }

                let now = Date()
                try self.cache.upsertPage(
                    items: items,
                    listType: listType,
                    syncId: sessionId,
                    updatedAt: now,
                    in: modelContext
                )

                self.updateState(listType: listType) { state in
                    state.itemsLoadedCount += chunk.itemsReceivedThisPage
                    state.estimatedTotalCount = chunk.totalItemsExpected
                    state.pagesLoaded = chunk.page
                    state.totalPages = chunk.totalPages
                    state.isInitialPageLoaded = true
                    state.syncSessionId = sessionId
                }

                if !didReceiveFirstPage {
                    didReceiveFirstPage = true
                    onFirstPage()
                }
            }

            guard isSessionActive(sessionId) else {
                throw CancellationError()
            }

            let completedAt = Date()
            try cache.finalizeIncrementalSync(listType: listType, syncId: sessionId, updatedAt: completedAt, in: modelContext)

            updateState(listType: listType) { state in
                state.isRefreshing = false
                state.isBackgroundRefreshing = false
                state.errorMessage = nil
                state.lastRefreshDate = completedAt
                state.itemsLoadedCount = summary.itemsFetched
                state.estimatedTotalCount = summary.totalItemsExpected
                state.pagesLoaded = summary.pagesFetched
                state.totalPages = summary.totalPages
                state.isInitialPageLoaded = true
            }

            return .success(())
        } catch is CancellationError {
            cache.failIncrementalSync(listType: listType, syncId: sessionId, in: modelContext)
            return .failure(CancellationError())
        } catch {
            cache.failIncrementalSync(listType: listType, syncId: sessionId, in: modelContext)
            updateState(listType: listType) { state in
                state.isRefreshing = false
                state.isBackgroundRefreshing = false
                state.errorMessage = error.localizedDescription
            }
            return .failure(error)
        }
    }

    func refreshAllIncremental(
        modelContext: ModelContext,
        onInitialGateReady: @escaping @MainActor () -> Void
    ) async -> RefreshResult {
        let fullSyncInterval = PerformanceMetrics.begin(.incrementalSyncFull)
        let firstPageInterval = PerformanceMetrics.begin(.incrementalSyncFirstPage)
        let sessionId = UUID()
        activeSyncSessionId = sessionId

        let syncStart = Date()
        var firstCollectionPageDate: Date?
        var firstWantlistPageDate: Date?
        var initialGateSent = false

        func tryEmitInitialGate() {
            guard !initialGateSent,
                  firstCollectionPageDate != nil,
                  firstWantlistPageDate != nil
            else {
                return
            }

            initialGateSent = true
            onInitialGateReady()
            let onboardingDuration = Date().timeIntervalSince(syncStart)
            print("metric time_to_onboarding_complete=\(String(format: "%.2f", onboardingDuration))s")
            PerformanceMetrics.end(.incrementalSyncFirstPage, firstPageInterval)
            PerformanceMetrics.gauge("incremental_sync_first_page_seconds", value: onboardingDuration)
        }

        print("metric sync_started_at=\(syncStart.timeIntervalSince1970)")

        async let collectionResult = refreshIncremental(
            listType: .collection,
            modelContext: modelContext,
            sessionId: sessionId,
            onFirstPage: {
                if firstCollectionPageDate == nil {
                    firstCollectionPageDate = Date()
                    let value = firstCollectionPageDate?.timeIntervalSince(syncStart) ?? 0
                    print("metric time_to_first_collection_page=\(String(format: "%.2f", value))s")
                }
                tryEmitInitialGate()
            }
        )

        await Task.yield()

        async let wantlistResult = refreshIncremental(
            listType: .wantlist,
            modelContext: modelContext,
            sessionId: sessionId,
            onFirstPage: {
                if firstWantlistPageDate == nil {
                    firstWantlistPageDate = Date()
                    let value = firstWantlistPageDate?.timeIntervalSince(syncStart) ?? 0
                    print("metric time_to_first_wantlist_page=\(String(format: "%.2f", value))s")
                }
                tryEmitInitialGate()
            }
        )

        let collection = await collectionResult
        let wantlist = await wantlistResult

        if activeSyncSessionId == sessionId {
            activeSyncSessionId = nil
        }

        if !initialGateSent {
            tryEmitInitialGate()
            if !initialGateSent {
                PerformanceMetrics.end(.incrementalSyncFirstPage, firstPageInterval)
            }
        }

        let fullDuration = Date().timeIntervalSince(syncStart)
        print("metric time_to_full_sync_complete=\(String(format: "%.2f", fullDuration))s")
        PerformanceMetrics.end(.incrementalSyncFull, fullSyncInterval)
        PerformanceMetrics.gauge("incremental_sync_full_seconds", value: fullDuration)

        let results = [collection, wantlist]
        let failures = results.compactMap { result -> String? in
            if case let .failure(error) = result {
                if error is CancellationError {
                    return nil
                }
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

    func refreshAll(modelContext: ModelContext) async -> RefreshResult {
        if incrementalLibrarySyncEnabled {
            return await refreshAllIncremental(modelContext: modelContext, onInitialGateReady: {})
        }

        // Discogs library endpoints are strict on rate limits.
        // Refresh sequentially to avoid avoidable 429 responses.
        let collection = await refresh(listType: .collection, modelContext: modelContext)
        let wantlist = await refresh(listType: .wantlist, modelContext: modelContext)
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

    func resetLibraryState() {
        activeSyncSessionId = nil
        collectionState = ListState()
        wantlistState = ListState()
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

    private func isSessionActive(_ sessionId: UUID) -> Bool {
        activeSyncSessionId == sessionId
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
