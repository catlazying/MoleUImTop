import Foundation

// MARK: - SystemMetrics (mactop v2 HeadlessOutput sample)

/// One immutable sample from mactop `--headless` JSON (NDJSON object per line).
/// Field names and types match metaspartan/mactop `HeadlessOutput` / nested structs.
struct SystemMetrics: Decodable, Sendable, Equatable {
    let timestamp: Date
    let socMetrics: SocMetrics
    let memory: MemoryMetrics
    let netDisk: NetDiskMetrics
    let cpuUsage: Double
    let eCluster: ClusterMetrics?
    let pCluster: ClusterMetrics?
    let sCluster: ClusterMetrics?
    let gpuUsage: Double
    let gpuMetrics: GPUMetrics
    let tflopsFP32: Double?
    let tflopsFP16: Double?
    let displayFPS: UInt32?
    let frameIntervalMs: Double?
    let coreUsages: [Double]
    let systemInfo: MonitorSystemInfo
    let thermalState: String
    let processes: [ProcessMetrics]
    let networkLinks: NetworkLinksMetrics?
    let volumes: [VolumeMetrics]
    let thunderbolt: ThunderboltMetrics?
    let tbNetTotalBytesInPerSec: Double?
    let tbNetTotalBytesOutPerSec: Double?
    let rdmaStatus: RDMAStatusMetrics?
    let fans: [FanMetrics]
    let temperatures: [TemperatureGroupMetrics]
    let battery: BatteryMetrics?

    /// Convenience: ANE utilization when available (`soc_metrics.ane_active`).
    var aneUsage: Double? {
        socMetrics.aneActive > 0 ? socMetrics.aneActive : nil
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case socMetrics = "soc_metrics"
        case memory
        case netDisk = "net_disk"
        case cpuUsage = "cpu_usage"
        case eCluster = "ecpu_usage"
        case pCluster = "pcpu_usage"
        case sCluster = "scpu_usage"
        case gpuUsage = "gpu_usage"
        case gpuMetrics = "gpu_metrics"
        case tflopsFP32 = "tflops_fp32"
        case tflopsFP16 = "tflops_fp16"
        case displayFPS = "display_fps"
        case frameIntervalMs = "frame_interval_ms"
        case coreUsages = "core_usages"
        case systemInfo = "system_info"
        case thermalState = "thermal_state"
        case processes
        case networkLinks = "network_links"
        case volumes
        case thunderbolt = "thunderbolt_info"
        case tbNetTotalBytesInPerSec = "tb_net_total_bytes_in_per_sec"
        case tbNetTotalBytesOutPerSec = "tb_net_total_bytes_out_per_sec"
        case rdmaStatus = "rdma_status"
        case fans
        case temperatures
        case battery
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try Self.decodeTimestamp(from: c)
        self.socMetrics = try c.decode(SocMetrics.self, forKey: .socMetrics)
        self.memory = try c.decode(MemoryMetrics.self, forKey: .memory)
        self.netDisk = try c.decode(NetDiskMetrics.self, forKey: .netDisk)
        self.cpuUsage = try c.decode(Double.self, forKey: .cpuUsage)
        self.eCluster = try c.decodeIfPresent(ClusterMetrics.self, forKey: .eCluster)
        self.pCluster = try c.decodeIfPresent(ClusterMetrics.self, forKey: .pCluster)
        self.sCluster = try c.decodeIfPresent(ClusterMetrics.self, forKey: .sCluster)
        self.gpuUsage = try c.decode(Double.self, forKey: .gpuUsage)
        self.gpuMetrics = try c.decode(GPUMetrics.self, forKey: .gpuMetrics)
        self.tflopsFP32 = try c.decodeIfPresent(Double.self, forKey: .tflopsFP32)
        self.tflopsFP16 = try c.decodeIfPresent(Double.self, forKey: .tflopsFP16)
        self.displayFPS = try c.decodeIfPresent(UInt32.self, forKey: .displayFPS)
        self.frameIntervalMs = try c.decodeIfPresent(Double.self, forKey: .frameIntervalMs)
        self.coreUsages = try c.decodeIfPresent([Double].self, forKey: .coreUsages) ?? []
        self.systemInfo = try c.decode(MonitorSystemInfo.self, forKey: .systemInfo)
        self.thermalState = try c.decode(String.self, forKey: .thermalState)
        self.processes = try c.decodeIfPresent([ProcessMetrics].self, forKey: .processes) ?? []
        self.networkLinks = try c.decodeIfPresent(NetworkLinksMetrics.self, forKey: .networkLinks)
        self.volumes = try c.decodeIfPresent([VolumeMetrics].self, forKey: .volumes) ?? []
        self.thunderbolt = try c.decodeIfPresent(ThunderboltMetrics.self, forKey: .thunderbolt)
        self.tbNetTotalBytesInPerSec = try c.decodeIfPresent(Double.self, forKey: .tbNetTotalBytesInPerSec)
        self.tbNetTotalBytesOutPerSec = try c.decodeIfPresent(Double.self, forKey: .tbNetTotalBytesOutPerSec)
        self.rdmaStatus = try c.decodeIfPresent(RDMAStatusMetrics.self, forKey: .rdmaStatus)
        self.fans = try c.decodeIfPresent([FanMetrics].self, forKey: .fans) ?? []
        self.temperatures = try c.decodeIfPresent([TemperatureGroupMetrics].self, forKey: .temperatures) ?? []
        self.battery = try c.decodeIfPresent(BatteryMetrics.self, forKey: .battery)
    }

