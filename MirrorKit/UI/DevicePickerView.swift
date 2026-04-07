import SwiftUI

/// Device picker view — shown when multiple iPhones are connected
struct DevicePickerView: View {
    let deviceManager: DeviceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detected Devices")
                .font(.headline)
                .foregroundColor(.white)

            ForEach(deviceManager.devices) { device in
                Button(action: {
                    deviceManager.selectDevice(device)
                }) {
                    HStack {
                        Image(systemName: "iphone")
                            .font(.title3)

                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.body)
                            Text(device.modelID)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if deviceManager.selectedDevice?.id == device.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(deviceManager.selectedDevice?.id == device.id
                                  ? Color.blue.opacity(0.2)
                                  : Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
            }
        }
        .padding()
    }
}
