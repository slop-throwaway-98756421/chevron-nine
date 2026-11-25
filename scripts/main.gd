extends Control
## Greybox season: HUD, build tools and the shipment count-up.
## All UI is built in code so the scene file stays trivial.

const TILE := 44
const GRID_ORIGIN := Vector2(16, 64)
const SIDE_X := 740.0
const GridView := preload("res://scripts/grid_view.gd")

var sim: Sim
var run_seed := 0
var speed := 0
var tool := ""
var hover := Vector2i(-1, -1)
var painting := false
var _hand_sig := ""
var _msg_timer := 0.0

var grid_view: Control
var lbl_season: Label
var lbl_time: Label
var lbl_proj: Label
var lbl_permits: Label
var lbl_workers: Label
var speed_buttons: Array = []
var tool_buttons := {}
var hand_box: VBoxContainer
var btn_redraw: Button
var stock_label: Label
var info_label: Label
var msg_label: Label

var overlay: ColorRect
var ship_title: Label
var ship_list: VBoxContainer
var ship_checks := {}
var ship_summary: Label
var ship_btn: Button
var tally_box: VBoxContainer
var score_holder: Control
var score_label: Label
var verdict_label: Label
var next_btn: Button
var retry_btn: Button
var newrun_btn: Button
var tally := {}


func _ready() -> void:
	sim = Sim.new()
	_build_ui()
	var seed := randi() % 100000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed = int(a.substr(7))
	new_run(seed)


func new_run(seed: int) -> void:
	run_seed = seed
	sim.new_run(seed)
	_season_start()


func _season_start() -> void:
	speed = 0
	set_tool("")
	overlay.hide()
	tally = {}
	var boss := "  BOSS SEASON" if sim.is_boss(sim.season) else ""
	var resupply := ""
	if sim.season > 1:
		resupply = " Emergency resupply tops the warehouse up to %s." % _cost_str(sim.C.season.get("resupply_floor", {}))
	say("Season %d: ship %d by the time the gate opens.%s%s Paused: plan, then press Space." % [sim.season, sim.quota, boss, resupply])


# ---------------------------------------------------------------- UI build

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#24272b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var top := HBoxContainer.new()
	top.position = Vector2(16, 12)
	top.add_theme_constant_override("separation", 22)
	add_child(top)
	lbl_season = _label(top, 18)
	lbl_time = _label(top, 18)
	lbl_proj = _label(top, 18)
	lbl_permits = _label(top, 18)
	lbl_workers = _label(top, 18)
	var speeds := HBoxContainer.new()
	top.add_child(speeds)
	for i in 4:
		var b := Button.new()
		b.text = ["II", "1x", "2x", "3x"][i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): speed = i)
		speeds.add_child(b)
		speed_buttons.append(b)
	var skip := Button.new()
	skip.text = "Skip to gate"
	skip.tooltip_text = "Playtest helper: jump to the end of the season."
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(func(): if sim.phase == "build": sim.step(sim.time_left + 1.0))
	speeds.add_child(skip)

	grid_view = GridView.new()
	grid_view.main = self
	grid_view.position = GRID_ORIGIN
	grid_view.size = Vector2(sim.w * TILE, sim.h * TILE)
	grid_view.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(grid_view)

	msg_label = Label.new()
	msg_label.position = Vector2(16, GRID_ORIGIN.y + sim.h * TILE + 10)
	msg_label.size = Vector2(sim.w * TILE, 60)
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(msg_label)

	var side := VBoxContainer.new()
	side.position = Vector2(SIDE_X, GRID_ORIGIN.y - 6)
	side.custom_minimum_size = Vector2(520, 0)
	side.add_theme_constant_override("separation", 6)
	add_child(side)

	_label(side, 15, "CORE  (no permit needed)").modulate = Color("#aab")
	var core := HBoxContainer.new()
	side.add_child(core)
	for t in ["road", "habitat", "demolish"]:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		if t == "demolish":
			b.text = "Demolish [X]"
			b.tooltip_text = "Built this season: full refund and the permit back. Older: half refund, and you keep a salvaged blueprint to rebuild it elsewhere without a permit."
		else:
			var d := sim.def_of(t)
			b.text = "%s [%s]  %s" % [d.name, "R" if t == "road" else "H", _cost_str(d.cost)]
			b.tooltip_text = d.desc
		b.pressed.connect(set_tool.bind(t))
		core.add_child(b)
		tool_buttons[t] = b

	var hand_head := HBoxContainer.new()
	side.add_child(hand_head)
	_label(hand_head, 15, "BLUEPRINT HAND  (1 permit each)").modulate = Color("#aab")
	btn_redraw = Button.new()
	btn_redraw.focus_mode = Control.FOCUS_NONE
	btn_redraw.pressed.connect(func():
		if sim.redraw():
			set_tool("")
			say("Redrew the hand.")
		else:
			say("No redraws left this season."))
	hand_head.add_child(btn_redraw)
	hand_box = VBoxContainer.new()
	side.add_child(hand_box)

	_label(side, 15, "WAREHOUSE").modulate = Color("#aab")
	stock_label = _label(side, 15)
	_label(side, 15, "INFO").modulate = Color("#aab")
	info_label = _label(side, 14)
	info_label.custom_minimum_size = Vector2(520, 150)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_build_overlay()


