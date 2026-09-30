import SwiftUI

/// Non-blocking status strip for Monitor / Processes / Dashboard.
struct MonitorStatusBanner: View {
    let title: String
    let message: String
    var isRetryable: Bool = false
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MoleTheme.ember)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isRetryable, let onRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(MoleTheme.ember.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MoleTheme.ember.opacity(0.25), lineWidth: 1)
        )
    }
}

struct MonitorAvailabilityNotices: View {
    let notices: [String]

    var body: some View {
        if !notices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(notices, id: \.self) { notice in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(MoleTheme.sky)
                        Text(notice)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MoleTheme.sky.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MoleTheme.sky.opacity(0.20), lineWidth: 1)
            )
        }
    }
}
