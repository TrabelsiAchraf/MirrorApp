import SwiftUI
import AppKit

/// Floating toolbar — traffic lights + device picker menu
struct FloatingToolbar: View {
    let devices: [ConnectedDevice]
    let selectedDevice: ConnectedDevice?
    let modelName: String
    var onSelect: ((ConnectedDevice) -> Void)?
    var onExpand: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Traffic lights
            HStack(spacing: 7) {
                Button(action: { NSApp.keyWindow?.close() }) {
                    Circle().fill(Color.red).frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)

                Button(action: { NSApp.keyWindow?.miniaturize(nil) }) {
                    Circle().fill(Color.yellow).frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)

                Button(action: { onExpand?() }) {
                    Circle().fill(Color.green).frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
            }

            // Device picker — custom label, native NSMenu on click
            Button(action: showDevicePopup) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedDevice?.name ?? "No device")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(modelName)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 5) {
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    )
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
    }

    /// Pop up a native NSMenu listing all detected devices.
    private func showDevicePopup() {
        guard !devices.isEmpty, let event = NSApp.currentEvent else { return }
        let menu = NSMenu()
        for device in devices {
            let item = NSMenuItem(
                title: device.name,
                action: #selector(MenuActionTarget.handle(_:)),
                keyEquivalent: ""
            )
            item.state = (device.id == selectedDevice?.id) ? .on : .off
            let target = MenuActionTarget { onSelect?(device) }
            item.target = target
            item.representedObject = target
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: NSApp.keyWindow?.contentView ?? NSView())
    }
}

/// Lightweight target so each NSMenuItem can carry its own SwiftUI closure.
private final class MenuActionTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func handle(_ sender: Any?) { action() }
}
