class_name Sim
extends RefCounted
## Deterministic greybox simulation for one colony run.
## No nodes, no rendering: the UI reads this state and calls its methods.
## The simulation advances in fixed ticks so a seed always plays out the same.

const TICK := 0.1
const OUT_CAP := 4  # output buffer per good before a building stalls
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

enum T { PLAIN, ORE, FERTILE, ROCK }
const TERRAIN_BY_NAME := {"ore": T.ORE, "fertile": T.FERTILE}
const TERRAIN_LABEL := {T.PLAIN: "Plain", T.ORE: "Ore deposit", T.FERTILE: "Fertile soil", T.ROCK: "Rock"}

var C: Dictionary
var rng := RandomNumberGenerator.new()
var seed_value := 0
var w := 16
var h := 12
var terrain := PackedInt32Array()
var grid := PackedInt32Array()  # building id per tile, -1 when empty
var buildings := {}  # id -> Dictionary
var order: Array = []  # building ids in placement order (staffing priority)
var next_id := 1
var depot_id := -1

var stock := {}
var season := 1
var time_left := 0.0
var quota := 0
var permits := 0
var redraws := 0
var deck: Array = []
var hand: Array = []
var phase := "build"  # build -> ship -> result -> build ... or over
var history: Array = []
var produced := {}
var last_result := {}
var workers_total := 0
var workers_used := 0

var _acc := 0.0
var _dirty := true


static func load_content(path := "res://data/content.json") -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	assert(parsed is Dictionary, "content.json failed to parse")
	return parsed


func _init(content: Dictionary = {}) -> void:
	C = content if not content.is_empty() else load_content()


# ---------------------------------------------------------------- run setup

func new_run(s: int) -> void:
	seed_value = s
	rng.seed = s
	w = int(C.grid.width)
	h = int(C.grid.height)
	grid = PackedInt32Array()
	grid.resize(w * h)
	grid.fill(-1)
	buildings.clear()
	order.clear()
	next_id = 1
	_gen_terrain()
	depot_id = _add_building("depot", w / 2, h / 2)
	stock = {}
	for g in C.goods:
		stock[g] = 0
	for g in C.season.start_stock:
		stock[g] = int(C.season.start_stock[g])
	deck = C.starter_deck.duplicate()
	season = 1
	history.clear()
	last_result = {}
	_start_season()


func _gen_terrain() -> void:
	terrain = PackedInt32Array()
	terrain.resize(w * h)
	terrain.fill(T.PLAIN)
	var cx := w / 2
	var cy := h / 2
	# Two deposits of each resource, one near the Depot and one farther out,
	# so every seed is playable but layouts still differ.
	for kind in [T.ORE, T.FERTILE, T.ORE, T.FERTILE]:
		var near: bool = kind == T.ORE and _count(T.ORE) == 0 or kind == T.FERTILE and _count(T.FERTILE) == 0
		var r := 3 if near else 6
		var p := _random_spot(cx, cy, r)
		_blob(p, kind, rng.randi_range(5, 7))
	for i in rng.randi_range(5, 8):
		var p := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
		if abs(p.x - cx) <= 1 and abs(p.y - cy) <= 1:
			continue
		if terrain[_i(p.x, p.y)] == T.PLAIN:
			terrain[_i(p.x, p.y)] = T.ROCK
	# Keep the landing zone clear.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			terrain[_i(cx + dx, cy + dy)] = T.PLAIN


func _random_spot(cx: int, cy: int, r: int) -> Vector2i:
	for attempt in 50:
		var p := Vector2i(cx + rng.randi_range(-r, r), cy + rng.randi_range(-r, r))
		if not _in(p.x, p.y):
			continue
		if abs(p.x - cx) <= 1 and abs(p.y - cy) <= 1:
			continue
		if terrain[_i(p.x, p.y)] == T.PLAIN:
			return p
	return Vector2i(clampi(cx + r, 0, w - 1), cy)


func _blob(start: Vector2i, kind: int, size: int) -> void:
	var p := start
	var placed := 0
	for step in size * 4:
		if placed >= size:
			break
		if _in(p.x, p.y) and terrain[_i(p.x, p.y)] == T.PLAIN:
			terrain[_i(p.x, p.y)] = kind
			placed += 1
		var d: Vector2i = DIRS[rng.randi_range(0, 3)]
		var q := p + d
		if _in(q.x, q.y):
			p = q


