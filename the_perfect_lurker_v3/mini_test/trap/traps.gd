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
var dropped_on_lap: int = 0  # Track which lap the trap was dropped on
var allow_self_damage: bool = false  # Set to true for boomerang missiles

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
	
	# Self-damage immunity checks
	if lurker.username == self.dropped_by:
		# Yellow traps have lap-based immunity - dropper can't be hit until next lap
		if trap_type == "yellow_attack" and lurker.lap_count == dropped_on_lap:
			print("yellow trap hit by dropper on same lap - immunity active")
			return
		# Red shells never hit their launcher unless it's a boomerang (1st place)
		elif trap_type == "red_shell" and not allow_self_damage:
			print("red shell hit by dropper - immunity active (not a boomerang)")
			return
		else:
			print("trap hit by dropper - self-damage allowed")
			# Continue to damage logic below
	else:
		print("trap hit by ", lurker.name)
	
	# Check if shield absorbs this trap
	var shield_level_before = lurker.shield_level
	var shield_level_after = lurker.absorb_shield()
	
	if shield_level_before > 0:
		# Shield was hit - emit shield_hit signal for logging
		event_stream.trap_shield_hit.emit(trap_type, dropped_by, lurker.username, shield_level_before, shield_level_after)
		var remaining = shield_level_after
		var msg = dropped_by + " hit " + lurker.username + "'s shield with " + trap_type + "! " + str(remaining) + " hits remaining."
		event_stream.system_message.emit(msg)
		trap_root.queue_free()
		return
	
	# Emit trap_hit signal for logging
	event_stream.trap_hit.emit(trap_type, lurker.username, dropped_by)
	
	# Send chat message for trap hit
	if lurker.username == dropped_by:
		var msg = dropped_by + " hit their own " + trap_type + "!"
		event_stream.system_message.emit(msg)
	else:
		var msg = dropped_by + " hit " + lurker.username + " with " + trap_type + "!"
		event_stream.system_message.emit(msg)
	
	lurker.hit_trap(self.slide_time)
	trap_root.queue_free()
