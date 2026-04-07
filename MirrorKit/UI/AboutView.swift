import SwiftUI

/// MirrorKit About window
struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 16) {
            // App icon
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            // Name
            Text("MirrorKit")
                .font(.title.bold())

            // Version
            Text("Version \(appVersion) (\(buildNumber))")
                .font(.caption)
                .foregroundColor(.secondary)

            // Description
            Text("Display your iPhone screen\non your Mac via USB.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()
                .padding(.horizontal, 40)

            // Copyright
            Text("© 2026 Achraf Trabelsi")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(32)
        .frame(width: 320, height: 340)
    }
}
