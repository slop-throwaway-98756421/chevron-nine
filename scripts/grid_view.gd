extends Control
## Draws the colony grid in grey boxes and forwards mouse input to main.

const TERRAIN_COLORS := {
	Sim.T.PLAIN: Color("#d8c9a3"),
	Sim.T.ORE: Color("#9c6644"),
	Sim.T.FERTILE: Color("#8db369"),
	Sim.T.ROCK: Color("#55534e"),
}

var main  # main.gd


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var t := _tile(event.position)
		if t != main.hover:
			main.hover = t
			if main.painting:
				main.click_tile(t, true)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				main.painting = true
				main.click_tile(_tile(event.position), false)
			else:
				main.painting = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			main.set_tool("")


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		main.hover = Vector2i(-1, -1)


func _tile(p: Vector2) -> Vector2i:
	var t := Vector2i(floori(p.x / main.TILE), floori(p.y / main.TILE))
	return t if main.sim._in(t.x, t.y) else Vector2i(-1, -1)


func _draw() -> void:
	var sim: Sim = main.sim
	var S: int = main.TILE
	var font := get_theme_default_font()
	for y in sim.h:
		for x in sim.w:
			var t := sim.terrain[sim._i(x, y)]
			var r := Rect2(x * S, y * S, S, S)
			draw_rect(r, TERRAIN_COLORS[t])
			draw_rect(r, Color(0, 0, 0, 0.08), false, 1.0)
			if t == Sim.T.ORE:
				draw_circle(r.position + Vector2(S * 0.25, S * 0.3), 3, Color("#5e3a22"))
				draw_circle(r.position + Vector2(S * 0.7, S * 0.65), 3, Color("#5e3a22"))
			elif t == Sim.T.FERTILE:
				for k in 3:
					var p := r.position + Vector2(S * (0.25 + 0.25 * k), S * 0.75)
					draw_line(p, p + Vector2(0, -8), Color("#4f7d33"), 2)

	# Roads first, so buildings sit on top of their stubs.
	for id in sim.order:
		var b: Dictionary = sim.buildings[id]
		if b.type != "road":
			continue
		var c := Vector2(b.x * S + S / 2.0, b.y * S + S / 2.0)
		var col := Color("#6d6d6d") if b.connected else Color("#c9772b")
		draw_circle(c, S * 0.18, col)
		for nid in sim._adjacent_ids(b.x, b.y):
			var nb: Dictionary = sim.buildings[nid]
			var nc := Vector2(nb.x * S + S / 2.0, nb.y * S + S / 2.0)
			draw_line(c, c.lerp(nc, 0.5), col, S * 0.3)

	for id in sim.order:
		var b: Dictionary = sim.buildings[id]
		if b.type == "road":
			continue
		var d: Dictionary = sim.def_of(b.type)
		var r := Rect2(b.x * S, b.y * S, S, S).grow(-3)
		draw_rect(r, Color(d.color))
		if b.type != "depot" and not b.connected:
			draw_rect(r, Color("#ff8c1a"), false, 3.0)
		draw_string(font, r.position + Vector2(0, S * 0.5), d.abbr, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, Color.WHITE)
		if d.has("outputs"):
			# progress bar
			var bar := Rect2(r.position + Vector2(3, r.size.y - 7), Vector2((r.size.x - 6) * b.progress, 4))
			draw_rect(Rect2(bar.position, Vector2(r.size.x - 6, 4)), Color(0, 0, 0, 0.35))
			draw_rect(bar, Color.WHITE)
			var dot := Color("#46d160")
			if not b.staffed or b.status.begins_with("Output"):
				dot = Color("#e8473f")
			elif b.status.begins_with("Waiting"):
				dot = Color("#f2c230")
			draw_circle(r.position + Vector2(r.size.x - 6, 6), 4, dot)
			if b.linked:
				draw_string(font, r.position + Vector2(3, 12), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#bfe3ff"))
		elif b.type == "habitat":
			var share := sim.fed_share(b) if b.meals > 0 else 1.0
			draw_rect(Rect2(r.position + Vector2(3, r.size.y - 7), Vector2(r.size.x - 6, 4)), Color(0, 0, 0, 0.35))
			draw_rect(Rect2(r.position + Vector2(3, r.size.y - 7), Vector2((r.size.x - 6) * share, 4)), Color("#93c47d"))
			if b.status.begins_with("Hungry"):
				draw_circle(r.position + Vector2(r.size.x - 6, 6), 4, Color("#e8473f"))

	_draw_ghost(sim, S, font)


func _draw_ghost(sim: Sim, S: int, font: Font) -> void:
	var h: Vector2i = main.hover
	if h == Vector2i(-1, -1) or main.tool == "" or sim.phase != "build":
		return
	var r := Rect2(h.x * S, h.y * S, S, S)
	if main.tool == "demolish":
		var col := Color("#e8473f")
		draw_line(r.position + Vector2(8, 8), r.end - Vector2(8, 8), col, 3)
		draw_line(Vector2(r.position.x + 8, r.end.y - 8), Vector2(r.end.x - 8, r.position.y + 8), col, 3)
		return
	var ok: bool = sim.can_place(main.tool, h.x, h.y) == ""
	draw_rect(r.grow(-2), Color(0.3, 1, 0.4, 0.45) if ok else Color(1, 0.2, 0.2, 0.4))
	var d: Dictionary = sim.def_of(main.tool)
	draw_string(font, r.position + Vector2(0, S * 0.5), d.abbr, HORIZONTAL_ALIGNMENT_CENTER, S, 13, Color.BLACK)
	# Preview adjacency: would this be Linked, how many pylons touch it?
	if d.has("inputs") or main.tool == "pylon":
		for nid in sim._adjacent_ids(h.x, h.y):
			var nb: Dictionary = sim.buildings[nid]
			var nd: Dictionary = sim.def_of(nb.type)
			var hit := false
			if main.tool == "pylon":
				hit = nd.has("outputs")
			else:
				for g in d.inputs:
					if nd.has("outputs") and nd.outputs.has(g):
						hit = true
				hit = hit or nb.type == "pylon"
			if hit:
				draw_rect(Rect2(nb.x * S, nb.y * S, S, S).grow(-1), Color("#3fa7ff"), false, 3.0)
