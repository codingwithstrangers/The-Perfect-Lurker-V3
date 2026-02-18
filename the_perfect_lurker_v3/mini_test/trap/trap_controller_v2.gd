extends PathFollow2D
class_name TrapControllerV2

signal red_motion_finished(target_id: String, trap: TrapControllerV2)

@export var red_delay: float = 1.2
@export var visual_scale: Vector2 = Vector2(0.25, 0.25)
@export var yellow_rotates: bool = false
@export var red_rotates: bool = true
@export var yellow_texture: Texture2D
@export var red_texture_forward: Texture2D
@export var red_texture_wrapped: Texture2D

@onready var trap_area: Trap = $trap_area
@onready var sprite: Sprite2D = $trap_sprite

var target_id: String = ""
var _motion_tween: Tween = null

func setup_collision(dropped_by: String, dropped_on_lap: int, trap_type: String, allow_self_damage: bool = false) -> void:
	trap_area.dropped_by = dropped_by
	trap_area.dropped_on_lap = dropped_on_lap
	trap_area.trap_type = trap_type
	trap_area.allow_self_damage = allow_self_damage

func place_yellow(progress_value: float, texture_override: Texture2D = null) -> void:
	progress = progress_value
	_update_visuals("yellow", false, texture_override)

func launch_red_by_points(attacker_points: float, target_points: float, max_points: float, delay: float = -1.0) -> void:
	var trap_start = _normalized_progress(attacker_points, max_points)
	var trap_end = _normalized_progress(target_points, max_points)
	var wrapped_forward = false

	if trap_end < trap_start:
		trap_end += 1.0
		wrapped_forward = true

	_update_visuals("red", wrapped_forward)
	_start_path_motion(trap_start, trap_end, delay)

func _start_path_motion(trap_start: float, trap_end: float, delay: float) -> void:
	progress_ratio = trap_start

	if _motion_tween and _motion_tween.is_valid():
		_motion_tween.kill()

	var tween_time = red_delay if delay < 0.0 else delay
	_motion_tween = create_tween()
	_motion_tween.tween_property(self, "progress_ratio", trap_end, tween_time).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	_motion_tween.finished.connect(_on_motion_finished)

func _update_visuals(state: String, wrapped_forward: bool, texture_override: Texture2D = null) -> void:
	sprite.scale = visual_scale

	if state == "red":
		sprite.rotation = randf_range(0.0, PI * 2.0) if red_rotates else 0.0
		if wrapped_forward and red_texture_wrapped != null:
			sprite.texture = red_texture_wrapped
		elif red_texture_forward != null:
			sprite.texture = red_texture_forward
	elif state == "yellow":
		sprite.rotation = randf_range(0.0, PI * 2.0) if yellow_rotates else 0.0
		if texture_override != null:
			sprite.texture = texture_override
		elif yellow_texture != null:
			sprite.texture = yellow_texture

func _normalized_progress(points: float, max_points: float) -> float:
	if max_points <= 0.0:
		return 0.0
	return points / max_points

func _on_motion_finished() -> void:
	red_motion_finished.emit(target_id, self)
	queue_free()
