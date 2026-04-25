import SwiftUI
import AppKit

/// Composites a list of annotations on top of a frame NSImage and returns a
/// new NSImage with the same dimensions. Used by `takeSnapshot()` to bake
/// annotations into the saved PNG.
enum AnnotationCompositor {
    @MainActor
    static func compositeSync(
        frame: NSImage,
        annotations: [Annotation],
        canvasSize: CGSize
    ) -> NSImage {
        guard !annotations.isEmpty else { return frame }

        // Render the annotation layer to a CGImage at the frame's dimensions.
        let renderer = ImageRenderer(content:
            AnnotationLayerStaticRenderer(annotations: annotations)
                .frame(width: canvasSize.width, height: canvasSize.height)
        )
        renderer.scale = 1.0
        guard let overlay = renderer.cgImage else { return frame }

        // Composite frame + overlay into a new NSImage.
        let result = NSImage(size: frame.size)
        result.lockFocus()
        defer { result.unlockFocus() }

        frame.draw(in: NSRect(origin: .zero, size: frame.size))

        if let context = NSGraphicsContext.current?.cgContext {
            let rect = CGRect(origin: .zero, size: frame.size)
            context.draw(overlay, in: rect)
        }

        return result
    }
}

/// Static (no-gesture) variant of AnnotationLayer used inside the compositor.
private struct AnnotationLayerStaticRenderer: View {
    let annotations: [Annotation]

    var body: some View {
        Canvas { context, size in
            for annotation in annotations {
                AnnotationDrawing.draw(annotation, in: context, size: size)
            }
        }
    }
}
