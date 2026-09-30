import AppKit
import SwiftUI

enum FullDiskAccessStatus: Equatable {
    case granted
    case notGranted
    case unknown

    var titleKey: String {
        switch self {
        case .granted: "settings.fda.granted.title"
        case .notGranted: "settings.fda.notGranted.title"
        case .unknown: "settings.fda.unknown.title"
        }
    }

    var detailKey: String {
        switch self {
        case .granted: "settings.fda.granted.detail"
        case .notGranted: "settings.fda.notGranted.detail"
        case .unknown: "settings.fda.unknown.detail"
        }
    }
}

enum FullDiskAccessHelper {
    private enum ProbeResult {
        case accessible
        case blocked
        case missing
    }

    static func status() -> FullDiskAccessStatus {
        let probes: [ProbeResult] = [
            probeFile(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")),
            probeDirectory(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.TCC")),
            probeDirectory(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")),
            probeDirectory(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari")),
            probeDirectory(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages")),
        ]

        if probes.contains(.accessible) {
            return .granted
        }
        if probes.contains(.blocked) {
            return .notGranted
        }
        return .unknown
    }

    static func openSystemSettings() {
        if revealSystemSettings(
            anchor: "Privacy_AllFiles",
            paneID: "com.apple.settings.PrivacySecurity.extension"
        ) {
            return
        }

        if revealSystemSettings(
            anchor: "Privacy_AllFiles",
            paneID: "com.apple.preference.security"
        ) {
            return
        }

        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ].compactMap(URL.init(string:))

        for url in urls where NSWorkspace.shared.open(url) {
            return
        }

        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private static func probeFile(_ url: URL) -> ProbeResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            _ = try handle.read(upToCount: 1)
            return .accessible
        } catch {
            return .blocked
        }
    }

    private static func probeDirectory(_ url: URL) -> ProbeResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missing
        }

        do {
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).prefix(1)
            return .accessible
        } catch {
            return .blocked
        }
    }

    private static func revealSystemSettings(anchor: String, paneID: String) -> Bool {
        let script = """
        tell application "System Settings"
            reveal anchor "\(anchor)" of pane id "\(paneID)"
            activate
        end tell
        """
        return runAppleScript(script)
    }

