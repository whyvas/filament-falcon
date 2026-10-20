#!/usr/bin/env bash
# Download real Earth/Moon textures + build the Fredericton OSM detail region into
# ~/.local/share/filament-falcon/assets (outside the repo). Safe to re-run: finished files
# are skipped, partial ones resume, each file has fallback URLs (next one on 404 / timeout).
# Offline / failures: the game falls back to its procedural planet and Moon.
# Usage (from anywhere: repo root, game/ or game/tools/):
#   tools/fetch_assets.sh [--months=all|7] [--region=fredericton] [--bbox=S,W,N,E] [--no-region]
# Needs curl; python3-numpy + python3-pil for the TIF/GEBCO conversion and the region.
GAME_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)" || { echo "fetch_assets: cannot find the game folder" >&2; exit 1; }
cd "$GAME_DIR" || exit 1
A="${XDG_DATA_HOME:-$HOME/.local/share}/filament-falcon/assets"
mkdir -p "$A" || { echo "fetch_assets: cannot create $A" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "fetch_assets: curl is missing (sudo apt install curl)" >&2; exit 1; }
HAVE_PY=1
python3 -c "import numpy, PIL" 2>/dev/null || { HAVE_PY=0; echo "note: python3-numpy / python3-pil missing: Moon + elevation conversion and the OSM region are skipped (sudo apt install python3-numpy python3-pil)"; }
MONTHS=all; REGION=fredericton; BBOX=45.915,-66.705,46.005,-66.575; DO_REGION=1
for a in "$@"; do case "$a" in
  --months=*) MONTHS="${a#*=}" ;; --region=*) REGION="${a#*=}" ;;
  --bbox=*) BBOX="${a#*=}" ;; --no-region) DO_REGION=0 ;;
  -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
  *) echo "fetch_assets: unknown option $a (see --help)" >&2; exit 2 ;; esac; done
N=https://eoimages.gsfc.nasa.gov/images/imagerecords
S=https://svs.gsfc.nasa.gov/vis/a000000/a004700/a004720     # NASA SVS CGI Moon Kit (svs.gsfc.nasa.gov/4720)
FAIL=0
get() {  # dest url [fallback urls...]: first URL that works wins (all public domain NASA data)
  local dest="$1"; shift
  [ -s "$A/$dest" ] && return 0
  echo "  $dest"
  for u in "$@"; do
    if curl -fL --retry 2 --connect-timeout 20 -C - --progress-bar -o "$A/$dest.part" "$u" || \
       { rm -f "$A/$dest.part"; curl -fL --retry 1 --connect-timeout 20 --progress-bar -o "$A/$dest.part" "$u"; }; then
      mv "$A/$dest.part" "$A/$dest"; return 0
    fi
    rm -f "$A/$dest.part"
    echo "  ! $u failed, trying the next source..."
  done
  echo "  ! $dest: no source worked (re-run later)"; FAIL=1; return 1
}
echo "Fetching Earth/Moon textures into $A (~60 MB, first run only)..."
IDS=(73580 73605 73630 73655 73701 73726 74092 74117 74142 74167 74192 74218)
for m in $(seq 1 12); do
  [ "$MONTHS" != all ] && [ "$m" != "$MONTHS" ] && continue
  id=${IDS[$((m-1))]}; mm=$(printf %02d "$m")
  get "earth_day_$mm.jpg" "$N/$((id/1000*1000))/$id/world.2004$mm.3x5400x2700.jpg"
done
get earth_night.jpg "$N/144000/144898/BlackMarble_2016_3km.jpg"
get earth_clouds.jpg "$N/57000/57747/cloud_combined_2048.jpg"
[ "$HAVE_PY" = 1 ] && get gebco_raw.png "$N/73000/73934/gebco_08_rev_elev_21600x10800.png"
# Moon: LROC colour (13 MB 4k TIF -> 3.3 MB 2k TIF -> 0.5 MB 2k JPG -> 1k JPG) and LOLA
# heights (2 MB uint16 TIF -> 4 MB float TIF -> 0.1 MB 8-bit JPG). The JPGs need no Pillow.
if [ ! -s "$A/moon_color.jpg" ]; then
  if [ "$HAVE_PY" = 1 ]; then
    get moon_color_src "$S/lroc_color_poles_4k.tif" "$S/lroc_color_poles_2k.tif" "$S/lroc_color_2k.jpg" "$S/lroc_color_poles_1k.jpg"
  else
    get moon_color.jpg "$S/lroc_color_2k.jpg" "$S/lroc_color_poles_1k.jpg"
  fi
fi
if [ "$HAVE_PY" = 1 ] && [ ! -s "$A/moon_height.png" ]; then
  get moon_ldem_src "$S/ldem_4_uint.tif" "$S/ldem_4.tif" "$S/ldem_3_8bit.jpg"
fi
curl -fsm 15 "https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=TLE" -o "$A/iss.tle.part" && \
  grep -q "^2 25544" "$A/iss.tle.part" && mv "$A/iss.tle.part" "$A/iss.tle" && echo "  iss.tle (REAL ISS mission)"
rm -f "$A/iss.tle.part"
if [ "$HAVE_PY" = 1 ]; then
python3 - "$A" <<'P' || { echo "  ! conversion failed (see above)"; FAIL=1; }
import os, sys
from PIL import Image
import numpy as np
Image.MAX_IMAGE_PIXELS = None
A = sys.argv[1]
def conv(src, dst, fn):
    s, d = os.path.join(A, src), os.path.join(A, dst)
    if os.path.exists(s) and not os.path.exists(d):
        fn(Image.open(s)).save(d)
        print("  ->", dst)
def height16(im, size):
    # any height image (uint16 / float TIF, 8-bit JPG / PNG) -> normalised 16-bit PNG
    a = np.asarray(im.convert("F") if im.mode not in ("F", "I;16", "I") else im, dtype=np.float32)
    if a.ndim == 3:
        a = a.mean(axis=2)
    a = (a - a.min()) / max(float(a.max() - a.min()), 1e-6)
    a = np.asarray(Image.fromarray(a, "F").resize(size, Image.BILINEAR))
    return Image.fromarray((np.clip(a, 0, 1) * 65535).astype(np.uint16))
conv("gebco_raw.png", "earth_height.png", lambda im: im.convert("L").resize((4096, 2048), Image.BILINEAR))
conv("moon_color_src", "moon_color.jpg", lambda im: (lambda c: c.resize((min(c.width, 4096), min(c.width, 4096) // 2), Image.BILINEAR))(
    Image.fromarray((np.asarray(im, dtype=np.float32) / 257.0).astype(np.uint8)).convert("RGB") if im.mode.startswith("I;16") or im.mode == "RGB;16" else im.convert("RGB")))
conv("moon_ldem_src", "moon_height.png", lambda im: height16(im, (1440, 720)))
P
fi
if [ "$DO_REGION" = 1 ] && [ "$HAVE_PY" = 1 ] && [ ! -f "$A/regions/$REGION/manifest.json" ]; then
  echo "Building OSM detail region '$REGION' ($BBOX; Overpass + terrain tiles, a few minutes)..."
  python3 tools/build_region.py --name "$REGION" --bbox "$BBOX" --out "$A/regions/$REGION" || { echo "  ! region build failed"; FAIL=1; }
fi
[ "$FAIL" = 0 ] && touch "$A/.fetched"
du -sh "$A" 2>/dev/null
echo "Done$( [ "$FAIL" = 1 ] && echo " (some items failed; re-run tools/fetch_assets.sh when online)")."
exit 0
