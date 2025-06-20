extends Node
class_name TrapDropper

@export var trap_textures: Array[Texture2D]
@export var drop_distance: float
@export_range(0, 1) var drop_time: float
@export var trap_prefab: PackedScene
@onready var track_manager: TrackManager = $"../track_manager"
@onready var lurker_gang: LurkerGang = $'../lurker_gang'
@onready var event_stream: EventStream = $'../event_stream'

func _ready():
	event_stream.trap_drop_attempted.connect(self._on_trap_drop_attempted)

func _on_trap_drop_attempted(username: String):
	if not lurker_gang.lurkers.has(username):
		print("lurker is not in race: ", username)
		return

	var lurker = lurker_gang.lurkers[username] as Lurker
	if lurker.state != Lurker.RaceState.Racing:
		print("lurker is not in race: ", username)
		return
		
	lurker.idle_timer = 0
	print(username, " dropped a trap")
	
	var new_trap = trap_prefab.instantiate()
	add_child(new_trap)
	var trap = new_trap as Trap
	trap.name = username + "_trap"
	trap.sprite.texture = self.trap_textures[randi_range(0, self.trap_textures.size()-1)]
	trap.rotate(randf_range(0, PI*2))
	trap.position = lurker.position
	trap.dropped_by = username
	
	var curve_point = track_manager.track.curve.sample_baked(lurker.progress - self.drop_distance)
	var trap_pos = track_manager.track.curve.get_closest_point(curve_point)
	var tween = new_trap.create_tween()
	var pos_tween = tween.tween_property(new_trap, "position", trap_pos, self.drop_time).from_current()
	pos_tween.set_ease(Tween.EASE_IN)
