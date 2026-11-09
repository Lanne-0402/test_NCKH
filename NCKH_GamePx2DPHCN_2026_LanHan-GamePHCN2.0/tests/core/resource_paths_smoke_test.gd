extends Node

const REQUIRED_SCENES := [
	"res://ui/screens/start/start_screen.tscn",
	"res://ui/screens/calibration/calibration_screen.tscn",
	"res://ui/screens/map_selection/level_selection.tscn",
	"res://ui/screens/level_selection/main_menu.tscn",
	"res://maps/shared/characters/player/player.tscn",
	"res://maps/shared/world/ground.tscn",
	"res://maps/map_1/obstacle.tscn",
	"res://maps/map_1/placeholders/map_1_background.tscn",
	"res://maps/map_1/placeholders/map_1_cave.tscn",
	"res://maps/map_1/placeholders/map_1_pose_guide.tscn",
	"res://maps/map_1/placeholders/map_1_rock_visual.tscn",
	"res://maps/map_1/main_level.tscn",
	"res://maps/map_1/visuals/map_1_background.tscn",
	"res://maps/map_1/visuals/map_1_ground.tscn",
	"res://maps/map_1/visuals/map_1_cave.tscn",
	"res://maps/map_1/visuals/map_1_rock_visual.tscn",
	"res://maps/map_2/placeholders/map_2_background.tscn",
	"res://maps/map_2/placeholders/map_2_pose_guide.tscn",
	"res://maps/map_2/placeholders/map_2_slab_visual.tscn",
	"res://maps/map_2/main_level.tscn",
	"res://maps/map_3/main_level.tscn",
	"res://maps/map_4/main_level.tscn",
	"res://maps/map_5/main_level.tscn",
]


func _ready() -> void:
	for path in REQUIRED_SCENES:
		assert(ResourceLoader.exists(path), "Missing required scene: %s" % path)
		var packed_scene := load(path) as PackedScene
		assert(packed_scene != null, "Could not load required scene: %s" % path)
		var instance := packed_scene.instantiate()
		assert(instance != null, "Could not instantiate required scene: %s" % path)
		instance.free()
	print("RESOURCE_PATHS_SMOKE_TEST: PASS")
	get_tree().quit(0)
