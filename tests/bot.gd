extends RefCounted
## A simple greedy player used by the headless tests and the balance report.
## It is not smart; it gives a floor for what a sensible first-time build scores.

const PRIORITY := ["mine", "smelter", "farm", "mill", "fabricator", "pylon"]

var sim: Sim


func _init(s: Sim) -> void:
	sim = s


func play_build_phase() -> void:
	# Spend permits on cards in priority order, twice through the list.
	for pass_i in 2:
		for card in PRIORITY:
			if sim.permits <= 0:
				return
			if sim.hand.has(card):
				_try_place(card)
		_ensure_workers()
	_ensure_workers()


func _ensure_workers() -> void:
	var guard := 0
	while _workers_needed() > sim.workers_total and guard < 4:
		guard += 1
		var spot := _spot_near_connected()
		if spot == Vector2i(-1, -1) or sim.place("habitat", spot.x, spot.y) != "":
			return
		sim._refresh()


func _workers_needed() -> int:
	var n := 0
	for id in sim.order:
		n += int(sim.def_of(sim.buildings[id].type).workers)
	return n


func _try_place(card: String) -> bool:
	var spot := Vector2i(-1, -1)
	var d := sim.def_of(card)
	if d.has("terrain"):
		spot = _best_terrain_spot(Sim.TERRAIN_BY_NAME[d.terrain])
	elif card == "pylon":
		spot = _spot_adjacent_to_most_producers()
	else:
		spot = _spot_adjacent_to_supplier(d.inputs.keys())
	if spot == Vector2i(-1, -1):
		return false
	if sim.can_place(card, spot.x, spot.y) != "":
		return false
	sim.place(card, spot.x, spot.y)
	_connect(spot)
	sim._refresh()
	return true


func _best_terrain_spot(kind: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1e9
	var c := Vector2i(sim.w / 2, sim.h / 2)
	for y in sim.h:
		for x in sim.w:
			if sim.terrain[sim._i(x, y)] == kind and sim.grid[sim._i(x, y)] == -1:
				var dist := absi(x - c.x) + absi(y - c.y)
				if dist < best_d:
					best_d = dist
					best = Vector2i(x, y)
	return best


func _spot_adjacent_to_supplier(goods: Array) -> Vector2i:
	for id in sim.order:
		var b: Dictionary = sim.buildings[id]
		var bd := sim.def_of(b.type)
		if not bd.has("outputs"):
			continue
		var supplies := false
		for g in goods:
			if bd.outputs.has(g):
				supplies = true
		if supplies:
			var s := _free_neighbor(b.x, b.y)
			if s != Vector2i(-1, -1):
				return s
	return _spot_near_connected()


func _spot_adjacent_to_most_producers() -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_n := 0
	for y in sim.h:
		for x in sim.w:
			if not _free(x, y):
				continue
			var n := 0
			for nid in sim._adjacent_ids(x, y):
				if sim.is_producer(sim.buildings[nid].type):
					n += 1
			if n > best_n:
				best_n = n
				best = Vector2i(x, y)
	return best


func _spot_near_connected() -> Vector2i:
	for id in sim.order:
		var b: Dictionary = sim.buildings[id]
		if b.type == "depot" or (b.type == "road" and b.connected):
			var s := _free_neighbor(b.x, b.y)
			if s != Vector2i(-1, -1):
				return s
	return Vector2i(-1, -1)


func _free_neighbor(x: int, y: int) -> Vector2i:
	for d in Sim.DIRS:
		if _free(x + d.x, y + d.y) and sim.terrain[sim._i(x + d.x, y + d.y)] == Sim.T.PLAIN:
			return Vector2i(x + d.x, y + d.y)
	for d in Sim.DIRS:
		if _free(x + d.x, y + d.y):
			return Vector2i(x + d.x, y + d.y)
	return Vector2i(-1, -1)


func _free(x: int, y: int) -> bool:
	return sim._in(x, y) and sim.grid[sim._i(x, y)] == -1 and sim.terrain[sim._i(x, y)] != Sim.T.ROCK


## Lay roads from the tile at p to the Depot network if it is not connected yet.
func _connect(p: Vector2i) -> void:
	sim._refresh()
	var b := sim.building_at(p.x, p.y)
	if b.is_empty() or b.connected:
		return
	# BFS over free tiles from p's neighbours to any tile touching the network.
	var prev := {}
	var queue: Array = []
	for d in Sim.DIRS:
		var q: Vector2i = p + d
		if _free(q.x, q.y):
			prev[q] = p
			queue.append(q)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if _touches_network(cur):
			var path: Array = []
			var t := cur
			while t != p:
				path.append(t)
				t = prev[t]
			for tile in path:
				if sim.place("road", tile.x, tile.y) != "":
					return
			return
		for d in Sim.DIRS:
			var q: Vector2i = cur + d
			if _free(q.x, q.y) and not prev.has(q):
				prev[q] = cur
				queue.append(q)


func _touches_network(t: Vector2i) -> bool:
	for nid in sim._adjacent_ids(t.x, t.y):
		var nb: Dictionary = sim.buildings[nid]
		if nb.type == "depot" or (nb.type == "road" and nb.connected):
			return true
	return false
