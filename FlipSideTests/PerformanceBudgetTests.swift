import XCTest
@testable import FlipSide

final class PerformanceBudgetTests: XCTestCase {
    func testBudgetsArePositiveAndReasonable() {
        XCTAssertGreaterThan(AppPerformanceBudget.scanToResultsMaxSeconds, 0)
        XCTAssertGreaterThan(AppPerformanceBudget.resultsToDetailFirstPaintMaxSeconds, 0)
        XCTAssertGreaterThan(AppPerformanceBudget.firstStatusBadgeMaxSeconds, 0)
        XCTAssertGreaterThan(AppPerformanceBudget.initialSyncFirstPageMaxSeconds, 0)
        XCTAssertGreaterThan(AppPerformanceBudget.initialSyncFullMaxSeconds, 0)

        XCTAssertLessThanOrEqual(
            AppPerformanceBudget.resultsToDetailFirstPaintMaxSeconds,
            AppPerformanceBudget.scanToResultsMaxSeconds
        )
        XCTAssertLessThanOrEqual(
            AppPerformanceBudget.initialSyncFirstPageMaxSeconds,
            AppPerformanceBudget.initialSyncFullMaxSeconds
        )
    }

    func testRateLimiterAllowsBurstThenThrottles() async {
        let limiter = DiscogsRateLimiter(requestsPerMinute: 120, burstCapacity: 2)

        let burstStart = Date()
        await limiter.acquire()
        await limiter.acquire()
        let burstElapsed = Date().timeIntervalSince(burstStart)
        XCTAssertLessThan(burstElapsed, 0.25)

        let throttledStart = Date()
        await limiter.acquire()
        let throttledElapsed = Date().timeIntervalSince(throttledStart)
        XCTAssertGreaterThanOrEqual(throttledElapsed, 0.30)
    }
}

final class CollectionStatusStoreTests: XCTestCase {
    actor CallCounter {
        private var value = 0

        func increment() {
            value += 1
        }

        func current() -> Int {
            value
        }
    }

    func testCoalescesInflightRequests() async throws {
        let store = CollectionStatusStore(ttl: 120)
        let counter = CallCounter()

        let task1 = Task {
            try await store.status(username: "tester", releaseId: 10) {
                await counter.increment()
                try await Task.sleep(nanoseconds: 120_000_000)
                return CollectionStatus(isInCollection: true, isInWantlist: false, collectionInstanceId: 101)
            }
        }

        let task2 = Task {
            try await store.status(username: "tester", releaseId: 10) {
                await counter.increment()
                try await Task.sleep(nanoseconds: 120_000_000)
                return CollectionStatus(isInCollection: true, isInWantlist: false, collectionInstanceId: 101)
            }
        }

        let first = try await task1.value
        let second = try await task2.value

        XCTAssertEqual(first, second)
        let callCount = await counter.current()
        XCTAssertEqual(callCount, 1)
    }

    func testCacheHitSkipsNetworkFetcher() async throws {
        let store = CollectionStatusStore(ttl: 120)
        let counter = CallCounter()

        _ = try await store.status(username: "tester", releaseId: 33) {
            await counter.increment()
            return CollectionStatus(isInCollection: false, isInWantlist: true, collectionInstanceId: nil)
        }

        _ = try await store.status(username: "tester", releaseId: 33) {
            await counter.increment()
            return CollectionStatus(isInCollection: true, isInWantlist: true, collectionInstanceId: nil)
        }

        let callCount = await counter.current()
        XCTAssertEqual(callCount, 1)
    }

    func testForceRefreshBypassesCache() async throws {
        let store = CollectionStatusStore(ttl: 120)
        let counter = CallCounter()

        _ = try await store.status(username: "tester", releaseId: 44) {
            await counter.increment()
            return CollectionStatus(isInCollection: false, isInWantlist: false, collectionInstanceId: nil)
        }

        _ = try await store.status(username: "tester", releaseId: 44, forceRefresh: true) {
            await counter.increment()
            return CollectionStatus(isInCollection: true, isInWantlist: false, collectionInstanceId: nil)
        }

        let callCount = await counter.current()
        XCTAssertEqual(callCount, 2)
    }
}

final class DiscogsCacheStoreTests: XCTestCase {
    actor CallCounter {
        private var value = 0

        func increment() {
            value += 1
        }

        func current() -> Int {
            value
        }
    }

    func testSearchCacheHitSkipsFetcherWithinTTL() async throws {
        let cache = DiscogsCacheStore()
        let counter = CallCounter()

        _ = try await cache.searchResults(query: "Miles Davis Kind of Blue", ttl: 600) {
            await counter.increment()
            return [
                DiscogsService.SearchResponse.SearchResult(
                    id: 10,
                    type: "release",
                    title: "Miles Davis - Kind Of Blue",
                    year: "1959",
                    label: ["Columbia"],
                    catno: "CL 1355",
                    genre: ["Jazz"],
                    coverImage: nil
                )
            ]
        }

        _ = try await cache.searchResults(query: "  miles   davis kind OF blue  ", ttl: 600) {
            await counter.increment()
            return []
        }

        let callCount = await counter.current()
        XCTAssertEqual(callCount, 1)
    }

    func testSimulatedScanToDetailCallBudgetWithinTarget() async throws {
        let cache = DiscogsCacheStore()
        let counter = CallCounter()
        let username = "tester"

        _ = try await cache.searchResults(query: "CL 1355", ttl: 600) {
            await counter.increment()
            return [
                DiscogsService.SearchResponse.SearchResult(
                    id: 123,
                    type: "release",
                    title: "Miles Davis - Kind Of Blue",
                    year: "1959",
                    label: ["Columbia"],
                    catno: "CL 1355",
                    genre: ["Jazz"],
                    coverImage: nil
                )
            ]
        }

        for releaseId in [101, 102, 103] {
            await cache.updateCachedStatus(
                username: username,
                releaseId: releaseId,
                status: CollectionStatus(isInCollection: true, isInWantlist: false, collectionInstanceId: releaseId * 10),
                ttl: 600
            )
        }

        for releaseId in [101, 102, 103, 104, 105] {
            _ = try await cache.status(
                username: username,
                releaseId: releaseId,
                ttl: 600
            ) {
                await counter.increment()
                return CollectionStatus(
                    isInCollection: false,
                    isInWantlist: false,
                    collectionInstanceId: nil
                )
            }
        }

        _ = try await cache.releaseDetails(releaseId: 123, ttl: 24 * 60 * 60) {
            await counter.increment()
            return DiscogsService.ReleaseResponse(
                id: 123,
                title: "Kind Of Blue",
                artists: nil,
                year: 1959,
                released: nil,
                country: "US",
                labels: nil,
                genres: ["Jazz"],
                styles: ["Modal"],
                images: nil,
                thumb: nil,
                formats: nil,
                tracklist: nil,
                identifiers: nil,
                videos: nil,
                lowestPrice: nil,
                numForSale: nil,
                community: nil,
                notes: nil,
                dataQuality: nil,
                masterId: nil,
                uri: nil,
                resourceUrl: nil
            )
        }

        _ = try await cache.priceSuggestions(releaseId: 123, ttl: 6 * 60 * 60) {
            await counter.increment()
            return [
                "Near Mint (NM or M-)": DiscogsMatch.ConditionPrice(currency: "USD", value: 72.50)
            ]
        }

        let totalCalls = await counter.current()
        XCTAssertEqual(totalCalls, 5)
        XCTAssertLessThanOrEqual(totalCalls, 7)
    }
}
