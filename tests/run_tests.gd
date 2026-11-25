extends SceneTree
## Headless checks. Run with:
##   godot --headless --path . --script res://tests/run_tests.gd
## Add `-- --balance` to also print a balance report across seeds.

const Bot := preload("res://tests/bot.gd")

var failures := 0


func _init() -> void:
	test_terrain_has_resources()
	test_placement_rules()
	test_chain_produces_and_scores()
	test_adjacency_link_speeds_up()
	test_hungry_habitat_lowers_mult()
	test_determinism()
	test_hand_always_has_extractor()
	test_demolish_keeps_blueprint()
	test_partial_shipment_and_reserve()
	test_resupply()
	test_main_scene_loads()
	if OS.get_cmdline_user_args().has("--balance"):
		balance_report()
	print("\n%s (%d failure%s)" % ["FAILED" if failures else "ALL PASSED", failures, "" if failures == 1 else "s"])
	quit(1 if failures else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func fresh(seed := 1) -> Sim:
	var s := Sim.new()
	s.new_run(seed)
	return s


func run_season(s: Sim) -> void:
	while s.phase == "build":
		s.step(1.0)


func test_terrain_has_resources() -> void:
	print("terrain")
	for seed in 20:
		var s := fresh(seed)
		check(s._count(Sim.T.ORE) >= 5 and s._count(Sim.T.FERTILE) >= 5, "seed %d has ore and fertile soil" % seed)


func test_placement_rules() -> void:
	print("placement")
	var s := fresh(3)
	var c := Vector2i(s.w / 2, s.h / 2)
	check(s.can_place("road", c.x, c.y) != "", "can't build on the Depot")
	var plain := Vector2i(c.x + 1, c.y)
	s.hand = ["mine", "smelter"]
	check(s.can_place("mine", plain.x, plain.y).contains("ore"), "mine needs ore deposit")
	check(s.can_place("fabricator", plain.x, plain.y).contains("not in your hand"), "card must be in hand")
	s.permits = 0
	check(s.can_place("smelter", plain.x, plain.y).contains("permit"), "cards need permits")
	check(s.can_place("road", plain.x, plain.y) == "", "core buildings need no permit")
	s.stock.ore = 0
	check(s.can_place("road", plain.x, plain.y).contains("Ore"), "costs are enforced")


func test_chain_produces_and_scores() -> void:
	print("chain")
	var s := fresh(5)
	var bot := Bot.new(s)
	s.hand = ["mine", "smelter", "farm", "mill"]
	bot.play_build_phase()
	run_season(s)
	check(s.phase == "ship", "season ends at the gate")
	check(int(s.produced.get("ore", 0)) > 0, "mines produced ore (%d)" % int(s.produced.get("ore", 0)))
	check(int(s.produced.get("alloy", 0)) > 0, "smelter produced alloy (%d)" % int(s.produced.get("alloy", 0)))
	var r := s.ship()
	check(r.score > 0, "shipment scores (%d vs quota %d)" % [r.score, r.quota])
	check(s.stock.alloy == 0, "shipped goods leave the warehouse")
	s.advance()
	check(s.phase == ("build" if r.passed else "over"), "advance follows pass/fail")


func test_adjacency_link_speeds_up() -> void:
	print("adjacency")
	var s := fresh(5)
	var c := Vector2i(s.w / 2, s.h / 2)
	s.terrain[s._i(c.x + 2, c.y)] = Sim.T.ORE
	s.hand = ["mine", "smelter", "pylon"]
	s.stock.ore = 100
	s.stock.alloy = 100
	s.place("smelter", c.x + 1, c.y)
	s.place("mine", c.x + 2, c.y)
	s._refresh()
	var sm := s.building_at(c.x + 1, c.y)
	check(sm.linked and is_equal_approx(sm.speed, 1.5), "smelter next to mine is linked (x%.2f)" % sm.speed)
	s.place("pylon", c.x + 1, c.y + 1)
	s._refresh()
	check(is_equal_approx(sm.speed, 1.75), "pylon stacks on top (x%.2f)" % sm.speed)


func test_hungry_habitat_lowers_mult() -> void:
	print("habitats")
	var s := fresh(7)
	var c := Vector2i(s.w / 2, s.h / 2)
	s.stock.rations = 0
	s.place("habitat", c.x - 1, c.y)
	run_season(s)
	check(is_equal_approx(s.multiplier(), 1.0), "starved habitat adds nothing (x%.2f)" % s.multiplier())
	var s2 := fresh(7)
	s2.stock.rations = 50
	s2.place("habitat", c.x - 1, c.y)
	run_season(s2)
	check(is_equal_approx(s2.multiplier(), 1.5), "fed habitat adds +0.5 (x%.2f)" % s2.multiplier())


func test_determinism() -> void:
	print("determinism")
	var scores := []
	for i in 2:
		var s := fresh(42)
		Bot.new(s).play_build_phase()
		run_season(s)
		scores.append(s.ship().score)
	check(scores[0] == scores[1], "same seed, same score (%d, %d)" % scores)


func test_hand_always_has_extractor() -> void:
	print("hand")
	var ok := true
	var first_ok := true
	for seed in 200:
		var s := fresh(seed)
		if not (s.hand.has("mine") and s.hand.has("farm")):
			first_ok = false
		for season in 4:
			if season > 0:
				s.season += 1
				s._draw_hand()
			if s.hand.size() != int(s.C.season.hand_size):
				ok = false
			for chain in s.C.chains:
				var covered := false
				for c in s.hand:
					if s.C.chains[chain].has(c):
						covered = true
				if not covered:
					ok = false
	check(first_ok, "200 first hands all have a Mine and a Farm")
	check(ok, "800 hands all have 4 cards covering both chains")


func test_demolish_keeps_blueprint() -> void:
	print("demolish")
	var s := fresh(9)
	var c := Vector2i(s.w / 2, s.h / 2)
	s.hand = ["smelter"]
	s.stock.ore = 100
	s.place("smelter", c.x + 1, c.y)
	check(s.permits == 3, "placing uses a permit")
	s.demolish(c.x + 1, c.y)
	check(s.permits == 4 and s.stock.ore == 100, "same-season undo refunds cost and permit")
	s.place("smelter", c.x + 1, c.y)
	s.season += 1  # pretend a season passed
	s.hand = ["mine"]
	s.permits = 0
	s.demolish(c.x + 1, c.y)
	check(int(s.salvage.get("smelter", 0)) == 1, "older building leaves a salvaged blueprint")
	check(s.can_place("smelter", c.x - 1, c.y) == "", "salvaged blueprint builds without card or permit")
	s.place("smelter", c.x - 1, c.y)
	check(int(s.salvage.get("smelter", 0)) == 0, "building it spends the blueprint")


func test_partial_shipment_and_reserve() -> void:
	print("shipping")
	var s := fresh(11)
	run_season(s)
	var ore_before: int = s.stock.ore
	var r := s.ship({"ore": 5, "alloy": true, "rations": false})
	check(s.stock.ore == ore_before - 5, "ship 5 Ore, keep the rest (%d left)" % s.stock.ore)
	check(s.stock.rations > 0 and s.stock.alloy == 0, "kept Rations, shipped all Alloy")
	s.advance()
	if s.phase == "build":
		check(true, "next season starts")
	var s2 := fresh(12)
	var c := Vector2i(s2.w / 2, s2.h / 2)
	s2.hand = ["smelter"]
	s2.stock.ore = 30
	s2.place("smelter", c.x + 1, c.y)
	run_season(s2)
	check(s2.stock.ore == int(s2.C.season.warehouse_reserve.ore), "smelter leaves the Ore reserve (%d)" % s2.stock.ore)


func test_resupply() -> void:
	print("resupply")
	var s := fresh(13)
	s.quota = 0
	run_season(s)
	s.ship()
	s.advance()
	check(s.season == 2 and s.stock.ore == int(s.C.season.resupply.ore), "season 2 starts with the resupply (%d Ore)" % s.stock.ore)


func test_main_scene_loads() -> void:
	print("scene")
	var packed: PackedScene = load("res://scenes/main.tscn")
	check(packed != null, "main scene loads")
	var inst = packed.instantiate()
	check(inst != null, "main scene instantiates")
	inst.free()


func balance_report() -> void:
	for keep in [false, true]:
		_balance(keep)


func _balance(keep_materials: bool) -> void:
	print("\nbalance: greedy bot, 30 seeds, %s" % ("keeps Ore and Rations" if keep_materials else "ships everything"))
	var sel := {"ore": false, "rations": false} if keep_materials else {}
	var reached := {}
	var s1_scores := []
	for seed in 30:
		var s := fresh(1000 + seed)
		var bot := Bot.new(s)
		while s.phase != "over" and s.season <= 12:
			bot.play_build_phase()
			run_season(s)
			var r := s.ship(sel)
			if s.season == 1:
				s1_scores.append(r.score)
			s.advance()
		var last := s.season if s.phase == "over" else 13
		reached[last] = int(reached.get(last, 0)) + 1
	s1_scores.sort()
	print("  season 1 score: min %d, median %d, max %d (quota %d)" % [
		s1_scores[0], s1_scores[s1_scores.size() / 2], s1_scores[-1], Sim.new().quota_for(1)])
	var keys := reached.keys()
	keys.sort()
	for k in keys:
		print("  failed at season %d: %d runs" % [k, reached[k]])
	var q := []
	for n in range(1, 9):
		q.append(Sim.new().quota_for(n))
	print("  quotas 1-8: ", q)
