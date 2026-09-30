<!--
type: reference
status: draft
updated_at: 2026-09-28
canonical: true
-->

# Mole X — mactop v2 Integration Map

사전 분석만 수행한 결과물이다. **기존 MoleUI 소스 코드는 수정하지 않았다.**

| 항목 | 값 |
|------|-----|
| MoleUI host | `/Volumes/linuxDev/_github/MoleUI` (local) · https://github.com/noah-qin/MoleUI |
| mactop v2 source | https://github.com/metaspartan/mactop · module `github.com/metaspartan/mactop/v2` · Go 1.25.4 |
| Analysis snapshot | local clone under `.analysis/mactop` (temporary; not for commit) |
| Upstream license | MIT · Copyright (c) 2024-2026 Carsen Klock |
| MoleUI license | MIT · Copyright (c) 2026 Fuyao Qin |

---

## 1. MoleUI 현재 구조 요약

### 1.1 Model 구조

아키텍처: **MV (Model-View)** + Swift `@Observable`. 비즈니스 로직은 Model, UI는 View.

| 파일 | 역할 |
|------|------|
| `MoleUI/Model/MetricsModel.swift` | Dashboard 메트릭. `mole status --json` 폴링 (기본 1s). 히스토리 ring buffer(최대 120). Clean/Optimize 특권 작업 중 pause |
| `MoleUI/Model/CleanModel.swift` | `mole clean` 스캔/실행 |
| `MoleUI/Model/DiskModel.swift` | `mole analyze --json` |
| `MoleUI/Model/OptimizeModel.swift` | `mole optimize` + health script |
| `MoleUI/Model/PurgeModel.swift` | `mole purge` |
| `MoleUI/Model/InstallerModel.swift` | `mole installer` |
| `MoleUI/Model/UninstallModel.swift` | `mole uninstall` / app scan |
| `MoleUI/Model/VersionModel.swift` | CLI/앱 버전 |
| `MoleUI/Model/SafetyController.swift` | dry-run / 확인 흐름 |
| `MoleUI/Model/CLIExecutor.swift` | Process + bash wrapper, timeout, progress, JSON decode |
| `MoleUI/Model/ErrorTranslator.swift` | 사용자 친화 에러 매핑 |
| `MoleUI/Model/SudoHelper.swift` | 권한 상승 |

**중요:** 현재 Dashboard 메트릭은 **Mole CLI** (`status --json`)에서 온다. mactop과는 별개 파이프라인이다. Mole X에서는 이 Mole 메트릭을 유지하면서 **별도 Monitor 서브시스템**을 추가해야 한다. `CLIExecutor`에 모니터링 로직을 섞지 말 것.

### 1.2 View 구조

| 파일 | 역할 |
|------|------|
| `MoleUI/View/MoleApp.swift` | `@main`, Environment 주입 |
| `MoleUI/View/ContentView.swift` | `SidebarItem` 라우팅 + 테마 컴포넌트 |
| `MoleUI/View/SidebarView.swift` | Monitor / Cleanup / App 섹션 |
| `MoleUI/View/DashboardView.swift` | Status 대시보드 (CPU/Mem/Disk/Power/Process/Network cards) |
| `MoleUI/View/CleanView.swift` | Cleanup |
| `MoleUI/View/DiskAnalyzerView.swift` | Storage analyze |
| `MoleUI/View/OptimizeView.swift` | Optimize |
| `MoleUI/View/PurgeView.swift` | Purge |
| `MoleUI/View/InstallerView.swift` | Installers |
| `MoleUI/View/UninstallView.swift` | Uninstall |
| `MoleUI/View/SettingsView.swift` | Settings |
| `MoleUI/View/MoleVersionView.swift` | Version UI |

현재 `SidebarItem`: Status, Disk Analyzer, Clean, Purge, Installers, Optimize, Uninstall, Settings.  
Mole X 목표: **Monitor**, **Processes** 항목 추가 (ARCHITECTURE.md §14).

### 1.3 CLIExecutor 구조

- `@MainActor final class CLIExecutor`
- `executeMole(_:options:)` → `findMoleBinary()` + `findMoleRoot()` 후 `cd <root> && mole <subcommand>`
- 일반 shell: `/bin/bash -c`
- JSON: `executeAndParseJSON<T: Decodable>`
- Dry-run: `MOLE_DRY_RUN=1` / `UI_TESTING` 인자
- Binary 탐색 순서: `Bundle.main/.../Resources/mole` → `/usr/local/bin` → `/opt/homebrew/bin` → `~/.config/mole`