func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and not tally.is_empty():
			tally.t = 999.0)
	add_child(overlay)
	var panel := PanelContainer.new()
	panel.position = Vector2(240, 60)
	panel.custom_minimum_size = Vector2(800, 580)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#30343a")
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	ship_title = _label(v, 26)
	ship_list = VBoxContainer.new()
	v.add_child(ship_list)
	ship_summary = _label(v, 18)
	ship_btn = Button.new()
	ship_btn.text = "Ship it  [Enter]"
	ship_btn.pressed.connect(_on_ship)
	v.add_child(ship_btn)
	tally_box = VBoxContainer.new()
	v.add_child(tally_box)
	score_holder = Control.new()
	score_holder.custom_minimum_size = Vector2(760, 70)
	v.add_child(score_holder)
	score_label = Label.new()
	score_label.size = Vector2(760, 70)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 44)
	score_holder.add_child(score_label)
	verdict_label = _label(v, 22)
	verdict_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	verdict_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)
	next_btn = Button.new()
	next_btn.text = "Next season  [Enter]"
	next_btn.pressed.connect(func():
		sim.advance()
		_season_start())
	btns.add_child(next_btn)
	retry_btn = Button.new()
	retry_btn.text = "Retry same seed"
	retry_btn.pressed.connect(func(): new_run(run_seed))
	btns.add_child(retry_btn)
	newrun_btn = Button.new()
	newrun_btn.text = "New run  [Enter]"
	newrun_btn.pressed.connect(func(): new_run(randi() % 100000))
	btns.add_child(newrun_btn)
	overlay.hide()