    init(
        timestamp: Date,
        socMetrics: SocMetrics,
        memory: MemoryMetrics,
        netDisk: NetDiskMetrics,
        cpuUsage: Double,
        eCluster: ClusterMetrics?,
        pCluster: ClusterMetrics?,
        sCluster: ClusterMetrics?,
        gpuUsage: Double,
        gpuMetrics: GPUMetrics,
        tflopsFP32: Double? = nil,
        tflopsFP16: Double? = nil,
        displayFPS: UInt32? = nil,
        frameIntervalMs: Double? = nil,
        coreUsages: [Double],
        systemInfo: MonitorSystemInfo,
        thermalState: String,
        processes: [ProcessMetrics] = [],
        networkLinks: NetworkLinksMetrics? = nil,
        volumes: [VolumeMetrics] = [],
        thunderbolt: ThunderboltMetrics? = nil,
        tbNetTotalBytesInPerSec: Double? = nil,
        tbNetTotalBytesOutPerSec: Double? = nil,
        rdmaStatus: RDMAStatusMetrics? = nil,
        fans: [FanMetrics] = [],
        temperatures: [TemperatureGroupMetrics] = [],
        battery: BatteryMetrics? = nil
    ) {
        self.timestamp = timestamp
        self.socMetrics = socMetrics
        self.memory = memory
        self.netDisk = netDisk
        self.cpuUsage = cpuUsage
        self.eCluster = eCluster
        self.pCluster = pCluster
        self.sCluster = sCluster
        self.gpuUsage = gpuUsage
        self.gpuMetrics = gpuMetrics
        self.tflopsFP32 = tflopsFP32
        self.tflopsFP16 = tflopsFP16
        self.displayFPS = displayFPS
        self.frameIntervalMs = frameIntervalMs
        self.coreUsages = coreUsages
        self.systemInfo = systemInfo
        self.thermalState = thermalState
        self.processes = processes
        self.networkLinks = networkLinks
        self.volumes = volumes
        self.thunderbolt = thunderbolt
        self.tbNetTotalBytesInPerSec = tbNetTotalBytesInPerSec
        self.tbNetTotalBytesOutPerSec = tbNetTotalBytesOutPerSec
        self.rdmaStatus = rdmaStatus
        self.fans = fans
        self.temperatures = temperatures
        self.battery = battery
    }

