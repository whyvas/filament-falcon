# Real Earth, Moon and OSM detail regions

`./run.sh` runs `game/tools/fetch_assets.sh` once on first launch (skip with `--no-fetch`; re-run by hand any time).
Files go to `~/.local/share/filament-falcon/assets` (outside the repo). If the download fails or you're offline, the game uses the procedural planet.

- **Earth:** NASA Blue Marble, all 12 months, 5400×2700 (pick the month in `settings.json` → `graphics.earth_month`). Also Black Marble night lights, cloud cover (drifting, casts shadows) and GEBCO elevation.
- **Moon:** LROC colour plus a LOLA heightmap, converted with Pillow.
- **Region:** `tools/build_region.py --name NAME --bbox S,W,N,E`. It pulls OpenStreetMap data (Overpass) and AWS terrain tiles, then writes chunk JSON to `assets/regions/NAME`. Choose it in game with `--region=NAME`, or point at any folder with `--region-dir=DIR`.
  - The default is Fredericton, NB, about 10×10 km.
  - In game: Sandbox → **FREDERICTON** (a descent from 4 km).
- **Packages:** `sudo apt install curl python3-numpy python3-pil`.
- **Test:** `godot --headless --path game -- --region-test --region-dir=DIR`.

**Approximate:**
- The planet is 600 km, so Earth textures are stretched over a small globe. KSC is rotated to sit under the game's pad.
- The procedural pad and runway may not match the coastline in the texture.
- Moon relief fades out near the landing site.
- Roofs are simple gabled or hipped. Building heights use Atlantic Canada defaults when OSM has no tags.
- Multipolygon holes are ignored. Each building sits at the ground height of its centroid.
- Bridges are flat. Landuse polygons stay within one chunk. The curvature bend is approximate.
- Overpass can rate-limit you. If it does, re-run later.
