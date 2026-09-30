import Foundation
@testable import Mole_UI
import Testing

// MARK: - Phase 9 helpers

private enum Phase9Fixtures {
    static func data(named name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(name).json")
        return try Data(contentsOf: url)
    }

    static func fullSample() throws -> SystemMetrics {
        try SystemMetricsDecoder.decodeSample(from: data(named: "mactop-headless"))
    }

    static func minimalSample() throws -> SystemMetrics {
        try SystemMetricsDecoder.decodeSample(from: data(named: "mactop-headless-minimal"))
    }

    /// Synthesize a loaded variant while preserving optional hardware fields.
    static func withLoad(_ base: SystemMetrics, cpu: Double, gpu: Double) -> SystemMetrics {
        SystemMetrics(
            timestamp: base.timestamp,
            socMetrics: base.socMetrics,
            memory: base.memory,
            netDisk: base.netDisk,
            cpuUsage: cpu,
            eCluster: base.eCluster,
            pCluster: base.pCluster,
            sCluster: base.sCluster,
            gpuUsage: gpu,
            gpuMetrics: GPUMetrics(freqMHz: base.gpuMetrics.freqMHz, activePercent: gpu),
            tflopsFP32: base.tflopsFP32,
            tflopsFP16: base.tflopsFP16,
            displayFPS: base.displayFPS,
            frameIntervalMs: base.frameIntervalMs,
            coreUsages: base.coreUsages,
            systemInfo: base.systemInfo,
            thermalState: base.thermalState,
            processes: base.processes,
            networkLinks: base.networkLinks,
            volumes: base.volumes,
            thunderbolt: base.thunderbolt,
            tbNetTotalBytesInPerSec: base.tbNetTotalBytesInPerSec,
            tbNetTotalBytesOutPerSec: base.tbNetTotalBytesOutPerSec,
            rdmaStatus: base.rdmaStatus,
            fans: base.fans,
            temperatures: base.temperatures,
            battery: base.battery
        )
    }
}

/// Counts start/stop/read — proves sampling does not respawn the collector per sample.
actor Phase9CountingAdapter: MactopAdapter {
    private var samples: [SystemMetrics]
    private var index = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var readCount = 0
    private var started = false
    private let loop: Bool

    init(samples: [SystemMetrics], loop: Bool = true) {
        self.samples = samples
        self.loop = loop
    }

    func start() async throws {
        startCount += 1
        started = true
        index = 0
    }

    func stop() async {
        stopCount += 1
        started = false
    }

    func readMetrics() async throws -> SystemMetrics {
        guard started else { throw MactopAdapterError.notStarted }
        readCount += 1
        if samples.isEmpty {
            throw MactopAdapterError.decodeFailed(detail: "empty")
        }
        if index >= samples.count {
            if loop {
                index = 0
            } else {
                throw MactopAdapterError.processExited(status: 0)
            }
        }
        let sample = samples[index]
        index += 1
        return sample
    }

    func counts() -> (starts: Int, stops: Int, reads: Int) {
        (startCount, stopCount, readCount)
    }
}

// MARK: - Hardware scenario decoding (fixture-backed)

@Test("Phase9: full fixture includes external display FPS")
func phase9ExternalDisplayFPS() throws {
    let metrics = try Phase9Fixtures.fullSample()
    #expect(metrics.displayFPS != nil)
    #expect(try #require(metrics.displayFPS) > 0)
}

@Test("Phase9: full fixture includes external volume")
func phase9ExternalSSDVolume() throws {
    let metrics = try Phase9Fixtures.fullSample()
    #expect(metrics.volumes.count >= 2)
    #expect(metrics.volumes.contains { $0.name.localizedCaseInsensitiveContains("external") })
}

@Test("Phase9: full fixture includes Thunderbolt buses")
func phase9ThunderboltDevice() throws {
    let metrics = try Phase9Fixtures.fullSample()
    let tb = try #require(metrics.thunderbolt)
    #expect(!tb.buses.isEmpty)
}

