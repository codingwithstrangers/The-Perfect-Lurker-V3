extends Node
class_name Trap

@export var slide_time: float
@export var drop_safe_time: float
@export var trap_root: Node
@export var sprite: Sprite2D

@onready var area: Area2D = $'.'
@onready var event_stream: EventStream = $/root/root/managers/event_stream

var dropped_by: String
var trap_type: String = "unknown"

func _ready() -> void:
	var drop_ignore_timer = Timer.new()
	add_child(drop_ignore_timer)
	drop_ignore_timer.wait_time = drop_safe_time
	drop_ignore_timer.timeout.connect(func():
		drop_ignore_timer.queue_free()
		# Don't clear dropped_by - we need it for logging when trap is hit
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
	
	# Emit trap_hit signal for logging
	event_stream.trap_hit.emit(trap_type, lurker.username, dropped_by)
	
	lurker.hit_trap(self.slide_time)
	trap_root.queue_free()
