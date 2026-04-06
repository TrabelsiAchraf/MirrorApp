import Foundation

/// États possibles du pipeline de capture
enum CaptureState: Equatable {
    /// Aucune activité — en attente d'un appareil
    case idle
    /// Recherche d'appareils en cours
    case detecting
    /// Appareil connecté, prêt à capturer
    case connected(ConnectedDevice)
    /// Capture en cours — flux vidéo actif
    case capturing
    /// Erreur rencontrée
    case error(String)

    static func == (lhs: CaptureState, rhs: CaptureState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.detecting, .detecting), (.capturing, .capturing):
            return true
        case let (.connected(a), .connected(b)):
            return a.id == b.id
        case let (.error(a), .error(b)):
            return a == b
        default:
            return false
        }
    }
}