**통합 규칙:** Monitor는 `CLIExecutor`를 재사용하지 않는다. 별도 `MonitorService` / `MactopAdapter` 경계를 둔다.

### 1.4 Mole CLI 실행 방식

1. 앱 번들에 `Resources/mole` 복사 (Xcode Run Script phase)
2. `just update-mole`로 Homebrew mole → `Resources/mole/` 동기화
3. 현재 번들 CLI 버전 마커: `MoleUI/.mole-cli-version` = `1.30.0`
4. Dashboard: `mole status --json` (매 샘플마다 **새 Process 생성**)
5. 기타 기능: `mole clean|analyze|optimize|purge|installer|uninstall`

Mole status는 이미 CPU/GPU/Mem/Disk/Network/Battery/Thermal/Process top을 제공한다.  
mactop 통합의 가치는 **Apple Silicon 전용 심층 메트릭**(ANE, DRAM BW, SoC power breakdown, GPU freq, thermal state, Thunderbolt, per-process GPU 등)이다.

### 1.5 프로젝트 빌드 방식

| 항목 | 값 |
|------|-----|
| Project | `MoleUI.xcodeproj` |
| Scheme | `MoleUI` |
| App product | `Mole UI.app` |
| Swift | 6.0 (target) |
| Deployment | macOS 14.0+ |
| Bundle ID | `com.qinfuyao.MoleUI` |
| Build runner | `just build` → `xcodebuild -scheme MoleUI -destination 'platform=macOS'` |
| Qualifiers | `just fmt` (swiftformat), `just lint` (swiftlint) |
| CI | `.github/workflows/ci.yml` · macos-15 · Xcode 16.1 |
| Mole bundle script | `pbxproj` Run Script → `Resources/mole` → app `Contents/Resources/mole` |

### 1.6 테스트 구조

| 대상 | 파일 | 내용 |
|------|------|------|
| Unit | `MoleUITests/MoleCoreTests.swift` | Swift Testing (`@Test`). Version, MetricsSnapshot JSON decode, Safety, models 등 (~44) |
| UI flow | `MoleUITests/UIFlowTests.swift` | 사용자 플로우 (~15) |
| Runner | `run-tests.sh` | `xcodebuild test -only-testing:MoleUITests` |

Monitor 추가 시: `SystemMetrics` decode / adapter / Apple Silicon gate 단위 테스트가 필요. 기존 MoleCoreTests는 건드리지 말고 확장.

### 1.7 기존 Dashboard 구조

`DashboardView` → `@Environment(MetricsModel)`:

1. Header: hardware + health score + uptime (`MoleHeroPanel`)
2. ASCII mole animation
3. Cards: CPU(+temp), Memory, Disk(+IO), Power/Battery, Top processes, Network(+sparkline)

수명주기: `.task { service.start() }` / `.onDisappear { service.stop() }`  
→ Dashboard가 보일 때만 Mole status 폴링.

Mole X Phase 6: 이 Dashboard에 **mactop 기반 compact monitor card**를 추가하고, 클릭 시 Monitor 화면으로 이동. 기존 Mole status 카드는 유지 가능(중복 최소화를 위해 점진 교체 권장).

---

## 2. 기능별 mactop 파일 매핑

mactop v2는 사실상 단일 패키지 `internal/app` + `internal/i18n`이다.  
수집 코어는 **CGO + Objective-C + C(SMC)** 에 집중되어 있다.

### 2.1 메트릭 → 소스 파일