    private static func decodeTimestamp(from c: KeyedDecodingContainer<CodingKeys>) throws -> Date {
        let raw = try c.decode(String.self, forKey: .timestamp)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            forKey: .timestamp,
            in: c,
            debugDescription: "Invalid timestamp"
        )
    }
}

// MARK: - Nested types

/// E/P/S cluster pair from headless `ecpu_usage` / `pcpu_usage` / `scpu_usage`: [freq_mhz, active_percent]
struct ClusterMetrics: Decodable, Sendable, Equatable {
    let frequencyMHz: Double
    let activePercent: Double

    init(frequencyMHz: Double, activePercent: Double) {
        self.frequencyMHz = frequencyMHz
        self.activePercent = activePercent
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.frequencyMHz = try container.decode(Double.self)
        self.activePercent = try container.decode(Double.self)
    }
}

struct SocMetrics: Decodable, Sendable, Equatable {
    let cpuPower: Double
    let gpuPower: Double
    let anePower: Double
    let dramPower: Double
    let gpuSramPower: Double
    let systemPower: Double
    let totalPower: Double
    let gpuFreqMHz: Int
    let gpuActive: Double
    let eClusterActive: Double
    let pClusterActive: Double
    let sClusterActive: Double?
    let eClusterFreqMHz: Int
    let pClusterFreqMHz: Int
    let sClusterFreqMHz: Int?
    let socTemp: Double
    let cpuTemp: Double
    let gpuTemp: Double
    let dramReadBWGBs: Double
    let dramWriteBWGBs: Double
    let dramBWCombinedGBs: Double
    let aneReadBWGBs: Double
    let aneWriteBWGBs: Double
    let aneBWCombinedGBs: Double
    let aneActive: Double

    enum CodingKeys: String, CodingKey {
        case cpuPower = "cpu_power"
        case gpuPower = "gpu_power"
        case anePower = "ane_power"
        case dramPower = "dram_power"
        case gpuSramPower = "gpu_sram_power"
        case systemPower = "system_power"
        case totalPower = "total_power"
        case gpuFreqMHz = "gpu_freq_mhz"
        case gpuActive = "gpu_active"
        case eClusterActive = "e_cluster_active"
        case pClusterActive = "p_cluster_active"
        case sClusterActive = "s_cluster_active"
        case eClusterFreqMHz = "e_cluster_freq_mhz"
        case pClusterFreqMHz = "p_cluster_freq_mhz"
        case sClusterFreqMHz = "s_cluster_freq_mhz"
        case socTemp = "soc_temp"
        case cpuTemp = "cpu_temp"
        case gpuTemp = "gpu_temp"
        case dramReadBWGBs = "dram_read_bw_gbs"
        case dramWriteBWGBs = "dram_write_bw_gbs"
        case dramBWCombinedGBs = "dram_bw_combined_gbs"
        case aneReadBWGBs = "ane_read_bw_gbs"
        case aneWriteBWGBs = "ane_write_bw_gbs"
        case aneBWCombinedGBs = "ane_bw_combined_gbs"
        case aneActive = "ane_active"
    }
}

struct MemoryMetrics: Decodable, Sendable, Equatable {
    let total: UInt64
    let used: UInt64
    let available: UInt64
    let swapTotal: UInt64
    let swapUsed: UInt64

    enum CodingKeys: String, CodingKey {
        case total, used, available
        case swapTotal = "swap_total"
        case swapUsed = "swap_used"
    }
}

struct NetDiskMetrics: Decodable, Sendable, Equatable {
    let outPacketsPerSec: Double
    let outBytesPerSec: Double
    let inPacketsPerSec: Double
    let inBytesPerSec: Double
    let readOpsPerSec: Double
    let writeOpsPerSec: Double
    let readKBytesPerSec: Double
    let writeKBytesPerSec: Double

