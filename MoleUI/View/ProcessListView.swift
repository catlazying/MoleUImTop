import SwiftUI

struct ProcessListView: View {
    @Environment(MonitorModel.self) private var monitor
    @Environment(LocalizationStore.self) private var localization

    @State private var searchText = ""
    @State private var sortColumn: ProcessSortColumn = .cpu
    @State private var sortAscending = false
    @State private var processPendingTerminate: ProcessMetrics?
    @State private var actionError: String?

    private enum ProcessSortColumn: String, CaseIterable {
        case name
        case pid
        case cpu
        case memory
        case gpu

        var titleKey: String {
            switch self {
            case .name: "processes.col.process"
            case .pid: "processes.col.pid"
            case .cpu: "processes.col.cpu"
            case .memory: "processes.col.memory"
            case .gpu: "processes.col.gpu"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !monitor.isSupported {
                ContentUnavailableView(
                    localization.t("processes.required.title"),
                    systemImage: "cpu",
                    description: Text(localization.t("processes.required.detail"))
                )
            } else if case .failed(let message) = monitor.runtimeStatus, monitor.latestMetrics == nil {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        localization.t("processes.unavailable.title"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                    Button(localization.t("monitor.retry")) { monitor.retry() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 0) {
                    if let titleKey = monitor.runtimeStatus.bannerTitleKey {
                        let message = monitor.runtimeStatus.bannerMessageKey.map { localization.t($0) }
                            ?? monitor.runtimeStatus.bannerMessage
                            ?? ""
                        MonitorStatusBanner(
                            title: localization.t(titleKey),
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
            localization.t("processes.terminate.title"),
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
            Button(localization.t("processes.terminate.cancel"), role: .cancel) {
                processPendingTerminate = nil
            }
            Button(localization.t("processes.terminate.confirm"), role: .destructive) {
                terminate(proc)
            }
        } message: { proc in
            Text("Send SIGTERM to \(proc.command) (PID \(proc.pid))?")
        }
        .alert(
            localization.t("processes.terminate.failed"),
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
                eyebrow: localization.t("processes.hero.eyebrow"),
                title: localization.t("processes.hero.title"),
                subtitle: localization.t("processes.hero.subtitle"),
                symbol: "list.bullet.rectangle"
            )

            HStack(spacing: 12) {
                MoleSearchField(prompt: localization.t("processes.filter"), text: $searchText)
                Button {
                    monitor.refresh()
                } label: {
                    Label(localization.t("processes.refresh"), systemImage: "arrow.clockwise")
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
                    localization.t("processes.empty.title"),
                    systemImage: "magnifyingglass",
                    description: Text(
                        monitor.latestMetrics == nil
                            ? localization.t("processes.empty.waiting")
                            : localization.t("processes.empty.none")
                    )
                )
            } else {
                Table(rows) {
                    TableColumn(localization.t(ProcessSortColumn.name.titleKey)) { (proc: ProcessMetrics) in
                        Text(proc.command)
                            .lineLimit(1)
                            .help(proc.command)
                    }
                    .width(min: 160, ideal: 240)

                    TableColumn(localization.t(ProcessSortColumn.pid.titleKey)) { proc in
                        Text("\(proc.pid)")
                            .monospacedDigit()
                    }
                    .width(60)

                    TableColumn(localization.t(ProcessSortColumn.cpu.titleKey)) { proc in
                        Text(String(format: "%.1f%%", proc.cpuPercent))
                            .monospacedDigit()
                    }
                    .width(70)

                    TableColumn(localization.t(ProcessSortColumn.memory.titleKey)) { proc in
                        Text(String(format: "%.1f%%", proc.memoryPercent))
                            .monospacedDigit()
                    }
                    .width(80)

                    TableColumn(localization.t(ProcessSortColumn.gpu.titleKey)) { proc in
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
                        Button(localization.t("processes.terminate.confirm")) {
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
                    Text(localization.t(column.titleKey)).tag(column)
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
