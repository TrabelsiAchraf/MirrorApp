import SwiftUI

/// Floating toolbar — traffic lights + device name
struct FloatingToolbar: View {
    let deviceName: String
    let modelName: String
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

            // Device name
            VStack(alignment: .leading, spacing: 1) {
                Text(deviceName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(modelName)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

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