| 메트릭 | 필수 파일 | 핵심 API / 타입 | 비고 |
|--------|-----------|-----------------|------|
| **CPU** | `processes.go` (`GetCPUUsage`), `metrics.go` (`GetCPUPercentages`, `averageCPUUsage`), `ioreport.go`+`.m` (E/P/S cluster active+freq), `sys_info.go` / `native_stats.go` (core topology) | `CPUUsage`, `CPUMetrics`, `core_usages` | host_statistics + IOReport cluster |
| **GPU** | `ioreport.go`+`.m`, `metrics.go` | `GPUActive`, `GPUFreqMHz`, `GPUMetrics` | IOReport GPU Stats |
| **ANE** | `ioreport.go`+`.m`, `metrics.go` (`aneUtilizationPercent`) | `ANEPower`, `ANEActive`, `ANE*BW` | PMP / Energy Model; OS별 fallback |
| **Memory** | `native_stats.go` (`GetNativeMemoryMetrics`), `metrics.go` (`getMemoryMetrics`) | `MemoryMetrics` | mach `HOST_VM_INFO64` |
| **Swap** | 동일 (Memory의 `SwapTotal`/`SwapUsed`) | `MemoryMetrics.Swap*` | |
| **Power** | `ioreport.go`+`.m`, `metrics.go` (`normalizeSocMetricsPower`) | `SocMetrics.*Power` | CPU/GPU/ANE/DRAM/GPU_SRAM/System/Total |
| **Temperature** | `ioreport.go`+`.m`, `smc.c`+`smc.h`, `info.go` (센서 분류), `headless.go` (`buildHeadlessTempGroups`) | `CPUTemp`, `GPUTemp`, `SocTemp`, `TempSensor` | SMC + HID |
| **Thermal** | `ioreport.go` (`getThermalState*`) | `thermal_state` string/level | OS thermal pressure |
| **DRAM bandwidth** | `ioreport.go`+`.m` | `DRAMReadBW`, `DRAMWriteBW`, `DRAMBWCombined` | AMC / power-derived M5+ |
| **Disk I/O** | `native_stats.go` (`GetNativeDiskMetrics`), `metrics.go` (`getNetDiskMetrics`) | `NetDiskMetrics.Read/Write*` | |
| **Network** | `native_stats.go` (`GetNativeNetworkMetrics`, `GetEthernetLinkInfo`), `ioreport.go` (`get_wifi_link_info` / CoreWLAN) | `NetDiskMetrics`, `HeadlessNetworkLinks` | |
| **Process** | `processes.go`, `processes_helpers.go`, `native_stats.go` (`GetGPUProcessStats`) | `ProcessMetrics`, `HeadlessProcess` | libproc + experimental GPU |
| **Battery** | `battery.go` | `BatteryInfo` | IOKit IOPowerSources |
| **Fan (read)** | `ioreport.go`+`.m`, `smc.c` | `FanInfo` / `HeadlessFan` | v1 = read-only |
| **Fan (write)** | `ioreport.go` (`SetFan*`), `events_helpers.go` | `SetFanMode/Target` | **v1 제외** |
| **Thunderbolt** | `thunderbolt.go` (`system_profiler`), `thunderbolt_network.go`, `native_stats.go` (IOKit switches), `rdma.go` | `ThunderboltOutput` | profiler JSON + net stats |
| **Arch gate** | `arch_check.go` | `isAppleSilicon`, `requireAppleSilicon` | Intel 차단 |
| **Headless JSON** | `headless.go`, `app.go` (flags), `cli.go` | `HeadlessOutput`, `--headless --pretty --count` | Phase 1 프로토타입 계약 |

### 2.2 보조 / 공용 수집 파일

| 파일 | 역할 | 통합 시 |
|------|------|---------|
| `main.go` | `app.Run()` 진입 | 바이너리 빌드용 |
| `types.go` | 공유 구조체 + TUI widget 일부 | 구조체만 참고; widget은 제외 |
| `globals.go` | 전역 상태 (headless flags 포함) | 선택적 |
| `sys_info.go` | SoC 이름/코어 수 sysctl | 필요 |
| `utils.go` | 유틸 | 선택적 |
| `i18n/*` | 다국어 | headless 에러 메시지용; GUI는 Swift 로컬라이즈 |

---

## 3. TUI 전용 — 제외할 파일

다음 파일은 Mole X v1에 **가져오지 않는다** (터미널 UI / 부가 기능).

| 파일 | 이유 |
|------|------|
| `layout.go` | TUI 레이아웃 |
| `theme.go`, `colors.go`, `catppuccin.go` | 터미널 테마 |
| `detection.go` | 터미널 light/dark OSC |
| `events.go`, `events_helpers.go` | 키 바인딩, **팬 제어**, kill UI |
| `app.go` 대부분 | TUI 메인 루프 (headless 분기·flag 정의만 참고) |
| `info.go` TUI 렌더링 부분 | Info 패널 UI (센서 분류 헬퍼는 재사용 가능) |
| `overlay.go`, `overlay.m` | Overlay HUD |
| `displayfps.go`, `displayfps.m` | FPS / Screen Recording |
| `menubar.go`, `menubar.m` | Cocoa menu bar 앱 |
| `profiler.go` | TUI 프로파일러 표시 |
| `metrics.go`의 Prometheus 서버 부분 | `-p` 메트릭 서버 (수집 함수는 유지) |
| `processes.go`의 UI builders | `buildHeader`, `buildProcessRows`, kill modal, gotui 의존 부분 |
| Party mode / 테마 사이클 | UI only |

