import SwiftUI
import CoreGraphics

/// Drawing tool the user has selected.
enum AnnotationTool: String, CaseIterable {
    case pen
    case arrow
    case circle
    case rectangle
    case highlighter

    /// SF Symbol name shown in the AnnotationToolbar.
    var iconName: String {
        switch self {
        case .pen:         return "pencil.tip"
        case .arrow:       return "arrow.up.right"
        case .circle:      return "circle"
        case .rectangle:   return "rectangle"
        case .highlighter: return "highlighter"
        }
    }

    /// Default stroke width per tool, applied at draw time.
    var defaultStrokeWidth: CGFloat {
        switch self {
        case .pen, .circle, .rectangle: return 2
        case .arrow:                    return 3
        case .highlighter:              return 24
        }
    }
}

/// Colors available in the annotation palette.
enum AnnotationColor: String, CaseIterable {
    case red, blue, green, yellow, white, black

    var color: Color {
        switch self {
        case .red:    return Color(red: 1.00, green: 0.23, blue: 0.19)
        case .blue:   return Color(red: 0.04, green: 0.52, blue: 1.00)
        case .green:  return Color(red: 0.20, green: 0.78, blue: 0.35)
        case .yellow: return Color(red: 1.00, green: 0.84, blue: 0.04)
        case .white:  return .white
        case .black:  return .black
        }
    }
}

/// One drawing operation. Coordinates are normalized to [0,1]×[0,1] of the
/// video display layer so they survive window resize and iPhone rotation.
struct Annotation: Identifiable, Equatable {
    let id: UUID
    let tool: AnnotationTool
    let color: AnnotationColor
    /// `pen` and `highlighter` use the full path of points.
    /// `arrow` / `circle` / `rectangle` use exactly two points: [start, current].
    var points: [CGPoint]
}
