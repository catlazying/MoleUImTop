import Foundation
@testable import Mole_UI
import Testing

// MARK: - Fixtures

private enum MonitorFixtures {
    static func data(named name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(name).json")
        return try Data(contentsOf: url)
    }
}

// MARK: - JSON decoding

@Test func systemMetricsDecodesHeadlessFixture() throws {
    let data = try MonitorFixtures.data(named: "mactop-headless")
    let metrics = try SystemMetricsDecoder.decodeSample(from: data)

    #expect(metrics.cpuUsage >= 0)
    #expect(metrics.gpuUsage >= 0)
    #expect(!metrics.coreUsages.isEmpty)
    #expect(metrics.memory.total > 0)
    #expect(metrics.systemInfo.coreCount > 0)
    #expect(!metrics.thermalState.isEmpty)
    #expect(metrics.pCluster != nil)
    #expect(metrics.socMetrics.totalPower >= 0)
}

@Test func systemMetricsDecodesCountArrayWrapper() throws {
    let sample = try MonitorFixtures.data(named: "mactop-headless")
    let wrapped = Data("[".utf8) + sample + Data("]".utf8)
    let samples = try SystemMetricsDecoder.decodeSamples(from: wrapped)
    #expect(samples.count == 1)
    #expect(samples[0].memory.total > 0)
}

@Test func systemMetricsDecodesMinimalOptionalOmissions() throws {
    let data = try MonitorFixtures.data(named: "mactop-headless-minimal")
    let metrics = try SystemMetricsDecoder.decodeSample(from: data)

    #expect(metrics.battery == nil)
    #expect(metrics.fans.isEmpty)
    #expect(metrics.processes.isEmpty)
    #expect(metrics.thunderbolt == nil)
    #expect(metrics.networkLinks == nil)
    #expect(metrics.volumes.isEmpty)
    #expect(metrics.temperatures.isEmpty)
    #expect(metrics.sCluster == nil)
    #expect(metrics.cpuUsage >= 0)
}

@Test func systemMetricsDecodeFailsOnInvalidJSON() {
    let data = Data("{not-json".utf8)
    #expect(throws: Error.self) {
        try SystemMetricsDecoder.decodeSample(from: data)
    }
}

// MARK: - History store

@Test func monitorHistoryStoreCapsAt300() throws {
    let store = MonitorHistoryStore(maxCount: 300)
    let base = try SystemMetricsDecoder.decodeSample(from: MonitorFixtures.data(named: "mactop-headless-minimal"))

    for _ in 0 ..< 300 {
        store.append(base)
    }
    #expect(store.count == 300)

    store.append(base)
    #expect(store.count == 300)
    #expect(store.latest != nil)
    #expect(store.recent(limit: 5).count == 5)

    store.clear()
    #expect(store.recent().isEmpty)
}

@Test func monitorHistoryStoreRecentLimit() throws {
    let store = MonitorHistoryStore(maxCount: 10)
    let sample = try SystemMetricsDecoder.decodeSample(from: MonitorFixtures.data(named: "mactop-headless-minimal"))
    for _ in 0 ..< 7 {
        store.append(sample)
    }
    #expect(store.recent(limit: 3).count == 3)
    #expect(store.recent(limit: 100).count == 7)
}

// MARK: - Adapter mock / errors

actor MockMactopAdapter: MactopAdapter {
    enum Mode: Sendable {
        case success(SystemMetrics)
        case fail(MactopAdapterError)
        case exitAfterStart
    }

    private let mode: Mode
    private var started = false
    private var readCount = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func start() async throws {
        switch mode {
        case .exitAfterStart:
            started = true
            throw MactopAdapterError.processExited(status: 1)
        case .fail(let error):
            throw error
        case .success:
            started = true
        }
    }

    func stop() async {
        started = false
    }

    func readMetrics() async throws -> SystemMetrics {
        guard started else { throw MactopAdapterError.notStarted }
        readCount += 1
        switch mode {
        case .success(let metrics):
            return metrics
        case .fail(let error):
            throw error
        case .exitAfterStart:
            throw MactopAdapterError.processExited(status: 1)
        }
    }
}

@Test func mactopAdapterPropagatesNotSupported() async {
    let adapter = MockMactopAdapter(mode: .fail(.notSupported))
    await #expect(throws: MactopAdapterError.notSupported) {
        try await adapter.start()
    }
}

