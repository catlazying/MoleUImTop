import Foundation
import os.log

/// Owns monitor lifecycle, adapter, sampling, and history.
/// SwiftUI must not talk to Process / mactop directly.
actor MonitorService {
    private let logger = Logger(subsystem: "com.qinfuyao.MoleUI", category: "MonitorService")

    private let historyStore: MonitorHistoryStore
    private let sampler: MonitorSampler
    private let maxTransientRetries: Int
    private let retryDelay: Duration

    private var adapter: (any MactopAdapter)?
    private var sampleTask: Task<Void, Never>?
    private var running = false
    private var consecutiveTransientFailures = 0
    /// Bumps on every start/stop so a finishing sample loop cannot clear a newer adapter.
    private var generation: UInt64 = 0
    /// Bumps synchronously at the start of each start/stop so overlapping starts can detect supersession
    /// across `await` points (before `running` becomes true).
    private var lifecycleEpoch: UInt64 = 0

    private(set) var latestMetrics: SystemMetrics?
    private(set) var lastError: Error?

    var isSupported: Bool {
        AppleSiliconCapability.isSupported
    }

    var isRunning: Bool {
        running
    }

    init(
        historyStore: MonitorHistoryStore = MonitorHistoryStore(maxCount: 300),
        sampler: MonitorSampler = MonitorSampler(interval: .seconds(1)),
        maxTransientRetries: Int = 3,
        retryDelay: Duration = .milliseconds(750)
    ) {
        self.historyStore = historyStore
        self.sampler = sampler
        self.maxTransientRetries = maxTransientRetries
        self.retryDelay = retryDelay
    }

    func history() -> MonitorHistoryStore {
        historyStore
    }

    /// Start monitoring with an optional injected adapter (tests) or default headless adapter.
    func start(adapter: (any MactopAdapter)? = nil) async throws {
        guard isSupported else {
            lastError = MactopAdapterError.notSupported
            throw MactopAdapterError.notSupported
        }
        guard !running else { return }

        lifecycleEpoch &+= 1
        let epoch = lifecycleEpoch

        // Wait out any in-flight failure teardown before installing a new collector.
        await joinSampleTask()
        guard epoch == lifecycleEpoch else { return }

        await teardownAdapter()
        guard epoch == lifecycleEpoch else { return }

        let resolved: any MactopAdapter = if let adapter {
            adapter
        } else {
            try HeadlessJSONAdapter()
        }

        do {
            try await resolved.start()
        } catch {
            guard epoch == lifecycleEpoch else { throw error }
            lastError = error
            throw error
        }

        // A newer start/stop won the race while we were launching — discard this collector.
        guard epoch == lifecycleEpoch else {
            await resolved.stop()
            return
        }

        generation &+= 1
        let startGeneration = generation
        self.adapter = resolved
        running = true
        lastError = nil
        consecutiveTransientFailures = 0

        sampleTask = Task { [weak self] in
            guard let self else { return }
            await runSampling(with: resolved, generation: startGeneration)
        }
        #if DEBUG
            logger.info("MonitorService started")
        #endif
    }

    func stop() async {
        lifecycleEpoch &+= 1
        generation &+= 1
        sampleTask?.cancel()
        await joinSampleTask()
        await teardownAdapter()
        running = false
        consecutiveTransientFailures = 0
        #if DEBUG
            logger.info("MonitorService stopped")
        #endif
    }

    /// Restart after a transient failure (keeps last good metrics / history).
    func retry(adapter: (any MactopAdapter)? = nil) async throws {
        await stop()
        try await start(adapter: adapter)
    }

    private func joinSampleTask() async {
        let task = sampleTask
        sampleTask = nil
        await task?.value
    }

    private func teardownAdapter() async {
        if let adapter {
            await adapter.stop()
        }
        adapter = nil
    }

    private func endSampling(
        with adapter: any MactopAdapter,
        error: Error?,
        generation startGeneration: UInt64
    ) async {
        lastError = error
        running = false
        await adapter.stop()
        // Only clear if we still own this generation — a newer start() may have replaced us.
        if generation == startGeneration {
            self.adapter = nil
        }
    }

    private func runSampling(with adapter: any MactopAdapter, generation startGeneration: UInt64) async {
        while !Task.isCancelled {
            // A newer start/stop invalidated this loop.
            if generation != startGeneration { return }

            do {
                for try await sample in sampler.samples(using: adapter) {
                    if generation != startGeneration { return }
                    latestMetrics = sample
                    historyStore.append(sample)
                    lastError = nil
                    consecutiveTransientFailures = 0
                }
                // AsyncSequence ended without throw — treat as unexpected exit.
                throw MactopAdapterError.processExited(status: 0)
            } catch is CancellationError {
                return
            } catch {
                if generation != startGeneration { return }

                logger.error("Monitor sampling error: \(error.localizedDescription, privacy: .public)")

                guard MonitorErrorMapper.isTransient(error),
                      consecutiveTransientFailures < maxTransientRetries
                else {
                    logger.error("Monitor sampling stopped after non-retryable or exhausted failures")
                    await endSampling(with: adapter, error: error, generation: startGeneration)
                    return
                }

                consecutiveTransientFailures += 1
                #if DEBUG
                    logger.info(
                        "Transient monitor failure \(self.consecutiveTransientFailures)/\(self.maxTransientRetries); retrying"
                    )
                #endif
                try? await Task.sleep(for: retryDelay)
                if Task.isCancelled || generation != startGeneration { return }

                do {
                    await adapter.stop()
                    if generation != startGeneration { return }
                    try await adapter.start()
                } catch {
                    if generation != startGeneration { return }
                    if !MonitorErrorMapper.isTransient(error)
                        || consecutiveTransientFailures >= maxTransientRetries
                    {
                        await endSampling(with: adapter, error: error, generation: startGeneration)
                        return
                    }
                    lastError = error
                }
            }
        }
        if generation == startGeneration {
            running = false
        }
    }
}
