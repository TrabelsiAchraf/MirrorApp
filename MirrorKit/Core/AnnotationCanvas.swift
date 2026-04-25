import SwiftUI
import CoreGraphics

/// Mutable state for the live annotation overlay. Owns the committed stroke
/// list, the in-flight stroke being drawn, the user's tool/color choice,
/// and the undo stack. All accesses are on the main actor.
@MainActor
@Observable
final class AnnotationCanvas {
    private(set) var annotations: [Annotation] = []
    private(set) var currentStroke: Annotation?

    var activeTool: AnnotationTool = .pen
    var activeColor: AnnotationColor = .red

    var isAnnotationModeActive: Bool = false {
        didSet {
            if !isAnnotationModeActive { currentStroke = nil }
        }
    }

    @ObservationIgnored private var undoStack: [[Annotation]] = []
    private static let maxUndoDepth = 20

    func beginStroke(at point: CGPoint) {
        currentStroke = Annotation(
            id: UUID(),
            tool: activeTool,
            color: activeColor,
            points: [point]
        )
    }

    func extendStroke(to point: CGPoint) {
        guard var stroke = currentStroke else { return }
        switch stroke.tool {
        case .pen, .highlighter:
            stroke.points.append(point)
        case .arrow, .circle, .rectangle:
            stroke.points = [stroke.points[0], point]
        }
        currentStroke = stroke
    }

    func endStroke() {
        guard let stroke = currentStroke else { return }
        // Discard zero-length strokes (a single tap with no drag).
        guard stroke.points.count > 1 else {
            currentStroke = nil
            return
        }
        pushUndoSnapshot()
        annotations.append(stroke)
        currentStroke = nil
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        annotations = previous
    }

    func clearAll() {
        guard !annotations.isEmpty else { return }
        pushUndoSnapshot()
        annotations.removeAll()
    }

    private func pushUndoSnapshot() {
        undoStack.append(annotations)
        if undoStack.count > Self.maxUndoDepth {
            undoStack.removeFirst()
        }
    }
}