@Test("Phase9: full fixture includes MacBook battery")
func phase9MacBookBattery() throws {
    let metrics = try Phase9Fixtures.fullSample()
    let battery = try #require(metrics.battery)
    #expect(battery.present)
    #expect(battery.percent != nil)
}

@Test("Phase9: idle minimal sample remains valid")
func phase9IdleMinimalSample() throws {
    let metrics = try Phase9Fixtures.minimalSample()
    #expect(metrics.cpuUsage >= 0)
    #expect(metrics.gpuUsage >= 0)
    #expect(metrics.memory.total > 0)
    #expect(metrics.systemInfo.coreCount > 0)
}

// MARK: - Sustained load / memory / charts

@Test("Phase9: sustained CPU load samples remain bounded and ordered")
func phase9SustainedCPULoad() async throws {
    let base = try Phase9Fixtures.fullSample()
    let series = (0 ..< 40).map { i in
        Phase9Fixtures.withLoad(base, cpu: 60 + Double(i % 40), gpu: base.gpuUsage)
    }
    let adapter = Phase9CountingAdapter(samples: series, loop: false)
    let service = MonitorService(
        sampler: MonitorSampler(interval: .milliseconds(5)),
        maxTransientRetries: 0
    )
    guard await service.isSupported else { return }

    try await service.start(adapter: adapter)
    try await Task.sleep(for: .milliseconds(350))
    let store = await service.history()
    #expect(store.count >= 10)
    #expect(store.count <= 300)
    let latest = await service.latestMetrics
    #expect(try #require(latest).cpuUsage >= 60)
    let starts = await adapter.counts().starts
    #expect(starts == 1)
    await service.stop()
}

@Test("Phase9: sustained GPU load samples remain bounded")
func phase9SustainedGPULoad() async throws {
    let base = try Phase9Fixtures.fullSample()
    let series = (0 ..< 40).map { i in
        Phase9Fixtures.withLoad(base, cpu: base.cpuUsage, gpu: 70 + Double(i % 30))
    }
    let adapter = Phase9CountingAdapter(samples: series, loop: false)
    let service = MonitorService(
        sampler: MonitorSampler(interval: .milliseconds(5)),
        maxTransientRetries: 0
    )
    guard await service.isSupported else { return }

    try await service.start(adapter: adapter)
    try await Task.sleep(for: .milliseconds(350))
    let latest = await service.latestMetrics
    #expect(try #require(latest).gpuUsage >= 70)
    let starts = await adapter.counts().starts
    #expect(starts == 1)
    await service.stop()
}

@Test("Phase9: memory pressure keeps history capped at 300")
func phase9MemoryPressureHistoryCap() throws {
    let base = try Phase9Fixtures.fullSample()
    let store = MonitorHistoryStore(maxCount: 300)
    let clock = ContinuousClock()
    let started = clock.now
    for i in 0 ..< 5_000 {
        store.append(Phase9Fixtures.withLoad(base, cpu: Double(i % 100), gpu: Double((i * 3) % 100)))
    }
    let elapsed = started.duration(to: clock.now)
    #expect(store.count == 300)
    #expect(store.recent(limit: 90).count == 90)
    // 5k appends should stay well under a second on CI.
    #expect(elapsed < .seconds(2))
}

@Test("Phase9: chart downsample of full history stays cheap")
func phase9ChartDownsampleOverhead() {
    let values = (0 ..< 300).map { Double($0 % 100) }
    let clock = ContinuousClock()
    let started = clock.now
    for _ in 0 ..< 200 {
        let points = MonitorChartData.downsample(values, maxPoints: 90)
        #expect(points.count == 90)
    }
    let elapsed = started.duration(to: clock.now)
    #expect(elapsed < .milliseconds(500))
}

@Test("Phase9: repeated full-fixture decode stays cheap")
func phase9DecodeThroughput() throws {
    let data = try Phase9Fixtures.data(named: "mactop-headless")
    let clock = ContinuousClock()
    let started = clock.now
    for _ in 0 ..< 100 {
        let metrics = try SystemMetricsDecoder.decodeSample(from: data)
        #expect(metrics.memory.total > 0)
    }
    let elapsed = started.duration(to: clock.now)
    #expect(elapsed < .seconds(2))
}

