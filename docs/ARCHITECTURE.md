# Mole X Architecture

## 1. Goal

Mole X is a native macOS application that combines:

- Mole CLI: cleanup, disk analysis, optimization, purge, installer management, app uninstall
- mactop v2: Apple Silicon real-time hardware monitoring
- SwiftUI: unified native GUI

The existing MoleUI project is the UI/application base. Do not rewrite its existing Mole functionality. Add monitoring as a separate subsystem.

## 2. Source projects

- MoleUI: https://github.com/noah-qin/MoleUI
- mactop v2: https://github.com/metaspartan/mactop
- Legacy mactop repository: https://github.com/context-labs/mactop

Important: context-labs/mactop states that v2 moved to metaspartan/mactop. Use metaspartan/mactop as the monitoring source.

## 3. Architectural rule

Do NOT merge the two repositories mechanically.

Use MoleUI as the host application and extract/reuse mactop's metrics/collection layer.

Target:

    SwiftUI
       |
       +-- Mole Services
       |     +-- status
       |     +-- clean
       |     +-- analyze
       |     +-- optimize
       |     +-- purge
       |     +-- installer
       |     +-- uninstall
       |
       +-- Monitor Services
             +-- CPU
             +-- GPU
             +-- ANE
             +-- Memory
             +-- DRAM bandwidth
             +-- Power
             +-- Temperature
             +-- Thermal state
             +-- Fans
             +-- Network
             +-- Disk I/O
             +-- Processes
             +-- Thunderbolt

## 4. Runtime separation

Mole operations are request-driven.

Monitoring is a long-running sampling service.

Recommended default sampling interval: 1000 ms.

Hardware sampling and SwiftUI rendering must be decoupled. The monitor service owns the latest sample and a bounded history buffer.

Do not create a new mactop process for every UI refresh.

## 5. Target project structure

MoleX/
├── MoleX.xcodeproj
├── MoleX/
│   ├── App/
│   │   ├── MoleXApp.swift
│   │   └── AppEnvironment.swift
│   ├── Model/
│   │   ├── MetricsModel.swift
│   │   ├── CleanModel.swift
│   │   ├── DiskModel.swift
│   │   ├── OptimizeModel.swift
│   │   ├── PurgeModel.swift
│   │   ├── InstallerModel.swift
│   │   ├── UninstallModel.swift
│   │   ├── VersionModel.swift
│   │   ├── SafetyController.swift
│   │   ├── CLIExecutor.swift
│   │   ├── ErrorTranslator.swift
│   │   ├── SudoHelper.swift
│   │   ├── MonitorModel.swift
│   │   └── ProcessModel.swift
│   ├── Services/
│   │   ├── MoleService.swift
│   │   ├── MonitorService.swift
│   │   ├── MonitorSampler.swift
│   │   ├── ProcessService.swift
│   │   └── MonitorHistoryStore.swift
│   ├── MonitorCore/
│   │   ├── MactopAdapter.swift
│   │   ├── MactopMetrics.swift
│   │   ├── MactopCollector.swift
│   │   └── MactopPlatform.swift
│   ├── Models/
│   │   ├── SystemMetrics.swift
│   │   ├── ProcessMetrics.swift
│   │   ├── TemperatureMetrics.swift
│   │   ├── PowerMetrics.swift
│   │   └── StorageMetrics.swift
│   └── View/
│       ├── ContentView.swift
│       ├── DashboardView.swift
│       ├── MonitorView.swift
│       ├── ProcessListView.swift
│       ├── CleanView.swift
│       ├── DiskAnalyzerView.swift
│       ├── OptimizeView.swift
│       ├── PurgeView.swift
│       ├── InstallerView.swift
│       ├── UninstallView.swift
│       ├── SettingsView.swift
│       └── SidebarView.swift
└── Vendor/
    └── mactop/          # only if source embedding is selected

## 6. Monitoring data model

SystemMetrics should represent one immutable sample:

- timestamp
- CPU usage
- GPU usage
- ANE usage
- core usage array
- CPU/GPU/ANE/DRAM/system/total power
- GPU frequency
- memory total/used/available
- swap total/used
- CPU/GPU/SoC temperatures
- thermal state
- DRAM read/write bandwidth
- network in/out
- disk read/write
- fan information
- battery information when available
- system information
- Thunderbolt information
- process snapshot

Keep optional fields optional. Hardware generations differ.

## 7. Apple Silicon support

The monitor is Apple Silicon only.

At startup:

1. Detect architecture.
2. If arm64, enable Monitor.
3. If Intel, keep Mole functions available and show monitoring as unsupported.

Do not block the entire application on monitor initialization.

## 8. Adapter boundary

Do not expose mactop's internal Go structs directly to SwiftUI.

Use:

    MactopCollector
          |
          v
    MactopAdapter
          |
          v
    SystemMetrics
          |
          v
    MonitorModel
          |
          v
    SwiftUI

This makes future replacement of the collector possible.

## 9. Process management

Process termination is a destructive operation.

UI must:

1. Select process.
2. Display process name/PID.
3. Ask for confirmation.
4. Execute termination through a dedicated ProcessService.
5. Refresh process snapshot.

Do not automatically terminate high CPU or memory processes.

## 10. Fan control

mactop v2 supports privileged fan writes.

Mole X should initially be read-only for fans.

Do NOT expose fan speed control in v1.

A future version may add it behind an explicit advanced setting and privileged helper.

## 11. History

Use a bounded in-memory ring buffer.

Suggested:

- 1-second samples
- 5-minute visible history
- maximum 300 samples per metric

Do not persist raw hardware samples to disk by default.

## 12. Performance

Rules:

- No polling faster than necessary.
- No CLI process creation per sample.
- No unbounded arrays.
- No expensive disk scans from Dashboard.
- Disk analysis runs only when its screen is opened or manually refreshed.
- Cleanup scan runs only on demand.
- SwiftUI charts receive already-downsampled data where appropriate.

## 13. Permissions

Core mactop metrics do not require sudo.

Full Disk Access remains a MoleUI concern for filesystem operations.

Screen Recording is not required for the main monitor.

FPS/display capture features from mactop overlay should not be included in v1.

## 14. UI navigation

Sidebar:

- Dashboard
- Monitor
- Processes
- Cleanup
- Storage
- Applications
- Optimize
- Settings

Dashboard is a summary. Monitor is the detailed mactop-derived screen.

## 15. Design principle

Mole = action.

mactop = observation.

Mole X = observation + safe action.

Never silently turn a monitoring condition into a destructive action.
