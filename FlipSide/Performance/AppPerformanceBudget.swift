import Foundation
import OSLog

enum AppPerformanceBudget {
    // Recent iPhone class budgets (seconds)
    static let scanToResultsMaxSeconds: TimeInterval = 5.0
    static let resultsToDetailFirstPaintMaxSeconds: TimeInterval = 1.0
    static let firstStatusBadgeMaxSeconds: TimeInterval = 0.75
    static let initialSyncFirstPageMaxSeconds: TimeInterval = 3.0
    static let initialSyncFullMaxSeconds: TimeInterval = 30.0
}

enum PerformanceEvent {
    case scanToResults
    case resultsToDetailFirstPaint
    case collectionStatusFetch
    case incrementalSyncFirstPage
    case incrementalSyncFull

    var signpostName: StaticString {
        switch self {
        case .scanToResults:
            return "scan_to_results"
        case .resultsToDetailFirstPaint:
            return "results_to_detail_first_paint"
        case .collectionStatusFetch:
            return "collection_status_fetch"
        case .incrementalSyncFirstPage:
            return "incremental_sync_first_page"
        case .incrementalSyncFull:
            return "incremental_sync_full"
        }
    }
}

enum PerformanceMetrics {
    static let subsystem = "com.flipside.app"
    static let logger = Logger(subsystem: subsystem, category: "performance")
    static let signposter = OSSignposter(logger: logger)

    @discardableResult
    static func begin(_ event: PerformanceEvent) -> OSSignpostIntervalState {
        signposter.beginInterval(event.signpostName)
    }

    static func end(_ event: PerformanceEvent, _ state: OSSignpostIntervalState) {
        signposter.endInterval(event.signpostName, state)
    }

    static func gauge(_ name: String, value: Double) {
        logger.log("gauge \(name, privacy: .public)=\(value, privacy: .public)")
    }

    static func incrementCounter(_ name: String) {
#if DEBUG
        Task {
            await DebugPerformanceCounter.shared.increment(name: name)
        }
#endif
    }
}

actor DebugPerformanceCounter {
    static let shared = DebugPerformanceCounter()

    private var counters: [String: Int] = [:]

    func increment(name: String) {
        counters[name, default: 0] += 1
        let value = counters[name, default: 0]
        PerformanceMetrics.logger.debug("counter \(name, privacy: .public)=\(value, privacy: .public)")
    }

    func value(for name: String) -> Int {
        counters[name, default: 0]
    }
}
