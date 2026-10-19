extends Node
## Headless layout check: every visible control of each Commander page must sit inside the
## viewport (scrolling pages count their scroll area as inside). Usage:
##   godot --headless --path game -- --ui-fit
var bad := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	for sz: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		var vp := SubViewport.new()
		vp.size = sz
		add_child(vp)
		var c := CommanderUI.new()
		vp.add_child(c)
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		c.position = Vector2.ZERO
		c.size = Vector2(sz)
		for i in 3:
			await get_tree().process_frame
		for p: String in c.pages:
			c.show_page(p)
			for i in 3:
				await get_tree().process_frame
			c.size = Vector2(sz)
			await get_tree().process_frame
			var pg := c.pages[p] as Control
			var wide := pg.get_combined_minimum_size().x > float(sz.x) - 28.0
			if wide and sz.x >= 1920:
				print("   %s needs sideways scrolling at %d px" % [p, sz.x])
				bad += 1
			var n := _check(c, Rect2(Vector2.ZERO, Vector2(sz)), p, sz)
			print("UI FIT %dx%d %-16s %s" % [sz.x, sz.y, p, "ok" if n == 0 else "%d controls off-screen" % n])
			if p == "MISSIONS":
				# every entry's detail panel (patch, diagram, overview, actions, logs, START)
				var worst := 0
				for e: Dictionary in MissionCatalog.ALL:
					c.select_entry(e["key"])
					for i in 2:
						await get_tree().process_frame
					if pg.get_combined_minimum_size().x > float(sz.x) - 28.0 and sz.x >= 1920:
						print("   MISSIONS/%s needs sideways scrolling" % e["key"])
						bad += 1
					var ne := _check(c, Rect2(Vector2.ZERO, Vector2(sz)), p + "/" + str(e["key"]), sz)
					worst = maxi(worst, ne)
				print("UI FIT %dx%d %-16s %s" % [sz.x, sz.y, "MISSIONS x%d" % MissionCatalog.ALL.size(), "ok" if worst == 0 else "off-screen controls"])
		vp.queue_free()
		await get_tree().process_frame
	print("UI FIT RESULT: ", "PASS" if bad == 0 else "FAIL")
	get_tree().quit(0 if bad == 0 else 1)

func _check(n: Node, area: Rect2, page: String, sz: Vector2i) -> int:
	var cnt := 0
	for ch in n.get_children():
		if ch is CanvasItem and not (ch as CanvasItem).visible:
			continue
		var a := area
		if ch is Control:
			var r := (ch as Control).get_global_rect()
			if r.size.x > 1 and r.size.y > 1 and not a.grow(1.0).encloses(r):
				cnt += 1
				bad += 1
				if cnt <= 3:
					print("   off: %s %s" % [ch.get_path(), r])
			if ch is ScrollContainer:
				continue   # its content scrolls
		cnt += _check(ch, a, page, sz)
	return cnt