func _count(kind: int) -> int:
	var n := 0
	for t in terrain:
		if t == kind:
			n += 1
	return n


func quota_for(n: int) -> int:
	var q: float = float(C.quota.base) * pow(float(C.quota.growth), n - 1)
	if n % int(C.quota.boss_every) == 0:
		q *= float(C.quota.boss_factor)
	var step := int(C.quota.round_to)
	return int(round(q / step)) * step


func is_boss(n: int) -> bool:
	return n % int(C.quota.boss_every) == 0


func _start_season() -> void:
	phase = "build"
	time_left = float(C.season.length_seconds)
	quota = quota_for(season)
	permits = int(C.season.permits)
	redraws = int(C.season.redraws)
	produced = {}
	_acc = 0.0
	for id in order:
		var b: Dictionary = buildings[id]
		if b.type == "habitat":
			b.fed = 0
			b.meals = 0
			b.eat_timer = 0.0
	_draw_hand()
	_dirty = true


func _draw_hand() -> void:
	hand.clear()
	var pool: Array = deck.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for card in pool:
		if hand.size() >= int(C.season.hand_size):
			break
		if not hand.has(card):
			hand.append(card)
	# Fairness rule [Guess]: every hand has at least one extractor.
	var has_extractor := false
	for card in hand:
		if C.extractors.has(card):
			has_extractor = true
	if not has_extractor and hand.size() > 0:
		for card in pool:
			if C.extractors.has(card) and not hand.has(card):
				hand[hand.size() - 1] = card
				break


func redraw() -> bool:
	if phase != "build" or redraws <= 0:
		return false
	redraws -= 1
	_draw_hand()
	return true


# ---------------------------------------------------------------- building

func def_of(type: String) -> Dictionary:
	return C.buildings[type]


func is_producer(type: String) -> bool:
	return def_of(type).has("outputs")


func can_place(type: String, x: int, y: int) -> String:
	if phase != "build":
		return "The gate is open; building is paused"
	if not _in(x, y):
		return "Out of bounds"
	var d := def_of(type)
	if d.get("buildable", true) == false:
		return "Can't build that"
	if grid[_i(x, y)] != -1:
		return "Tile is occupied"
	var t := terrain[_i(x, y)]
	if t == T.ROCK:
		return "Rock: nothing can be built here"
	if d.has("terrain") and t != TERRAIN_BY_NAME[d.terrain]:
		return "%s must go on %s" % [d.name, TERRAIN_LABEL[TERRAIN_BY_NAME[d.terrain]].to_lower()]
	if d.get("card", false):
		if not hand.has(type):
			return "%s is not in your hand this season" % d.name
		if permits <= 0:
			return "No construction permits left this season"
	var missing := missing_cost(type)
	if missing != "":
		return missing
	return ""


func missing_cost(type: String) -> String:
	var cost: Dictionary = def_of(type).cost
	for g in cost:
		var need := int(cost[g]) - int(stock.get(g, 0))
		if need > 0:
			return "Need %d more %s" % [need, C.goods[g].name]
	return ""


func place(type: String, x: int, y: int) -> String:
	var err := can_place(type, x, y)
	if err != "":
		return err
	var d := def_of(type)
	for g in d.cost:
		stock[g] -= int(d.cost[g])
	if d.get("card", false):
		permits -= 1
	_add_building(type, x, y)
	return ""


func demolish(x: int, y: int) -> String:
	if phase != "build":
		return "The gate is open; building is paused"
	if not _in(x, y) or grid[_i(x, y)] == -1:
		return "Nothing to demolish"
	var id := grid[_i(x, y)]
	var b: Dictionary = buildings[id]
	if b.type == "depot":
		return "The Depot can't be demolished"
	var d := def_of(b.type)
	for g in d.cost:
		stock[g] += int(d.cost[g]) / 2  # 50% refund [Guess]
	buildings.erase(id)
	order.erase(id)
	grid[_i(x, y)] = -1
	_dirty = true
	return ""


