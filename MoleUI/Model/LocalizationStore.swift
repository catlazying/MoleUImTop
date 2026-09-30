import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case korean

    var id: String { rawValue }

    var displayNameKey: String {
        switch self {
        case .system: "lang.system"
        case .english: "lang.english"
        case .korean: "lang.korean"
        }
    }
}

@Observable @MainActor
final class LocalizationStore {
    private static let defaultsKey = "moleui.appLanguage"

    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
           let saved = AppLanguage(rawValue: raw)
        {
            language = saved
        } else {
            language = .system
        }
    }

    var resolvedIsKorean: Bool {
        switch language {
        case .korean:
            true
        case .english:
            false
        case .system:
            Locale.preferredLanguages.first?.hasPrefix("ko") == true
        }
    }

    func t(_ key: String) -> String {
        let table = resolvedIsKorean ? Self.ko : Self.en
        return table[key] ?? Self.en[key] ?? key
    }
}

// MARK: - String tables

private extension LocalizationStore {
    static let en: [String: String] = [
        // Language picker
        "lang.system": "System",
        "lang.english": "English",
        "lang.korean": "한국어",
        "lang.section": "Language",
        "lang.section.detail": "Choose the app UI language. Mole CLI raw output stays unchanged.",

        // Sidebar
        "sidebar.brand.subtitle": "System care for macOS",
        "sidebar.section.monitor": "Monitor",
        "sidebar.section.cleanup": "Cleanup",
        "sidebar.section.app": "App",
        "sidebar.status": "Status",
        "sidebar.hardware": "Hardware",
        "sidebar.processes": "Processes",
        "sidebar.diskAnalyzer": "Disk Analyzer",
        "sidebar.clean": "Clean",
        "sidebar.purge": "Purge",
        "sidebar.installer": "Installers",
        "sidebar.optimize": "Optimize",
        "sidebar.uninstall": "Uninstall",
        "sidebar.settings": "Settings",

        // Settings
        "settings.hero.eyebrow": "Control Room",
        "settings.hero.title": "Settings",
        "settings.hero.subtitle": "Version details, language, disk-scan privacy guidance, and upstream CLI tools outside this GUI.",
        "settings.about": "About",
        "settings.permissions": "Disk Access & Privacy",
        "settings.cli": "Selected Upstream CLI Tools",
        "settings.cli.intro": "These are a few upstream Mole commands that stay outside the GUI. This is a guide to the most relevant ones, not a full command reference.",
        "settings.fda.open": "Open Full Disk Access",
        "settings.fda.refresh": "Refresh Status",
        "settings.fda.privacy": "Open Privacy & Security",
        "settings.fda.granted.title": "Full Disk Access appears enabled",
        "settings.fda.granted.detail": "Broad disk scans should be able to inspect protected Library content without repeated folder-by-folder interruptions.",
        "settings.fda.notGranted.title": "Full Disk Access is not enabled",
        "settings.fda.notGranted.detail": "macOS does not provide a one-shot prompt for Full Disk Access. Mole UI can guide you to the correct System Settings page so you can enable it yourself.",
        "settings.fda.unknown.title": "Full Disk Access could not be confirmed",
        "settings.fda.unknown.detail": "Mole UI could not positively verify Full Disk Access yet. Refresh after changing System Settings, or try Disk Analyzer again.",
        "settings.tip.prompts.title": "Reduce repeated prompts",
        "settings.tip.prompts.detail": "Desktop, Documents, Downloads, iCloud, and parts of Library all have separate privacy rules. Full Disk Access is the most reliable way to avoid repeated denials during broad scans.",
        "settings.tip.when.title": "When Full Disk Access helps",
        "settings.tip.when.detail": "If you want to analyze your whole Home folder, app data, iCloud files, or deeper Library content, granting Full Disk Access will make Disk Analyzer much more consistent.",

        // Status / Dashboard
        "status.hero.eyebrow": "Monitor",
        "status.hero.title": "Status",
        "status.health": "Health",
        "status.uptime": "Uptime",
        "status.loading": "Loading system metrics...",
        "status.connectionError": "Connection Error",
        "status.hw.title": "Hardware Monitor",
        "status.hw.open": "Open",
        "status.hw.unavailable": "Unavailable on Intel",
        "status.hw.sampling": "Sampling…",
        "status.hw.starting": "Starting…",
        "status.cpu": "CPU",
        "status.memory": "Memory",
        "status.disk": "Disk",
        "status.power": "Power",
        "status.processes": "Processes",
        "status.network": "Network",

        // Hardware monitor
        "monitor.hero.eyebrow": "Monitor",
        "monitor.required.title": "Apple Silicon Required",
        "monitor.required.detail": "Apple Silicon monitoring is unavailable on this Mac. Mole cleanup tools remain available.",
        "monitor.unavailable.title": "Monitor Unavailable",
        "monitor.retry": "Retry",
        "monitor.starting": "Starting hardware monitor...",
        "monitor.waitingSample": "Waiting for first sample",
        "monitor.history": "History",
        "monitor.history.subtitle": "Bounded in-memory samples · ~5 minutes at 1s",
        "monitor.cpu": "CPU",
        "monitor.gpu": "GPU",
        "monitor.memory": "Memory",
        "monitor.powerThermal": "Power / Thermal",
        "monitor.dram": "DRAM Bandwidth",
        "monitor.diskNet": "Disk / Network",
        "monitor.fans": "Fans (read-only)",
        "monitor.system": "System",
        "monitor.chart.cpu": "CPU",
        "monitor.chart.gpu": "GPU",
        "monitor.chart.memory": "Memory",
        "monitor.chart.power": "Power",
        "monitor.chart.dram": "DRAM Bandwidth",
        "monitor.degraded.title": "Monitoring degraded",
        "monitor.failed.title": "Monitoring stopped",
        "monitor.unsupported.title": "Apple Silicon monitoring unavailable",
        "monitor.unsupported.detail": "Mole cleanup tools remain available on this Mac.",

        // Processes
        "processes.hero.eyebrow": "Monitor",
        "processes.hero.title": "Processes",
        "processes.hero.subtitle": "Search, sort, and terminate with confirmation. No automatic killing.",
        "processes.refresh": "Refresh",
        "processes.filter": "Filter processes",
        "processes.required.title": "Apple Silicon Required",
        "processes.required.detail": "Process GPU metrics require Apple Silicon monitoring.",
        "processes.unavailable.title": "Monitor Unavailable",
        "processes.empty.title": "No Processes",
        "processes.empty.waiting": "Waiting for monitor sample…",
        "processes.empty.none": "No matches.",
        "processes.col.process": "Process",
        "processes.col.pid": "PID",
        "processes.col.cpu": "CPU",
        "processes.col.memory": "Memory",
        "processes.col.gpu": "GPU",
        "processes.terminate.title": "Terminate process?",
        "processes.terminate.confirm": "Terminate",
        "processes.terminate.cancel": "Cancel",
        "processes.terminate.failed": "Terminate failed",
    ]

