import SwiftUI

struct CursorSetupSection: View {
    @StateObject private var manager = CursorSetupManager.shared
    @State private var showInstallConfirmation = false

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
                Text(I18n.shared.string(.autoInstallDescription))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showInstallConfirmation = true
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
                .alert(isPresented: $showInstallConfirmation) {
                    Alert(
                        title: Text(I18n.shared.string(.installConfirmTitle)),
                        message: Text(I18n.shared.string(.installConfirmMessage)),
                        primaryButton: .cancel(Text(I18n.shared.string(.cancel))),
                        secondaryButton: .default(Text(I18n.shared.string(.autoInstall))) {
                            manager.installAutomatically()
                        }
                    )
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
}
