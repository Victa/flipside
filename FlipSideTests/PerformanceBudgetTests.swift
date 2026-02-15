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
                return CollectionStatus(isInCollection: true, isInWantlist: false)
            }
        }

        let task2 = Task {
            try await store.status(username: "tester", releaseId: 10) {
                await counter.increment()
                try await Task.sleep(nanoseconds: 120_000_000)
                return CollectionStatus(isInCollection: true, isInWantlist: false)
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
            return CollectionStatus(isInCollection: false, isInWantlist: true)
        }

        _ = try await store.status(username: "tester", releaseId: 33) {
            await counter.increment()
            return CollectionStatus(isInCollection: true, isInWantlist: true)
        }

        let callCount = await counter.current()
        XCTAssertEqual(callCount, 1)
    }

    func testForceRefreshBypassesCache() async throws {
        let store = CollectionStatusStore(ttl: 120)
        let counter = CallCounter()

        _ = try await store.status(username: "tester", releaseId: 44) {
            await counter.increment()
            return CollectionStatus(isInCollection: false, isInWantlist: false)
        }

        _ = try await store.status(username: "tester", releaseId: 44, forceRefresh: true) {
            await counter.increment()
            return CollectionStatus(isInCollection: true, isInWantlist: false)
        }

        let callCount = await counter.current()
        XCTAssertEqual(callCount, 2)
    }
}
