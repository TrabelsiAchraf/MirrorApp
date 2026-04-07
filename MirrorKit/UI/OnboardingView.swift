import SwiftUI

/// Onboarding screen shown on first launch
struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep = 0

    private let steps: [(icon: String, title: String, description: String)] = [
        (
            "iphone.and.arrow.forward",
            "Welcome to MirrorKit",
            "Display your iPhone screen directly on your Mac. Perfect for presentations, development, or just keeping an eye on your phone."
        ),
        (
            "cable.connector",
            "Plug in your iPhone via USB",
            "Connect your iPhone to your Mac with a USB or USB-C cable. MirrorKit uses a wired connection for real-time, low-latency display."
        ),
        (
            "camera.fill",
            "Grant camera access",
            "macOS will ask for camera permission. This is normal — your iPhone is seen as a video capture device. No data is recorded or transmitted."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            Image(systemName: steps[currentStep].icon)
                .font(.system(size: 64))
                .foregroundStyle(.blue)
                .frame(height: 80)
                .padding(.bottom, 24)

            // Title
            Text(steps[currentStep].title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            // Description
            Text(steps[currentStep].description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.bottom, 32)

            Spacer()

            // Progress indicators
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? Color.blue : Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 24)

            // Buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button("Next") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 440, height: 400)
    }
}
