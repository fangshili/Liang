import SwiftUI
import AppKit

struct CodeBuddySetupSection: View {
    @StateObject private var manager = CodeBuddySetupManager.shared
    @State private var activeAlert: SetupAlert?

    var showCardBackgrounds = true

    var body: some View {
        Group {
            if showCardBackgrounds {
                cardContent
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
            } else {
                cardContent
            }
        }
        .onAppear {
            manager.refresh()
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow

            if !manager.status.isConfigured {
                Text(I18n.shared.string(.codebuddyInstallDescription))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    handleConfigure()
                } label: {
                    if manager.isInstalling {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Text(I18n.shared.string(.configure))
                    }
                }
                .disabled(manager.isInstalling)
                .alert(item: $activeAlert) { alert in
                    switch alert {
                    case .installConfirmation:
                        return Alert(
                            title: Text(I18n.shared.string(.installConfirmTitle)),
                            message: Text(I18n.shared.string(.codebuddyInstallConfirmMessage)),
                            primaryButton: .cancel(Text(I18n.shared.string(.cancel))),
                            secondaryButton: .default(Text(I18n.shared.string(.autoInstall))) {
                                manager.installAutomatically()
                            }
                        )
                    case .notInstalled:
                        return Alert(
                            title: Text(I18n.shared.string(.onboardingCodebuddyNotInstalledTitle)),
                            message: Text(I18n.shared.string(.onboardingCodebuddyNotInstalledMessage)),
                            primaryButton: .default(Text(I18n.shared.string(.onboardingCodebuddyNotInstalledDownload))) {
                                if let url = URL(string: "https://www.codebuddy.ai") {
                                    NSWorkspace.shared.open(url)
                                }
                            },
                            secondaryButton: .cancel(Text(I18n.shared.string(.cancel)))
                        )
                    }
                }
            }

            if let error = manager.lastInstallError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
            Text(statusText)
                .font(.system(size: 13, weight: .medium))
            Spacer()
        }
    }

    private var statusIcon: String {
        if manager.status.isConfigured { return "checkmark.circle.fill" }
        if case .partial = manager.status { return "exclamationmark.circle.fill" }
        return "xmark.circle.fill"
    }

    private var statusColor: Color {
        if manager.status.isConfigured { return .green }
        if case .partial = manager.status { return .orange }
        return .red
    }

    private var statusText: String {
        if manager.status.isConfigured {
            return I18n.shared.string(.onboardingCursorConnected)
        }
        switch manager.status {
        case .partial: return I18n.shared.string(.cursorSetupStatusPartial)
        case .notConfigured: return I18n.shared.string(.cursorSetupStatusNotConfigured)
        case .unknown: return I18n.shared.string(.cursorSetupStatusChecking)
        default: return I18n.shared.string(.cursorSetupStatusChecking)
        }
    }

    private func handleConfigure() {
        manager.refresh()
        if manager.isCodeBuddyInstalled {
            activeAlert = .installConfirmation
        } else {
            activeAlert = .notInstalled
        }
    }
}

private enum SetupAlert: Identifiable {
    case installConfirmation
    case notInstalled

    var id: String {
        switch self {
        case .installConfirmation: return "install"
        case .notInstalled: return "not-installed"
        }
    }
}
