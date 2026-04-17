import SwiftUI

/// Settings window content — save location and display preferences.
struct SettingsView: View {
    @AppStorage("showDeviceFrame") private var showDeviceFrame = true
    @State private var saveFolderPath: String = SaveLocationManager.resolveBookmark()?.path ?? "Not set"

    var body: some View {
        Form {
            Section("Captures") {
                LabeledContent("Save location") {
                    HStack {
                        Text(saveFolderPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .help(saveFolderPath)

                        Button("Choose…") {
                            if let url = SaveLocationManager.promptForFolder() {
                                saveFolderPath = url.path
                            }
                        }
                    }
                }
            }

            Section("Display") {
                Toggle("Show device frame", isOn: $showDeviceFrame)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 180)
    }
}
