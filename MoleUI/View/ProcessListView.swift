import SwiftUI

struct ProcessListView: View {
    @Environment(MonitorModel.self) private var monitor

    @State private var searchText = ""
    @State private var sortColumn: ProcessSortColumn = .cpu
    @State private var sortAscending = false
    @State private var processPendingTerminate: ProcessMetrics?
    @State private var actionError: String?

    private enum ProcessSortColumn: String, CaseIterable {
        case name = "Process"
        case pid = "PID"
        case cpu = "CPU"
        case memory = "Memory"
        case gpu = "GPU"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !monitor.isSupported {
                ContentUnavailableView(
                    "Apple Silicon Required",
                    systemImage: "cpu",
                    description: Text("Process GPU metrics require Apple Silicon monitoring.")
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
            } else {
                VStack(spacing: 0) {
                    if let title = monitor.runtimeStatus.bannerTitle,
                       let message = monitor.runtimeStatus.bannerMessage
                    {
                        MonitorStatusBanner(
                            title: title,
                            message: message,
                            isRetryable: monitor.runtimeStatus.isRetryable,
                            onRetry: { monitor.retry() }
                        )
                        .padding(12)
                    }
                    processTable
                }
            }
        }
        .task {
            monitor.start()
        }
        .alert(
            "Terminate process?",
            isPresented: Binding(
                get: { processPendingTerminate != nil },
                set: {
                    if !$0 {
                        processPendingTerminate = nil
                    }
                }
            ),
            presenting: processPendingTerminate
        ) { proc in
            Button("Cancel", role: .cancel) {
                processPendingTerminate = nil
            }
            Button("Terminate", role: .destructive) {
                terminate(proc)
            }
        } message: { proc in
            Text("Send SIGTERM to \(proc.command) (PID \(proc.pid))?")
        }
        .alert(
            "Terminate failed",
            isPresented: Binding(
                get: { actionError != nil },
                set: {
                    if !$0 {
                        actionError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            MoleHeroPanel(
                eyebrow: "Monitor",
                title: "Processes",
                subtitle: "Search, sort, and terminate with confirmation. No automatic killing.",
                symbol: "list.bullet.rectangle"
            )

            HStack(spacing: 12) {
                MoleSearchField(prompt: "Filter processes", text: $searchText)
                Button {
                    monitor.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private var processTable: some View {
        let rows = filteredSortedProcesses
        return Group {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No Processes",
                    systemImage: "magnifyingglass",
                    description: Text(monitor.latestMetrics == nil ? "Waiting for monitor sample…" : "No matches.")
                )
            } else {
                Table(rows) {
                    TableColumn(ProcessSortColumn.name.rawValue) { (proc: ProcessMetrics) in
                        Text(proc.command)
                            .lineLimit(1)
                            .help(proc.command)
                    }
                    .width(min: 160, ideal: 240)

                    TableColumn(ProcessSortColumn.pid.rawValue) { proc in
                        Text("\(proc.pid)")
                            .monospacedDigit()
                    }
                    .width(60)

                    TableColumn(ProcessSortColumn.cpu.rawValue) { proc in
                        Text(String(format: "%.1f%%", proc.cpuPercent))
                            .monospacedDigit()
                    }
                    .width(70)

                    TableColumn(ProcessSortColumn.memory.rawValue) { proc in
                        Text(String(format: "%.1f%%", proc.memoryPercent))
                            .monospacedDigit()
                    }
                    .width(80)

                    TableColumn(ProcessSortColumn.gpu.rawValue) { proc in
                        // Headless reports GPU as ms/s; display as approximate %.
                        Text(String(format: "%.1f%%", proc.gpuMsPerSec / 10.0))
                            .monospacedDigit()
                    }
                    .width(70)

                    TableColumn("RSS") { proc in
                        Text(MetricsFormatter.humanBytes(UInt64(max(0, proc.rssKB)) * 1024))
                            .monospacedDigit()
                    }
                    .width(90)

                    TableColumn("") { proc in
                        Button("Terminate") {
                            processPendingTerminate = proc
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(MoleTheme.ember)
                    }
                    .width(100)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    sortBar
                }
            }
        }
    }

    private var sortBar: some View {
        HStack(spacing: 8) {
            Text("Sort")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Sort", selection: $sortColumn) {
                ForEach(ProcessSortColumn.allCases, id: \.self) { column in
                    Text(column.rawValue).tag(column)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Button {
                sortAscending.toggle()
            } label: {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
            }
            .buttonStyle(.borderless)
            .help("Toggle sort direction")

            Spacer()
            Text("\(filteredSortedProcesses.count) processes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var filteredSortedProcesses: [ProcessMetrics] {
        let source = monitor.latestMetrics?.processes ?? []
        let filtered: [ProcessMetrics]
        if searchText.isEmpty {
            filtered = source
        } else {
            let q = searchText.lowercased()
            filtered = source.filter {
                $0.command.lowercased().contains(q) || "\($0.pid)".contains(q)
            }
        }

        return filtered.sorted { lhs, rhs in
            let ascending = sortAscending
            let result: Bool = switch sortColumn {
            case .name:
                lhs.command.localizedCaseInsensitiveCompare(rhs.command) == .orderedAscending
            case .pid:
                lhs.pid < rhs.pid
            case .cpu:
                lhs.cpuPercent < rhs.cpuPercent
            case .memory:
                lhs.memoryPercent < rhs.memoryPercent
            case .gpu:
                lhs.gpuMsPerSec < rhs.gpuMsPerSec
            }
            return ascending ? result : !result
        }
    }

    private func terminate(_ proc: ProcessMetrics) {
        do {
            try ProcessService.terminate(pid: proc.pid)
            processPendingTerminate = nil
        } catch {
            processPendingTerminate = nil
            actionError = error.localizedDescription
        }
    }
}
