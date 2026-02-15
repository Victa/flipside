import Foundation

actor DiscogsCacheStore {
    static let shared = DiscogsCacheStore()

    private struct SearchCacheEntry {
        let results: [DiscogsService.SearchResponse.SearchResult]
        let expiresAt: Date
    }

    private struct ReleaseCacheEntry {
        let release: DiscogsService.ReleaseResponse
        let expiresAt: Date
    }

    private struct PriceCacheEntry {
        let suggestions: [String: DiscogsMatch.ConditionPrice]
        let expiresAt: Date
    }

    private struct StatusCacheEntry {
        let status: CollectionStatus
        let expiresAt: Date
    }

    private var searchCache: [String: SearchCacheEntry] = [:]
    private var searchInFlight: [String: Task<[DiscogsService.SearchResponse.SearchResult], Error>] = [:]

    private var releaseCache: [Int: ReleaseCacheEntry] = [:]
    private var releaseInFlight: [Int: Task<DiscogsService.ReleaseResponse, Error>] = [:]

    private var priceCache: [Int: PriceCacheEntry] = [:]
    private var priceInFlight: [Int: Task<[String: DiscogsMatch.ConditionPrice], Error>] = [:]

    private var statusCache: [String: StatusCacheEntry] = [:]
    private var statusInFlight: [String: Task<CollectionStatus, Error>] = [:]

    func searchResults(
        query: String,
        ttl: TimeInterval,
        forceRefresh: Bool = false,
        fetcher: @escaping @Sendable () async throws -> [DiscogsService.SearchResponse.SearchResult]
    ) async throws -> [DiscogsService.SearchResponse.SearchResult] {
        let key = normalizeQuery(query)
        guard !key.isEmpty else {
            return try await fetcher()
        }

        if !forceRefresh, let cached = cachedSearchResults(query: query) {
            return cached
        }

        if let inFlight = searchInFlight[key] {
            return try await inFlight.value
        }

        let task = Task<[DiscogsService.SearchResponse.SearchResult], Error> {
            try await fetcher()
        }
        searchInFlight[key] = task

        do {
            let results = try await task.value
            searchCache[key] = SearchCacheEntry(
                results: results,
                expiresAt: Date().addingTimeInterval(ttl)
            )
            searchInFlight[key] = nil
            return results
        } catch {
            searchInFlight[key] = nil
            throw error
        }
    }

    func cachedSearchResults(query: String) -> [DiscogsService.SearchResponse.SearchResult]? {
        let key = normalizeQuery(query)
        guard !key.isEmpty else { return nil }
        guard let entry = searchCache[key] else { return nil }
        guard entry.expiresAt > Date() else {
            searchCache[key] = nil
            return nil
        }
        return entry.results
    }

    func releaseDetails(
        releaseId: Int,
        ttl: TimeInterval,
        forceRefresh: Bool = false,
        fetcher: @escaping @Sendable () async throws -> DiscogsService.ReleaseResponse
    ) async throws -> DiscogsService.ReleaseResponse {
        if !forceRefresh, let cached = cachedReleaseDetails(releaseId: releaseId) {
            return cached
        }

        if let inFlight = releaseInFlight[releaseId] {
            return try await inFlight.value
        }

        let task = Task<DiscogsService.ReleaseResponse, Error> {
            try await fetcher()
        }
        releaseInFlight[releaseId] = task

        do {
            let details = try await task.value
            releaseCache[releaseId] = ReleaseCacheEntry(
                release: details,
                expiresAt: Date().addingTimeInterval(ttl)
            )
            releaseInFlight[releaseId] = nil
            return details
        } catch {
            releaseInFlight[releaseId] = nil
            throw error
        }
    }

    func cachedReleaseDetails(releaseId: Int) -> DiscogsService.ReleaseResponse? {
        guard let entry = releaseCache[releaseId] else { return nil }
        guard entry.expiresAt > Date() else {
            releaseCache[releaseId] = nil
            return nil
        }
        return entry.release
    }

    func priceSuggestions(
        releaseId: Int,
        ttl: TimeInterval,
        forceRefresh: Bool = false,
        fetcher: @escaping @Sendable () async throws -> [String: DiscogsMatch.ConditionPrice]
    ) async throws -> [String: DiscogsMatch.ConditionPrice] {
        if !forceRefresh, let cached = cachedPriceSuggestions(releaseId: releaseId) {
            return cached
        }

        if let inFlight = priceInFlight[releaseId] {
            return try await inFlight.value
        }

        let task = Task<[String: DiscogsMatch.ConditionPrice], Error> {
            try await fetcher()
        }
        priceInFlight[releaseId] = task

        do {
            let suggestions = try await task.value
            priceCache[releaseId] = PriceCacheEntry(
                suggestions: suggestions,
                expiresAt: Date().addingTimeInterval(ttl)
            )
            priceInFlight[releaseId] = nil
            return suggestions
        } catch {
            priceInFlight[releaseId] = nil
            throw error
        }
    }

    func cachedPriceSuggestions(releaseId: Int) -> [String: DiscogsMatch.ConditionPrice]? {
        guard let entry = priceCache[releaseId] else { return nil }
        guard entry.expiresAt > Date() else {
            priceCache[releaseId] = nil
            return nil
        }
        return entry.suggestions
    }

    func status(
        username: String,
        releaseId: Int,
        ttl: TimeInterval,
        forceRefresh: Bool = false,
        fetcher: @escaping @Sendable () async throws -> CollectionStatus
    ) async throws -> CollectionStatus {
        let key = statusKey(username: username, releaseId: releaseId)

        if !forceRefresh, let cached = cachedStatus(username: username, releaseId: releaseId) {
            return cached
        }

        if let existing = statusInFlight[key] {
            return try await existing.value
        }

        let task = Task<CollectionStatus, Error> {
            let signpost = PerformanceMetrics.begin(.collectionStatusFetch)
            defer {
                PerformanceMetrics.end(.collectionStatusFetch, signpost)
            }
            PerformanceMetrics.incrementCounter("collection_status_requests")
            return try await fetcher()
        }
        statusInFlight[key] = task

        do {
            let status = try await task.value
            statusCache[key] = StatusCacheEntry(
                status: status,
                expiresAt: Date().addingTimeInterval(ttl)
            )
            statusInFlight[key] = nil
            return status
        } catch {
            statusInFlight[key] = nil
            throw error
        }
    }

    func cachedStatus(username: String, releaseId: Int) -> CollectionStatus? {
        let key = statusKey(username: username, releaseId: releaseId)
        guard let entry = statusCache[key] else { return nil }
        guard entry.expiresAt > Date() else {
            statusCache[key] = nil
            return nil
        }
        return entry.status
    }

    func updateCachedStatus(
        username: String,
        releaseId: Int,
        status: CollectionStatus,
        ttl: TimeInterval
    ) {
        let key = statusKey(username: username, releaseId: releaseId)
        statusCache[key] = StatusCacheEntry(
            status: status,
            expiresAt: Date().addingTimeInterval(ttl)
        )
    }

    func invalidateStatus(username: String, releaseId: Int) {
        let key = statusKey(username: username, releaseId: releaseId)
        statusCache[key] = nil
        statusInFlight[key]?.cancel()
        statusInFlight[key] = nil
    }

    func invalidateAllStatus(username: String) {
        let normalized = normalizeUsername(username)
        let keysToRemove = statusCache.keys.filter { $0.hasPrefix("\(normalized)::") }
        keysToRemove.forEach { statusCache[$0] = nil }

        let inFlightKeys = statusInFlight.keys.filter { $0.hasPrefix("\(normalized)::") }
        for key in inFlightKeys {
            statusInFlight[key]?.cancel()
            statusInFlight[key] = nil
        }
    }

    private func normalizeQuery(_ query: String) -> String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func normalizeUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func statusKey(username: String, releaseId: Int) -> String {
        "\(normalizeUsername(username))::\(releaseId)"
    }
}

