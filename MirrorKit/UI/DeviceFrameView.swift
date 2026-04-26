import SwiftUI

/// Device frame container — wraps the mirror content in one of two styles:
/// classic (colored bezel + Dynamic Island) or frameless (just rounded corners).
struct DeviceFrameView<Content: View>: View {
    let spec: DeviceFrameSpec
    let style: BezelStyle
    let content: Content

    init(spec: DeviceFrameSpec, style: BezelStyle, @ViewBuilder content: () -> Content) {
        self.spec = spec
        self.style = style
        self.content = content()
    }

    var body: some View {
        switch style {
        case .classic: classicBody
        case .none:    framelessBody
        }
    }

    // MARK: - Classic (existing v1.0 implementation)

    private var classicBody: some View {
        GeometryReader { geometry in
            // Scale reference: shortest side, so bezels stay consistent in any orientation.
            let reference: CGFloat = spec.kind == .iPad ? 820 : 390
            let baseline = min(geometry.size.width, geometry.size.height) / reference
            let bezel = spec.bezelWidth * baseline
            let outerRadius = spec.cornerRadius * baseline
            let innerRadius = max(outerRadius - bezel, 8)

            let screenWidth = geometry.size.width - bezel * 2
            let screenHeight = geometry.size.height - bezel * 2

            ZStack {
                RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                    .fill(frameColor)

                content
                    .frame(width: screenWidth, height: screenHeight)
                    .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))

                if spec.kind == .iPhone, spec.notchStyle == .dynamicIsland {
                    VStack {
                        Capsule()
                            .fill(frameColor)
                            .frame(
                                width: geometry.size.width * 0.25,
                                height: max(geometry.size.height * 0.015, 8)
                            )
                            .padding(.top, bezel + geometry.size.height * 0.008)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Frameless (just rounded corners)

    private var framelessBody: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
    }

    // MARK: - Helpers

    private var frameColor: Color {
        switch spec.frameColor {
        case .black:  return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .silver: return Color(red: 0.89, green: 0.89, blue: 0.91)
        case .gold:   return Color(red: 0.96, green: 0.90, blue: 0.81)
        }
    }
}
