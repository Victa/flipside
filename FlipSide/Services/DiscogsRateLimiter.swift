import Foundation

actor DiscogsRateLimiter {
    static let shared = DiscogsRateLimiter(requestsPerMinute: 60, burstCapacity: 4)

    private let refillPerSecond: Double
    private let capacity: Double

    private var tokens: Double
    private var lastRefillTimestamp: TimeInterval
    private var enforcedWaitUntil: TimeInterval = 0

    init(requestsPerMinute: Int, burstCapacity: Int) {
        refillPerSecond = Double(max(requestsPerMinute, 1)) / 60.0
        capacity = Double(max(burstCapacity, 1))
        tokens = Double(max(burstCapacity, 1))
        lastRefillTimestamp = CFAbsoluteTimeGetCurrent()
    }

    func acquire() async {
        while true {
            let now = CFAbsoluteTimeGetCurrent()
            refillTokens(now: now)

            let enforcedWait = max(0, enforcedWaitUntil - now)
            if enforcedWait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(enforcedWait * 1_000_000_000))
                continue
            }

            if tokens >= 1.0 {
                tokens -= 1.0
                return
            }

            let waitForToken = (1.0 - tokens) / refillPerSecond
            let jitter = Double.random(in: 0...0.05)
            try? await Task.sleep(nanoseconds: UInt64((waitForToken + jitter) * 1_000_000_000))
        }
    }

    func backoff(attempt: Int, retryAfter: TimeInterval? = nil) async {
        let exponent = max(0, attempt)
        let base = retryAfter ?? pow(2.0, Double(exponent))
        let jitter = Double.random(in: 0...0.25)
        let delay = max(0.05, base + jitter)
        let target = CFAbsoluteTimeGetCurrent() + delay

        enforcedWaitUntil = max(enforcedWaitUntil, target)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    nonisolated static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        if let header = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
           let seconds = TimeInterval(header) {
            return seconds
        }

        if let header = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            if let date = formatter.date(from: header) {
                return max(0, date.timeIntervalSinceNow)
            }
        }

        return nil
    }

    private func refillTokens(now: TimeInterval) {
        let elapsed = max(0, now - lastRefillTimestamp)
        guard elapsed > 0 else { return }

        tokens = min(capacity, tokens + (elapsed * refillPerSecond))
        lastRefillTimestamp = now
    }
}
