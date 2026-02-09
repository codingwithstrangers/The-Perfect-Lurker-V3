extends PathFollow2D
class_name Missle

@export var speed: float
@export var boomerang_distance: float = 300.0  # Distance to travel before reversing

@onready var sprite: Sprite2D = $missle_sprite
@onready var area: Area2D = $missle_area
@onready var trap: Trap = $missle_area

var is_boomerang: bool = false
var initial_progress: float = 0.0
var has_reversed: bool = false

func _process(delta: float) -> void:
	if is_boomerang and not has_reversed:
		# Check if we've traveled far enough to reverse
		if self.progress - initial_progress >= boomerang_distance:
			has_reversed = true
			speed = -speed  # Reverse direction
			sprite.flip_h = !sprite.flip_h  # Flip sprite to show direction change
	
	self.progress += speed * delta
