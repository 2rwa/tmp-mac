import Foundation

enum CaptureHold: Hashable {
    case systemSleep, screenSleep, inactiveSession
}

// Tokens prevent frames captured before a sleep/wake transition from being shown afterward.
struct CaptureState {
    private(set) var holds = Set<CaptureHold>()
    private(set) var activeToken: UInt64?
    private(set) var retryAfter = Date.distantPast
    private(set) var failures = 0
    private var nextToken: UInt64 = 0
    private var startedAt: Date?

    mutating func suspend(_ hold: CaptureHold) {
        holds.insert(hold)
        invalidate()
    }
    mutating func resume(_ hold: CaptureHold, at now: Date) {
        holds.remove(hold)
        reset(at: now, delay: 2)
    }
    mutating func reset(at now: Date, delay: TimeInterval) {
        invalidate()
        failures = 0
        retryAfter = now.addingTimeInterval(delay)
    }
    private mutating func invalidate() {
        activeToken = nil
        startedAt = nil
    }
    func canStart(at now: Date) -> Bool {
        holds.isEmpty && activeToken == nil && now >= retryAfter
    }
    mutating func begin(at now: Date) -> UInt64? {
        guard canStart(at: now) else { return nil }
        nextToken &+= 1
        activeToken = nextToken
        startedAt = now
        return nextToken
    }
    @discardableResult
    mutating func finish(_ token: UInt64, succeeded: Bool, at now: Date) -> Bool {
        guard activeToken == token, holds.isEmpty else { return false }
        invalidate()
        if succeeded {
            failures = 0
            retryAfter = .distantPast
        } else {
            failures = min(failures + 1, 10)
            retryAfter = now.addingTimeInterval(min(16, pow(2, Double(failures - 1))))
        }
        return true
    }
    mutating func expireIfNeeded(at now: Date) -> Bool {
        guard let token = activeToken, let startedAt,
              now.timeIntervalSince(startedAt) >= 6 else { return false }
        return finish(token, succeeded: false, at: now)
    }
    static func selfTest() -> Bool {
        let t = Date(timeIntervalSince1970: 100)
        var s = CaptureState()
        guard let first = s.begin(at: t) else { return false }
        s.suspend(.systemSleep)
        s.suspend(.screenSleep)
        s.resume(.systemSleep, at: t.addingTimeInterval(1))
        guard !s.canStart(at: t.addingTimeInterval(10)) else { return false }
        s.resume(.screenSleep, at: t.addingTimeInterval(11))
        guard !s.canStart(at: t.addingTimeInterval(12)),
              !s.finish(first, succeeded: true, at: t.addingTimeInterval(13)),
              let second = s.begin(at: t.addingTimeInterval(14)),
              second != first,
              s.finish(second, succeeded: false, at: t.addingTimeInterval(14)),
              !s.canStart(at: t.addingTimeInterval(14.5)),
              let third = s.begin(at: t.addingTimeInterval(16)),
              s.expireIfNeeded(at: t.addingTimeInterval(23)),
              !s.finish(third, succeeded: true, at: t.addingTimeInterval(24)),
              let fourth = s.begin(at: t.addingTimeInterval(26))
        else { return false }
        return s.finish(fourth, succeeded: true, at: t.addingTimeInterval(27))
            && s.failures == 0 && s.canStart(at: t.addingTimeInterval(27))
    }
}
