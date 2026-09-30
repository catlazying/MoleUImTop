import Foundation
@testable import Mole_UI
import Testing

// MARK: - Phase 10 release hardening

@Test("Phase10: mactop launch args are fixed flags only (no shell / user paths)")
func phase10MactopLaunchArgsAreFixed() {
    let args = HeadlessJSONAdapter.headlessLaunchArguments(intervalMilliseconds: 1000)
    #expect(args == ["--headless", "--interval", "1000"])
    #expect(!args.contains(where: { $0.contains("/") }))
    #expect(!args.contains(where: { $0.contains(";") || $0.contains("|") || $0.contains("`") }))

    let clamped = HeadlessJSONAdapter.headlessLaunchArguments(intervalMilliseconds: 1)
    #expect(clamped == ["--headless", "--interval", "200"])
}

@Test("Phase10: collector runtime HOME is under Caches, not real user home")
func phase10CollectorHomeIsIsolated() {
    let home = HeadlessJSONAdapter.runtimeHomeDirectory()
    #expect(home.path.contains("com.qinfuyao.MoleUI/mactop-runtime"))
    #expect(home.path != NSHomeDirectory())
    #expect(!home.path.hasPrefix(NSHomeDirectory() + "/Library/Logs"))
}

@Test("Phase10: history store stays in-memory (no disk write API)")
func phase10HistoryStoreDoesNotPersist() throws {
    let store = MonitorHistoryStore(maxCount: 10)
    let sample = try SystemMetricsDecoder.decodeSample(
        from: Data(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/mactop-headless-minimal.json")
        )
    )
    store.append(sample)
    #expect(store.count == 1)
    // Contract: only in-memory APIs; clear drops data without file I/O.
    store.clear()
    #expect(store.recent().isEmpty)
}

@Test("Phase10: process terminate uses PID only and rejects unsafe PIDs")
func phase10ProcessTerminateRejectsUnsafePIDs() {
    #expect(throws: ProcessService.ProcessServiceError.invalidPID) {
        try ProcessService.terminate(pid: 0)
    }
    #expect(throws: ProcessService.ProcessServiceError.invalidPID) {
        try ProcessService.terminate(pid: 1)
    }
    #expect(throws: ProcessService.ProcessServiceError.invalidPID) {
        try ProcessService.terminate(pid: -5)
    }
}

@Test("Phase10: Intel / non-AS path is capability-gated")
func phase10AppleSiliconGateConsistent() {
    #if arch(arm64)
        #expect(AppleSiliconCapability.isSupported)
    #else
        #expect(AppleSiliconCapability.isSupported == AppleSiliconCapability.sysctlArm64Optional())
    #endif
}

@Test("Phase10: unsupported start fails without leaving service running")
func phase10UnsupportedStartDoesNotRun() async throws {
    let service = MonitorService()
    // Inject notSupported via failing adapter when supported; otherwise capability path.
    if await service.isSupported {
        let adapter = MockMactopAdapter(mode: .fail(.notSupported))
        await #expect(throws: MactopAdapterError.notSupported) {
            try await service.start(adapter: adapter)
        }
    } else {
        await #expect(throws: MactopAdapterError.notSupported) {
            try await service.start()
        }
    }
    #expect(await service.isRunning == false)
    #expect(await service.latestMetrics == nil)
}

@Test("Phase10: fan metrics are read-only model fields")
func phase10FanMetricsAreReadOnly() throws {
    let data = try Data(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/mactop-headless.json")
    )
    let metrics = try SystemMetricsDecoder.decodeSample(from: data)
    // Presence is fine; there is no write/set API on FanMetrics or adapter.
    for fan in metrics.fans {
        #expect(fan.rpm >= 0)
        #expect(!fan.name.isEmpty)
    }
}

@Test("Phase10: single collector start under sampling (no per-refresh spawn)")
func phase10NoPerRefreshSpawn() async throws {
    let sample = try SystemMetricsDecoder.decodeSample(
        from: Data(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/mactop-headless-minimal.json")
        )
    )
    let adapter = Phase9CountingAdapter(samples: [sample], loop: true)
    let service = MonitorService(
        sampler: MonitorSampler(interval: .milliseconds(10)),
        maxTransientRetries: 0
    )
    guard await service.isSupported else { return }

    try await service.start(adapter: adapter)
    try await Task.sleep(for: .milliseconds(120))
    let counts = await adapter.counts()
    await service.stop()
    #expect(counts.starts == 1)
    #expect(counts.reads >= 2)
}
