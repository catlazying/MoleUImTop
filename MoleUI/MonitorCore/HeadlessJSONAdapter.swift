import Foundation
import os.log

/// Long-lived `mactop --headless` process adapter.
///
/// Output format (infinite / `--count 0`): NDJSON — one `HeadlessOutput` object per line.
/// Does **not** spawn a new process per sample.
actor HeadlessJSONAdapter: MactopAdapter {
    private let logger = Logger(subsystem: "com.qinfuyao.MoleUI", category: "HeadlessJSONAdapter")
    private let binaryURL: URL
    private let intervalMilliseconds: Int
    private let sampleTimeout: Duration

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var readerTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var isStarted = false

    private var pendingContinuations: [CheckedContinuation<SystemMetrics, Error>] = []
    private var latestMetrics: SystemMetrics?

    init(
        binaryURL: URL? = nil,
        intervalMilliseconds: Int = 1000,
        sampleTimeout: Duration = .seconds(15)
    ) throws {
        if let binaryURL {
            self.binaryURL = binaryURL
        } else if let found = Self.findMactopBinary() {
            self.binaryURL = found
        } else {
            throw MactopAdapterError.binaryNotFound
        }
        self.intervalMilliseconds = max(200, intervalMilliseconds)
        self.sampleTimeout = sampleTimeout
    }

    func start() async throws {
        guard AppleSiliconCapability.isSupported else {
            throw MactopAdapterError.notSupported
        }
        guard !isStarted else {
            throw MactopAdapterError.alreadyStarted
        }

        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = Self.headlessLaunchArguments(intervalMilliseconds: intervalMilliseconds)

        // Keep collector scratch/logs out of the real user home (no metrics persistence).
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = Self.runtimeHomeDirectory().path
        proc.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] finished in
            Task { await self?.handleProcessExit(status: finished.terminationStatus) }
        }

        do {
            try proc.run()
        } catch {
            logger.error("Failed to launch mactop: \(error.localizedDescription, privacy: .public)")
            throw MactopAdapterError.binaryNotFound
        }

        process = proc
        stdoutPipe = outPipe
        stderrPipe = errPipe
        isStarted = true

        readerTask = Task { await self.readStdout(outPipe.fileHandleForReading) }
        stderrTask = Task { await self.readStderr(errPipe.fileHandleForReading) }
        #if DEBUG
            logger.info("Started mactop headless PID \(proc.processIdentifier)")
        #endif
    }

    func stop() async {
        isStarted = false
        readerTask?.cancel()
        stderrTask?.cancel()
        readerTask = nil
        stderrTask = nil

        if let proc = process, proc.isRunning {
            proc.terminate()
            // Brief wait; escalate if needed.
            try? await Task.sleep(for: .milliseconds(500))
            if proc.isRunning {
                proc.interrupt()
            }
        }

        failPending(.cancelled)
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        #if DEBUG
            logger.info("Stopped mactop headless adapter")
        #endif
    }

    func readMetrics() async throws -> SystemMetrics {
        guard isStarted, let proc = process, proc.isRunning else {
            if let status = process?.terminationStatus {
                throw MactopAdapterError.processExited(status: status)
            }
            throw MactopAdapterError.notStarted
        }

        do {
            return try await withThrowingTaskGroup(of: SystemMetrics.self) { group in
                group.addTask {
                    try await self.waitForNextSample()
                }
                group.addTask {
                    try await Task.sleep(for: self.sampleTimeout)
                    throw MactopAdapterError.timedOut
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } catch {
            // Timeout / cancellation must resume the waiter continuation or it stays orphaned
            // and a later deliver() can double-resume it.
            let mapped: MactopAdapterError = if let adapterError = error as? MactopAdapterError {
                adapterError
            } else if error is CancellationError {
                .cancelled
            } else {
                .timedOut
            }
            failPending(mapped)
            throw error
        }
    }

    // MARK: - Binary location

    /// Fixed argv for the long-lived collector — never includes process names or user paths.
    nonisolated static func headlessLaunchArguments(intervalMilliseconds: Int) -> [String] {
        [
            "--headless",
            "--interval",
            "\(max(200, intervalMilliseconds))",
        ]
    }

    /// Scratch HOME for the child process so collector logs stay out of the real user home.
    nonisolated static func runtimeHomeDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent("com.qinfuyao.MoleUI/mactop-runtime", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func findMactopBinary() -> URL? {
        let fm = FileManager.default
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("mactop", isDirectory: true)
            .appendingPathComponent("mactop")
        {
            if fm.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }

        // Project / test fallbacks (not for production preference order after bundle).
        let candidates = [
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/mactop/mactop"),
            URL(fileURLWithPath: "/opt/homebrew/bin/mactop"),
            URL(fileURLWithPath: "/usr/local/bin/mactop"),
        ]
        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            return url
        }
        return nil
    }

    // MARK: - Private

    private func waitForNextSample() async throws -> SystemMetrics {
        try await withCheckedThrowingContinuation { continuation in
            pendingContinuations.append(continuation)
        }
    }

    private func deliver(_ metrics: SystemMetrics) {
        latestMetrics = metrics
        let waiting = pendingContinuations
        pendingContinuations.removeAll()
        for continuation in waiting {
            continuation.resume(returning: metrics)
        }
    }

    private func failPending(_ error: MactopAdapterError) {
        let waiting = pendingContinuations
        pendingContinuations.removeAll()
        for continuation in waiting {
            continuation.resume(throwing: error)
        }
    }

    private func handleProcessExit(status: Int32) {
        isStarted = false
        failPending(.processExited(status: status))
        logger.error("mactop exited with status \(status)")
    }

    private func readStdout(_ handle: FileHandle) async {
        var buffer = Data()
        while !Task.isCancelled {
            let chunk: Data = await Task.detached {
                handle.availableData
            }.value
            if chunk.isEmpty {
                // EOF
                break
            }
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer.subdata(in: buffer.startIndex ..< newline)
                buffer.removeSubrange(buffer.startIndex ... newline)
                guard !lineData.isEmpty else { continue }
                do {
                    let metrics = try SystemMetricsDecoder.decodeSample(from: lineData)
                    deliver(metrics)
                } catch {
                    // Minimal diagnostic — never log full stdout payload.
                    logger.error(
                        "JSON decode failed (\(lineData.count) bytes): \(error.localizedDescription, privacy: .public)"
                    )
                    // Do not fail the whole stream on one bad line; waiters keep waiting.
                }
            }
        }

        if isStarted {
            failPending(.processExited(status: process?.terminationStatus ?? -1))
        }
    }

    private func readStderr(_ handle: FileHandle) async {
        // Drain stderr without logging payloads (release hardening).
        while !Task.isCancelled {
            let chunk: Data = await Task.detached {
                handle.availableData
            }.value
            if chunk.isEmpty {
                break
            }
        }
    }
}
