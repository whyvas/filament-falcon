#!/usr/bin/env bash
# Download real Earth/Moon textures + build the Fredericton OSM detail region into
# ~/.local/share/filament-falcon/assets (outside the repo). Safe to re-run: finished files
# are skipped, partial ones resume. Offline / failures: the game falls back to procedural.
# Usage: tools/fetch_assets.sh [--months=all|7] [--region=fredericton] [--bbox=S,W,N,E] [--no-region]
# Needs curl; python3-numpy + python3-pil for the moon/GEBCO conversion and the region.
cd "$(dirname "$0")/.."
A="${XDG_DATA_HOME:-$HOME/.local/share}/filament-falcon/assets"
mkdir -p "$A"
MONTHS=all; REGION=fredericton; BBOX=45.915,-66.705,46.005,-66.575; DO_REGION=1
for a in "$@"; do case "$a" in
  --months=*) MONTHS="${a#*=}" ;; --region=*) REGION="${a#*=}" ;;
  --bbox=*) BBOX="${a#*=}" ;; --no-region) DO_REGION=0 ;; esac; done
N=https://eoimages.gsfc.nasa.gov/images/imagerecords
S=https://svs.gsfc.nasa.gov/vis/a000000/a004700/a004720
FAIL=0
get() {  # url dest
  [ -s "$A/$2" ] && return 0
  echo "  $2"
  if curl -fL --retry 2 -C - --progress-bar -o "$A/$2.part" "$1"; then mv "$A/$2.part" "$A/$2"
  else echo "  ! failed: $1"; FAIL=1; return 1; fi
}
echo "Fetching Earth/Moon textures into $A (~60 MB, first run only)..."
IDS=(73580 73605 73630 73655 73701 73726 74092 74117 74142 74167 74192 74218)
for m in $(seq 1 12); do
  [ "$MONTHS" != all ] && [ "$m" != "$MONTHS" ] && continue
  id=${IDS[$((m-1))]}; mm=$(printf %02d "$m")
  get "$N/$((id/1000*1000))/$id/world.2004$mm.3x5400x2700.jpg" "earth_day_$mm.jpg"
done
get "$N/144000/144898/BlackMarble_2016_3km.jpg" earth_night.jpg
get "$N/57000/57747/cloud_combined_2048.jpg" earth_clouds.jpg
get "$N/73000/73934/gebco_08_rev_elev_21600x10800.png" gebco_raw.png
get "$S/lroc_color_poles_4k.tif" moon_color.tif
get "$S/ldem_4.tif" moon_ldem.tif
python3 - "$A" <<'P' || echo "  ! conversion skipped (sudo apt install python3-pil python3-numpy)"
import os, sys
from PIL import Image
import numpy as np
Image.MAX_IMAGE_PIXELS = None
A = sys.argv[1]
def conv(src, dst, fn):
    s, d = os.path.join(A, src), os.path.join(A, dst)
    if os.path.exists(s) and not os.path.exists(d):
        fn(Image.open(s)).save(d); print("  ->", dst)
conv("gebco_raw.png", "earth_height.png", lambda im: im.convert("L").resize((4096, 2048), Image.BILINEAR))
conv("moon_color.tif", "moon_color.jpg", lambda im: im.convert("RGB").resize((4096, 2048), Image.BILINEAR))
def ldem(im):
    a = np.asarray(im, dtype=np.float32)
    a = (a - a.min()) / max(float(a.max() - a.min()), 1e-6) * 65535.0
    return Image.fromarray(a.astype(np.uint16)).resize((1440, 720), Image.BILINEAR)
conv("moon_ldem.tif", "moon_height.png", ldem)
P
if [ "$DO_REGION" = 1 ] && [ ! -f "$A/regions/$REGION/manifest.json" ]; then
  echo "Building OSM detail region '$REGION' ($BBOX; Overpass + terrain tiles, a few minutes)..."
  python3 tools/build_region.py --name "$REGION" --bbox "$BBOX" --out "$A/regions/$REGION" || { echo "  ! region build failed"; FAIL=1; }
fi
[ "$FAIL" = 0 ] && touch "$A/.fetched"
du -sh "$A" 2>/dev/null
echo "Done$( [ "$FAIL" = 1 ] && echo " (some items failed; re-run tools/fetch_assets.sh when online)")."
exit 0
