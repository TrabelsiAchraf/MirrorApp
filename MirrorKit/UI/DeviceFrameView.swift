import SwiftUI

/// Device frame container — wraps the mirror content in one of three styles:
/// classic (existing colored bezel + Dynamic Island), floating (no bezel +
/// soft drop shadow), or frameless (just rounded corners).
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
        case .classic:  classicBody
        case .floating: floatingBody
        case .none:     framelessBody
        }
    }

    // MARK: - Classic (existing v1.0 implementation)

    private var classicBody: some View {
        GeometryReader { geometry in
            // Scale reference: shortest side, so bezels stay consistent in any orientation.
            let reference: CGFloat = spec.kind == .iPad ? 820 : 390
            let baseline = min(geometry.size.width, geometry.size.height) / reference
            let bezel = spec.bezelWidth * baseline
            // iPhones have taller top/bottom bezels than left/right; iPad is uniform.
            let verticalBezel = spec.kind == .iPad ? bezel : bezel * 1.8
            let outerRadius = spec.cornerRadius * baseline
            let innerRadius = max(outerRadius - bezel, 8)

            let screenWidth = geometry.size.width - bezel * 2
            let screenHeight = geometry.size.height - verticalBezel * 2

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
                            .padding(.top, verticalBezel + geometry.size.height * 0.008)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Floating (no bezel + drop shadow)

    private var floatingBody: some View {
        GeometryReader { geometry in
            let reference: CGFloat = spec.kind == .iPad ? 820 : 390
            let baseline = min(geometry.size.width, geometry.size.height) / reference
            let outerRadius = spec.cornerRadius * baseline

            content
                .clipShape(RoundedRectangle(cornerRadius: outerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
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
