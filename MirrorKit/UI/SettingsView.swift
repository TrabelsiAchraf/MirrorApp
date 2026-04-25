import SwiftUI

/// Settings window content — save location, bezel style, and background.
struct SettingsView: View {
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
                BackgroundPresetPicker()
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 360)
    }
}
