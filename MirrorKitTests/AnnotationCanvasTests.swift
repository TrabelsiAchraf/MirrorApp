import Testing
import CoreGraphics
@testable import MirrorKit

@Suite("AnnotationCanvas")
@MainActor
struct AnnotationCanvasTests {
    @Test("Empty canvas has no annotations")
    func emptyCanvas() {
        let canvas = AnnotationCanvas()
        #expect(canvas.annotations.isEmpty)
        #expect(canvas.currentStroke == nil)
    }

    @Test("endStroke commits a multi-point stroke")
    func endStrokeCommits() {
        let canvas = AnnotationCanvas()
        canvas.beginStroke(at: CGPoint(x: 0.1, y: 0.1))
        canvas.extendStroke(to: CGPoint(x: 0.5, y: 0.5))
        canvas.endStroke()
        #expect(canvas.annotations.count == 1)
        #expect(canvas.currentStroke == nil)
    }

    @Test("Single-point stroke (no drag) is discarded on endStroke")
    func singlePointStrokeDiscarded() {
        let canvas = AnnotationCanvas()
        canvas.beginStroke(at: CGPoint(x: 0.5, y: 0.5))
        canvas.endStroke()
        #expect(canvas.annotations.isEmpty)
        #expect(canvas.currentStroke == nil)
    }

    @Test("extendStroke on .pen appends every point")
    func extendStrokePenAppends() {
        let canvas = AnnotationCanvas()
        canvas.activeTool = .pen
        canvas.beginStroke(at: CGPoint(x: 0.0, y: 0.0))
        canvas.extendStroke(to: CGPoint(x: 0.1, y: 0.0))
        canvas.extendStroke(to: CGPoint(x: 0.2, y: 0.0))
        canvas.extendStroke(to: CGPoint(x: 0.3, y: 0.0))
        #expect(canvas.currentStroke?.points.count == 4)
    }

    @Test("extendStroke on .circle replaces the endpoint")
    func extendStrokeCircleReplaces() {
        let canvas = AnnotationCanvas()
        canvas.activeTool = .circle
        canvas.beginStroke(at: CGPoint(x: 0.0, y: 0.0))
        canvas.extendStroke(to: CGPoint(x: 0.1, y: 0.1))
        canvas.extendStroke(to: CGPoint(x: 0.5, y: 0.5))
        #expect(canvas.currentStroke?.points.count == 2)
        #expect(canvas.currentStroke?.points.last == CGPoint(x: 0.5, y: 0.5))
    }

    @Test("undo reverts the last committed stroke")
    func undoRevertsLastStroke() {
        let canvas = AnnotationCanvas()
        canvas.beginStroke(at: .zero)
        canvas.extendStroke(to: CGPoint(x: 0.5, y: 0.5))
        canvas.endStroke()
        #expect(canvas.annotations.count == 1)
        canvas.undo()
        #expect(canvas.annotations.isEmpty)
    }

    @Test("undo on empty stack is a no-op")
    func undoEmptyIsNoOp() {
        let canvas = AnnotationCanvas()
        canvas.undo()
        #expect(canvas.annotations.isEmpty)
    }

    @Test("undo stack capped at 20")
    func undoStackCapped() {
        let canvas = AnnotationCanvas()
        for i in 0..<25 {
            canvas.beginStroke(at: CGPoint(x: Double(i) * 0.01, y: 0))
            canvas.extendStroke(to: CGPoint(x: Double(i) * 0.01 + 0.05, y: 0.05))
            canvas.endStroke()
        }
        #expect(canvas.annotations.count == 25)

        // Pop all 20 undo snapshots
        for _ in 0..<20 {
            canvas.undo()
        }
        // After 20 undos, the 21st undo is a no-op (stack is empty).
        // We've reverted to whatever annotations existed before the oldest
        // remembered snapshot — which is the 5th stroke (since strokes 1-5
        // were dropped from the cap).
        #expect(canvas.annotations.count == 5)
        canvas.undo()  // no-op
        #expect(canvas.annotations.count == 5)
    }

    @Test("clearAll removes annotations and is undoable")
    func clearAllUndoable() {
        let canvas = AnnotationCanvas()
        canvas.beginStroke(at: .zero)
        canvas.extendStroke(to: CGPoint(x: 0.5, y: 0.5))
        canvas.endStroke()
        canvas.beginStroke(at: CGPoint(x: 0.6, y: 0.6))
        canvas.extendStroke(to: CGPoint(x: 0.9, y: 0.9))
        canvas.endStroke()
        #expect(canvas.annotations.count == 2)

        canvas.clearAll()
        #expect(canvas.annotations.isEmpty)

        canvas.undo()
        #expect(canvas.annotations.count == 2)
    }

    @Test("Toggling annotation mode off clears any in-flight stroke")
    func togglingOffClearsInFlight() {
        let canvas = AnnotationCanvas()
        canvas.isAnnotationModeActive = true
        canvas.beginStroke(at: CGPoint(x: 0.1, y: 0.1))
        canvas.extendStroke(to: CGPoint(x: 0.4, y: 0.4))
        #expect(canvas.currentStroke != nil)

        canvas.isAnnotationModeActive = false
        #expect(canvas.currentStroke == nil)
    }
}