    private static func runAppleScript(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LocalizationStore.self) private var localization
    @State private var fullDiskAccessStatus = FullDiskAccessHelper.status()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                heroCard
                languageCard
                aboutCard
                permissionsCard
                cliOnlyCard
            }
            .padding(16)
        }
        .onAppear {
            refreshFullDiskAccessStatus()
        }
    }

    private var heroCard: some View {
        MoleHeroPanel(
            eyebrow: localization.t("settings.hero.eyebrow"),
            title: localization.t("settings.hero.title"),
            subtitle: localization.t("settings.hero.subtitle"),
            symbol: "gearshape.2.fill"
        )
    }

    private var languageCard: some View {
        settingsCard(title: localization.t("lang.section"), symbol: "globe") {
            VStack(alignment: .leading, spacing: 12) {
                Text(localization.t("lang.section.detail"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker(localization.t("lang.section"), selection: Bindable(localization).language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(localization.t(lang.displayNameKey)).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var aboutCard: some View {
        settingsCard(title: localization.t("settings.about"), symbol: "info.circle") {
            VStack(alignment: .leading, spacing: 14) {
                MoleVersionView(bundledCLIVersion: readMoleCLIVersion())

                HStack(alignment: .top) {
                    Text("GitHub")
                    Spacer()
                    Link("github.com/imnotnoahhh/MoleUI", destination: URL(string: "https://github.com/imnotnoahhh/MoleUI")!)
                        .foregroundStyle(MoleTheme.sky)
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
    }

    private var permissionsCard: some View {
        settingsCard(title: localization.t("settings.permissions"), symbol: "hand.raised") {
            VStack(alignment: .leading, spacing: 12) {
                statusPill(
                    title: localization.t(fullDiskAccessStatus.titleKey),
                    detail: localization.t(fullDiskAccessStatus.detailKey),
                    tint: fullDiskAccessTint
                )

                HStack(spacing: 10) {
                    Button {
                        openFullDiskAccessSettings()
                    } label: {
                        Label(localization.t("settings.fda.open"), systemImage: "lock.open.display")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(localization.t("settings.fda.refresh")) {
                        refreshFullDiskAccessStatus()
                    }

                    Button(localization.t("settings.fda.privacy")) {
                        openPrivacyAndSecuritySettings()
                    }
                }

                permissionTip(
                    title: localization.t("settings.tip.prompts.title"),
                    detail: localization.t("settings.tip.prompts.detail")
                )
                permissionTip(
                    title: localization.t("settings.tip.when.title"),
                    detail: localization.t("settings.tip.when.detail")
                )
            }
        }
    }

    private var cliOnlyCard: some View {
        settingsCard(title: localization.t("settings.cli"), symbol: "terminal") {
            VStack(alignment: .leading, spacing: 10) {
                Text(localization.t("settings.cli.intro"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                cliFeatureRow("mo touchid", "Configure Touch ID for sudo in the upstream CLI. This changes macOS sudo PAM config and stays outside MoleUI.")
                cliFeatureRow("mo completion", "Generate or install shell completion scripts for bash, zsh, and fish.")
                cliFeatureRow("mo update", "Self-update the upstream Mole CLI to the latest stable release.")
                cliFeatureRow("mo update --nightly", "Switch the upstream CLI to the latest unreleased main build.")
                cliFeatureRow("mo remove", "Uninstall the upstream Mole CLI from the system.")
            }
        }
    }

    private func settingsCard(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            MoleSectionHeader(title: title, subtitle: nil, symbol: symbol)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(colorScheme == .dark ? Color(red: 0.13, green: 0.14, blue: 0.16) : Color.white.opacity(0.92))
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.white.opacity(0.28))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(MoleTheme.line, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.05), radius: 16, y: 8)
    }

    private func settingsValueRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.system(.caption, design: .monospaced))
        }
    }

    private func statusPill(title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.12 : 0.08))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(colorScheme == .dark ? 0.22 : 0.14), lineWidth: 1)
        )
    }

    private func permissionTip(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cliFeatureRow(_ command: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func readMoleCLIVersion() -> String? {
        if let versionFile = Bundle.main.url(forResource: ".mole-cli-version", withExtension: nil),
           let version = try? String(contentsOf: versionFile, encoding: .utf8)
        {
            return version.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private var fullDiskAccessTint: Color {
        switch fullDiskAccessStatus {
        case .granted:
            .green
        case .notGranted:
            .blue
        case .unknown:
            .orange
        }
    }

    private func refreshFullDiskAccessStatus() {
        fullDiskAccessStatus = FullDiskAccessHelper.status()
    }

    private func openFullDiskAccessSettings() {
        if revealSystemSettings(
            anchor: "Privacy_AllFiles",
            paneID: "com.apple.settings.PrivacySecurity.extension"
        ) {
            return
        }

        if revealSystemSettings(
            anchor: "Privacy_AllFiles",
            paneID: "com.apple.preference.security"
        ) {
            return
        }

        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ].compactMap(URL.init(string:))

        for url in urls where NSWorkspace.shared.open(url) {
            return
        }

        openPrivacyAndSecuritySettings()
    }

    private func openPrivacyAndSecuritySettings() {
        if revealSystemSettingsPane("com.apple.settings.PrivacySecurity.extension") {
            return
        }

        if revealSystemSettingsPane("com.apple.preference.security") {
            return
        }

        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
            "x-apple.systempreferences:com.apple.preference.security",
        ].compactMap(URL.init(string:))

        for url in urls where NSWorkspace.shared.open(url) {
            return
        }

        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func revealSystemSettings(anchor: String, paneID: String) -> Bool {
        let script = """
        tell application "System Settings"
            reveal anchor "\(anchor)" of pane id "\(paneID)"
            activate
        end tell
        """
        return runAppleScript(script)
    }

    private func revealSystemSettingsPane(_ paneID: String) -> Bool {
        let script = """
        tell application "System Settings"
            reveal pane id "\(paneID)"
            activate
        end tell
        """
        return runAppleScript(script)
    }

    private func runAppleScript(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
