extends Node
class_name Trap

@export var slide_time: float
@export var drop_safe_time: float
@export var trap_root: Node
@export var sprite: Sprite2D

@onready var area: Area2D = $'.'

var dropped_by: String

func _ready() -> void:
	var drop_ignore_timer = Timer.new()
	add_child(drop_ignore_timer)
	drop_ignore_timer.wait_time = drop_safe_time
	drop_ignore_timer.timeout.connect(func():
		drop_ignore_timer.queue_free()
		self.dropped_by = ""
	)
	drop_ignore_timer.start()

func _on_trap_area_area_entered(other: Area2D) -> void:
	print("trap collided by ", other.name)
	if not other.get_parent() is Lurker:
		print("trap hit not by a lurker")
		return
	
	var lurker = other.get_parent() as Lurker
	if lurker.username == self.dropped_by:
		print("trap hit by ourself")
		return
		
	print("trap hit by ", lurker.name)
	
	lurker.hit_trap(self.slide_time)
	trap_root.queue_free()
