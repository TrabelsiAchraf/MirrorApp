# Fiche App Store — Français (France) — MirrorKit 1.2.0

Limites de caractères : nom 30, sous-titre 30, texte promotionnel 170, mots-clés 100, description 4000.

## Nom (30)

MirrorKit – iPhone sur Mac

## Sous-titre (30)

Recopie d’écran iPhone en USB

## Texte promotionnel (170)

Affichez l’écran de votre iPhone sur votre Mac en USB, en temps réel, avec une bordure réaliste. Enregistrez, capturez, annotez. Désormais en français.

## Mots-clés (100)

iphone,recopie,miroir,écran,usb,enregistrer,capture,démo,présentation,quicktime,affichage,mirror

## Description (4000)

MirrorKit affiche l’écran de votre iPhone ou de votre iPad sur votre Mac avec un simple câble USB. Pas de Wi‑Fi, pas de code d’appairage, pas de latence : le même pipeline que QuickTime Player, dans une fenêtre qui ressemble à votre appareil.

POURQUOI MIRRORKIT
• Temps réel en USB — une connexion filaire, donc une vidéo fluide et aucune configuration réseau.
• Une bordure fidèle — MirrorKit reconnaît le modèle de votre iPhone depuis le flux vidéo et dessine la bordure et la Dynamic Island correspondantes. Noir, argent, or, ou sans bordure.
• Pensé pour présenter — mode étendu plein écran sur un fond soigné, fenêtre toujours au premier plan, rotation en paysage d’une touche.

CAPTURE
• Enregistrez l’écran de votre iPhone en vidéo d’un clic ou avec ⌘R.
• Prenez une capture avec ⌘S, avec le vrai son d’obturateur.
• Annotez en direct par-dessus l’écran recopié : stylo, cercles, annulation, effacement.
• Choisissez le dossier où vont vos vidéos et vos captures.

PLUSIEURS APPAREILS
• Branchez plusieurs iPhone ou iPad et passez de l’un à l’autre depuis la barre d’outils.
• MirrorKit se souvient du dernier appareil choisi.

CONÇU POUR LE MAC
• App native, écrite en Swift avec SwiftUI et AppKit. Pas d’Electron, pas de service en arrière-plan.
• Fenêtre sans bordure avec ses propres feux, barre d’outils au survol, icône dans la barre des menus, réouverture depuis le Dock.
• Tout au clavier : ⌘R enregistrer, ⌘S capturer, ⌘T toujours au premier plan, ⌘← ⌘→ pivoter, ⌘0 réinitialiser le zoom, A annoter.
• Libellés VoiceOver sur chaque contrôle.
• Disponible en français et en anglais.

QUAND ÇA COINCE
Si un iPhone refuse de diffuser son écran, MirrorKit vous dit exactement quoi vérifier — redémarrer l’iPhone, le déverrouiller, les restrictions Temps d’écran, les profils de gestion — au lieu de vous laisser devant un écran noir.

COMMENT ÇA MARCHE
MirrorKit s’appuie sur les frameworks publics CoreMediaIO et AVFoundation qu’utilise QuickTime Player pour « Nouvel enregistrement vidéo ». macOS demande l’accès à la caméra parce qu’il présente l’écran de l’iPhone comme une source vidéo ; MirrorKit n’enregistre et ne transmet rien sans votre action, et tout reste sur votre Mac.

CONFIGURATION REQUISE
• macOS 14 Sonoma ou ultérieur.
• Un iPhone ou un iPad branché en USB et déverrouillé ; touchez « Se fier à cet ordinateur » la première fois.

MirrorKit est un achat unique. Pas d’abonnement, pas de compte, pas de suivi.

## Nouveautés (4000)

• Interface en français
• Nom du modèle et bordure fidèles à votre iPhone, détectés depuis le flux vidéo
• Un guide clair quand un iPhone refuse la recopie, au lieu d’un écran noir
• Mémorise le dernier iPhone choisi quand plusieurs sont branchés
• Réglages accessibles depuis le menu des appareils et l’icône de la barre des menus
• L’icône du Dock rouvre la fenêtre
• Libellés VoiceOver sur la barre d’outils
• Corrections : fenêtre Réglages qui ne s’ouvrait pas sur macOS 15+, image figée au changement d’appareil

## Captures d’écran à préparer (interface en français)

Lancer l’app avec l’argument `-AppleLanguages "(fr)"` (Xcode › Scheme › Run › Arguments, ou `open MirrorKit.app --args -AppleLanguages "(fr)"`).
1. Écran d’accueil de l’iPhone recopié avec la bordure noire classique, barre d’outils visible.
2. Mode étendu sur un fond dégradé (présentation).
3. Mode annotation avec un cercle tracé et le panneau latéral.
4. Menu des appareils ouvert avec deux iPhone listés.
5. Fenêtre Réglages (emplacement, style de bordure, arrière-plan).
Tailles : 1280×800 ou 2560×1600 minimum pour Mac ; capturer la fenêtre sur un bureau uni.
