import SwiftUI

struct WelcomeView: View {
    let permissionsService: PermissionsService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "camera.aperture")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text("Welcome to Snapshot Safari")
                .font(.largeTitle.bold())

            Text("I'll help you save and restore your Safari tabs\nso you can free up RAM without losing anything.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            Divider()
                .frame(width: 200)

            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(
                    icon: "keyboard",
                    title: "Automation Access",
                    description: "I need permission to read your Safari tabs and open them again."
                )
                PermissionRow(
                    icon: "square.on.square",
                    title: "Snapshots",
                    description: "Save all open tabs with one click. Restore any time."
                )
                PermissionRow(
                    icon: "clock.arrow.circlepath",
                    title: "Auto-Snapshots",
                    description: "Optional: automatically save snapshots on a schedule."
                )
                PermissionRow(
                    icon: "lock.shield",
                    title: "100% Private",
                    description: "All data stays on your Mac. No tracking, no servers."
                )
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        let granted = await permissionsService.checkAutomationPermission()
                        if !granted {
                            permissionsService.openAutomationSettings()
                        }
                        dismiss()
                    }
                } label: {
                    Label("Get Started", systemImage: "arrow.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Checks Automation permission and opens System Settings if needed, then continues to the app.")

                Button("Skip for now") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHint("Closes this welcome screen without setting up Automation permission.")
            }
            .padding(.horizontal, 40)
        }
        .padding()
        .frame(width: 420, height: 520)
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
