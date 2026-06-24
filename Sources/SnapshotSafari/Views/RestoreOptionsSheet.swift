import SwiftUI

struct RestoreOptionsSheet: View {
    let title: String
    let onRestore: (SnapshotService.RestoreMode) -> Void

    @State private var selectedMode: SnapshotService.RestoreMode = .newWindow
    @Environment(\.dismiss) private var dismiss

    init(
        title: String = "Restore Snapshot",
        onRestore: @escaping (SnapshotService.RestoreMode) -> Void
    ) {
        self.title = title
        self.onRestore = onRestore
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.title2.bold())

            Text("How would you like to open these tabs?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Restore mode", selection: $selectedMode) {
                ForEach(SnapshotService.RestoreMode.allCases, id: \.self) { mode in
                    HStack {
                        Image(systemName: mode == .newWindow ? "macwindow.on.rectangle" : "macwindow")
                            .font(.title3)
                        Text(mode.rawValue)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Restore") {
                    onRestore(selectedMode)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 360)
    }
}
