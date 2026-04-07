#!/usr/bin/env bash
# Interactive capture of MirrorKit window for App Store screenshots.
# Usage: ./capture.sh <name>
#   e.g.: ./capture.sh 01-mirroring

set -e

NAME="${1:-screenshot}"
RAW_DIR="$(dirname "$0")/raw"
mkdir -p "$RAW_DIR"

echo "When the crosshair appears, click on the MirrorKit window to capture it."
echo "(Press Esc to cancel.)"
sleep 1

# -W = capture a window by clicking on it
# -o = no shadow
screencapture -o -W "$RAW_DIR/${NAME}.png"

echo "Saved: $RAW_DIR/${NAME}.png"
sips -g pixelWidth -g pixelHeight "$RAW_DIR/${NAME}.png" | tail -n +2
