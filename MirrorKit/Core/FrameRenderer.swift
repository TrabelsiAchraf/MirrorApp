import SwiftUI
import AppKit
import CoreMedia
import CoreVideo

/// Vue NSViewRepresentable qui affiche les frames vidéo via un CALayer
struct FrameRenderer: NSViewRepresentable {
    /// Référence vers le layer d'affichage pour mise à jour externe
    let displayLayer: VideoDisplayLayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = displayLayer
        displayLayer.contentsGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Pas de mise à jour SwiftUI nécessaire — le layer est mis à jour directement
    }
}

/// CALayer spécialisé pour l'affichage des frames vidéo
/// Mis à jour directement depuis le callback de capture (sur le main thread)
final class VideoDisplayLayer: CALayer {

    override init() {
        super.init()
        // Désactiver les animations implicites pour éviter le lag
        self.actions = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull()
        ]
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Affiche un CMSampleBuffer — doit être appelé sur le main thread
    func displaySampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        displayPixelBuffer(pixelBuffer)
    }

    /// Affiche un CVPixelBuffer directement
    func displayPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        // Créer une CIImage puis CGImage pour l'affichage via CALayer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        self.contents = cgImage
    }
}
