# Mole X Documentation

Mole X combines MoleUI and mactop v2.

Start here:

1. `ARCHITECTURE.md`
2. `IMPLEMENTATION_PLAN.md`
3. `MERGE_PLAN.md`
4. `CURSOR_PROMPT.md`

Recommended first action in Cursor:

Read all four files, inspect the current source trees, and create
`docs/MACTOP_INTEGRATION_MAP.md` before modifying code.

## Architecture summary

MoleUI remains the host.

Mole remains responsible for system-management actions.

mactop v2 supplies Apple Silicon monitoring.

SwiftUI renders the unified interface.

The architectural boundary is:

    Mole CLI -> MoleService
    mactop  -> MactopAdapter -> MonitorService
    SwiftUI  -> View models/views

## v1 scope

Monitoring:
- CPU
- GPU
- ANE
- Memory
- Swap
- Power
- Temperature
- Thermal
- DRAM bandwidth
- Disk I/O
- Network
- Process
- Battery
- basic Thunderbolt

Management:
- existing MoleUI functionality

Excluded from v1:
- fan control
- overlay/FPS capture
- Prometheus
- terminal UI
- automatic process killing
