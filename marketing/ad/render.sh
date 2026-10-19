#!/bin/sh
# Build the ad « The toys break out » (see README.md). Re-renders only what changed.
#   ./render.sh                 final 1080x1920 video: build/sketches-ad-vertical.mp4
#   ./render.sh --preview       fast low-res animatic: build/preview/sketches-ad-preview.mp4
#   ./render.sh --shots 2,7     only these shots; --force re-renders them; --every 3 (preview) one frame in three
set -eu
cd "$(dirname "$0")"
exec python3 -I scripts/build.py "$@"
