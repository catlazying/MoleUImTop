import Foundation

/// Sampling loop over a `MactopAdapter`.
/// Prefers Swift concurrency (`Task` / async loop) over `Timer`.
struct MonitorSampler: Sendable {
    /// Minimum pause after a successful sample when the adapter returns faster than desired.
    let interval: Duration

    init(interval: Duration = .seconds(1)) {
        self.interval = interval
    }

    /// Continuously read samples until cancelled or the adapter throws.
    func samples(using adapter: MactopAdapter) -> AsyncThrowingStream<SystemMetrics, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        let started = ContinuousClock.now
                        let metrics = try await adapter.readMetrics()
                        continuation.yield(metrics)

                        let elapsed = ContinuousClock.now - started
                        if elapsed < interval {
                            try await Task.sleep(for: interval - elapsed)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