// MARK: - Lifecycle: open/close, sleep/wake

@Test("Phase9: monitor open/close repeatedly does not accumulate starts incorrectly")
func phase9MonitorOpenCloseRepeatedly() async throws {
    let sample = try Phase9Fixtures.minimalSample()
    let adapter = Phase9CountingAdapter(samples: [sample])
    let service = MonitorService(
        sampler: MonitorSampler(interval: .milliseconds(20)),
        maxTransientRetries: 0
    )
    guard await service.isSupported else { return }

    for _ in 0 ..< 8 {
        try await service.start(adapter: adapter)
        try await Task.sleep(for: .milliseconds(40))
        await service.stop()
        try await Task.sleep(for: .milliseconds(10))
    }

    let counts = await adapter.counts()
    #expect(counts.starts == 8)
    // stop() plus defensive teardown on the next start may yield extra stops.
    #expect(counts.stops >= 8)
    #expect(counts.reads >= 1)
    let running = await service.isRunning
    #expect(running == false)
}

@Test("Phase9: sleep/wake simulated stop/start preserves last metrics and history")
func phase9SleepWakeSimulated() async throws {
    let sample = try Phase9Fixtures.fullSample()
    let adapter = Phase9CountingAdapter(samples: [sample])
    let service = MonitorService(
        sampler: MonitorSampler(interval: .milliseconds(15)),
        maxTransientRetries: 0
    )
    guard await service.isSupported else { return }

    try await service.start(adapter: adapter)
    try await Task.sleep(for: .milliseconds(80))
    let beforeStop = await service.latestMetrics
    #expect(beforeStop != nil)

    // Sleep — stop collector; last sample and history must survive.
    await service.stop()
    let historyAfterSleep = await service.history().count
    #expect(historyAfterSleep >= 1)
    #expect(await service.latestMetrics != nil)

    // Wake
    try await service.start(adapter: adapter)
    try await Task.sleep(for: .milliseconds(80))
    #expect(await service.latestMetrics != nil)
    #expect(await service.history().count >= historyAfterSleep)
    await service.stop()
}

// MARK: - Overhead: single long-lived collector

@Test("Phase9: sustained sampling uses one collector start (no per-sample spawn)")
func phase9SamplingOverheadSingleStart() async throws {
    let base = try Phase9Fixtures.minimalSample()
    let adapter = Phase9CountingAdapter(samples: [base], loop: true)
    let service = MonitorService(
        sampler: MonitorSampler(interval: .milliseconds(8)),
        maxTransientRetries: 0
    )
    guard await service.isSupported else { return }

    let clock = ContinuousClock()
    let started = clock.now
    try await service.start(adapter: adapter)
    try await Task.sleep(for: .milliseconds(250))
    let counts = await adapter.counts()
    let elapsed = started.duration(to: clock.now)
    await service.stop()

    #expect(counts.starts == 1)
    #expect(counts.reads >= 5)
    #expect(elapsed < .seconds(2))
    #expect(await service.history().count <= 300)
}

@Test("Phase9: Apple Silicon live idle sample when mactop is available")
func phase9LiveIdleWhenMactopPresent() async throws {
    guard AppleSiliconCapability.isSupported else { return }
    let adapter: HeadlessJSONAdapter
    do {
        adapter = try HeadlessJSONAdapter(intervalMilliseconds: 500, sampleTimeout: .seconds(8))
    } catch MactopAdapterError.binaryNotFound {
        return
    }

    let service = MonitorService(
        sampler: MonitorSampler(interval: .milliseconds(200)),
        maxTransientRetries: 1,
        retryDelay: .milliseconds(100)
    )
    try await service.start(adapter: adapter)
    try await Task.sleep(for: .seconds(2))
    let latest = await service.latestMetrics
    await service.stop()

    // Soft assert: if collector produced a sample, it should be sane.
    if let latest {
        #expect(latest.cpuUsage >= 0)
        #expect(latest.cpuUsage <= 100)
        #expect(latest.memory.total > 0)
    }
}
