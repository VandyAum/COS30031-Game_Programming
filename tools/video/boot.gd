extends Node
## Entry scene for recording the video: adds the Director to the root (so it
## survives the scene change), then loads the real game scene.
##
##   Godot --path . --windowed --resolution 1920x1080 --fixed-fps 30 \
##     --write-movie out.avi res://tools/video/boot.tscn -- shot=showcase
##
## tools/ is excluded from the web export, so none of this ships.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Take the narration transcript and record gameplay video to sync
#    alongside it."


func _ready() -> void:
	# The project asks for fullscreen; record in a plain 1920x1080 window.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	# Tips are shown by the director when it wants them, not automatically.
	for id in ["welcome", "first_call", "dispatched", "blocked", "passed_on", "stage_1", "stage_2", "stage_3"]:
		Run.tips_seen[id] = true
	var director: Node = preload("res://tools/video/director.gd").new()
	director.name = "Director"
	get_tree().root.add_child.call_deferred(director)
	get_tree().change_scene_to_file.call_deferred("res://main.tscn")
