import SwiftUI

/// Bezel style picker for the SettingsView Display section.
/// Shows the three styles as a segmented control. When `style == .classic`,
/// reveals a color sub-row (black/silver/gold).
struct BezelStylePicker: View {
    @AppStorage("bezelStyle") private var styleRaw: String = "classic"
    @AppStorage("bezelColor") private var colorRaw: String = "black"

    private var style: BezelStyle {
        BezelStyle(rawValue: styleRaw) ?? .classic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Bezel style") {
                // Real label (hidden visually) so accessibility gets a name and
                // Xcode's string extraction doesn't produce an empty key.
                Picker("Bezel style", selection: $styleRaw) {
                    ForEach(BezelStyle.allCases) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if style == .classic {
                LabeledContent("Bezel color") {
                    Picker("Bezel color", selection: $colorRaw) {
                        Text("Black").tag("black")
                        Text("Silver").tag("silver")
                        Text("Gold").tag("gold")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: style == .classic)
    }
}