func _add_building(type: String, x: int, y: int) -> int:
	var id := next_id
	next_id += 1
	var b := {
		"id": id, "type": type, "x": x, "y": y,
		"progress": 0.0, "inb": {}, "outb": {},
		"staffed": true, "connected": false, "linked": false,
		"pylons": 0, "speed": 1.0, "status": "", "adj": [],
		"fed": 0, "meals": 0, "eat_timer": 0.0,
	}
	buildings[id] = b
	order.append(id)
	grid[_i(x, y)] = id
	_dirty = true
	return id


func building_at(x: int, y: int) -> Dictionary:
	if not _in(x, y):
		return {}
	var id := grid[_i(x, y)]
	return buildings[id] if id != -1 else {}


# ---------------------------------------------------------------- simulation

func step(dt: float) -> void:
	if phase != "build":
		return
	_acc += dt
	while _acc >= TICK:
		_acc -= TICK
		_tick()
		time_left -= TICK
		if time_left <= 0.0001:
			time_left = 0.0
			_end_season()
			return


func _refresh() -> void:
	# Roads reachable from the Depot.
	var reach := {}
	var queue: Array = [depot_id]
	reach[depot_id] = true
	while not queue.is_empty():
		var cur: Dictionary = buildings[queue.pop_front()]
		for nid in _adjacent_ids(cur.x, cur.y):
			if not reach.has(nid) and buildings[nid].type == "road":
				reach[nid] = true
				queue.append(nid)
	for id in order:
		var b: Dictionary = buildings[id]
		b.adj = _adjacent_ids(b.x, b.y)
		if b.type == "depot" or b.type == "road":
			b.connected = reach.has(id)
			continue
		b.connected = false
		for nid in b.adj:
			if reach.has(nid):
				b.connected = true
		# Adjacency bonuses.
		var d := def_of(b.type)
		b.linked = false
		b.pylons = 0
		if d.has("outputs"):
			for nid in b.adj:
				var nb: Dictionary = buildings[nid]
				if nb.type == "pylon":
					b.pylons += 1
				var nd := def_of(nb.type)
				if nd.has("outputs"):
					for g in d.inputs:
						if nd.outputs.has(g):
							b.linked = true
			b.speed = 1.0 + (float(C.adjacency.linked_speed_bonus) if b.linked else 0.0) \
				+ float(C.adjacency.pylon_speed_bonus) * b.pylons
	# Staffing in placement order.
	workers_total = int(C.season.start_crew)
	for id in order:
		if buildings[id].type == "habitat":
			workers_total += int(def_of("habitat").housing)
	workers_used = 0
	for id in order:
		var b: Dictionary = buildings[id]
		var need := int(def_of(b.type).workers)
		if need == 0:
			b.staffed = true
			continue
		b.staffed = workers_used + need <= workers_total
		if b.staffed:
			workers_used += need


func _tick() -> void:
	if _dirty:
		_refresh()
		_dirty = false
	for id in order:
		var b: Dictionary = buildings[id]
		if b.type == "habitat":
			_tick_habitat(b)
			continue
		var d := def_of(b.type)
		if not d.has("outputs"):
			continue
		if not b.staffed:
			b.status = "No workers"
			continue
		for g in d.inputs:
			var want := int(d.inputs[g]) * 2 - int(b.inb.get(g, 0))
			if want > 0:
				b.inb[g] = int(b.inb.get(g, 0)) + _pull(b, g, want)
		var missing := ""
		for g in d.inputs:
			if int(b.inb.get(g, 0)) < int(d.inputs[g]):
				missing = C.goods[g].name
		var full := false
		for g in d.outputs:
			if int(b.outb.get(g, 0)) >= OUT_CAP:
				full = true
		if full:
			b.status = "Output full: link it to the Depot or a consumer"
		elif missing != "":
			b.status = "Waiting for %s" % missing
		else:
			b.status = "Working"
			b.progress += TICK * b.speed / float(d.cycle)
			if b.progress >= 1.0:
				b.progress -= 1.0
				for g in d.inputs:
					b.inb[g] -= int(d.inputs[g])
				for g in d.outputs:
					b.outb[g] = int(b.outb.get(g, 0)) + int(d.outputs[g])
					produced[g] = int(produced.get(g, 0)) + int(d.outputs[g])
		_push(b)


