import SwiftUI

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

            // Device picker menu
            Menu {
                if devices.isEmpty {
                    Text("No device connected")
                } else {
                    ForEach(devices) { device in
                        Button {
                            onSelect?(device)
                        } label: {
                            if device.id == selectedDevice?.id {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(selectedDevice?.name ?? "No device")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(modelName)
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    if devices.count > 1 {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
    }
}
