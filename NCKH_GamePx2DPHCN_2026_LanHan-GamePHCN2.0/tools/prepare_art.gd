extends SceneTree


func _initialize() -> void:
	# Original packs live OUTSIDE res:// after the asset audit.
	# Run with: -- --source-assets=D:/.../ASSETS_UNUSED_2026-10-09/assets
	var sources := "res://assets"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-assets="):
			sources = argument.trim_prefix("--source-assets=").trim_suffix("/")
	var root := sources + "/itch.io/Legacy-Fantasy - High Forest 2.0/Legacy-Fantasy - High Forest 2.3/"
	if not FileAccess.file_exists(root + "Assets/Tiles.png"):
		push_error("Source packs are archived. Pass --source-assets=<archive>/assets; see HANDOFF_BE.txt.")
		quit(1)
		return
	var out := "res://assets/shared/environment/"
	DirAccess.make_dir_recursive_absolute(out)
	for pair in [["Background/Background.png", "sky.png"], ["Trees/Background.png", "forest.png"], ["Assets/Props-Rocks.png", "rocks.png"]]:
		assert(DirAccess.copy_absolute(root + pair[0], out + pair[1]) == OK)
	for pair in [["ground_grass_tile.png", "grass.png"], ["ground_rock_tile.png", "stone.png"], ["forest_near.png", "bushes.png"], ["forest_far.png", "forest.png"]]:
		assert(DirAccess.copy_absolute("res://assets/map_1/environment/" + pair[0], out + pair[1]) == OK)
	var tiles := Image.load_from_file(root + "Assets/Tiles.png")
	assert(tiles.get_region(Rect2i(96, 304, 32, 16)).save_png(out + "water.png") == OK)
	assert(DirAccess.copy_absolute(sources + "/itch.io/Treasure Hunters/Treasure Hunters/Palm Tree Island/Sprites/Objects/Spikes/Spikes.png", out + "spikes.png") == OK)
	DirAccess.make_dir_recursive_absolute("res://assets/shared/ui")
	for name in ["panel_tan_inlay.png", "button_tan.png", "button_brown_pressed.png", "LICENSE-KENNEY.txt"]:
		var source: String = sources + "/map_1/ui/" + name
		if not FileAccess.file_exists(source):
			source = "res://assets/map_1/ui/" + name
		assert(DirAccess.copy_absolute(source, "res://assets/shared/ui/" + name) == OK)
	print("CURATED_ART: PASS")
	quit()
