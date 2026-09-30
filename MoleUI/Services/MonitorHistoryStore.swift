import Foundation

/// Bounded in-memory ring buffer for monitor samples.
/// Does not persist to disk.
final class MonitorHistoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [SystemMetrics] = []
    private let maxCount: Int

    init(maxCount: Int = 300) {
        self.maxCount = max(1, maxCount)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    var latest: SystemMetrics? {
        lock.lock()
        defer { lock.unlock() }
        return buffer.last
    }

    func append(_ sample: SystemMetrics) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(sample)
        if buffer.count > maxCount {
            buffer.removeFirst(buffer.count - maxCount)
        }
    }

    func recent(limit: Int? = nil) -> [SystemMetrics] {
        lock.lock()
        defer { lock.unlock() }
        guard let limit, limit >= 0 else {
            return buffer
        }
        if limit >= buffer.count {
            return buffer
        }
        return Array(buffer.suffix(limit))
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
    }
}
