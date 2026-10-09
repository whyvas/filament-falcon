#!/usr/bin/env bash
# Renders the README screenshots with the real Forward+ Vulkan renderer on a virtual X server
# using Mesa's software Vulkan driver (lavapipe). Slow (~minutes) but needs no GPU.
#   GODOT=/path/to/godot tests/run_screenshots.sh [only=shot1,shot2]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
LVP=$(ls /usr/share/vulkan/icd.d/lvp_icd*.json 2>/dev/null | head -1 || true)
[ -n "$LVP" ] && export VK_ICD_FILENAMES="$LVP"
EXTRA=()
[ $# -gt 0 ] && EXTRA+=("--$1")
xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path . --audio-driver Dummy --resolution 1920x1080 \
  -- --dev --quality=${QUALITY:-high} --screenshots=../docs/game/screenshots "${EXTRA[@]}"
# Keep the repo lean: convert to JPEG (needs python3-pil; PNGs are kept if it is missing)
python3 - <<'PY' || true
import glob, os
from PIL import Image
for f in glob.glob("../docs/game/screenshots/*.png"):
    Image.open(f).convert("RGB").save(f[:-4] + ".jpg", quality=88, optimize=True)
    os.remove(f)
PY