**v1 기능 제외 (MERGE_PLAN):** terminal layouts, party mode, themes, overlay HUD, Prometheus, fan control, FPS capture.

---

## 4. Go → Swift 연동이 필요한 부분

### 4.1 권장 2단계

```
Phase A (프로토타입)
  SwiftUI → MonitorService → Process(번들 mactop --headless --count 1 --pretty)
           → JSON decode → SystemMetrics

Phase B (목표)
  SwiftUI → MonitorService → MactopAdapter
           → 장기 실행 collector (embedded Go lib 또는 장기 프로세스 + IPC)
           → SystemMetrics
```

### 4.2 연동 경계

| 계층 | 책임 |
|------|------|
| `SystemMetrics` (Swift) | UI용 immutable 샘플. Go 타입에 비의존 |
| `MactopAdapter` | JSON 또는 native bridge → `SystemMetrics` |
| `MonitorService` / `MonitorSampler` | 1s 샘플링, start/stop, Intel degrade |
| `MonitorHistoryStore` | ring buffer ≤ 300 samples |
| `MonitorModel` | `@Observable` UI 바인딩 |

### 4.3 JSON 계약 (HeadlessOutput → Swift)

`HeadlessOutput` (`headless.go`)가 사실상의 안정 API이다.

주요 JSON 필드:

- `timestamp`, `cpu_usage`, `core_usages`
- `ecpu_usage` / `pcpu_usage` / `scpu_usage` (freq + active)
- `gpu_usage`, `gpu_metrics.freq_mhz`, `gpu_metrics.active_percent`
- `soc_metrics.*` (power, temps, DRAM/ANE BW, ANE active)
- `memory` (total/used/available/swap_*)
- `net_disk` (bytes/ops rates)
- `thermal_state`
- `processes[]` (pid, command, cpu_percent, gpu_ms_per_sec, memory_percent, rss_kb)
- `network_links`, `volumes`, `thunderbolt_info`, `fans`, `temperatures`, `battery`

### 4.4 장기 프로세스 규칙

- UI refresh마다 mactop을 새로 띄우지 말 것.
- Mode A라도 **하나의 long-lived** `--headless` 스트림(또는 `--count` 배치를 sampler가 소유)으로 유지.
- Mode B에서는 in-process CGO / `go build -buildmode=c-archive` + Swift bridging이 이상적이나 빌드 복잡도 큼.

---

## 5. CGO 사용 여부

**예. CGO는 필수다.** `.goreleaser.yaml`도 `CGO_ENABLED=1`, `goos: darwin`, `goarch: arm64`만 빌드한다.

| 파일 | CGO | 네이티브 코드 |
|------|-----|---------------|
| `ioreport.go` + `ioreport.m` | `#cgo CFLAGS: -x objective-c` | IOReport, SMC 연동, Wi-Fi, fans |
| `smc.c` / `smc.h` | ObjC에서 링크 | AppleSMC IOKit |
| `native_stats.go` | inline C | VM, disk, net, IOKit devices, GPU process |
| `battery.go` | inline C | IOPowerSources |
| `processes.go` | inline C | sysctl/libproc/mach |
| `sys_info.go` | CGO | sysctl helpers |
| `menubar.go/.m` | Cocoa | **제외** |
| `overlay.go/.m` | AppKit/CG | **제외** |
| `displayfps.go/.m` | CoreGraphics | **제외** |

순수 Swift 재구현으로 IOReport/SMC를 다시 짜는 것은 가능하지만 비용이 매우 크다. **v1은 Go CGO 바이너리/라이브러리 재사용이 현실적이다.**

---

## 6. 필요한 macOS Framework / 라이브러리