func _tick_habitat(b: Dictionary) -> void:
	var d := def_of("habitat")
	b.eat_timer -= TICK
	if b.eat_timer <= 0.0:
		b.eat_timer += float(d.eat_every)
		b.meals += 1
		var got := 0
		for g in d.eats:
			got = _pull(b, g, int(d.eats[g]))
		if got > 0:
			b.fed += 1
			b.status = "Fed"
		else:
			b.status = "Hungry: needs Rations from the Depot or an adjacent Mill"


## Fetch up to n of good g: adjacent producers first, then the warehouse.
func _pull(b: Dictionary, g: String, n: int) -> int:
	var got := 0
	for nid in b.adj:
		if got >= n:
			break
		var nb: Dictionary = buildings[nid]
		var have := int(nb.outb.get(g, 0))
		if have > 0:
			var take := mini(have, n - got)
			nb.outb[g] = have - take
			got += take
	if got < n and b.connected:
		var take := mini(int(stock.get(g, 0)), n - got)
		stock[g] -= take
		got += take
	return got


## Hand outputs to adjacent consumers first, then the warehouse.
func _push(b: Dictionary) -> void:
	for g in b.outb.keys():
		var have := int(b.outb[g])
		if have <= 0:
			continue
		for nid in b.adj:
			if have <= 0:
				break
			var nb: Dictionary = buildings[nid]
			var nd := def_of(nb.type)
			if nd.has("inputs") and nd.inputs.has(g) and nb.staffed:
				var room := int(nd.inputs[g]) * 2 - int(nb.inb.get(g, 0))
				var give := mini(room, have)
				if give > 0:
					nb.inb[g] = int(nb.inb.get(g, 0)) + give
					have -= give
		if have > 0 and b.connected:
			stock[g] += have
			have = 0
		b.outb[g] = have


func _end_season() -> void:
	# Final sweep: goods waiting in connected buildings reach the warehouse.
	for id in order:
		var b: Dictionary = buildings[id]
		if b.connected:
			for g in b.outb:
				stock[g] += int(b.outb[g])
				b.outb[g] = 0
	phase = "ship"


# ---------------------------------------------------------------- scoring

func fed_share(b: Dictionary) -> float:
	return float(b.fed) / float(b.meals) if b.meals > 0 else 0.0


func multiplier() -> float:
	var m := float(C.prosperity.base_mult)
	for id in order:
		var b: Dictionary = buildings[id]
		if b.type == "habitat":
			m += float(C.prosperity.per_fed_habitat) * fed_share(b)
	return snappedf(m, 0.01)


func preview(selection: Dictionary = {}) -> Dictionary:
	var lines: Array = []
	var base := 0
	for g in C.goods:
		var qty := int(stock.get(g, 0))
		if qty <= 0 or selection.get(g, true) == false:
			continue
		var v := int(C.goods[g].value)
		lines.append({"good": g, "name": C.goods[g].name, "qty": qty, "value": v, "subtotal": qty * v})
		base += qty * v
	var m := multiplier()
	var score := int(floor(base * m))
	return {"lines": lines, "base": base, "mult": m, "score": score,
		"quota": quota, "passed": score >= quota, "season": season}


func ship(selection: Dictionary = {}) -> Dictionary:
	if phase != "ship":
		return {}
	var r := preview(selection)
	for line in r.lines:
		stock[line.good] -= line.qty
	r["produced"] = produced.duplicate()
	history.append(r)
	last_result = r
	phase = "result"
	return r


func advance() -> void:
	if phase != "result":
		return
	if last_result.passed:
		season += 1
		_start_season()
	else:
		phase = "over"


# ---------------------------------------------------------------- helpers

func _in(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func _i(x: int, y: int) -> int:
	return y * w + x


func _adjacent_ids(x: int, y: int) -> Array:
	var out: Array = []
	for d in DIRS:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if _in(nx, ny) and grid[_i(nx, ny)] != -1:
			out.append(grid[_i(nx, ny)])
	return out