actor CollectionStatusStore {
    static let shared = CollectionStatusStore()

    private let ttl: TimeInterval
    private let cacheStore = DiscogsCacheStore.shared

    init(ttl: TimeInterval = 10 * 60) {
        self.ttl = ttl
    }

    func cachedStatus(username: String, releaseId: Int) async -> CollectionStatus? {
        await cacheStore.cachedStatus(username: username, releaseId: releaseId)
    }

    func status(
        username: String,
        releaseId: Int,
        forceRefresh: Bool = false,
        fetcher: @escaping @Sendable () async throws -> CollectionStatus
    ) async throws -> CollectionStatus {
        try await cacheStore.status(
            username: username,
            releaseId: releaseId,
            ttl: ttl,
            forceRefresh: forceRefresh,
            fetcher: fetcher
        )
    }

    func updateCachedStatus(username: String, releaseId: Int, status: CollectionStatus) async {
        await cacheStore.updateCachedStatus(
            username: username,
            releaseId: releaseId,
            status: status,
            ttl: ttl
        )
    }

    func invalidate(username: String, releaseId: Int) async {
        await cacheStore.invalidateStatus(username: username, releaseId: releaseId)
    }

    func invalidateAll(username: String) async {
        await cacheStore.invalidateAllStatus(username: username)
    }
}
