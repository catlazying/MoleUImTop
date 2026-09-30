import Foundation

/// Boundary between MonitorService and the mactop collection backend.
protocol MactopAdapter: Sendable {
    /// Start the underlying collector (e.g. long-lived headless process).
    func start() async throws

    /// Stop the collector and release resources.
    func stop() async

    /// Wait for the next metrics sample from the running collector.
    func readMetrics() async throws -> SystemMetrics
}

enum MactopAdapterError: Error, Equatable, LocalizedError, Sendable {
    case notSupported
    case binaryNotFound
    case notStarted
    case alreadyStarted
    case processExited(status: Int32)
    case decodeFailed(detail: String)
    case timedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notSupported:
            "Apple Silicon monitoring is unavailable on this Mac."
        case .binaryNotFound:
            "Bundled mactop binary was not found."
        case .notStarted:
            "Monitor adapter is not started."
        case .alreadyStarted:
            "Monitor adapter is already started."
        case .processExited(let status):
            "mactop process exited (status \(status))."
        case .decodeFailed(let detail):
            "Failed to decode mactop metrics (\(detail))."
        case .timedOut:
            "Timed out waiting for mactop metrics."
        case .cancelled:
            "Monitor adapter was cancelled."
        }
    }
}

/// Apple Silicon gate for the Monitor subsystem (does not affect Mole features).
enum AppleSiliconCapability: Sendable {
    /// True when the host can run mactop's IOReport-based collector.
    static var isSupported: Bool {
        #if arch(arm64)
            true
        #else
            sysctlArm64Optional()
        #endif
    }

    /// `hw.optional.arm64` — useful under Rosetta / non-arm64 builds.
    static func sysctlArm64Optional() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }
}
