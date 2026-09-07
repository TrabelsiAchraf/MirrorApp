#!/usr/bin/env bash
# Compose every PNG in raw/ onto a 2880x1800 gradient background
# with a marketing headline + subtitle on top.
#
# Output goes into final/ at App Store Mac size (2880x1800).
# Requires ImageMagick: brew install imagemagick
#
# To customize copy per screenshot, edit the headline_for / subtitle_for
# functions below. Match by the raw file basename (without .png).

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
# Language of the marketing copy: "en" (default) or "fr".
#   ./compose.sh        -> raw/    -> final/
#   ./compose.sh fr     -> raw/    -> final-fr/
# The raw window captures are shared; only the copy on top changes.
LANG_CODE="${1:-en}"
RAW="$DIR/raw"
if [ "$LANG_CODE" = "en" ]; then OUT="$DIR/final"; else OUT="$DIR/final-$LANG_CODE"; fi
mkdir -p "$OUT"

WIDTH=2880
HEIGHT=1800
BG="$DIR/bg.png"

if ! command -v magick >/dev/null 2>&1; then
    echo "ImageMagick is required: brew install imagemagick"
    exit 1
fi

# ---- Marketing copy per screenshot --------------------------------------
# Add a case branch for every raw/<name>.png file you capture.
headline_for() {
    if [ "$LANG_CODE" = "fr" ]; then
        case "$1" in
            01-welcome)        echo "Votre iPhone, sur votre Mac" ;;
            02-waiting)        echo "Branchez. C’est tout." ;;
            03-mirroring-home) echo "Recopie en temps réel, en USB" ;;
            04-mirroring-app)  echo "Fidèle au pixel, sans latence" ;;
            05-fullscreen)     echo "Plein écran pour vos présentations" ;;
            06-about)          echo "Natif. Léger. Achat unique." ;;
            *)                 echo "MirrorKit" ;;
        esac
        return
    fi
    case "$1" in
        01-welcome)        echo "Your iPhone, on your Mac" ;;
        02-waiting)        echo "Just plug in. That's it." ;;
        03-mirroring-home) echo "Real-time mirroring over USB" ;;
        04-mirroring-app)  echo "Pixel-perfect, zero latency" ;;
        05-fullscreen)     echo "Fullscreen for presentations" ;;
        06-about)          echo "Native. Lightweight. One-time price." ;;
        *)                 echo "MirrorKit" ;;
    esac
}

subtitle_for() {
    if [ "$LANG_CODE" = "fr" ]; then
        case "$1" in
            01-welcome)        echo "La façon la plus simple de recopier l’écran de votre iPhone." ;;
            02-waiting)        echo "N’importe quel iPhone, un câble USB, aucune configuration." ;;
            03-mirroring-home) echo "Propulsé par le même moteur que QuickTime Player." ;;
            04-mirroring-app)  echo "Démos d’apps, tutoriels vidéo, débogage en direct." ;;
            05-fullscreen)     echo "Un clic pour étendre. Idéal en réunion." ;;
            06-about)          echo "Payez une fois. À vous pour toujours." ;;
            *)                 echo "" ;;
        esac
        return
    fi
    case "$1" in
        01-welcome)        echo "The simplest way to mirror your iPhone screen." ;;
        02-waiting)        echo "Connect any iPhone with a USB cable — no setup." ;;
        03-mirroring-home) echo "Powered by the same engine as QuickTime Player." ;;
        04-mirroring-app)  echo "Demo apps, record tutorials, debug live." ;;
        05-fullscreen)     echo "One click to expand. Perfect for meetings." ;;
        06-about)          echo "Pay once. Yours forever." ;;
        *)                 echo "" ;;
    esac
}
# -------------------------------------------------------------------------

# Generate the dark purple gradient background once
magick -size ${WIDTH}x${HEIGHT} \
    gradient:'#1F1B40-#0D0D1F' \
    "$BG"

# Layout
TEXT_TOP=180                # vertical position of headline
HEADLINE_SIZE=120
SUBTITLE_SIZE=56
HEADLINE_FONT="Helvetica-Bold"
SUBTITLE_FONT="Helvetica"
TEXT_AREA_HEIGHT=380        # space reserved at the top for the text
SCREENSHOT_TOP_MARGIN=$((TEXT_AREA_HEIGHT + 40))

shopt -s nullglob
found=0
for src in "$RAW"/*.png; do
    found=1
    name=$(basename "$src" .png)
    out="$OUT/${name}.png"

    headline=$(headline_for "$name")
    subtitle=$(subtitle_for "$name")

    src_w=$(sips -g pixelWidth "$src" | tail -1 | awk '{print $2}')
    src_h=$(sips -g pixelHeight "$src" | tail -1 | awk '{print $2}')

    # Available area for the screenshot below the text
    avail_h=$((HEIGHT - SCREENSHOT_TOP_MARGIN - 120))
    avail_w=$((WIDTH * 75 / 100))

    # Scale to fit within the available area, preserving aspect ratio
    target_h=$avail_h
    target_w=$((src_w * target_h / src_h))
    if [ "$target_w" -gt "$avail_w" ]; then
        target_w=$avail_w
        target_h=$((src_h * target_w / src_w))
    fi

    # Vertical center of the lower area (below the text block)
    lower_top=$SCREENSHOT_TOP_MARGIN
    lower_h=$((HEIGHT - lower_top))
    shot_y=$((lower_top + (lower_h - target_h) / 2))

    magick "$BG" \
        -font "$HEADLINE_FONT" -pointsize $HEADLINE_SIZE -fill white \
        -gravity north -annotate +0+${TEXT_TOP} "$headline" \
        -font "$SUBTITLE_FONT" -pointsize $SUBTITLE_SIZE -fill '#B8B5D6' \
        -gravity north -annotate +0+$((TEXT_TOP + HEADLINE_SIZE + 40)) "$subtitle" \
        \( "$src" -resize ${target_w}x${target_h} \) \
        -gravity north -geometry +0+${shot_y} -composite \
        "$out"

    echo "Composed: $out"
    echo "  headline: $headline"
    echo "  subtitle: $subtitle"
done

if [ "$found" = "0" ]; then
    echo "No PNG files found in $RAW. Capture the windows first (see capture.sh)."
    exit 1
fi

echo ""
echo "Done. Upload files from $OUT to App Store Connect."
