import Foundation

/// User-facing monitor status independent of Mole CLI errors.
enum MonitorRuntimeStatus: Equatable, Sendable {
    case unsupported
    case idle
    case starting
    case running
    case degraded(message: String)
    case failed(message: String)

    var bannerTitleKey: String? {
        switch self {
        case .unsupported:
            "monitor.unsupported.title"
        case .degraded:
            "monitor.degraded.title"
        case .failed:
            "monitor.failed.title"
        case .idle, .starting, .running:
            nil
        }
    }

    /// Localized detail for `.unsupported`; raw collector text for degraded/failed.
    var bannerMessageKey: String? {
        switch self {
        case .unsupported:
            "monitor.unsupported.detail"
        default:
            nil
        }
    }

    var bannerMessage: String? {
        switch self {
        case .degraded(let message), .failed(let message):
            message
        case .unsupported, .idle, .starting, .running:
            nil
        }
    }

    var isRetryable: Bool {
        switch self {
        case .failed, .degraded:
            true
        default:
            false
        }
    }
}

/// Maps collector errors and sparse samples into actionable copy.
enum MonitorErrorMapper {
    static func userMessage(for error: Error) -> String {
        if let adapterError = error as? MactopAdapterError {
            return adapterMessage(adapterError)
        }
        return error.localizedDescription
    }

    static func adapterMessage(_ error: MactopAdapterError) -> String {
        switch error {
        case .notSupported:
            "Apple Silicon monitoring is unavailable on this Mac."
        case .binaryNotFound:
            "mactop binary was not found. Run `just update-mactop` or install mactop via Homebrew."
        case .notStarted:
            "Hardware monitor is not running."
        case .alreadyStarted:
            "Hardware monitor is already running."
        case .processExited(let status):
            "Collector exited unexpectedly (status \(status)). Other Mole features are unaffected."
        case .decodeFailed:
            "Received invalid collector output. Waiting for the next valid sample."
        case .timedOut:
            "Timed out waiting for hardware metrics. The collector may be busy or unavailable."
        case .cancelled:
            "Hardware monitor was stopped."
        }
    }

    /// Soft notices for clearly missing optional metrics — never hides available data.
    /// Avoids idle-zero false positives (GPU 0%, DRAM 0 GB/s).
    static func availabilityNotices(for metrics: SystemMetrics) -> [String] {
        var notices: [String] = []

        if metrics.socMetrics.cpuTemp == 0,
           metrics.socMetrics.gpuTemp == 0,
           metrics.socMetrics.socTemp == 0,
           metrics.temperatures.isEmpty
        {
            notices.append("Temperature sensors unavailable. Other monitoring metrics are still active.")
        }

        // Empty process lists are common on sparse/idle samples — avoid false "unavailable".

        return notices
    }

    static func isTransient(_ error: Error) -> Bool {
        guard let adapterError = error as? MactopAdapterError else {
            return true
        }
        switch adapterError {
        case .timedOut, .processExited, .decodeFailed, .notStarted:
            return true
        case .notSupported, .binaryNotFound, .alreadyStarted, .cancelled:
            return false
        }
    }
}
