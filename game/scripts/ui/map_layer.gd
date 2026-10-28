class_name MapLayer
extends RefCounted
## OSM vector layer for the AREAS map (AreaMap): lakes, rivers, roads and town names from
## ~/.local/share/filament-falcon/maps/*.ffml, which tools/map_layer.py builds on this PC from
## the cached Geofabrik extracts (format: see that script). Loaded lazily on a worker thread the
## first time the map is drawn; the lines are cached as merged segment lists (one draw call per
## bucket) bucketed by kind / zoom tier / detail level / map cell, and only buckets that are in
## view, at the current detail level and zoomed in far enough for their tier get drawn. Geometry
## is stored as (lon, -lat) so one canvas transform maps the whole layer to the screen.

const TIER_MAX_DPP := [0.4, 0.05, 0.012, 0.003]   # tier t is drawn below this many deg / px
const LEVEL_MIN_DPP := [0.02, 0.003, 0.0]         # detail level l is used at >= this deg / px
const CELL := [360.0, 1.0, 0.2]                   # bucket cell size (deg) per level
const PLACE_MAX_DPP := {"city": 0.06, "town": 0.015, "village": 0.004, "hamlet": 0.0012, "suburb": 0.0012}
const PLACE_FONT := {"city": 17, "town": 15, "village": 13, "hamlet": 12, "suburb": 12}
const ROAD_PX := [3.0, 2.2, 1.6, 1.1]
const RIVER_PX := [2.2, 1.6, 1.0, 1.0]
const ROAD_COL := [Color(1.0, 0.6, 0.2), Color(1.0, 0.82, 0.35), Color(1.0, 0.93, 0.6, 0.9), Color(0.95, 0.95, 0.95, 0.75)]
const WATER_COL := Color(0.3, 0.55, 0.95, 0.9)
const LAKE_COL := Color(0.18, 0.42, 0.85, 0.85)
const MAX_LABELS := 160

static var layers := {}          # path -> {"mtime", "bbox": Rect2, "places": Array, "buckets": [[...] x3 levels]}
static var version := 0          # bumped when a layer finished loading (maps redraw)
static var _tasks := {}          # path -> WorkerThreadPool task
static var _scan_ms := -1e9
static var files: Array = []     # .ffml files found by the last scan
static var drawn := Vector2i.ZERO  # last frame: (line / lake buckets, labels), for the test


static func maps_dir() -> String:
	return Geo.asset_dir().get_base_dir() + "/maps"


## Rescan maps/ (at most every few s) and start loading new or changed files.
static func poll(force := false) -> void:
	if not force and Time.get_ticks_msec() - _scan_ms < 5000.0:
		return
	_scan_ms = Time.get_ticks_msec()
	var d := maps_dir()
	var found: Array = []
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".ffml"):
				found.append(d + "/" + f)
	files = found
	for p: String in layers.keys():
		if not found.has(p):
			layers.erase(p)
			version += 1
	for p: String in found:
		var mt := FileAccess.get_modified_time(p)
		if _tasks.has(p) or (layers.has(p) and int(layers[p]["mtime"]) == mt):
			continue
		_tasks[p] = WorkerThreadPool.add_task(func() -> void:
			var lay := parse(p)
			(func() -> void:
				if _tasks.has(p):     # every task waited for once (an unwaited one aborts the exit)
					WorkerThreadPool.wait_for_task_completion(int(_tasks[p]))
					_tasks.erase(p)
				if not lay.is_empty():
					_finish(lay)
					lay["mtime"] = mt
					layers[p] = lay
					version += 1).call_deferred(), false, "map layer")


static func loading() -> bool:
	return not _tasks.is_empty()


## Wait for the loaders and drop everything (the last AreaMap leaving the tree).
static func release() -> void:
	for p: String in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(int(_tasks[p]))
	_tasks.clear()
	layers.clear()
	_scan_ms = -1e9