func _label(parent: Node, size: int, text := "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _cost_str(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts: Array = []
	for g in cost:
		parts.append("%d %s" % [int(cost[g]), sim.C.goods[g].name])
	return ", ".join(parts)


func _rebuild_hand() -> void:
	for c in hand_box.get_children():
		c.queue_free()
	for k in tool_buttons.keys():
		if not k in ["road", "habitat", "demolish"]:
			tool_buttons.erase(k)
	var n := 1
	for card in sim.hand:
		var d := sim.def_of(card)
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "[%d] %s   (%s)\n      %s" % [n, d.name, _cost_str(d.cost), d.desc]
		b.custom_minimum_size = Vector2(520, 50)
		b.pressed.connect(set_tool.bind(card))
		hand_box.add_child(b)
		tool_buttons[card] = b
		n += 1
	# Blueprints kept from demolished buildings: build without the card or a permit.
	for type in sim.salvage:
		var count := int(sim.salvage[type])
		if count <= 0:
			continue
		var d := sim.def_of(type)
		if tool_buttons.has(type):
			tool_buttons[type].text += "   +%d salvaged" % count
			continue
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "Salvaged %s ×%d   (%s, no permit)\n      %s" % [d.name, count, _cost_str(d.cost), d.desc]
		b.custom_minimum_size = Vector2(520, 50)
		b.modulate = Color("#cfe8ff")
		b.pressed.connect(set_tool.bind(type))
		hand_box.add_child(b)
		tool_buttons[type] = b


# ---------------------------------------------------------------- input

func set_tool(t: String) -> void:
	tool = "" if t == tool else t
	for k in tool_buttons:
		tool_buttons[k].set_pressed_no_signal(k == tool)


func click_tile(t: Vector2i, dragging: bool) -> void:
	if t == Vector2i(-1, -1) or tool == "" or sim.phase != "build":
		return
	if dragging and not tool in ["road", "demolish"]:
		return
	var err := ""
	if tool == "demolish":
		err = sim.demolish(t.x, t.y)
	else:
		err = sim.place(tool, t.x, t.y)
		if err == "" and sim.def_of(tool).get("card", false) and sim.permits == 0:
			say("Out of permits for this season.")
			set_tool("")
			return
	if err != "" and not dragging:
		say(err)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if overlay.visible:
		if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
			if not tally.is_empty() and tally.t < tally.end:
				tally.t = 999.0
			elif sim.phase == "ship":
				_on_ship()
			elif next_btn.visible:
				next_btn.pressed.emit()
			elif newrun_btn.visible:
				newrun_btn.pressed.emit()
		return
	match k:
		KEY_SPACE:
			speed = 1 if speed == 0 else 0
		KEY_1, KEY_2, KEY_3, KEY_4:
			var i := k - KEY_1
			if i < sim.hand.size():
				set_tool(sim.hand[i])
		KEY_R:
			set_tool("road")
		KEY_H:
			set_tool("habitat")
		KEY_X:
			set_tool("demolish")
		KEY_ESCAPE:
			set_tool("")
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			speed = mini(speed + 1, 3)
		KEY_MINUS, KEY_KP_SUBTRACT:
			speed = maxi(speed - 1, 0)


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if sim.phase == "build":
		sim.step(delta * speed)
	if sim.phase == "ship" and not overlay.visible:
		_open_gate()
	var sig := ",".join(sim.hand) + str(sim.season) + str(sim.salvage)
	if sig != _hand_sig:
		_hand_sig = sig
		_rebuild_hand()
	_update_hud()
	_update_tally(delta)
	grid_view.queue_redraw()
	if _msg_timer > 0:
		_msg_timer -= delta
		if _msg_timer <= 0:
			msg_label.text = ""


func say(text: String) -> void:
	msg_label.text = text
	_msg_timer = 6.0


func _update_hud() -> void:
	var boss := " BOSS" if sim.is_boss(sim.season) else ""
	lbl_season.text = "Season %d%s  ·  Quota %d" % [sim.season, boss, sim.quota]
	var tl := int(ceil(sim.time_left))
	lbl_time.text = "Gate in %d:%02d" % [tl / 60, tl % 60]
	var p := sim.preview()
	lbl_proj.text = "Shipment %d  (×%.2f)" % [p.score, p.mult]
	lbl_proj.modulate = Color("#7ee081") if p.passed else Color("#ffffff")
	lbl_permits.text = "Permits %d" % sim.permits
	lbl_workers.text = "Workers %d/%d" % [sim.workers_used, sim.workers_total]
	for i in speed_buttons.size():
		speed_buttons[i].set_pressed_no_signal(i == speed)
	btn_redraw.text = "Redraw (%d)" % sim.redraws
	btn_redraw.disabled = sim.redraws <= 0 or sim.phase != "build"
	for k in tool_buttons:
		if k == "demolish":
			continue
		tool_buttons[k].disabled = sim.missing_cost(k) != "" or (sim.def_of(k).get("card", false) \
			and sim.permits <= 0 and int(sim.salvage.get(k, 0)) <= 0)
	var lines: Array = []
	for g in sim.C.goods:
		var good: Dictionary = sim.C.goods[g]
		lines.append("%-14s %4d   × %2d  = %d" % [good.name, int(sim.stock[g]), int(good.value), int(sim.stock[g]) * int(good.value)])
	stock_label.text = "\n".join(lines)
	info_label.text = _hover_text()


func _hover_text() -> String:
	if hover == Vector2i(-1, -1):
		return "Hover a tile for details.\nKeys: Space pause/run, +/- speed, 1-4 cards, R road, H habitat, X demolish, Esc/right-click cancel.\nOrange outline = not linked to the Depot. Blue + = Linked (+50% speed). Dot: green working, yellow waiting, red stalled."
	var t := sim.terrain[sim._i(hover.x, hover.y)]
	var out: Array = ["%s  (%d, %d)" % [Sim.TERRAIN_LABEL[t], hover.x, hover.y]]
	var b := sim.building_at(hover.x, hover.y)
	if b.is_empty():
		if tool != "" and tool != "demolish":
			var err := sim.can_place(tool, hover.x, hover.y)
			out.append("Click to build %s." % sim.def_of(tool).name if err == "" else err)
		return "\n".join(out)
	var d := sim.def_of(b.type)
	out.append("%s: %s" % [d.name, d.desc])
	if b.type == "road" or b.type == "depot":
		if b.type == "road":
			out.append("Linked to Depot: %s" % ("yes" if b.connected else "no"))
		return "\n".join(out)
	out.append("Linked to Depot: %s" % ("yes" if b.connected else "NO, needs a road or to touch the Depot"))
	if d.has("outputs"):
		out.append("Status: %s" % (b.status if b.status != "" else "Idle"))
		out.append("Speed ×%.2f%s%s  ·  workers %d%s" % [b.speed,
			"  (Linked)" if b.linked else "",
			"  (%d pylon)" % b.pylons if b.pylons > 0 else "",
			int(d.workers), "" if b.staffed else "  UNSTAFFED"])
		out.append("In: %s   Out: %s   Progress %d%%" % [_buf(b.inb), _buf(b.outb), int(b.progress * 100)])
	elif b.type == "habitat":
		out.append("Fed %d of %d meals this season  ·  adds ×%.2f" % [b.fed, b.meals,
			float(sim.C.prosperity.per_fed_habitat) * sim.fed_share(b)])
		if b.status != "":
			out.append(b.status)
	return "\n".join(out)


func _buf(buf: Dictionary) -> String:
	var parts: Array = []
	for g in buf:
		if int(buf[g]) > 0:
			parts.append("%d %s" % [int(buf[g]), sim.C.goods[g].name])
	return ", ".join(parts) if parts.size() else "-"


# ---------------------------------------------------------------- shipment

func _open_gate() -> void:
	speed = 0
	set_tool("")
	painting = false
	overlay.show()
	ship_title.text = "The gate opens: Season %d shipment" % sim.season
	for c in ship_list.get_children():
		c.queue_free()
	ship_checks.clear()
	for g in sim.C.goods:
		var qty := int(sim.stock[g])
		if qty <= 0:
			continue
		var v := int(sim.C.goods[g].value)
		var row := HBoxContainer.new()
		var name_l := Label.new()
		name_l.text = sim.C.goods[g].name
		name_l.custom_minimum_size = Vector2(130, 0)
		row.add_child(name_l)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = qty
		slider.step = 1
		slider.value = qty
		slider.focus_mode = Control.FOCUS_NONE
		slider.custom_minimum_size = Vector2(220, 24)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(slider)
		var amt := Label.new()
		amt.custom_minimum_size = Vector2(190, 0)
		row.add_child(amt)
		var refresh := func(val: float):
			amt.text = "  ship %d × %d = %d   keep %d" % [int(val), v, int(val) * v, qty - int(val)]
			_update_ship_summary()
		slider.value_changed.connect(refresh)
		for preset in [["All", qty], ["None", 0]]:
			var pb := Button.new()
			pb.text = preset[0]
			pb.focus_mode = Control.FOCUS_NONE
			pb.pressed.connect(func(): slider.value = preset[1])
			row.add_child(pb)
		ship_list.add_child(row)
		ship_checks[g] = slider
		amt.text = "  ship %d × %d = %d   keep 0" % [qty, v, qty * v]

	ship_list.show()
	ship_btn.show()
	ship_summary.show()
	tally_box.hide()
	score_label.text = ""
	verdict_label.text = "Slide down anything you want to keep. Kept goods stay for building and feeding next season."
	verdict_label.modulate = Color.WHITE
	next_btn.hide()
	retry_btn.hide()
	newrun_btn.hide()
	_update_ship_summary()


func _selection() -> Dictionary:
	var sel := {}
	for g in ship_checks:
		sel[g] = int(ship_checks[g].value)
	return sel


func _update_ship_summary() -> void:
	var p := sim.preview(_selection())
	ship_summary.text = "Value %d × %.2f Prosperity = %d     Quota %d" % [p.base, p.mult, p.score, p.quota]
	ship_summary.modulate = Color("#7ee081") if p.passed else Color("#ff8f80")


func _on_ship() -> void:
	if sim.phase != "ship":
		return
	var r := sim.ship(_selection())
	ship_list.hide()
	ship_btn.hide()
	ship_summary.hide()
	verdict_label.text = ""
	for c in tally_box.get_children():
		c.queue_free()
	tally_box.show()
	var labels: Array = []
	for line in r.lines:
		labels.append(_label(tally_box, 20))
	var base_l := _label(tally_box, 22)
	var mult_l := _label(tally_box, 22)
	var n: int = r.lines.size()
	tally = {"r": r, "t": 0.0, "labels": labels, "base_l": base_l, "mult_l": mult_l,
		"t_base": n * 0.45 + 0.2, "t_mult": n * 0.45 + 0.7, "t_score": n * 0.45 + 1.2,
		"end": n * 0.45 + 2.6, "done": false}


func _update_tally(delta: float) -> void:
	if tally.is_empty() or tally.done:
		return
	tally.t += delta
	var t: float = tally.t
	var r: Dictionary = tally.r
	for i in r.lines.size():
		var line: Dictionary = r.lines[i]
		var lt := clampf((t - i * 0.45) / 0.4, 0.0, 1.0)
		var l: Label = tally.labels[i]
		if lt <= 0.0:
			l.text = ""
			continue
		l.text = "%-14s %4d × %2d   = %d" % [line.name, line.qty, line.value, int(line.subtotal * lt)]
	if t >= tally.t_base:
		tally.base_l.text = "Value  %d" % r.base
	if t >= tally.t_mult:
		tally.mult_l.text = "× %.2f  Prosperity" % r.mult
	if t >= tally.t_score:
		var st := clampf((t - tally.t_score) / (tally.end - tally.t_score), 0.0, 1.0)
		var shown := int(lerpf(r.base, r.score, ease(st, 0.4)))
		score_label.text = "%d / %d" % [shown, r.quota]
		var pulse := 1.0 - st
		score_label.position = Vector2(randf_range(-6, 6), randf_range(-4, 4)) * pulse
		score_label.modulate = Color("#ffffff").lerp(Color("#7ee081") if shown >= r.quota else Color("#ffd27f"), st)
	if t >= tally.end:
		tally.done = true
		score_label.position = Vector2.ZERO
		score_label.text = "%d / %d" % [r.score, r.quota]
		_show_verdict(r)


func _show_verdict(r: Dictionary) -> void:
	if r.passed:
		var over := int(round((float(r.score) / r.quota - 1.0) * 100.0))
		verdict_label.text = "QUOTA MET  (+%d%% over)\nNext: Season %d, quota %d" % [over, sim.season + 1, sim.quota_for(sim.season + 1)]
		verdict_label.modulate = Color("#7ee081")
		score_label.modulate = Color("#7ee081")
		next_btn.show()
	else:
		verdict_label.text = "QUOTA MISSED by %d. The gate collapses.\nRun over after %d season%s (seed %d)." % [
			r.quota - r.score, sim.season - 1, "" if sim.season == 2 else "s", run_seed]
		verdict_label.modulate = Color("#ff8f80")
		score_label.modulate = Color("#ff8f80")
		retry_btn.show()
		newrun_btn.show()
		sim.advance()
