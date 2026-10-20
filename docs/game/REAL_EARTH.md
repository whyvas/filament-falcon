# Real Earth, Moon and OSM detail regions

`./run.sh` runs `game/tools/fetch_assets.sh` once on first launch (skip with `--no-fetch`; re-run by hand any time).
Files go to `~/.local/share/filament-falcon/assets` (outside the repo). If the download fails or you're offline, the game uses the procedural planet.

- **Earth:** NASA Blue Marble, all 12 months, 5400×2700 (pick the month in `settings.json` → `graphics.earth_month`). Also Black Marble night lights, cloud cover (drifting, casts shadows) and GEBCO elevation.
- **HD Earth** (default; `--no-hd` skips it, `--hd-months=all` gets every month): the 21600×10800 Blue Marble for your month, resized to 16384×8192 (the GPU limit). Also Black Marble 8k, NASA clouds 8k, and a GEBCO DEM normal map plus a land/water mask (8k, relief ×6). About 80 MB, downloaded once.
  - On the first run the game block-compresses them (BC1/BC4/BC5) on a worker thread and caches the result in `~/.local/share/filament-falcon/cache/tex/`. Later runs load that cache in well under a second. The 5400 px set shows until the HD set is ready.
  - Shading: sunlight comes through the same Rayleigh/Mie/ozone air as the sky (orange terminator), with aerial-perspective haze on the ground and clouds, ocean Fresnel reflection plus a GGX sun glint, soft cloud shadows cast along the sun from the 4.5 km deck, and city lights that fade in through the terminator.
- **Moon:** LROC colour plus a LOLA heightmap from the NASA SVS CGI Moon Kit (svs.gsfc.nasa.gov/4720), converted with Pillow. Each file has fallback URLs (4k TIF, 2k TIF, 2k JPG, 1k JPG; uint16, float, 8-bit heights); the script tries the next one on a 404 or timeout.
- **Region (city):** `tools/build_region.py --region NAME` (presets: fredericton, moncton, saint-john, dieppe, bathurst, miramichi, edmundston, sackville, campbellton, oromocto; `--list` shows them), or `--name NAME --bbox S,W,N,E` for anywhere in the province.
  - The source is the Geofabrik `new-brunswick-latest.osm.pbf` (~65 MB), parsed locally with pyosmium. With osmium-tool, the city is cut out of the file in C++ first, which takes seconds. The province file is downloaded once and re-checked only when it is older than 30 days, using If-Modified-Since / Last-Modified, so an unchanged file is not downloaded again. Without pyosmium it falls back to Overpass.
  - Chunks are built in parallel (`--jobs`, all cores by default). The landuse colour is computed per terrain vertex, so forests now cover every chunk they touch.
  - A region whose inputs haven't changed is skipped (`build_key` in its manifest); `--force` rebuilds it.
  - In game, chunks are parsed and meshed on worker threads and attached one per frame. Pick the city with `./run.sh --region=moncton`. Sandbox → **FREDERICTON** descends over whichever region is selected.
- **Where the files live** (all under `~/.local/share/filament-falcon/`):
  - `osm/new-brunswick-<date>.osm.pbf` (+ `.meta.json`): the province extract.
  - `osm/extract_<city>_<key>.json.gz`: one city's features, cached per .pbf version and bbox.
  - `dem/terrarium/13/<x>_<y>.png`: elevation tiles, shared by all cities.
  - `assets/regions/<city>/`: `manifest.json`, `c_<ix>_<iz>.json` chunks, `water.json`.
  - `assets/`: NASA textures (5400 px set, `*_hd.jpg/png` HD set, `earth_normal.png`, `earth_mask.png`). Sources that are still being converted sit in `assets/src/`.
  - `cache/tex/*.v1.<mtime>.res`: GPU-compressed textures built on the first run.
  - `eva_vr.log`: the headset client log.
- **Packages:** `sudo apt install curl python3-numpy python3-pil python3-osmium osmium-tool`.
- **Tests:** `godot --headless --path game -- --region-test --region-dir=DIR` (sync + threaded build) and `XDG_DATA_HOME=/tmp/x godot --headless --path game -- --asset-test` (shader compile + texture cache).

**Approximate:**
- The planet is still 600 km (1:10.6, real surface gravity). All 16 missions, the orbits and the robot flight tests are tuned to it, so a bigger Earth would mean re-tuning every flight. The visual upgrade here is in textures and lighting. In VR the planet is still drawn in scaled space inside the far plane. KSC is rotated to sit under the game's pad.
- The procedural pad and runway may not match the coastline in the texture.
- Moon relief fades out near the landing site.
- Roofs are simple gabled or hipped. Building heights use Atlantic Canada defaults when OSM has no tags.
- Multipolygon holes are ignored. Each building sits at the ground height of its centroid.
- Bridges are flat. The curvature bend is approximate.
- Overpass (the fallback only) can rate-limit you. If it does, re-run later.