## Read one .ffml (worker thread safe: no RenderingServer objects).
static func parse(path: String) -> Dictionary:
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 12 or b.slice(0, 4).get_string_from_ascii() != "FFML" or b.decode_u32(4) != 1:
		push_warning("map layer: %s is not a version-1 .ffml" % path)
		return {}
	var n := b.decode_u32(8)
	var meta: Variant = JSON.parse_string(b.slice(12, 12 + n).get_string_from_utf8())
	if not (meta is Dictionary):
		return {}
	var bk := {}                 # int key -> {"kind", "tier", "level", "rect", "pts"}
	var o := 12 + n
	while o + 4 <= b.size():
		var kind := b[o]
		var tier := mini(b[o + 1], 3)
		o += 4
		for lv in 3:
			if o + 4 > b.size():
				break
			var cnt := b.decode_u32(o)
			o += 4
			if cnt == 0:
				continue
			var ints := b.slice(o, o + 8 * cnt).to_int32_array()
			o += 8 * cnt
			var pts := PackedVector2Array()
			pts.resize(cnt)
			for i in cnt:
				pts[i] = Vector2(ints[2 * i] * 1e-6, -ints[2 * i + 1] * 1e-6)
			var cs: float = CELL[lv]
			var key := (((kind * 4 + tier) * 3 + lv) * 4000 + int((pts[0].x + 180.0) / cs)) * 4000 + int((pts[0].y + 90.0) / cs)
			var e: Dictionary = bk.get(key, {})
			if e.is_empty():
				e = {"kind": kind, "tier": tier, "level": lv, "rect": Rect2(pts[0], Vector2.ZERO), "pts": PackedVector2Array()}
				bk[key] = e
			var r: Rect2 = e["rect"]
			for q in pts:
				r = r.expand(q)
			e["rect"] = r
			var out: PackedVector2Array = e["pts"]
			if kind == 2:          # lake: triangles
				var idx := Geometry2D.triangulate_polygon(pts)
				for i in idx:
					out.append(pts[i])
			else:                  # line: segment pairs for draw_multiline
				for i in cnt - 1:
					out.append(pts[i])
					out.append(pts[i + 1])
			e["pts"] = out
	var levels: Array = [[], [], []]
	for e: Dictionary in bk.values():
		if (e["pts"] as PackedVector2Array).size() > 0:
			levels[int(e["level"])].append(e)
	for lv: Array in levels:   # lakes, then rivers, then roads minor -> major (major on top)
		lv.sort_custom(func(a: Dictionary, c: Dictionary) -> bool:
			var ka: int = (2 - int(a["kind"])) * 10 + 3 - int(a["tier"])
			var kc: int = (2 - int(c["kind"])) * 10 + 3 - int(c["tier"])
			return ka < kc)
	var pl: Array = []
	for p: Variant in (meta as Dictionary).get("places", []):
		if p is Array and (p as Array).size() >= 5 and PLACE_MAX_DPP.has(str(p[1])):
			pl.append([str(p[0]), str(p[1]), int(p[2]), Vector2(float(p[4]), -float(p[3]))])
	var bb: Array = (meta as Dictionary).get("bbox", [0, 0, 0, 0])
	return {"bbox": Rect2(Vector2(float(bb[1]), -float(bb[2])), Vector2(float(bb[3]) - float(bb[1]), float(bb[2]) - float(bb[0]))),
		"places": pl, "levels": levels, "counts": (meta as Dictionary).get("counts", {})}


## Main thread: lake triangle lists -> one ArrayMesh per bucket.
static func _finish(lay: Dictionary) -> void:
	for lv: Array in lay["levels"]:
		for e: Dictionary in lv:
			if int(e["kind"]) == 2:
				var arr := []
				arr.resize(Mesh.ARRAY_MAX)
				arr[Mesh.ARRAY_VERTEX] = e["pts"]
				var m := ArrayMesh.new()
				m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				e["mesh"] = m


static func level_for(dpp: float) -> int:
	return 0 if dpp >= LEVEL_MIN_DPP[0] else (1 if dpp >= LEVEL_MIN_DPP[1] else 2)


## Draw lakes / rivers / roads (call between the base map and the overlays). center = (lon, lat).
static func draw_lines(ci: CanvasItem, center: Vector2, dpp: float, size: Vector2) -> int:
	drawn.x = 0
	if layers.is_empty():
		return 0
	var lv := level_for(dpp)
	var view := Rect2(Vector2(center.x, -center.y) - size * 0.5 * dpp, size * dpp)
	ci.draw_set_transform(size * 0.5 - Vector2(center.x, -center.y) / dpp, 0.0, Vector2.ONE / dpp)
	var n := 0
	for lay: Dictionary in layers.values():
		if not (lay["bbox"] as Rect2).grow(0.5).intersects(view):
			continue
		for e: Dictionary in lay["levels"][lv]:
			var t: int = e["tier"]
			if dpp >= TIER_MAX_DPP[t] or not (e["rect"] as Rect2).intersects(view):
				continue
			match int(e["kind"]):
				2:
					if e.has("mesh"):
						ci.draw_mesh(e["mesh"], null, Transform2D.IDENTITY, LAKE_COL)
				1:
					ci.draw_multiline(e["pts"], WATER_COL, maxf(RIVER_PX[t], 1.0) * dpp)
				_:
					ci.draw_multiline(e["pts"], ROAD_COL[t], ROAD_PX[t] * dpp)
			n += 1
	ci.draw_set_transform(Vector2.ZERO)
	drawn.x = n
	return n


## Place names by zoom (cities first, then towns, villages, hamlets), no overlaps.
static func draw_labels(ci: CanvasItem, center: Vector2, dpp: float, size: Vector2, font: Font) -> int:
	drawn.y = 0
	if layers.is_empty():
		return 0
	var view := Rect2(Vector2(center.x, -center.y) - size * 0.5 * dpp, size * dpp)
	var taken: Array[Rect2] = []
	for lay: Dictionary in layers.values():
		if not (lay["bbox"] as Rect2).grow(0.5).intersects(view):
			continue
		for p: Array in lay["places"]:       # sorted city > town > village > hamlet, by population
			if taken.size() >= MAX_LABELS:
				break
			var kind: String = p[1]
			if dpp >= float(PLACE_MAX_DPP[kind]):
				continue
			var g: Vector2 = p[3]
			if not view.has_point(g):
				continue
			var s := (g - Vector2(center.x, -center.y)) / dpp + size * 0.5
			var fs: int = PLACE_FONT[kind]
			var w := font.get_string_size(p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var r := Rect2(s + Vector2(-4, -fs - 2), Vector2(w + 12, fs + 8))
			var clash := false
			for q in taken:
				if q.intersects(r):
					clash = true
					break
			if clash:
				continue
			taken.append(r)
			var big := kind == "city" or kind == "town"
			ci.draw_circle(s, 3.5 if big else 2.5, Color(1, 1, 1) if big else Color(0.9, 0.9, 0.9, 0.9))
			ci.draw_string_outline(font, s + Vector2(6, -3), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
			ci.draw_string(font, s + Vector2(6, -3), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1) if big else Color(0.92, 0.92, 0.85))
	drawn.y = taken.size()
	return taken.size()
