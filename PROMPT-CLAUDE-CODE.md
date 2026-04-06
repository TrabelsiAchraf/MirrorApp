# MirrorKit — Prompt pour Claude Code CLI

## Comment utiliser

```bash
# Depuis le dossier où tu veux créer le projet :
claude

# Puis colle le prompt ci-dessous (ou utilise cat + pipe) :
cat PROMPT-CLAUDE-CODE.md | claude
```

---

## Prompt à envoyer

```
Tu es mon copilote pour développer MirrorKit, une app macOS native (SwiftUI + AppKit) qui affiche l'écran d'un iPhone connecté en USB sur le Mac. Le fichier MirrorKit-Plan-Technique.docx contient le plan technique complet — lis-le d'abord.

## Contexte
- Dev senior iOS, je connais Swift/SwiftUI/AppKit
- Scope v1 : mirror vidéo uniquement (pas d'interaction touch), connexion USB obligatoire
- Distribution : Mac App Store à 9,99€
- Target : macOS 14.0+ (Sonoma), Swift 5.9+, SwiftUI lifecycle

## Approche technique validée
L'app repose sur le mécanisme utilisé par QuickTime Player :
1. Activer `kCMIOHardwarePropertyAllowScreenCaptureDevices` via CoreMediaIO
2. Découvrir l'iPhone via `AVCaptureDevice.DiscoverySession` (deviceTypes: [.external], mediaType: .muxed)
3. Capturer le flux avec `AVCaptureSession` + `AVCaptureVideoDataOutput`
4. Afficher les frames via `CALayer` (ou `MTKView` pour Metal)
5. Le tout dans une `NSWindow` borderless avec aspect ratio verrouillé

## Ce que je veux que tu fasses — Phase 1 (Prototype)

Crée le projet Xcode complet avec cette structure :

```
MirrorKit/
├── MirrorKitApp.swift              // @main, SwiftUI App lifecycle
├── AppDelegate.swift               // NSApplicationDelegate pour setup CoreMediaIO au launch
├── Core/
│   ├── DeviceManager.swift         // @Observable — détection iPhone USB via CoreMediaIO + AVCaptureDevice notifications
│   ├── CaptureEngine.swift         // Actor — AVCaptureSession pipeline (input → output → delegate)
│   └── FrameRenderer.swift         // NSViewRepresentable wrapping CALayer pour afficher les CMSampleBuffer
├── UI/
│   ├── MirrorWindow.swift          // NSWindow borderless, resizable, movable, aspect ratio lock
│   ├── MirrorContentView.swift     // Vue principale : état connexion + rendu vidéo
│   └── DevicePickerView.swift      // Liste des appareils détectés (si plusieurs)
├── Models/
│   ├── ConnectedDevice.swift       // Struct : id, name, modelID, resolution
│   └── CaptureState.swift          // Enum : idle, detecting, connected, capturing, error
└── Info.plist                      // NSCameraUsageDescription obligatoire
```

## Contraintes techniques importantes

1. **CoreMediaIO init** : Appeler `CMIOObjectSetPropertyData` avec `kCMIOHardwarePropertyAllowScreenCaptureDevices` le plus tôt possible (AppDelegate.applicationDidFinishLaunching)
2. **Détection asynchrone** : Après l'activation CoreMediaIO, les devices mettent quelques secondes à apparaître. Utiliser `NotificationCenter` avec `.AVCaptureDeviceWasConnected` / `.AVCaptureDeviceWasDisconnected`
3. **Thread safety** : CaptureEngine doit être un Actor. La capture queue doit être une DispatchQueue serial haute priorité
4. **Performance** : `alwaysDiscardsLateVideoFrames = true` sur le output. Ne jamais retenir les CMSampleBuffer
5. **Pixel format** : Utiliser `kCVPixelFormatType_32BGRA` pour compatibilité CALayer
6. **Aspect ratio** : Récupérer la résolution du flux et verrouiller le ratio de la fenêtre avec `window.aspectRatio`
7. **Fenêtre** : NSWindow styleMask [.borderless, .resizable], isMovableByWindowBackground = true, coins arrondis + ombre
8. **Entitlements** : com.apple.security.device.camera = true (obligatoire), com.apple.security.app-sandbox = true

## Style de code
- Swift moderne : async/await, @Observable (pas @Published/@ObservableObject), Actor
- Pas de force unwrap sauf pour les cas triviaux (IBOutlet etc.)
- Commentaires en français
- Nommage en anglais
- Error handling propre avec do/catch

## Ce que tu NE dois PAS faire
- Pas de CocoaPods/SPM dependencies externes — 100% frameworks Apple
- Pas de storyboard/xib — tout en code (SwiftUI + AppKit programmatic)
- Pas d'interaction touch/clavier vers l'iPhone (hors scope v1)
- Pas de Wi-Fi/AirPlay (hors scope v1)

Commence par créer tous les fichiers avec le code complet et fonctionnel. Je testerai avec un iPhone physique branché en USB.
```
