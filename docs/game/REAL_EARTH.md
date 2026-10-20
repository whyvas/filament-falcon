# Real Earth, Moon and OSM detail regions

`./run.sh` runs `game/tools/fetch_assets.sh` once on first launch (skip with `--no-fetch`; re-run by hand any time).
Files go to `~/.local/share/filament-falcon/assets` (outside the repo). If the download fails or you're offline, the game uses the procedural planet.

- **Earth:** NASA Blue Marble, all 12 months, 5400×2700 (pick the month in `settings.json` → `graphics.earth_month`). Also Black Marble night lights, cloud cover (drifting, casts shadows) and GEBCO elevation.
- **HD Earth** (default; `--no-hd` skips it, `--hd-months=all` gets every month): the 21600×10800 Blue Marble for your month, resized to 16384×8192 (the GPU limit). Also Black Marble 8k, NASA clouds 8k, and a GEBCO DEM normal map plus a land/water mask (8k, relief ×6). About 80 MB, downloaded once.
  - On the first run the game block-compresses them (BC1/BC4/BC5) on a worker thread and caches the result in `~/.local/share/filament-falcon/cache/tex/`. Later runs load that cache in well under a second. The 5400 px set shows until the HD set is ready.
  - Shading: sunlight comes through the same Rayleigh/Mie/ozone air as the sky (orange terminator), with aerial-perspective haze on the ground and clouds, ocean Fresnel reflection plus a GGX sun glint, soft cloud shadows cast along the sun from the 4.5 km deck, and city lights that fade in through the terminator.
- **Moon:** LROC colour plus a LOLA heightmap from the NASA SVS CGI Moon Kit (svs.gsfc.nasa.gov/4720), converted with Pillow. Each file has fallback URLs (4k TIF, 2k TIF, 2k JPG, 1k JPG; uint16, float, 8-bit heights); the script tries the next one on a 404 or timeout.
- **Region:** `tools/build_region.py --name NAME --bbox S,W,N,E`. It pulls OpenStreetMap data (Overpass) and AWS terrain tiles, then writes chunk JSON to `assets/regions/NAME`. Choose it in game with `--region=NAME`, or point at any folder with `--region-dir=DIR`.
  - The default is Fredericton, NB, about 10×10 km.
  - In game: Sandbox → **FREDERICTON** (a descent from 4 km).
- **Packages:** `sudo apt install curl python3-numpy python3-pil`.
- **Test:** `godot --headless --path game -- --region-test --region-dir=DIR`.

**Approximate:**
- The planet is still 600 km (1:10.6, real surface gravity). All 16 missions, the orbits and the robot flight tests are tuned to it, so a bigger Earth would mean re-tuning every flight. The visual upgrade here is in textures and lighting. In VR the planet is still drawn in scaled space inside the far plane. KSC is rotated to sit under the game's pad.
- The procedural pad and runway may not match the coastline in the texture.
- Moon relief fades out near the landing site.
- Roofs are simple gabled or hipped. Building heights use Atlantic Canada defaults when OSM has no tags.
- Multipolygon holes are ignored. Each building sits at the ground height of its centroid.
- Bridges are flat. Landuse polygons stay within one chunk. The curvature bend is approximate.
- Overpass can rate-limit you. If it does, re-run later.
