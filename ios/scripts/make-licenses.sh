#!/bin/sh
# Collects the licences of everything the toys ship (Swift packages, the guitar
# recordings) into Toys/Resources/Licenses.txt, shown on the parents page.
# Run after adding or updating a package: ios/scripts/make-licenses.sh [DerivedData]
set -eu
cd "$(dirname "$0")/.."
DD="${1:-$PWD/build/dd}"
C="$DD/SourcePackages/checkouts"
[ -d "$C" ] || { echo "no packages at $C: build once first" >&2; exit 1; }
OUT=Toys/Resources/Licenses.txt
{
  echo "Sketches for kids! and Leontine Tube use these open-source works. Thank you to their authors."
  echo
  for f in AudioKit/LICENSE AudioKitEX/LICENSE SoundpipeAudioKit/LICENSE SoundpipeAudioKit/Sources/Soundpipe/lib/inih/LICENSE.txt DunneAudioKit/LICENSE DunneAudioKit/Sources/CDunneAudioKit/DunneCore/Sampler/Wavpack/license.txt Tonic/LICENSE KissFFT/COPYING; do
    [ -f "$C/$f" ] || continue
    name=${f%%/*}
    case "$f" in
      *inih*) name="$name (inih)" ;;
      *Wavpack*) name="$name (WavPack)" ;;
    esac
    echo "==== $name"
    echo
    cat "$C/$f"
    echo
  done
  echo "==== Guitar recordings: FluidR3 GM SoundFont (nylon guitar, rendered to notes)"
  echo
  echo "Copyright (c) 2000-2002, 2008 Frank Wen <getfrank@gmail.com>"
  echo "Copyright (c) 2008 Toby Smithe"
  echo
  cat <<'MIT'
Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
MIT
  echo
  echo "==== Baloo 2 typeface (Sketches for kids!): SIL Open Font License 1.1, see Baloo2-OFL.txt"
} > "$OUT"
echo "wrote $OUT ($(wc -l < "$OUT") lines)"