| Framework / lib | 용도 | v1 필요 |
|-----------------|------|---------|
| **IOKit** | SMC, power sources, devices, network media | ✅ |
| **CoreFoundation** | CF 타입, IOReport 딕셔너리 | ✅ |
| **Foundation** | ObjC 런타임 (ioreport.m) | ✅ |
| **libIOReport** (`-lIOReport`) | private-ish Apple Silicon 메트릭 | ✅ |
| **CoreWLAN** | Wi-Fi link info | ✅ (optional degrade) |
| Cocoa / AppKit | menu bar, overlay | ❌ v1 |
| CoreGraphics / ScreenCapture | FPS overlay | ❌ v1 |

권한:

- Core metrics: **sudo 불필요** (mactop README)
- Fan write: root 필요 → v1 미노출
- Screen Recording: FPS only → v1 미포함
- Full Disk Access: Mole 파일 작업용 (기존 MoleUI) — Monitor와 분리

---

## 7. 데이터 구조 매핑

### 7.1 제안 Swift `SystemMetrics`

ARCHITECTURE / IMPLEMENTATION_PLAN과 정렬:

```swift
struct SystemMetrics: Sendable {
    let timestamp: Date
    let cpuUsage: Double
    let gpuUsage: Double
    let aneUsage: Double?
    let coreUsages: [Double]
    let eCluster: ClusterMetrics?   // freqMHz + active%
    let pCluster: ClusterMetrics?
    let sCluster: ClusterMetrics?
    let memory: MemoryMetrics
    let power: PowerMetrics?
    let thermal: ThermalMetrics
    let bandwidth: BandwidthMetrics?
    let network: NetworkMetrics?
    let diskIO: DiskIOMetrics?
    let fans: [FanMetrics]          // read-only
    let battery: BatteryMetrics?
    let thunderbolt: ThunderboltMetrics?
    let processes: [ProcessMetrics]
    let systemInfo: MonitorSystemInfo
}

struct MemoryMetrics: Sendable {
    let total, used, available, swapTotal, swapUsed: UInt64
}

struct PowerMetrics: Sendable {
    let cpuW, gpuW, aneW, dramW, gpuSramW, systemW, totalW: Double
    let gpuFreqMHz: Int
}

struct ThermalMetrics: Sendable {
    let state: String               // from thermal_state
    let cpuTempC, gpuTempC, socTempC: Double?
}

struct BandwidthMetrics: Sendable {
    let dramReadGBs, dramWriteGBs, dramCombinedGBs: Double
    let aneReadGBs, aneWriteGBs: Double?
}
```

### 7.2 HeadlessOutput ↔ SystemMetrics

| Headless JSON | SystemMetrics |
|---------------|---------------|
| `timestamp` | `timestamp` |
| `cpu_usage` | `cpuUsage` |
| `gpu_usage` / `gpu_metrics` | `gpuUsage` + power.gpuFreqMHz |
| `soc_metrics.ane_active` / ANE power fallback | `aneUsage` |
| `core_usages` | `coreUsages` |
| `ecpu_usage`/`pcpu_usage`/`scpu_usage` | cluster metrics |
| `memory.*` | `memory` (+ swap) |
| `soc_metrics.*_power` | `power` |
| `soc_metrics.*_temp` + `temperatures` | `thermal` |
| `thermal_state` | `thermal.state` |
| `soc_metrics.dram_*_bw_gbs` | `bandwidth` |
| `net_disk.in/out_bytes_per_sec` | `network` |
| `net_disk.read/write_kbytes_per_sec` | `diskIO` |
| `fans` | `fans` (read-only) |
| `battery` | `battery` |
| `thunderbolt_info` | `thunderbolt` |
| `processes` | `processes` (GPU: ms/s → UI에서 % 변환 가능: `/10`) |
| `system_info` | `systemInfo` |

### 7.3 기존 MoleUI `MetricsSnapshot`과의 관계

| | Mole `MetricsSnapshot` | mactop `SystemMetrics` |
|--|------------------------|-------------------------|
| 소스 | `mole status --json` | mactop collector |
| 용도 | Dashboard / Mole health | Monitor / deep AS metrics |
| ANE / DRAM BW / GPU freq | 없음 또는 약함 | 강함 |
| Disk capacity analyze | disks[] | volumes (경량) |
| Cleanup safety | N/A | N/A |

**혼합 금지:** `MetricsModel`에 Go 파싱을 넣지 말 것. Dashboard compact card는 `MonitorModel`을 구독.

---

## 8. 예상되는 Xcode 빌드 문제

