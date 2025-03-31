extends PathFollow2D
class_name Missle

@export var speed: float

@onready var sprite: Sprite2D = $missle_sprite
@onready var area: Area2D = $missle_area
@onready var trap: Trap = $missle_area

func _process(delta: float) -> void:
	self.progress += speed * delta