    enum CodingKeys: String, CodingKey {
        case outPacketsPerSec = "out_packets_per_sec"
        case outBytesPerSec = "out_bytes_per_sec"
        case inPacketsPerSec = "in_packets_per_sec"
        case inBytesPerSec = "in_bytes_per_sec"
        case readOpsPerSec = "read_ops_per_sec"
        case writeOpsPerSec = "write_ops_per_sec"
        case readKBytesPerSec = "read_kbytes_per_sec"
        case writeKBytesPerSec = "write_kbytes_per_sec"
    }
}

struct GPUMetrics: Decodable, Sendable, Equatable {
    let freqMHz: Int
    let activePercent: Double

    enum CodingKeys: String, CodingKey {
        case freqMHz = "freq_mhz"
        case activePercent = "active_percent"
    }
}

struct MonitorSystemInfo: Decodable, Sendable, Equatable {
    let name: String
    let coreCount: Int
    let eCoreCount: Int?
    let pCoreCount: Int
    let sCoreCount: Int?
    let gpuCoreCount: Int

    enum CodingKeys: String, CodingKey {
        case name
        case coreCount = "core_count"
        case eCoreCount = "e_core_count"
        case pCoreCount = "p_core_count"
        case sCoreCount = "s_core_count"
        case gpuCoreCount = "gpu_core_count"
    }
}

struct ProcessMetrics: Decodable, Sendable, Equatable, Identifiable {
    let pid: Int
    let command: String
    let cpuPercent: Double
    let gpuMsPerSec: Double
    let memoryPercent: Double
    let rssKB: Int64

    var id: Int {
        pid
    }

    enum CodingKeys: String, CodingKey {
        case pid
        case command
        case cpuPercent = "cpu_percent"
        case gpuMsPerSec = "gpu_ms_per_sec"
        case memoryPercent = "memory_percent"
        case rssKB = "rss_kb"
    }
}

struct NetworkLinksMetrics: Decodable, Sendable, Equatable {
    let ethernet: [EthernetLinkMetrics]
    let wifi: WiFiLinkMetrics?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ethernet = try c.decodeIfPresent([EthernetLinkMetrics].self, forKey: .ethernet) ?? []
        self.wifi = try c.decodeIfPresent(WiFiLinkMetrics.self, forKey: .wifi)
    }

    enum CodingKeys: String, CodingKey {
        case ethernet, wifi
    }
}

struct EthernetLinkMetrics: Decodable, Sendable, Equatable {
    let name: String
    let linkUp: Bool
    let speedMbps: UInt64
    let speedFormatted: String

    enum CodingKeys: String, CodingKey {
        case name
        case linkUp = "link_up"
        case speedMbps = "speed_mbps"
        case speedFormatted = "speed_formatted"
    }
}

struct WiFiLinkMetrics: Decodable, Sendable, Equatable {
    let interface: String
    let phyMode: String
    let generation: String
    let txRateMbps: Int
    let connected: Bool

    enum CodingKeys: String, CodingKey {
        case interface
        case phyMode = "phy_mode"
        case generation
        case txRateMbps = "tx_rate_mbps"
        case connected
    }
}

struct VolumeMetrics: Decodable, Sendable, Equatable {
    let name: String
    let totalGB: Double
    let usedGB: Double
    let usedPercent: Double

    enum CodingKeys: String, CodingKey {
        case name
        case totalGB = "total_gb"
        case usedGB = "used_gb"
        case usedPercent = "used_percent"
    }
}

struct FanMetrics: Decodable, Sendable, Equatable, Identifiable {
    let id: Int
    let name: String
    let rpm: Int
    let targetRPM: Int
    let minRPM: Int
    let maxRPM: Int
    let mode: String

    enum CodingKeys: String, CodingKey {
        case id, name, rpm, mode
        case targetRPM = "target_rpm"
        case minRPM = "min_rpm"
        case maxRPM = "max_rpm"
    }
}

struct TemperatureGroupMetrics: Decodable, Sendable, Equatable {
    let group: String
    let avgCelsius: Double
    let minCelsius: Double
    let maxCelsius: Double
    let sensorCount: Int

