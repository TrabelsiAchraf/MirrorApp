import SwiftUI

/// Écran d'onboarding affiché au premier lancement
struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep = 0

    private let steps: [(icon: String, title: String, description: String)] = [
        (
            "iphone.and.arrow.forward",
            "Bienvenue dans MirrorKit",
            "Affichez l'écran de votre iPhone directement sur votre Mac. Idéal pour les présentations, le développement ou simplement garder un œil sur votre téléphone."
        ),
        (
            "cable.connector",
            "Branchez votre iPhone en USB",
            "Connectez votre iPhone à votre Mac avec un câble USB ou USB-C. MirrorKit utilise la connexion filaire pour un affichage en temps réel sans latence."
        ),
        (
            "camera.fill",
            "Autorisez l'accès caméra",
            "macOS va vous demander une permission d'accès caméra. C'est normal : votre iPhone est vu comme un périphérique de capture vidéo. Aucune donnée n'est enregistrée ni transmise."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icône
            Image(systemName: steps[currentStep].icon)
                .font(.system(size: 64))
                .foregroundStyle(.blue)
                .frame(height: 80)
                .padding(.bottom, 24)

            // Titre
            Text(steps[currentStep].title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            // Description
            Text(steps[currentStep].description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.bottom, 32)

            Spacer()

            // Indicateurs de progression
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? Color.blue : Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 24)

            // Boutons
            HStack {
                if currentStep > 0 {
                    Button("Précédent") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button("Suivant") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Commencer") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 440, height: 400)
    }
}
