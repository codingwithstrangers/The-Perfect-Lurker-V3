extends Node
class_name TrapDropper

@export var trap_textures: Array[Texture2D]
@export var drop_distance: float
@export_range(0, 1) var drop_time: float
@export var trap_prefab: PackedScene
@export var red_delay: float = 1.2
@onready var track_manager: TrackManager = $"../track_manager"
@onready var lurker_gang: LurkerGang = $'../lurker_gang'
@onready var event_stream: EventStream = $'../event_stream'

var red_traps_by_target: Dictionary = {}

func _ready():
	event_stream.trap_drop_attempted.connect(self._on_trap_drop_attempted)
	event_stream.trap_hit.connect(self._on_trap_hit)
	event_stream.trap_shield_hit.connect(self._on_trap_shield_hit)

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

	var trap_texture: Texture2D = null
	if self.trap_textures.size() > 0:
		trap_texture = self.trap_textures[randi_range(0, self.trap_textures.size() - 1)]

	var trap_type = _resolve_trap_type(trap_texture)
	if trap_type == "red_shell":
		_spawn_red_trap(username, lurker)
		return

	_spawn_yellow_trap(username, lurker, trap_texture)

func _spawn_trap_instance() -> TrapControllerV2:
	if track_manager.track == null:
		push_error("No track selected yet; trap spawn aborted")
		return null

	var new_trap = trap_prefab.instantiate()
	track_manager.track.add_child(new_trap)

	var trap = new_trap as TrapControllerV2
	if trap == null:
		push_error("Trap prefab root must use TrapControllerV2")
		new_trap.queue_free()
		return null

	trap.loop = true
	return trap

func _spawn_yellow_trap(username: String, lurker: Lurker, texture: Texture2D) -> void:
	var trap = _spawn_trap_instance()
	if trap == null:
		return

	trap.name = username + "_trap"
	trap.setup_collision(username, lurker.lap_count, "yellow_attack", false)
	trap.place_yellow(lurker.progress, texture)
	_place_trap_behind_lurker(trap, lurker)

func _place_trap_behind_lurker(trap: TrapControllerV2, lurker: Lurker) -> void:
	var tween = trap.create_tween()
	var target_progress = lurker.progress - self.drop_distance
	tween.tween_property(trap, "progress", target_progress, self.drop_time).set_ease(Tween.EASE_IN)

func _spawn_red_trap(username: String, attacker: Lurker) -> void:
	var target_id = _get_target_in_front(username)
	if target_id.is_empty():
		print("no valid red trap target in front: ", username)
		return
	if not lurker_gang.lurkers.has(target_id):
		print("red trap target missing from lurker list: ", target_id)
		return

	var max_points = _get_max_points()
	if max_points <= 0.0:
		print("track max points unavailable; red trap aborted")
		return

	var trap = _spawn_trap_instance()
	if trap == null:
		return

	var target_lurker = lurker_gang.lurkers[target_id] as Lurker
	var attacker_points = attacker.progress
	var target_points = target_lurker.progress

	_remove_red_trap_for_target(target_id)
	red_traps_by_target[target_id] = trap

	trap.name = username + "_red_trap_" + target_id
	trap.target_id = target_id
	trap.setup_collision(username, attacker.lap_count, "red_shell", false)
	trap.red_motion_finished.connect(_on_red_motion_finished)
	trap.launch_red_by_points(attacker_points, target_points, max_points, red_delay)

func _resolve_trap_type(texture: Texture2D) -> String:
	if texture == null:
		return "yellow_attack"

	var texture_path = texture.resource_path
	if "red" in texture_path.to_lower():
		return "red_shell"
	return "yellow_attack"

func _get_target_in_front(username: String) -> String:
	if lurker_gang.rankings.is_empty():
		return ""

	var rank_index = lurker_gang.rankings.find(username)
	if rank_index <= 0:
		return ""

	return lurker_gang.rankings[rank_index - 1]

func _get_max_points() -> float:
	if track_manager.track == null or track_manager.track.curve == null:
		return 0.0
	return track_manager.track.curve.get_baked_length()

func _on_red_motion_finished(target_id: String, trap: TrapControllerV2) -> void:
	if target_id.is_empty():
		return
	if red_traps_by_target.get(target_id) == trap:
		red_traps_by_target.erase(target_id)

func _on_trap_hit(trap_type: String, hit_by: String, _dropped_by: String) -> void:
	if trap_type != "red_shell":
		return
	_remove_red_trap_for_target(hit_by)

func _on_trap_shield_hit(trap_type: String, _dropped_by: String, hit_by: String, _shield_level_before: int, _shield_level_after: int) -> void:
	if trap_type != "red_shell":
		return
	_remove_red_trap_for_target(hit_by)

func _remove_red_trap_for_target(target_id: String) -> void:
	if not red_traps_by_target.has(target_id):
		return

	var existing_trap = red_traps_by_target[target_id] as TrapControllerV2
	red_traps_by_target.erase(target_id)
	if existing_trap != null and is_instance_valid(existing_trap):
		existing_trap.queue_free()