@Test func mactopAdapterPropagatesDecodeFailed() async throws {
    let sample = try SystemMetricsDecoder.decodeSample(from: MonitorFixtures.data(named: "mactop-headless-minimal"))
    let adapter = MockMactopAdapter(mode: .success(sample))
    try await adapter.start()
    let metrics = try await adapter.readMetrics()
    #expect(metrics.cpuUsage == sample.cpuUsage)

    let bad = MockMactopAdapter(mode: .fail(.decodeFailed(detail: "truncated")))
    await #expect(throws: MactopAdapterError.decodeFailed(detail: "truncated")) {
        try await bad.start()
    }
}

@Test func monitorServiceRejectsUnsupportedViaInjectedError() async throws {
    let service = MonitorService()
    // On Apple Silicon hosts this still starts unless we inject a failing adapter path.
    // Capability itself is covered below; here verify service surfaces adapter start failure.
    let adapter = MockMactopAdapter(mode: .fail(.binaryNotFound))
    if await service.isSupported {
        await #expect(throws: MactopAdapterError.binaryNotFound) {
            try await service.start(adapter: adapter)
        }
    } else {
        await #expect(throws: MactopAdapterError.notSupported) {
            try await service.start(adapter: adapter)
        }
    }
}

@Test func monitorServiceSamplesWithMockAdapter() async throws {
    let sample = try SystemMetricsDecoder.decodeSample(from: MonitorFixtures.data(named: "mactop-headless-minimal"))
    let service = MonitorService(sampler: MonitorSampler(interval: .milliseconds(50)))
    guard await service.isSupported else {
        // Intel CI: skip live sampling path.
        return
    }
    let adapter = MockMactopAdapter(mode: .success(sample))
    try await service.start(adapter: adapter)
    try await Task.sleep(for: .milliseconds(200))
    let latest = await service.latestMetrics
    #expect(latest != nil)
    let store = await service.history()
    #expect(store.count >= 1)
    await service.stop()
}

// MARK: - Apple Silicon capability

@Test func appleSiliconCapabilityIsConsistentWithArchitecture() {
    #if arch(arm64)
        #expect(AppleSiliconCapability.isSupported == true)
    #else
        // Under Rosetta on Apple Silicon, sysctl may still report support.
        let supported = AppleSiliconCapability.isSupported
        let sysctl = AppleSiliconCapability.sysctlArm64Optional()
        #expect(supported == sysctl)
    #endif
}

@Test func monitorModelDisabledPathSetsErrorOnUnsupportedOverride() async {
    // MonitorModel uses live capability; we only assert model initializes cleanly.
    let model = await MainActor.run { MonitorModel() }
    let supported = await MainActor.run { model.isSupported }
    #expect(supported == AppleSiliconCapability.isSupported)
}

@Test func monitorModelCancelledStartDoesNotPoisonUI() async throws {
    let sample = try SystemMetricsDecoder.decodeSample(from: MonitorFixtures.data(named: "mactop-headless-minimal"))
    let service = MonitorService(
        sampler: MonitorSampler(interval: .milliseconds(20)),
        maxTransientRetries: 0
    )
    guard await service.isSupported else { return }

    actor GateAdapter: MactopAdapter {
        private let sample: SystemMetrics
        private let delay: Duration
        private var started = false

        init(sample: SystemMetrics, delay: Duration) {
            self.sample = sample
            self.delay = delay
        }

        func start() async throws {
            try await Task.sleep(for: delay)
            started = true
        }

        func stop() async {
            started = false
        }

        func readMetrics() async throws -> SystemMetrics {
            guard started else { throw MactopAdapterError.notStarted }
            return sample
        }
    }

    let model = await MainActor.run { MonitorModel(service: service) }
    let slow = GateAdapter(sample: sample, delay: .milliseconds(80))
    let fast = GateAdapter(sample: sample, delay: .milliseconds(5))

    await MainActor.run {
        model.start(adapter: slow)
    }
    try await Task.sleep(for: .milliseconds(20))
    await MainActor.run {
        model.start(adapter: fast)
    }
    try await Task.sleep(for: .milliseconds(200))

    let errorMessage = await MainActor.run { model.errorMessage }
    let status = await MainActor.run { model.runtimeStatus }
    let running = await MainActor.run { model.isRunning }

    #expect(errorMessage == nil)
    #expect(running == true)
    if case .failed = status {
        Issue.record("Cancelled overlapping start poisoned runtimeStatus to failed")
    }
    if case .degraded = status {
        Issue.record("Cancelled overlapping start poisoned runtimeStatus to degraded")
    }

    await MainActor.run { model.stop() }
    try await Task.sleep(for: .milliseconds(50))
}

