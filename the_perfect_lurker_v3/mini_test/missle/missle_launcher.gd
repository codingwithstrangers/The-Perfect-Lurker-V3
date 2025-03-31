extends Node
class_name MissleLauncher

@export var missle_prefab: PackedScene
@export var missle_textures: Array[Texture2D]

@onready var event_stream: EventStream = $'../event_stream'
@onready var lurker_gang: LurkerGang = $'../lurker_gang'
@onready var track_path: Path2D = $'../../track_path'

func _ready() -> void:
	event_stream.missle_launch_attempted.connect(self._on_missle_launch_attempted)
	
func _on_missle_launch_attempted(username: String):
	if not lurker_gang.lurkers.has(username):
		print("lurker is not in race: ", username)
		return

	print("missle is launching: ", username)
	
	var new_missle = missle_prefab.instantiate()
	track_path.add_child(new_missle)
	var lurker = lurker_gang.lurkers[username] as Lurker
	var missle = new_missle.get_node(".") as Missle
	
	missle.name = username + "_missle"
	missle.sprite.texture = self.missle_textures[randi_range(0, self.missle_textures.size()-1)]
	missle.progress = lurker.progress
	missle.trap.dropped_by = username
