# Mole X Merge Plan

## Strategy

Do not merge Git histories.

MoleUI is the host application.

mactop v2 is the monitoring engine source.

Result:

    MoleUI
       +
    mactop collector/core
       =
    Mole X

## Repository setup

Recommended:

```bash
git clone https://github.com/noah-qin/MoleUI.git MoleX
cd MoleX

git remote rename origin moleui-upstream
git remote add mactop-upstream https://github.com/metaspartan/mactop.git

git checkout -b feature/mactop-monitor
```

Do not add mactop as a Git submodule unless development requires independent upstream tracking.

## Integration modes

### Mode A - subprocess JSON

Use mactop:

```bash
mactop --headless --pretty
```

Pros:
- fastest prototype
- minimum invasive changes

Cons:
- separate process
- parsing/IPC overhead
- weaker lifecycle control

Use only for Phase 1 prototype.

### Mode B - embedded collector

Extract mactop's native collection layer and expose a library/bridge.

Pros:
- lower overhead
- direct lifecycle
- cleaner GUI integration

Cons:
- CGO/build complexity
- more maintenance

This is the target architecture.

## Recommended transition

Phase 1:

SwiftUI
  -> MonitorService
  -> bundled mactop --headless
  -> JSON
  -> SystemMetrics

Phase 2:

SwiftUI
  -> MonitorService
  -> MactopAdapter
  -> native collector
  -> SystemMetrics

This lets the UI be developed before the deepest native bridge is finalized.

## Important mactop v2 capabilities

Current mactop v2 includes:

- CPU/GPU/ANE usage
- E/P/S core information on supported chips
- power metrics
- GPU frequency
- temperatures
- thermal state
- DRAM bandwidth
- memory/swap
- network
- disk I/O
- fan monitoring
- battery
- Thunderbolt
- process list
- experimental per-process GPU
- headless JSON
- Prometheus
- menu bar
- overlay

Mole X should NOT attempt to reproduce every mactop UI feature in v1.

## v1 inclusion

Include:

- CPU
- GPU
- ANE
- Memory
- Swap
- Power
- Temperature
- Thermal state
- DRAM bandwidth
- Disk I/O
- Network
- Process list
- Battery
- basic Thunderbolt information

Exclude:

- mactop terminal layouts
- party mode
- terminal themes
- overlay HUD
- Prometheus server
- fan control
- FPS capture

## Licensing

Both source projects are MIT-licensed according to their repositories.

Still:

1. Preserve copyright notices.
2. Preserve LICENSE files/attribution required by the source.
3. Record exactly which mactop files are imported.
4. Do not claim the mactop code as newly written.
5. Recheck upstream license before each major release.

## Git commit sequence

Recommended commits:

```text
1. chore: baseline MoleUI
2. docs: add Mole X architecture
3. feat: add monitor domain models
4. feat: add mactop headless adapter
5. feat: add monitor sampling service
6. feat: add monitor dashboard
7. feat: add monitor charts
8. feat: add process monitor
9. feat: add Apple Silicon capability detection
10. test: add monitor unit tests
11. perf: optimize monitoring update path
12. chore: harden release configuration
```

Keep commits small so mactop integration can be reverted independently.

## Cursor execution rule

Cursor should never rewrite existing MoleUI files wholesale.

Before editing:

1. inspect the target file
2. identify existing architecture
3. make the smallest compatible change
4. build
5. run tests
6. report changed files

If a requested mactop feature requires modifying an existing MoleUI model, add an adapter/service first rather than mixing Go/monitoring logic into the Mole CLI model.

## First Cursor task

Prompt Cursor with:

"Read docs/ARCHITECTURE.md, docs/IMPLEMENTATION_PLAN.md and docs/MERGE_PLAN.md. Do not modify code yet. Inspect the current MoleUI project and the vendored/checked-out mactop v2 source. Produce a file-by-file integration map showing which mactop files are required for CPU/GPU/ANE/memory/temperature/power/process metrics, which files are terminal UI only and should not be imported, and identify any CGO/Xcode build issues. Stop after the report."

Only after this report should implementation begin.