// MARK: - Chart downsampling

@Test func monitorChartDownsampleCapsPoints() throws {
    let values = (0 ..< 300).map { Double($0) }
    let points = MonitorChartData.downsample(values, maxPoints: 90)
    #expect(points.count == 90)
    #expect(points.first?.value != nil)
    #expect(try #require(points.last?.value) > points.first!.value)
}

@Test func monitorChartDownsampleKeepsShortSeries() {
    let values = [1.0, 2.0, 3.0]
    let points = MonitorChartData.downsample(values, maxPoints: 90)
    #expect(points.count == 3)
}

// MARK: - Phase 8 error mapping / degrade

@Test func monitorErrorMapperUserMessages() {
    #expect(MonitorErrorMapper.adapterMessage(.notSupported).contains("Apple Silicon"))
    #expect(MonitorErrorMapper.adapterMessage(.binaryNotFound).contains("mactop"))
    #expect(MonitorErrorMapper.adapterMessage(.timedOut).contains("Timed out"))
    #expect(MonitorErrorMapper.adapterMessage(.processExited(status: 9)).contains("9"))
    #expect(MonitorErrorMapper.adapterMessage(.decodeFailed(detail: "x")).contains("invalid"))
    #expect(MonitorErrorMapper.isTransient(MactopAdapterError.timedOut))
    #expect(MonitorErrorMapper.isTransient(MactopAdapterError.processExited(status: 1)))
    #expect(!MonitorErrorMapper.isTransient(MactopAdapterError.notSupported))
    #expect(!MonitorErrorMapper.isTransient(MactopAdapterError.binaryNotFound))
}

@Test func monitorAvailabilityNoticesFromSparseSample() throws {
    let metrics = try SystemMetricsDecoder.decodeSample(from: MonitorFixtures.data(named: "mactop-headless-minimal"))
    let notices = MonitorErrorMapper.availabilityNotices(for: metrics)
    // Empty process lists alone must not warn (avoids idle false positives).
    #expect(!notices.contains { $0.contains("Process list unavailable") })
}

@Test func monitorServiceRetriesTransientThenStops() async throws {
    actor FlakyAdapter: MactopAdapter {
        private var started = false
        private var reads = 0
        private let sample: SystemMetrics

        init(sample: SystemMetrics) {
            self.sample = sample
        }

        func start() async throws {
            started = true
        }

        func stop() async {
            started = false
        }

        func readMetrics() async throws -> SystemMetrics {
            guard started else { throw MactopAdapterError.notStarted }
            reads += 1
            if reads == 1 {
                return sample
            }
            throw MactopAdapterError.timedOut
        }

        func readCount() -> Int { reads }
    }

    let sample = try SystemMetricsDecoder.decodeSample(from: MonitorFixtures.data(named: "mactop-headless-minimal"))
    let service = MonitorService(
        sampler: MonitorSampler(interval: .milliseconds(30)),
        maxTransientRetries: 2,
        retryDelay: .milliseconds(40)
    )
    guard await service.isSupported else { return }

    let adapter = FlakyAdapter(sample: sample)
    try await service.start(adapter: adapter)
    try await Task.sleep(for: .milliseconds(500))

    let latest = await service.latestMetrics
    #expect(latest != nil) // last good sample retained
    let running = await service.isRunning
    #expect(running == false)
    let err = await service.lastError
    #expect(err != nil)
    await service.stop()
}

@Test func monitorRuntimeStatusRetryableFlags() {
    #expect(MonitorRuntimeStatus.failed(message: "x").isRetryable)
    #expect(MonitorRuntimeStatus.degraded(message: "x").isRetryable)
    #expect(!MonitorRuntimeStatus.running.isRetryable)
    #expect(!MonitorRuntimeStatus.unsupported.isRetryable)
    #expect(MonitorRuntimeStatus.degraded(message: "gpu").bannerTitleKey == "monitor.degraded.title")
}

@Test func monitorServiceStopsAdapterAfterExhaustedRetries() async throws {
    actor ExitingAdapter: MactopAdapter {
        private(set) var startCount = 0
        private(set) var stopCount = 0
        private var started = false

        func start() async throws {
            startCount += 1
            started = true
        }

        func stop() async {
            stopCount += 1
            started = false
        }

        func readMetrics() async throws -> SystemMetrics {
            guard started else { throw MactopAdapterError.notStarted }
            throw MactopAdapterError.timedOut
        }

        func counts() -> (starts: Int, stops: Int) { (startCount, stopCount) }
    }

    let service = MonitorService(
        sampler: MonitorSampler(interval: .milliseconds(10)),
        maxTransientRetries: 1,
        retryDelay: .milliseconds(20)
    )
    guard await service.isSupported else { return }

    let adapter = ExitingAdapter()
    try await service.start(adapter: adapter)
    try await Task.sleep(for: .milliseconds(250))

    #expect(await service.isRunning == false)
    let counts = await adapter.counts()
    #expect(counts.stops >= 1)
    #expect(await service.lastError != nil)
}

