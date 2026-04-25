import SwiftUI
import AppKit

/// Grid of preset thumbnails + "Custom…" cell that opens NSColorPanel.
/// Bound to two @AppStorage keys: `backgroundPreset` and `backgroundCustomColor`.
struct BackgroundPresetPicker: View {
    @AppStorage("backgroundPreset") private var rawValue: String = "midnight"
    @AppStorage("backgroundCustomColor") private var customHex: String = "#1F1C40"

    private var selectedPreset: BackgroundPreset {
        BackgroundPreset(rawValue: rawValue) ?? .midnight
    }

    private var customColor: Color {
        Color(hex: customHex) ?? .black
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Background (expanded mode)")
                .font(.system(size: 13, weight: .regular))

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(BackgroundPreset.allCases.filter { $0 != .custom }) { preset in
                    presetCell(preset)
                }
                customCell
            }
        }
    }

    private func presetCell(_ preset: BackgroundPreset) -> some View {
        let isSelected = selectedPreset == preset
        return VStack(spacing: 4) {
            preset.makeBackground(customColor: customColor)
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(4)
                    }
                }
            Text(preset.displayName)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { rawValue = preset.rawValue }
    }

    private var customCell: some View {
        let isSelected = selectedPreset == .custom
        return VStack(spacing: 4) {
            ZStack {
                customColor
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            Text("Custom…")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            rawValue = BackgroundPreset.custom.rawValue
            openColorPanel()
        }
    }

    private func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.color = NSColor(customColor)
        panel.showsAlpha = false
        panel.setTarget(ColorPanelObserver.shared)
        panel.setAction(#selector(ColorPanelObserver.colorChanged(_:)))
        ColorPanelObserver.shared.binding = { newHex in
            self.customHex = newHex
        }
        panel.makeKeyAndOrderFront(nil)
    }
}

/// Bridges NSColorPanel target/action (Objective-C) to a SwiftUI closure.
@MainActor
private final class ColorPanelObserver: NSObject {
    static let shared = ColorPanelObserver()
    var binding: ((String) -> Void)?

    @objc func colorChanged(_ sender: NSColorPanel) {
        let hex = ColorPersistence.hex(from: sender.color)
        binding?(hex)
    }
}