| 위험 | 설명 | 완화 |
|------|------|------|
| CGO + Xcode | Xcode는 Go/CGO를 네이티브로 모름 | Run Script로 `go build` 후 binary/xcframework 번들 |
| `-lIOReport` | SDK에 헤더가 public이 아님 | mactop처럼 심볼 선언; 링크는 시스템 dylib |
| ObjC `.m` in Go | clang 툴체인/SDK 경로 의존 | 동일 macOS/Xcode로 CI 고정 |
| Go 1.25.4 | CI에 Go 설치 필요 | `setup-go` + macos-15 runner |
| Code signing | 번들 내 실행 파일 Hardened Runtime | entitlements + sign nested binary |
| Sandbox | MoleUI entitlements와 충돌 가능 | Monitor용 최소 entitlement만 추가 |
| Universal / Intel | mactop arm64-only | arm64 slice만 번들; Intel에선 Monitor disable |
| Module size | `ioreport.m` ~3500 LOC | 전체 app.go TUI를 넣지 말 것 |
| Duplicate symbols | 여러 CGO 패키지 링크 시 | 단일 Go main/package로 archive |
| SPM 불가 | CGO Go를 SPM으로 넣기 어려움 | Vendor + script 또는 subprocess |

---

## 9. Apple Silicon 호환성 문제

| 이슈 | 상세 |
|------|------|
| Intel Mac | IOReport AMC/PMP 채널 없음 → hang 가능. `arch_check.go` 패턴을 Swift에서도 재현 (`uname` / `hw.optional.arm64`) |
| Rosetta | amd64 바이너리라도 하드웨어는 arm64일 수 있음 → sysctl 교차 확인 |
| M1–M4 vs M5 | DRAM BW / ANE 소스 채널이 다름 (AMC vs PMP). mactop이 이미 fallback 보유 |
| Fanless Mac | `fans` 빈 배열 → UI optional |
| Desktop (no battery) | `battery` omit → optional |
| Sensor 키 변동 | OS/칩마다 SMC 키 다름 → null-safe |
| Thunderbolt | `system_profiler` 호출 비용 → 샘플마다 말고 주기적 refresh (mactop도 warmup/캐시) |

Mole X 시작 시:

1. arch 감지  
2. arm64 → Monitor enable  
3. Intel → Mole 기능만, Monitor unavailable 메시지  

앱 전체 초기화를 Monitor 실패로 막지 말 것.

---

## 10. 라이선스 / 저작권 처리

| 프로젝트 | 라이선스 | Copyright |
|----------|----------|-----------|
| MoleUI | MIT | Fuyao Qin (2026) |
| mactop v2 | MIT | Carsen Klock (2024-2026) |

필수 조치:

1. `Vendor/mactop/LICENSE` 또는 `ThirdParty/mactop-NOTICE` 유지  
2. 앱 About / Docs에 attribution  
3. import 파일 목록을 이 문서(또는 `docs/reference/mactopImportManifest.md`)에 기록  
4. mactop 코드를 “신규 작성”으로 주장하지 말 것  
5. 메이저 릴리스 전 upstream LICENSE 재확인  
6. 파일 헤더의 Carsen Klock 저작권 주석 유지 (ioreport.go 등)

gotui / prometheus / toon 등 의존성은 Mode A(바이너리 번들)에서는 바이너리 안에 포함. Mode B(소스 임베드) 시 TUI 의존성(`gotui`, tcell)은 **제외 빌드 태그**로 제거하는 것이 이상적.

---

## 11. 가장 안전한 통합 방법

### 11.1 원칙

1. **MoleUI 호스트 유지** — Git history merge 없음  
2. **Monitor는 별도 서브시스템** — `CLIExecutor` / `MetricsModel`에 침투 금지  
3. **UI 먼저, native bridge 나중** — Mode A → Mode B  
4. **작은 커밋** — MERGE_PLAN 시퀀스 준수  
5. **Fan write / auto-kill / FPS / Prometheus / TUI 제외**

### 11.2 권장 실행 순서

```
1. feature/mactop-monitor 브랜치
2. Swift SystemMetrics + Codable(HeadlessOutput 호환) 추가 (새 파일만)
3. MactopAdapter 프로토콜 + HeadlessJSONAdapter
4. Resources에 arm64 mactop 바이너리 번들 (Mole CLI와 동일 패턴의 copy script)
5. MonitorService: 장기 프로세스 또는 소유된 샘플 루프 (1s), history store
6. MonitorView / ProcessListView / Sidebar 항목 (최소 diff)
7. Dashboard compact card → MonitorModel 구독
8. Apple Silicon capability gate
9. 테스트: JSON fixture decode, Intel path, adapter failure degrade
10. (이후) embedded collector로 교체 — Adapter만 교체, UI 유지
```

