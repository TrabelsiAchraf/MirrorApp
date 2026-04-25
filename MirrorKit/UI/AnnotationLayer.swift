import SwiftUI
import CoreGraphics

/// Pure rendering helper used by both the live `AnnotationLayer` and the
/// `AnnotationCompositor` (snapshot output). Single source of truth — what
/// the user sees on screen is what the PNG contains.
enum AnnotationDrawing {
    static func draw(_ annotation: Annotation, in context: GraphicsContext, size: CGSize) {
        let denormalized = annotation.points.map {
            CGPoint(x: $0.x * size.width, y: $0.y * size.height)
        }
        let strokeColor = annotation.color.color
        let lineWidth = annotation.tool.defaultStrokeWidth

        switch annotation.tool {
        case .pen:
            guard !denormalized.isEmpty else { return }
            var path = Path()
            path.move(to: denormalized[0])
            for p in denormalized.dropFirst() { path.addLine(to: p) }
            context.stroke(
                path,
                with: .color(strokeColor),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )

        case .highlighter:
            guard !denormalized.isEmpty else { return }
            var path = Path()
            path.move(to: denormalized[0])
            for p in denormalized.dropFirst() { path.addLine(to: p) }
            context.stroke(
                path,
                with: .color(strokeColor.opacity(0.35)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )

        case .arrow:
            guard denormalized.count == 2 else { return }
            drawArrow(from: denormalized[0], to: denormalized[1], in: context, color: strokeColor, width: lineWidth)

        case .circle:
            guard denormalized.count == 2 else { return }
            let rect = boundingRect(denormalized[0], denormalized[1])
            context.stroke(Path(ellipseIn: rect), with: .color(strokeColor), lineWidth: lineWidth)

        case .rectangle:
            guard denormalized.count == 2 else { return }
            let rect = boundingRect(denormalized[0], denormalized[1])
            context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(strokeColor), lineWidth: lineWidth)
        }
    }

    private static func boundingRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    private static func drawArrow(
        from start: CGPoint,
        to end: CGPoint,
        in context: GraphicsContext,
        color: Color,
        width: CGFloat
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 14
        let p1 = CGPoint(
            x: end.x - headLength * cos(angle - .pi / 6),
            y: end.y - headLength * sin(angle - .pi / 6)
        )
        let p2 = CGPoint(
            x: end.x - headLength * cos(angle + .pi / 6),
            y: end.y - headLength * sin(angle + .pi / 6)
        )
        path.addLine(to: p1)
        path.move(to: end)
        path.addLine(to: p2)
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
    }
}

/// Live SwiftUI overlay for drawing annotations on top of the mirror video.
/// Captures gestures, normalizes coordinates to [0,1], and forwards them to
/// the shared AnnotationCanvas.
struct AnnotationLayer: View {
    let canvas: AnnotationCanvas

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                for annotation in canvas.annotations {
                    AnnotationDrawing.draw(annotation, in: context, size: size)
                }
                if let inflight = canvas.currentStroke {
                    AnnotationDrawing.draw(inflight, in: context, size: size)
                }
            }
            .gesture(drawingGesture(in: geo.size))
        }
    }

    private func drawingGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let normalized = CGPoint(
                    x: max(0, min(1, value.location.x / size.width)),
                    y: max(0, min(1, value.location.y / size.height))
                )
                if canvas.currentStroke == nil {
                    canvas.beginStroke(at: normalized)
                } else {
                    canvas.extendStroke(to: normalized)
                }
            }
            .onEnded { _ in canvas.endStroke() }
    }
}
