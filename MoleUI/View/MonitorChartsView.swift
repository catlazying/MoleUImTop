import Charts
import SwiftUI

/// One point in a monitor history series (already downsampled for display).
struct MonitorChartPoint: Identifiable, Sendable {
    let id: Int
    let index: Int
    let value: Double
}

enum MonitorChartSeries: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "Memory"
    case power = "Power"
    case dramBandwidth = "DRAM BW"

    var id: String {
        rawValue
    }

    var unitLabel: String {
        switch self {
        case .cpu, .gpu, .memory: "%"
        case .power: "W"
        case .dramBandwidth: "GB/s"
        }
    }

    var tint: Color {
        switch self {
        case .cpu: MoleTheme.pine
        case .gpu: MoleTheme.sky
        case .memory: .yellow
        case .power: MoleTheme.ember
        case .dramBandwidth: MoleTheme.moss
        }
    }
}

enum MonitorChartData {
    /// Downsample to at most `maxPoints` using stride averaging for SwiftUI Charts.
    static func downsample(_ values: [Double], maxPoints: Int = 90) -> [MonitorChartPoint] {
        guard !values.isEmpty else { return [] }
        if values.count <= maxPoints {
            return values.enumerated().map { MonitorChartPoint(id: $0.offset, index: $0.offset, value: $0.element) }
        }
        let bucketSize = Double(values.count) / Double(maxPoints)
        var points: [MonitorChartPoint] = []
        points.reserveCapacity(maxPoints)
        for i in 0 ..< maxPoints {
            let start = Int((Double(i) * bucketSize).rounded(.down))
            let end = min(values.count, Int((Double(i + 1) * bucketSize).rounded(.down)))
            guard start < end else { continue }
            let slice = values[start ..< end]
            let avg = slice.reduce(0, +) / Double(slice.count)
            points.append(MonitorChartPoint(id: i, index: i, value: avg))
        }
        return points
    }
}

struct MonitorHistoryChart: View {
    let title: String
    let unitLabel: String
    let values: [Double]
    let tint: Color
    var yDomain: ClosedRange<Double>?

    private var points: [MonitorChartPoint] {
        MonitorChartData.downsample(values)
    }

    private var resolvedDomain: ClosedRange<Double> {
        if let yDomain {
            return yDomain
        }
        let maxValue = points.map(\.value).max() ?? 1
        let ceiling = max(maxValue * 1.15, 1)
        return 0 ... ceiling
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                if let last = values.last {
                    Text(formatted(last))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if points.count < 2 {
                Text("Collecting history…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("t", point.index),
                        y: .value(unitLabel, point.value)
                    )
                    .foregroundStyle(tint)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("t", point.index),
                        y: .value(unitLabel, point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.28), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYScale(domain: resolvedDomain)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(MoleTheme.line)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(shortAxis(v))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MoleTheme.line, lineWidth: 1)
        )
    }

    private func formatted(_ value: Double) -> String {
        switch unitLabel {
        case "%":
            String(format: "%.1f%%", value)
        case "W":
            String(format: "%.1f W", value)
        case "GB/s":
            String(format: "%.2f GB/s", value)
        default:
            String(format: "%.2f %@", value, unitLabel)
        }
    }

    private func shortAxis(_ value: Double) -> String {
        if unitLabel == "%" {
            return String(format: "%.0f", value)
        }
        if value >= 10 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

struct MonitorChartsSection: View {
    let cpu: [Double]
    let gpu: [Double]
    let memory: [Double]
    let power: [Double]
    let dramBandwidth: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MoleSectionHeader(
                title: "History",
                subtitle: "Bounded in-memory samples · ~5 minutes at 1s",
                symbol: "chart.xyaxis.line"
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                MonitorHistoryChart(
                    title: "CPU",
                    unitLabel: "%",
                    values: cpu,
                    tint: MonitorChartSeries.cpu.tint,
                    yDomain: 0 ... 100
                )
                MonitorHistoryChart(
                    title: "GPU",
                    unitLabel: "%",
                    values: gpu,
                    tint: MonitorChartSeries.gpu.tint,
                    yDomain: 0 ... 100
                )
                MonitorHistoryChart(
                    title: "Memory",
                    unitLabel: "%",
                    values: memory,
                    tint: MonitorChartSeries.memory.tint,
                    yDomain: 0 ... 100
                )
                MonitorHistoryChart(
                    title: "Power",
                    unitLabel: "W",
                    values: power,
                    tint: MonitorChartSeries.power.tint
                )
                MonitorHistoryChart(
                    title: "DRAM Bandwidth",
                    unitLabel: "GB/s",
                    values: dramBandwidth,
                    tint: MonitorChartSeries.dramBandwidth.tint
                )
                .gridCellColumns(2)
            }
        }
    }
}
