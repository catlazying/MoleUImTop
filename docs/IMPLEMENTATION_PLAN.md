# Mole X Implementation Plan

## Phase 0 - Baseline

1. Fork/clone MoleUI.
2. Rename application target only after baseline builds.
3. Run:
   - just build
   - just test
   - just lint
4. Confirm existing Mole features work unchanged.
5. Create branch: feature/mactop-monitor.

Acceptance:
- Existing dashboard, cleanup, disk analyzer, optimize, purge, installer and uninstall still work.

## Phase 1 - Import mactop v2 source

Source:
https://github.com/metaspartan/mactop

Do not copy the terminal UI into SwiftUI.

Inspect the following areas first:

- internal/app
- internal/native stats / IOReport
- process collection
- temperature collection
- power collection
- memory collection
- network/disk collection
- Thunderbolt collection

Document every imported file and its license before copying code.

Preferred initial integration:
- keep mactop collection code isolated
- expose a stable adapter
- keep terminal UI code out of the Mole X target

## Phase 2 - Collector contract

Define a platform-neutral Swift model:

```swift
struct SystemMetrics: Sendable {
    let timestamp: Date
    let cpuUsage: Double
    let gpuUsage: Double
    let aneUsage: Double?
    let coreUsages: [Double]
    let memory: MemoryMetrics
    let power: PowerMetrics?
    let thermal: ThermalMetrics
    let bandwidth: BandwidthMetrics?
    let network: NetworkMetrics?
    let diskIO: DiskIOMetrics?
    let fans: [FanMetrics]
    let battery: BatteryMetrics?
    let processes: [ProcessMetrics]
}
```

Do not make SwiftUI depend on Go implementation details.

## Phase 3 - Sampling service

Create:

- MonitorService
- MonitorSampler
- MonitorHistoryStore

Behavior:

```text
start()
  -> sample every 1 second
  -> publish latest metrics
  -> append bounded history

stop()
  -> stop timer/task
  -> release resources
```

Use Swift concurrency where practical.

## Phase 4 - Monitor screen

Create MonitorView with sections:

1. CPU
2. GPU
3. ANE
4. Memory
5. Power
6. Temperature/Thermal
7. DRAM bandwidth
8. Network/Disk I/O
9. Fans
10. System information

First version should prioritize CPU/GPU/Memory/Temperature.

## Phase 5 - Process screen

Process table:

- Process
- PID
- CPU
- Memory
- GPU when available
- State

Features:

- search
- sort
- refresh
- terminate with confirmation

Do not expose fan control.

## Phase 6 - Dashboard integration

Existing Mole status data remains the source for Mole-specific status.

Add a compact monitoring card:

```text
CPU  23%
GPU  18%
RAM  14.2 / 24 GB
Temp 54°C
Power 18.4 W
```

Clicking the card opens Monitor.

## Phase 7 - Charts

Add:

- CPU history
- GPU history
- Memory history
- Power history
- DRAM bandwidth history

Use a bounded history.

## Phase 8 - Error handling

Expected errors:

- Intel Mac
- unsupported metric
- IOReport unavailable
- SMC sensor unavailable
- permission issue
- collector initialization failure

A collector failure must not crash the application.

Example:

```text
GPU metrics unavailable
Other monitoring metrics are still active.
```

## Phase 9 - Performance tests

Test:

- idle M-series Mac
- sustained CPU load
- sustained GPU load
- memory pressure
- external display
- external SSD
- Thunderbolt device
- MacBook battery
- sleep/wake
- monitor open/close repeatedly

Verify CPU overhead of Mole X monitoring is small and stable.

## Phase 10 - Release hardening

Before release:

- [x] remove debug logging (Monitor lifecycle `info`/`debug` gated or removed; errors retained)
- [x] verify no raw metrics are persisted unintentionally (in-memory history only; collector `HOME` isolated under Caches)
- [x] verify no shell command injection through process names/paths (fixed mactop argv; terminate by PID only)
- [x] verify destructive Mole actions still require existing safety flow (`SafetyController` unchanged; process terminate requires UI confirmation)
- [x] verify code signing (Xcode Manual + Apple Development; release via `just sign-and-notarize`)
- [x] verify Apple Silicon build / Intel Monitor-disabled path (`AppleSiliconCapability` + UI unavailable states)
- [x] automated checks in `MoleUITests/MonitorReleaseHardeningTests.swift`

## Definition of Done

Mole X v1 is complete when:

- [x] MoleUI functions remain intact.
- [x] Dashboard displays live hardware metrics.
- [x] Monitor displays live Apple Silicon metrics.
- [x] Process list works.
- [x] CPU/GPU/Memory charts work.
- [x] No per-refresh mactop subprocess spawning occurs.
- [x] Intel gracefully disables Monitor only.
- [x] Fan control is not exposed.
- [x] Existing Mole cleanup safety controls remain intact.

**Status:** `done` (implementation + automated DoD checks). Remaining release ops: Developer ID notarization when shipping (`just ci-release`).
