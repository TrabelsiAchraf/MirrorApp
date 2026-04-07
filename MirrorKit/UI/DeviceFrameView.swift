import SwiftUI

/// Device frame container — draws an iPhone frame around the content passed as parameter
struct DeviceFrameView<Content: View>: View {
    let spec: DeviceFrameSpec
    let content: Content

    init(spec: DeviceFrameSpec, @ViewBuilder content: () -> Content) {
        self.spec = spec
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 390.0
            let bezel = spec.bezelWidth * scale
            let verticalBezel = bezel * 1.8
            let outerRadius = spec.cornerRadius * scale
            let innerRadius = max(outerRadius - bezel, 8)

            // Exact dimensions of the inner screen
            let screenWidth = geometry.size.width - bezel * 2
            let screenHeight = geometry.size.height - verticalBezel * 2

            // The full iPhone frame
            ZStack {
                // Device body (black rounded rectangle)
                RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                    .fill(frameColor)

                // Screen (video content) — fixed size, centered
                content
                    .frame(width: screenWidth, height: screenHeight)
                    .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))

                // Dynamic Island
                if spec.notchStyle == .dynamicIsland {
                    VStack {
                        Capsule()
                            .fill(frameColor)
                            .frame(
                                width: geometry.size.width * 0.25,
                                height: max(geometry.size.height * 0.015, 8)
                            )
                            .padding(.top, verticalBezel + geometry.size.height * 0.008)
                        Spacer()
                    }
                }
            }
        }
    }

    private var frameColor: Color {
        switch spec.frameColor {
        case .black: return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .silver: return Color(red: 0.89, green: 0.89, blue: 0.91)
        case .gold: return Color(red: 0.96, green: 0.90, blue: 0.81)
        }
    }
}