### 11.3 안전하지 않은 방법 (하지 말 것)

- `MetricsModel.fetchMetrics()`를 mactop으로 교체해 Mole status 제거  
- 매 SwiftUI redraw마다 `mactop` 실행  
- `app.go` / TUI / overlay 전체를 Vendor에 넣고 빌드  
- Fan control UI 노출  
- Process 자동 종료  
- Go 구조체를 SwiftUI에 직접 바인딩  

### 11.4 파일 추가 예상 위치 (구현 시 — 지금은 만들지 않음)

```
MoleUI/
  Model/          # 기존 유지
  Services/       # NEW: MonitorService, MonitorSampler, MonitorHistoryStore
  MonitorCore/    # NEW: MactopAdapter, HeadlessJSONAdapter, ...
  Models/         # NEW: SystemMetrics, ...
  View/MonitorView.swift, ProcessListView.swift  # NEW
Resources/mactop/ # NEW: bundled arm64 binary (+ LICENSE)
Vendor/mactop/    # OPTIONAL later for source embed
```

---

## 12. MoleUI 관련 파일 체크리스트 (수정 후보 — 아직 수정 금지)

구현 단계에서 **최소 diff**로 손댈 가능성이 있는 기존 파일:

| 파일 | 예상 변경 |
|------|-----------|
| `MoleApp.swift` | `MonitorModel` Environment 주입 |
| `ContentView.swift` / `SidebarView.swift` | Monitor / Processes 라우트 |
| `DashboardView.swift` | compact monitor card (MonitorModel) |
| `project.pbxproj` | 새 소스 + mactop copy script |
| `justfile` | mactop 번들/업데이트 타깃 (선택) |
| CI workflow | Go toolchain (Mode A 바이너리 프리빌드 시 불필요) |

**건드리지 말아야 할 것:** `CLIExecutor` 내부 로직, Clean/Disk/Optimize/Purge/Installer/Uninstall 모델의 Mole CLI 계약.

---

## 13. mactop 필요 vs 제외 요약표

### Include (collector / contract)

```
main.go                          # binary entry (Mode A)
internal/app/arch_check.go
internal/app/battery.go
internal/app/headless.go         # JSON contract
internal/app/ioreport.go
internal/app/ioreport.m
internal/app/smc.c
internal/app/smc.h
internal/app/metrics.go         # collection helpers (strip Prometheus server later)
internal/app/native_stats.go
internal/app/processes.go       # collection only; strip TUI later for embed
internal/app/processes_helpers.go
internal/app/sys_info.go
internal/app/thunderbolt.go
internal/app/thunderbolt_network.go
internal/app/rdma.go             # optional with Thunderbolt
internal/app/types.go            # shared structs
internal/app/globals.go          # flags/state (subset)
internal/app/utils.go
internal/i18n/*                  # if keeping headless stderr messages
LICENSE
```

### Exclude (TUI / extras)

```
layout.go, theme.go, colors.go, catppuccin.go, detection.go
events.go, events_helpers.go
overlay.go, overlay.m
displayfps.go, displayfps.m
menubar.go, menubar.m
profiler.go (TUI)
app.go TUI loop (keep flag definitions as reference only)
info.go UI rendering (keep sensor classification helpers if embedding)
Prometheus HTTP server paths
Party mode / terminal themes
```

---

## 14. 결론

- MoleUI는 **Mole CLI JSON 래퍼 GUI**이며 Dashboard는 이미 `mole status --json`을 쓴다.  
- mactop v2는 **CGO 기반 Apple Silicon 전용 수집기**이며 headless JSON이 가장 안전한 1차 계약이다.  
- 통합은 **호스트=MoleUI, 엔진=mactop collector**로 분리하고, TUI/팬제어/오버레이는 버린다.  
- 가장 안전한 경로: **번들 mactop `--headless` → `SystemMetrics` → Monitor UI**, 이후 동일 Adapter 뒤에서 native embed로 교체.

**다음 단계 (이 문서 승인 후):** Phase 0 baseline build/test → Phase 2 `SystemMetrics` 모델 추가 (새 파일만).

---

*Generated as analysis-only. No MoleUI application source files were modified.*
