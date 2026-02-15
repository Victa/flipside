import Foundation

actor CollectionStatusStore {
    static let shared = CollectionStatusStore()

    private struct Key: Hashable {
        let username: String
        let releaseId: Int
    }

    private struct CacheEntry {
        let status: CollectionStatus
        let expiresAt: Date
    }

    private let ttl: TimeInterval
    private var cache: [Key: CacheEntry] = [:]
    private var inFlight: [Key: Task<CollectionStatus, Error>] = [:]

    init(ttl: TimeInterval = 120) {
        self.ttl = ttl
    }

    func cachedStatus(username: String, releaseId: Int) -> CollectionStatus? {
        let key = Self.makeKey(username: username, releaseId: releaseId)
        guard let entry = cache[key] else {
            return nil
        }

        if entry.expiresAt <= Date() {
            cache.removeValue(forKey: key)
            return nil
        }

        return entry.status
    }

    func status(
        username: String,
        releaseId: Int,
        forceRefresh: Bool = false,
        fetcher: @escaping @Sendable () async throws -> CollectionStatus
    ) async throws -> CollectionStatus {
        let key = Self.makeKey(username: username, releaseId: releaseId)

        if !forceRefresh, let cached = cachedStatus(username: username, releaseId: releaseId) {
            return cached
        }

        if let existing = inFlight[key] {
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

        inFlight[key] = task

        do {
            let value = try await task.value
            cache[key] = CacheEntry(
                status: value,
                expiresAt: Date().addingTimeInterval(ttl)
            )
            inFlight[key] = nil
            return value
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func updateCachedStatus(username: String, releaseId: Int, status: CollectionStatus) {
        let key = Self.makeKey(username: username, releaseId: releaseId)
        cache[key] = CacheEntry(
            status: status,
            expiresAt: Date().addingTimeInterval(ttl)
        )
    }

    func invalidate(username: String, releaseId: Int) {
        let key = Self.makeKey(username: username, releaseId: releaseId)
        cache.removeValue(forKey: key)
        inFlight[key]?.cancel()
        inFlight[key] = nil
    }

    func invalidateAll(username: String) {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let keys = cache.keys.filter { $0.username == normalized }
        keys.forEach { cache.removeValue(forKey: $0) }

        let inFlightKeys = inFlight.keys.filter { $0.username == normalized }
        for key in inFlightKeys {
            inFlight[key]?.cancel()
            inFlight[key] = nil
        }
    }

    private static func makeKey(username: String, releaseId: Int) -> Key {
        Key(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            releaseId: releaseId
        )
    }
}
