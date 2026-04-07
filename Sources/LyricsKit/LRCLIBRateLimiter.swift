import Foundation

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
actor RequestRateLimiter {
    private let minimumInterval: TimeInterval
    private var nextAllowedTime: Date

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = max(0, minimumInterval)
        self.nextAllowedTime = .distantPast
    }

    func waitIfNeeded() async throws {
        let now = Date()
        let scheduledTime = max(now, nextAllowedTime)
        nextAllowedTime = scheduledTime.addingTimeInterval(minimumInterval)

        let delay = scheduledTime.timeIntervalSince(now)
        guard delay > 0 else { return }

        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: UInt64((delay * 1_000_000_000).rounded(.up)))
    }

    func penalize(retryAfter: TimeInterval?) {
        guard let retryAfter, retryAfter > 0 else { return }

        let now = Date()
        nextAllowedTime = max(nextAllowedTime, now.addingTimeInterval(retryAfter))
    }
}
