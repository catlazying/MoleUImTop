import SwiftUI

/// Apple Silicon hardware monitor (mactop-backed). Separate from Mole Status dashboard.
struct MonitorView: View {
    @Environment(MonitorModel.self) private var monitor

    var body: some View {
        Group {
            if !monitor.isSupported {
                ContentUnavailableView(
                    "Apple Silicon Required",
                    systemImage: "cpu",
                    description: Text("Apple Silicon monitoring is unavailable on this Mac. Mole cleanup tools remain available.")
                )
            } else if case .failed(let message) = monitor.runtimeStatus, monitor.latestMetrics == nil {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "Monitor Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                    Button("Retry") { monitor.retry() }
                        .buttonStyle(.borderedProminent)
                }
            } else if let metrics = monitor.latestMetrics {
                ScrollView {
                    VStack(spacing: 16) {
                        statusBanners
                        header(metrics)
                        MonitorChartsSection(
                            cpu: monitor.cpuHistory,
                            gpu: monitor.gpuHistory,
                            memory: monitor.memoryHistory,
                            power: monitor.powerHistory,
                            dramBandwidth: monitor.dramBandwidthHistory
                        )
                        equalHeightRow {
                            cpuSection(metrics)
                            gpuSection(metrics)
                        }
                        equalHeightRow {
                            memorySection(metrics)
                            powerThermalSection(metrics)
                        }
                        equalHeightRow {
                            bandwidthSection(metrics)
                            ioSection(metrics)
                        }
                        if !metrics.fans.isEmpty {
                            fansSection(metrics.fans)
                        }
                        systemSection(metrics)
                    }
                    .padding()
                }
            } else {
                MoleLoadingState(
                    title: "Starting hardware monitor...",
                    subtitle: monitor.isRunning ? "Waiting for first sample" : nil
                )
            }
        }
        .task {
            monitor.start()
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusBanners: some View {
        if let title = monitor.runtimeStatus.bannerTitle,
           let message = monitor.runtimeStatus.bannerMessage
        {
            MonitorStatusBanner(
                title: title,
                message: message,
                isRetryable: monitor.runtimeStatus.isRetryable,
                onRetry: { monitor.retry() }
            )
        }
        MonitorAvailabilityNotices(notices: monitor.availabilityNotices)
    }

    // MARK: - Layout

    private func equalHeightRow(
        @ViewBuilder content: () -> TupleView<(some View, some View)>
    ) -> some View {
        let views = content()
        return HStack(alignment: .top, spacing: 12) {
            views.value.0.frame(maxHeight: .infinity, alignment: .top)
            views.value.1.frame(maxHeight: .infinity, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func header(_ m: SystemMetrics) -> some View {
        MoleHeroPanel(
            eyebrow: "Monitor",
            title: m.systemInfo.name,
            subtitle: "\(m.systemInfo.coreCount) cores · GPU \(m.systemInfo.gpuCoreCount) · \(m.thermalState)",
            symbol: "gauge.with.dots.needle.67percent"
        ) {
            VStack(alignment: .trailing, spacing: 10) {
                MoleMetricBadge(
                    title: "CPU",
                    value: String(format: "%.0f%%", m.cpuUsage),
                    systemImage: "cpu",
                    tint: MoleTheme.pine
                )
                MoleMetricBadge(
                    title: "GPU",
                    value: String(format: "%.0f%%", m.gpuUsage),
                    systemImage: "rectangle.3.group",
                    tint: MoleTheme.sky
                )
            }
        }
    }

    // MARK: - Sections

    private func cpuSection(_ m: SystemMetrics) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("CPU", systemImage: "cpu").font(.headline)
                metricRow("Total", String(format: "%.1f%%", m.cpuUsage), m.cpuUsage)
                MiniSparklineView(data: monitor.cpuHistory, color: MoleTheme.pine)
                if let e = m.eCluster {
                    Text(String(format: "E  %.0f MHz · %.0f%%", e.frequencyMHz, e.activePercent))
                        .foregroundStyle(.secondary)
                }
                if let p = m.pCluster {
                    Text(String(format: "P  %.0f MHz · %.0f%%", p.frequencyMHz, p.activePercent))
                        .foregroundStyle(.secondary)
                }
                if let s = m.sCluster {
                    Text(String(format: "S  %.0f MHz · %.0f%%", s.frequencyMHz, s.activePercent))
                        .foregroundStyle(.secondary)
                }
                if let ane = m.aneUsage {
                    metricRow("ANE", String(format: "%.1f%%", ane), ane, color: .purple)
                }
                Spacer(minLength: 0)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }

    private func gpuSection(_ m: SystemMetrics) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("GPU", systemImage: "rectangle.3.group").font(.headline)
                metricRow("Active", String(format: "%.1f%%", m.gpuUsage), m.gpuUsage, color: MoleTheme.sky)
                MiniSparklineView(data: monitor.gpuHistory, color: MoleTheme.sky)
                Text("\(m.gpuMetrics.freqMHz) MHz · \(m.systemInfo.gpuCoreCount) cores")
                    .foregroundStyle(.secondary)
                if let fps = m.displayFPS {
                    Text("Display \(fps) fps").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }

    private func memorySection(_ m: SystemMetrics) -> some View {
        let usedPct = m.memory.total > 0
            ? Double(m.memory.used) / Double(m.memory.total) * 100
            : 0
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Memory", systemImage: "memorychip").font(.headline)
                metricRow("Used", String(format: "%.1f%%", usedPct), usedPct, color: .yellow)
                MiniSparklineView(data: monitor.memoryHistory, color: .yellow)
                Text("\(MetricsFormatter.humanBytes(m.memory.used)) / \(MetricsFormatter.humanBytes(m.memory.total))")
                Text("Swap \(MetricsFormatter.humanBytes(m.memory.swapUsed)) / \(MetricsFormatter.humanBytes(m.memory.swapTotal))")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }

    private func powerThermalSection(_ m: SystemMetrics) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Power / Thermal", systemImage: "thermometer.medium").font(.headline)
                Text(String(format: "Total  %.1f W", m.socMetrics.totalPower))
                Text(String(
                    format: "CPU %.1f · GPU %.1f · ANE %.1f · DRAM %.1f",
                    m.socMetrics.cpuPower,
                    m.socMetrics.gpuPower,
                    m.socMetrics.anePower,
                    m.socMetrics.dramPower
                ))
                .foregroundStyle(.secondary)
                MiniSparklineView(data: monitor.powerHistory, color: MoleTheme.ember)
                Text(String(
                    format: "CPU %.1f°C · GPU %.1f°C · SoC %.1f°C",
                    m.socMetrics.cpuTemp,
                    m.socMetrics.gpuTemp,
                    m.socMetrics.socTemp
                ))
                Text("Thermal \(m.thermalState)")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }

    private func bandwidthSection(_ m: SystemMetrics) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("DRAM Bandwidth", systemImage: "arrow.left.arrow.right").font(.headline)
                Text(String(format: "Read   %.2f GB/s", m.socMetrics.dramReadBWGBs))
                Text(String(format: "Write  %.2f GB/s", m.socMetrics.dramWriteBWGBs))
                Text(String(format: "Total  %.2f GB/s", m.socMetrics.dramBWCombinedGBs))
                if m.socMetrics.aneBWCombinedGBs > 0.01 {
                    Text(String(format: "ANE BW %.2f GB/s", m.socMetrics.aneBWCombinedGBs))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }

    private func ioSection(_ m: SystemMetrics) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Disk / Network", systemImage: "externaldrive").font(.headline)
                Text(String(
                    format: "Disk R %.1f KB/s · W %.1f KB/s",
                    m.netDisk.readKBytesPerSec,
                    m.netDisk.writeKBytesPerSec
                ))
                Text(String(
                    format: "Net  ↓ %@ · ↑ %@",
                    MetricsFormatter.formatRate(m.netDisk.inBytesPerSec / 1_048_576),
                    MetricsFormatter.formatRate(m.netDisk.outBytesPerSec / 1_048_576)
                ))
                if let wifi = m.networkLinks?.wifi, wifi.connected {
                    Text("Wi-Fi \(wifi.generation) · \(wifi.txRateMbps) Mbps")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }

    private func fansSection(_ fans: [FanMetrics]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Fans (read-only)", systemImage: "fanblades").font(.headline)
                ForEach(fans) { fan in
                    Text("\(fan.name)  \(fan.rpm) RPM  (\(fan.mode))")
                }
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func systemSection(_ m: SystemMetrics) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label("System", systemImage: "info.circle").font(.headline)
                Text(m.systemInfo.name)
                Text("E \(m.systemInfo.eCoreCount ?? 0) · P \(m.systemInfo.pCoreCount) · S \(m.systemInfo.sCoreCount ?? 0) · GPU \(m.systemInfo.gpuCoreCount)")
                    .foregroundStyle(.secondary)
                if let bat = m.battery, bat.present {
                    let pct = bat.percent.map { "\($0)%" } ?? "—"
                    Text("Battery \(pct) · \(bat.state)")
                        .foregroundStyle(.secondary)
                }
                if let tb = m.thunderbolt {
                    Text("Thunderbolt buses: \(tb.buses.count)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricRow(
        _ title: String,
        _ value: String,
        _ percent: Double,
        color: Color = .green
    ) -> some View {
        HStack {
            Text(title).frame(width: 50, alignment: .leading)
            UsageBar(percent, color: color)
            Text(value).monospacedDigit()
        }
    }
}
