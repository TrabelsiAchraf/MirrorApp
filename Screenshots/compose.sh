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
RAW="$DIR/raw"
OUT="$DIR/final"
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
    echo "No PNG files found in $RAW. Run capture.sh first."
    exit 1
fi

echo ""
echo "Done. Upload files from $OUT to App Store Connect."
