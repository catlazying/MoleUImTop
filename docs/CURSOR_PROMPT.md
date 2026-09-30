# Mole X - Cursor Implementation Prompt

You are working on Mole X, a native macOS SwiftUI application derived from MoleUI and integrating mactop v2 monitoring.

Read these documents first:

- docs/ARCHITECTURE.md
- docs/IMPLEMENTATION_PLAN.md
- docs/MERGE_PLAN.md

Repositories:

- MoleUI: https://github.com/noah-qin/MoleUI
- mactop v2: https://github.com/metaspartan/mactop

## Non-negotiable rules

1. Do not rewrite the existing MoleUI architecture.
2. Do not remove existing Mole CLI features.
3. Do not mix monitoring logic into CLIExecutor.
4. Do not create a mactop subprocess on every SwiftUI refresh.
5. Do not expose fan control in v1.
6. Do not add automatic process killing.
7. Do not persist raw monitoring samples by default.
8. Keep Monitor code behind a service/adapter boundary.
9. Use Apple Silicon capability detection.
10. Preserve upstream MIT attribution for imported mactop code.
11. Build and test after each logical change.
12. Prefer small commits.

## Current task

First perform analysis only.

Inspect:

- MoleUI/Model
- MoleUI/View
- MoleUI project configuration
- MoleUI test target
- mactop v2/internal
- mactop v2 main.go
- mactop v2 go.mod
- mactop native/IOReport/SMC/IOKit related code

Produce:

docs/MACTOP_INTEGRATION_MAP.md

The report must contain:

- required source files
- excluded terminal UI files
- CGO dependencies
- Apple frameworks involved
- data structures that must be mapped
- proposed Swift SystemMetrics mapping
- build risks
- licensing/attribution points
- recommended first implementation path

Do not modify application code until this report is complete.

## After analysis

Implement in this order:

1. SystemMetrics domain models
2. MactopAdapter protocol
3. MonitorService
4. headless JSON prototype if needed
5. MonitorView
6. Dashboard compact metrics
7. ProcessView
8. charts
9. native collector optimization
10. tests

At every stage:

- build
- test
- lint/format
- report changed files

## Acceptance criteria

The final application must provide:

Dashboard:
- CPU
- GPU
- Memory
- Temperature
- Power

Monitor:
- CPU history
- GPU history
- ANE
- Memory
- Swap
- DRAM bandwidth
- Power
- Temperature
- Thermal state
- Disk I/O
- Network
- Fan read-only status
- Battery when available

Processes:
- search
- sort
- CPU
- memory
- GPU when available
- PID
- explicit terminate confirmation

Mole:
- existing cleanup
- disk analysis
- optimization
- purge
- installer
- uninstall

## Failure behavior

A missing monitoring metric must degrade gracefully.

Example:

"GPU metrics unavailable"

must not disable:

- CPU
- memory
- Mole cleanup
- disk analysis

Intel Mac:

"Apple Silicon monitoring is unavailable on this Mac."

Mole features remain fully usable.

## Do not do

- Do not port mactop's terminal UI to SwiftUI line-by-line.
- Do not duplicate Mole's cleanup engine.
- Do not add a second disk analyzer.
- Do not make Dashboard perform expensive scans.
- Do not use shell interpolation with untrusted process names.
- Do not add privileged operations without explicit user confirmation.
