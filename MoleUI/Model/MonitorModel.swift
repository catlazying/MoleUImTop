import Foundation
import Observation

/// Observable façade for SwiftUI (Monitor UI comes later).
/// Kept separate from `MetricsModel` / Mole CLI dashboard state.
@Observable @MainActor
final class MonitorModel {
    private(set) var isSupported: Bool
    private(set) var isRunning = false
    private(set) var latestMetrics: SystemMetrics?
    private(set) var errorMessage: String?
    private(set) var historyCount = 0
    private(set) var availabilityNotices: [String] = []
    private(set) var runtimeStatus: MonitorRuntimeStatus = .idle

    /// Recent samples for charts (bounded by history store).
    private(set) var recentHistory: [SystemMetrics] = []

    var cpuHistory: [Double] {
        recentHistory.map(\.cpuUsage)
    }

    var gpuHistory: [Double] {
        recentHistory.map(\.gpuUsage)
    }

    var memoryHistory: [Double] {
        recentHistory.map { sample in
            guard sample.memory.total > 0 else { return 0 }
            return Double(sample.memory.used) / Double(sample.memory.total) * 100
        }
    }

    var powerHistory: [Double] {
        recentHistory.map(\.socMetrics.totalPower)
    }

    var temperatureHistory: [Double] {
        recentHistory.map(\.socMetrics.cpuTemp)
    }

    var dramBandwidthHistory: [Double] {
        recentHistory.map(\.socMetrics.dramBWCombinedGBs)
    }

    private let service: MonitorService
    private var syncTask: Task<Void, Never>?
    /// Adapter retained only for test injection across retry.
    private var injectedAdapter: (any MactopAdapter)?

    init(service: MonitorService = MonitorService()) {
        self.service = service
        self.isSupported = AppleSiliconCapability.isSupported
        if !isSupported {
            runtimeStatus = .unsupported
            errorMessage = MonitorErrorMapper.adapterMessage(.notSupported)
        }
    }

    func start(adapter: (any MactopAdapter)? = nil) {
        if let adapter {
            injectedAdapter = adapter
        }
        guard isSupported else {
            runtimeStatus = .unsupported
            errorMessage = MonitorErrorMapper.adapterMessage(.notSupported)
            isRunning = false
            return
        }
        guard !isRunning else { return }

        runtimeStatus = .starting
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.start(adapter: injectedAdapter)
                guard !Task.isCancelled else { return }
                await refreshFromService()
                isRunning = true
                errorMessage = nil
                runtimeStatus = .running
                await pollServiceState()
            } catch is CancellationError {
                // Superseded by a newer start/stop/retry — do not poison UI state.
                return
            } catch {
                guard !Task.isCancelled else { return }
                isRunning = false
                applyFailure(error)
            }
        }
    }

    func stop() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }
            await service.stop()
            isRunning = false
            await refreshFromService()
            if case .failed = runtimeStatus {
                // keep failed status
            } else if case .degraded = runtimeStatus {
                // keep degraded status
            } else {
                runtimeStatus = .idle
            }
        }
    }

    /// Pull latest sample / history into UI without restarting the collector.
    func refresh() {
        Task { [weak self] in
            await self?.refreshFromService()
        }
    }

    /// User-initiated restart after failure / degrade.
    func retry() {
        guard isSupported else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }
            runtimeStatus = .starting
            errorMessage = nil
            do {
                try await service.retry(adapter: injectedAdapter)
                guard !Task.isCancelled else { return }
                await refreshFromService()
                isRunning = true
                runtimeStatus = .running
                await pollServiceState()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                isRunning = false
                applyFailure(error)
            }
        }
    }

    private func pollServiceState() async {
        while !Task.isCancelled {
            await refreshFromService()
            let running = await service.isRunning
            isRunning = running
            if !running {
                if let err = await service.lastError {
                    applyFailure(err)
                } else if case .running = runtimeStatus {
                    runtimeStatus = .idle
                }
                break
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func refreshFromService() async {
        latestMetrics = await service.latestMetrics
        let store = await service.history()
        historyCount = store.count
        recentHistory = store.recent()
        if let metrics = latestMetrics {
            availabilityNotices = MonitorErrorMapper.availabilityNotices(for: metrics)
        } else {
            availabilityNotices = []
        }
        if let err = await service.lastError, await service.isRunning == false {
            applyFailure(err)
        } else if isRunning, errorMessage == nil {
            runtimeStatus = .running
        }
    }

    private func applyFailure(_ error: Error) {
        let message = MonitorErrorMapper.userMessage(for: error)
        errorMessage = message
        if latestMetrics != nil {
            runtimeStatus = .degraded(message: message)
        } else {
            runtimeStatus = .failed(message: message)
        }
    }
}