    enum CodingKeys: String, CodingKey {
        case group
        case avgCelsius = "avg_celsius"
        case minCelsius = "min_celsius"
        case maxCelsius = "max_celsius"
        case sensorCount = "sensor_count"
    }
}

struct BatteryMetrics: Decodable, Sendable, Equatable {
    let present: Bool
    let percent: Int?
    let charging: Bool
    let onACPower: Bool
    let state: String

    enum CodingKeys: String, CodingKey {
        case present, percent, charging, state
        case onACPower = "on_ac_power"
    }
}

struct ThunderboltMetrics: Decodable, Sendable, Equatable {
    let buses: [ThunderboltBusMetrics]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.buses = try c.decodeIfPresent([ThunderboltBusMetrics].self, forKey: .buses) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case buses
    }
}

struct ThunderboltBusMetrics: Decodable, Sendable, Equatable {
    let name: String
    let status: String
    let icon: String?
    let speed: String?
    let domainUUID: String?
    let switchUID: String?
    let receptacleID: String?
    let devices: [ThunderboltDeviceMetrics]
    let networkStats: ThunderboltNetStatsMetrics?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.status = try c.decode(String.self, forKey: .status)
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.speed = try c.decodeIfPresent(String.self, forKey: .speed)
        self.domainUUID = try c.decodeIfPresent(String.self, forKey: .domainUUID)
        self.switchUID = try c.decodeIfPresent(String.self, forKey: .switchUID)
        self.receptacleID = try c.decodeIfPresent(String.self, forKey: .receptacleID)
        self.devices = try c.decodeIfPresent([ThunderboltDeviceMetrics].self, forKey: .devices) ?? []
        self.networkStats = try c.decodeIfPresent(ThunderboltNetStatsMetrics.self, forKey: .networkStats)
    }

    enum CodingKeys: String, CodingKey {
        case name, status, icon, speed, devices
        case domainUUID = "domain_uuid"
        case switchUID = "switch_uid"
        case receptacleID = "receptacle_id"
        case networkStats = "network_stats"
    }
}

struct ThunderboltDeviceMetrics: Decodable, Sendable, Equatable {
    let name: String
    let vendor: String?
    let vendorID: String?
    let mode: String?
    let switchUID: String?
    let deviceID: String?
    let domainUUID: String?
    let info: String?

    enum CodingKeys: String, CodingKey {
        case name, vendor, mode, info
        case vendorID = "vendor_id"
        case switchUID = "switch_uid"
        case deviceID = "device_id"
        case domainUUID = "domain_uuid"
    }
}

struct ThunderboltNetStatsMetrics: Decodable, Sendable, Equatable {
    let interfaceName: String
    let bytesIn: UInt64
    let bytesOut: UInt64
    let bytesInPerSec: Double
    let bytesOutPerSec: Double
    let packetsIn: UInt64
    let packetsOut: UInt64

    enum CodingKeys: String, CodingKey {
        case interfaceName = "interface_name"
        case bytesIn = "bytes_in"
        case bytesOut = "bytes_out"
        case bytesInPerSec = "bytes_in_per_sec"
        case bytesOutPerSec = "bytes_out_per_sec"
        case packetsIn = "packets_in"
        case packetsOut = "packets_out"
    }
}

struct RDMAStatusMetrics: Decodable, Sendable, Equatable {
    let available: Bool
    let status: String
}

// MARK: - Decoding helpers

enum SystemMetricsDecoder {
    static func makeJSONDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    /// Decode a single headless sample object.
    static func decodeSample(from data: Data) throws -> SystemMetrics {
        try makeJSONDecoder().decode(SystemMetrics.self, from: data)
    }

    /// Decode `--count N` array output (`[{...}, ...]`) or a single object.
    static func decodeSamples(from data: Data) throws -> [SystemMetrics] {
        let decoder = makeJSONDecoder()
        if let array = try? decoder.decode([SystemMetrics].self, from: data) {
            return array
        }
        return try [decoder.decode(SystemMetrics.self, from: data)]
    }
}