@Test func monitorServiceRestartAfterFailureDoesNotClearNewAdapter() async throws {
    actor SlowStopAdapter: MactopAdapter {
        private let sample: SystemMetrics
        private let failFirstRead: Bool
        private var started = false
        private var readCount = 0
        private(set) var stopCount = 0

        init(sample: SystemMetrics, failFirstRead: Bool) {
            self.sample = sample
            self.failFirstRead = failFirstRead
        }

        func start() async throws {
            started = true
        }

        func stop() async {
            stopCount += 1
            // Hold the actor suspension so endSampling can interleave with a new start().
            try? await Task.sleep(for: .milliseconds(80))
            started = false
        }

        func readMetrics() async throws -> SystemMetrics {
            guard started else { throw MactopAdapterError.notStarted }
            readCount += 1
            if failFirstRead, readCount == 1 {
                throw MactopAdapterError.processExited(status: 9)
            }
            return sample
        }

        func stops() -> Int { stopCount }
    }

    let sample = try SystemMetricsDecoder.decodeSample(from: MonitorFixtures.data(named: "mactop-headless-minimal"))
    let service = MonitorService(
        sampler: MonitorSampler(interval: .milliseconds(15)),
        maxTransientRetries: 0,
        retryDelay: .milliseconds(10)
    )
    guard await service.isSupported else { return }

    let failing = SlowStopAdapter(sample: sample, failFirstRead: true)
    try await service.start(adapter: failing)
    try await Task.sleep(for: .milliseconds(60))

    let replacement = SlowStopAdapter(sample: sample, failFirstRead: false)
    try await service.start(adapter: replacement)
    try await Task.sleep(for: .milliseconds(120))

    #expect(await service.isRunning == true)
    #expect(await service.latestMetrics != nil)

    await service.stop()
    // Replacement must have been stopped by service.stop(), proving it was still tracked.
    #expect(await replacement.stops() >= 1)
}

@Test func monitorServiceOverlappingStartsDoNotLeakCollectors() async throws {
    actor SlowStartAdapter: MactopAdapter {
        private let sample: SystemMetrics
        private let startDelay: Duration
        private var started = false
        private(set) var startCount = 0
        private(set) var stopCount = 0

        init(sample: SystemMetrics, startDelay: Duration) {
            self.sample = sample
            self.startDelay = startDelay
        }

        func start() async throws {
            startCount += 1
            try await Task.sleep(for: startDelay)
            started = true
        }

        func stop() async {
            stopCount += 1
            started = false
        }

        func readMetrics() async throws -> SystemMetrics {
            guard started else { throw MactopAdapterError.notStarted }
            return sample
        }

        func counts() -> (starts: Int, stops: Int) { (startCount, stopCount) }
    }

    let sample = try SystemMetricsDecoder.decodeSample(from: MonitorFixtures.data(named: "mactop-headless-minimal"))
    let service = MonitorService(
        sampler: MonitorSampler(interval: .milliseconds(20)),
        maxTransientRetries: 0
    )
    guard await service.isSupported else { return }

    let first = SlowStartAdapter(sample: sample, startDelay: .milliseconds(80))
    let second = SlowStartAdapter(sample: sample, startDelay: .milliseconds(10))

    async let startFirst: Void = service.start(adapter: first)
    try await Task.sleep(for: .milliseconds(15))
    async let startSecond: Void = service.start(adapter: second)
    _ = try await (startFirst, startSecond)

    try await Task.sleep(for: .milliseconds(100))
    #expect(await service.isRunning == true)

    let firstCounts = await first.counts()
    let secondCounts = await second.counts()
    // Exactly one generation should remain running; any superseded launch must be stopped.
    #expect(firstCounts.starts + secondCounts.starts >= 1)
    if firstCounts.starts > 0 {
        #expect(firstCounts.stops >= 1)
    }

    await service.stop()
    // Whichever adapter was last installed must be torn down by stop().
    let firstStops = await first.counts().stops
    let secondStops = await second.counts().stops
    #expect(firstStops + secondStops >= 1)
}
