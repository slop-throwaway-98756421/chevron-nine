extends SceneTree
## Renders two screenshots of a bot-played season (needs a display, e.g. xvfb-run).
##   godot --path . --script res://tests/screenshot.gd -- --out=/some/dir

const Bot := preload("res://tests/bot.gd")


func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.new_run(1234)
	Bot.new(main.sim).play_build_phase()
	main.sim.step(70.0)
	main.hover = Vector2i(main.sim.w / 2 + 1, main.sim.h / 2)
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("build.png"))
	main.sim.step(999.0)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out.path_join("gate.png"))
	main._on_ship()
	main.tally.t = 999.0
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("tally.png"))
	quit()
