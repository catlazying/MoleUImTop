import Darwin
import Foundation

/// Destructive process operations for the Monitor subsystem.
/// UI must confirm before calling `terminate`.
enum ProcessService: Sendable {
    enum ProcessServiceError: Error, LocalizedError, Equatable {
        case invalidPID
        case terminateFailed(errnoCode: Int32)

        var errorDescription: String? {
            switch self {
            case .invalidPID:
                "Invalid process ID."
            case .terminateFailed(let code):
                "Failed to terminate process (errno \(code))."
            }
        }
    }

    /// Sends `SIGTERM` to the given PID. Does not escalate to SIGKILL.
    static func terminate(pid: Int) throws {
        guard pid > 1 else {
            throw ProcessServiceError.invalidPID
        }
        let result = kill(pid_t(pid), SIGTERM)
        if result != 0 {
            throw ProcessServiceError.terminateFailed(errnoCode: errno)
        }
    }
}