    static let ko: [String: String] = [
        "lang.system": "시스템",
        "lang.english": "English",
        "lang.korean": "한국어",
        "lang.section": "언어",
        "lang.section.detail": "앱 UI 언어를 선택합니다. Mole CLI 원문 출력은 그대로 유지됩니다.",

        "sidebar.brand.subtitle": "macOS를 위한 시스템 관리",
        "sidebar.section.monitor": "모니터",
        "sidebar.section.cleanup": "정리",
        "sidebar.section.app": "앱",
        "sidebar.status": "상태",
        "sidebar.hardware": "하드웨어",
        "sidebar.processes": "프로세스",
        "sidebar.diskAnalyzer": "디스크 분석",
        "sidebar.clean": "클린",
        "sidebar.purge": "퍼지",
        "sidebar.installer": "설치 파일",
        "sidebar.optimize": "최적화",
        "sidebar.uninstall": "제거",
        "sidebar.settings": "설정",

        "settings.hero.eyebrow": "제어실",
        "settings.hero.title": "설정",
        "settings.hero.subtitle": "버전 정보, 언어, 디스크 스캔 개인정보 안내, GUI 밖 업스트림 CLI 도구.",
        "settings.about": "정보",
        "settings.permissions": "디스크 접근 및 개인정보",
        "settings.cli": "업스트림 CLI 도구",
        "settings.cli.intro": "GUI 밖에 남아 있는 주요 Mole CLI 명령입니다. 전체 레퍼런스가 아닌 안내입니다.",
        "settings.fda.open": "전체 디스크 접근 열기",
        "settings.fda.refresh": "상태 새로고침",
        "settings.fda.privacy": "개인정보 보호 및 보안 열기",
        "settings.fda.granted.title": "전체 디스크 접근이 허용된 것으로 보입니다",
        "settings.fda.granted.detail": "보호된 Library 콘텐츠를 폴더마다 반복 중단 없이 광범위 스캔할 수 있어야 합니다.",
        "settings.fda.notGranted.title": "전체 디스크 접근이 꺼져 있습니다",
        "settings.fda.notGranted.detail": "macOS는 전체 디스크 접근을 한 번에 요청하지 않습니다. Mole UI가 시스템 설정의 해당 페이지로 안내합니다.",
        "settings.fda.unknown.title": "전체 디스크 접근을 확인할 수 없습니다",
        "settings.fda.unknown.detail": "아직 확실히 확인되지 않았습니다. 시스템 설정 변경 후 새로고침하거나 디스크 분석을 다시 시도하세요.",
        "settings.tip.prompts.title": "반복 권한 요청 줄이기",
        "settings.tip.prompts.detail": "데스크탑, 문서, 다운로드, iCloud, Library 일부는 각각 다른 개인정보 규칙이 있습니다. 전체 디스크 접근이 가장 안정적입니다.",
        "settings.tip.when.title": "전체 디스크 접근이 필요한 경우",
        "settings.tip.when.detail": "홈 폴더 전체, 앱 데이터, iCloud, Library 심층 분석을 원하면 전체 디스크 접근을 허용하는 것이 좋습니다.",

        "status.hero.eyebrow": "모니터",
        "status.hero.title": "상태",
        "status.health": "상태 점수",
        "status.uptime": "가동 시간",
        "status.loading": "시스템 지표를 불러오는 중...",
        "status.connectionError": "연결 오류",
        "status.hw.title": "하드웨어 모니터",
        "status.hw.open": "열기",
        "status.hw.unavailable": "Intel에서는 사용할 수 없음",
        "status.hw.sampling": "수집 중…",
        "status.hw.starting": "시작 중…",
        "status.cpu": "CPU",
        "status.memory": "메모리",
        "status.disk": "디스크",
        "status.power": "전원",
        "status.processes": "프로세스",
        "status.network": "네트워크",

        "monitor.hero.eyebrow": "모니터",
        "monitor.required.title": "Apple Silicon 필요",
        "monitor.required.detail": "이 Mac에서는 Apple Silicon 모니터링을 사용할 수 없습니다. Mole 정리 도구는 계속 사용할 수 있습니다.",
        "monitor.unavailable.title": "모니터를 사용할 수 없음",
        "monitor.retry": "다시 시도",
        "monitor.starting": "하드웨어 모니터 시작 중...",
        "monitor.waitingSample": "첫 샘플 대기 중",
        "monitor.history": "기록",
        "monitor.history.subtitle": "메모리 내 샘플 · 1초 간격 약 5분",
        "monitor.cpu": "CPU",
        "monitor.gpu": "GPU",
        "monitor.memory": "메모리",
        "monitor.powerThermal": "전력 / 온도",
        "monitor.dram": "DRAM 대역폭",
        "monitor.diskNet": "디스크 / 네트워크",
        "monitor.fans": "팬 (읽기 전용)",
        "monitor.system": "시스템",
        "monitor.chart.cpu": "CPU",
        "monitor.chart.gpu": "GPU",
        "monitor.chart.memory": "메모리",
        "monitor.chart.power": "전력",
        "monitor.chart.dram": "DRAM 대역폭",
        "monitor.degraded.title": "모니터링 저하",
        "monitor.failed.title": "모니터링 중지됨",
        "monitor.unsupported.title": "Apple Silicon 모니터링 불가",
        "monitor.unsupported.detail": "이 Mac에서도 Mole 정리 도구는 사용할 수 있습니다.",

        "processes.hero.eyebrow": "모니터",
        "processes.hero.title": "프로세스",
        "processes.hero.subtitle": "검색·정렬·확인 후 종료. 자동 종료는 없습니다.",
        "processes.refresh": "새로고침",
        "processes.filter": "프로세스 필터",
        "processes.required.title": "Apple Silicon 필요",
        "processes.required.detail": "프로세스 GPU 지표는 Apple Silicon 모니터링이 필요합니다.",
        "processes.unavailable.title": "모니터를 사용할 수 없음",
        "processes.empty.title": "프로세스 없음",
        "processes.empty.waiting": "모니터 샘플 대기 중…",
        "processes.empty.none": "일치하는 항목이 없습니다.",
        "processes.col.process": "프로세스",
        "processes.col.pid": "PID",
        "processes.col.cpu": "CPU",
        "processes.col.memory": "메모리",
        "processes.col.gpu": "GPU",
        "processes.terminate.title": "프로세스를 종료할까요?",
        "processes.terminate.confirm": "종료",
        "processes.terminate.cancel": "취소",
        "processes.terminate.failed": "종료 실패",
    ]
}
