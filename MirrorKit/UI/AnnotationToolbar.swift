import SwiftUI

/// Vertical side panel shown when annotation mode is active.
/// 5 tool buttons + 6 color dots + undo + clear, stacked top-to-bottom.
struct AnnotationToolbar: View {
    let canvas: AnnotationCanvas

    var body: some View {
        VStack(spacing: 8) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                toolButton(tool)
            }

            divider

            ForEach(AnnotationColor.allCases, id: \.self) { color in
                colorDot(color)
            }

            divider

            iconButton("arrow.uturn.backward") { canvas.undo() }
            iconButton("trash") { canvas.clearAll() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 18, height: 1)
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let isSelected = canvas.activeTool == tool
        return Button {
            canvas.activeTool = tool
        } label: {
            Image(systemName: tool.iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.4) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func colorDot(_ color: AnnotationColor) -> some View {
        let isSelected = canvas.activeColor == color
        return Button {
            canvas.activeColor = color
        } label: {
            Circle()
                .fill(color.color)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: isSelected ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}
