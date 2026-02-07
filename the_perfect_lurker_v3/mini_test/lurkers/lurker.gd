extends PathFollow2D
class_name Lurker

enum RaceState { Out, Racing, Pitting, InThePit, LeavingThePit, Stunned }
signal lap_completed(user_name: String, lap_count: int)

@export var max_speed: float
@export var acceleration_rate: float
@export var deceleration_rate: float
@export var target_rate: float
@export_range(0, 60, 1, "suffix:minutes") var idle_time_before_pitting: float
@export var shield_scale: Vector2 = Vector2(0.2, 0.2)
@export var shield_offset: Vector2 = Vector2(0, -80)
@export_range(0.0, 1.0, 0.01) var shield_opacity: float = 1.0

@onready var debugger: Debugger = $/root/debugger
@onready var car_sprite: Sprite2D = $lurker_sprite
@onready var event_stream: EventStream = $/root/root/managers/event_stream
@onready var area: Area2D = $lurker_area

var username: String
var profile_url: String
var profile_image: Texture2D

var speed = 0.0
var target_speed = 0.0
var lap_count = 0
var previous_progress = 0.0
var idle_timer: float = 0
var crown_sprite: Sprite2D = null
@export var units_per_mile: float = 1000.0
var total_distance: float = 0.0
var last_state_before_leave: RaceState = RaceState.Out  # Track where they left from
var shield_level: int = 0
var shield_sprite: Sprite2D = null

signal distance_updated(user_name: String, total_distance: float)

var state: RaceState = RaceState.Out:
	set(new_state):
		if new_state == state:
			return
		state = new_state
		if state == RaceState.Out or state == RaceState.Pitting:
			target_speed = 0

func _ready() -> void:
	area.area_entered.connect(_area_entered)
	state = RaceState.Racing

func _process(delta: float) -> void:
	if state == RaceState.Out || state == RaceState.InThePit || state == RaceState.Stunned:
		return

	if self.speed < self.target_speed:
		speed = min(self.speed + self.acceleration_rate * delta, self.target_speed)
	else:
		speed = max(self.speed - self.deceleration_rate * delta, self.target_speed)
		if speed <= 0 and state == RaceState.Pitting:
			state = RaceState.InThePit
	
	if self.state == RaceState.Racing or self.state == RaceState.LeavingThePit:
		self.target_speed = min(self.target_speed + self.target_rate * delta, self.max_speed)
	
	self.progress += speed * delta
	# Track total distance (used for ranking)
	self.total_distance += speed * delta

	# Compute laps from total_distance using track length
	var track_len = 0.0
	if get_parent() and get_parent().curve:
		track_len = get_parent().curve.get_baked_length()

	if track_len > 0:
		var new_laps = int(self.total_distance / track_len)
		if new_laps > lap_count:
			lap_count = new_laps
			lap_completed.emit(username, lap_count)

	# Emit distance update for ranking
	distance_updated.emit(username, self.total_distance)

	self.idle_timer += delta

	# Report miles (two decimals) and other stats
	var miles = self.total_distance / units_per_mile
	debugger.report(self.username+"_miles", String.num(miles, 2))
	debugger.report(self.username+"_laps", String.num(self.lap_count, 0))
	debugger.report(self.username+"_speed", String.num(self.speed, 3))
	debugger.report(self.username+"_target_speed", String.num(self.target_speed, 3))
	debugger.report(self.username+"_state", RaceState.keys()[state])

func chat():
	print(username, " sent a chat message and is slowing down")
	target_speed = 0
	idle_timer = 0

func set_shield(level: int) -> void:
	shield_level = max(level, 0)
	if shield_level <= 0:
		clear_shield()
		return
	if shield_sprite == null:
		shield_sprite = Sprite2D.new()
		add_child(shield_sprite)
	shield_sprite.scale = shield_scale
	shield_sprite.offset = shield_offset
	shield_sprite.modulate = Color(1, 1, 1, shield_opacity)
	_update_shield_texture()

func _update_shield_texture() -> void:
	if shield_sprite == null:
		return
	if shield_level >= 3:
		shield_sprite.texture = load("res://mini_test/shield/blue_shield.png")
	elif shield_level == 2:
		shield_sprite.texture = load("res://mini_test/shield/yellow_shield.png")
	elif shield_level == 1:
		shield_sprite.texture = load("res://mini_test/shield/red_Shield.png")
	else:
		clear_shield()

func clear_shield() -> void:
	shield_level = 0
	if shield_sprite != null:
		shield_sprite.queue_free()
		shield_sprite = null

func absorb_shield() -> bool:
	# Returns true if a shield absorbed this hit
	if shield_level > 0:
		shield_level -= 1
		_update_shield_texture()
		if shield_level <= 0:
			clear_shield()
		return true
	return false

func hit_trap(slide_time: float):
	var start_state = state
	self.state = RaceState.Stunned
	var tween = self.create_tween()
	tween.set_parallel(true)
	
	var prog_tween = tween.tween_property(self, "progress", self.progress + self.speed * 0.5, slide_time)
	prog_tween.set_ease(Tween.EASE_IN)
	var rot_tween = tween.tween_property(self.car_sprite, "rotation", self.car_sprite.rotation+PI*4, slide_time)
	rot_tween.set_ease(Tween.EASE_IN_OUT)
	
	tween.tween_callback(func():
		self.state = start_state
		self.speed = 0
	)
#Would like to make a commmand for users to remove themself from the lurker 
func leave_race():
	print(username, " has left the race")
	# Save current state before setting Out (for rejoin logic)
	if state == RaceState.InThePit or state == RaceState.Pitting:
		last_state_before_leave = RaceState.InThePit
	else:
		last_state_before_leave = RaceState.Racing
	car_sprite.visible = false
	# Clear shield when leaving
	clear_shield()
	state = RaceState.Out
#	we need to remove pic from track not just stats 

func join_race():
	print(username, " has joined the race")
	car_sprite.visible = true
	car_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	idle_timer = 0
	lap_count = 0
	progress = 0
	previous_progress = 0.0
	speed = 0.0
	target_speed = 0.0
	remove_crown()
	state = RaceState.Racing

# Smart rejoin: restore to pit or track based on where they left
func rejoin_race():
	print(username, " has rejoined the race (restoring to track)")
	car_sprite.visible = true
	car_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	idle_timer = 0
	speed = 0.0
	target_speed = 0.0
	remove_crown()

	# Reset in-race stats when a player rejoins after leaving.
	# This ensures the rejoined player starts fresh on the main track.
	progress = 0
	previous_progress = 0.0
	lap_count = 0
	total_distance = 0.0
	# Always set to Racing on rejoin (will be reparented to track by LurkerGang)
	state = RaceState.Racing
	print(username, " is back at the track start (stats reset)")
	
func _kick(target_username: String) -> void:
	if username.to_lower() == target_username.to_lower():
		print("Kicking user: ", username)
		state = RaceState.Out
	
func _area_entered(hit_area: Area2D) -> void:
	if hit_area.get_meta("pit_enter", false) and self.idle_timer > idle_time_before_pitting * 60:
		print(username, " should enter the pits")
		event_stream.send_to_pit.emit(username)
	elif hit_area.get_meta("pit_exit", false) and state == RaceState.LeavingThePit:
		print(username, " should exit the pits")
		event_stream.send_to_track.emit(username)
		state = RaceState.Racing

func leave_pit():
	if state != RaceState.InThePit:
		return
	print(username, " is leaving the pit")
	# Restore sprite color
	car_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	state = RaceState.LeavingThePit
	idle_timer = 0
	progress = 0
	speed = 0.0
	target_speed = 0.0
	
func enter_pit():
	print(username, " has entered the pit")
	# Shields reset on pit entry
	clear_shield()
	# Grey out sprite in pit lane (full opacity)
	car_sprite.modulate = Color(0.5, 0.5, 0.5, 1.0)
	state = RaceState.InThePit

func set_crown(crown_texture: Texture2D) -> void:
	if crown_sprite == null:
		crown_sprite = Sprite2D.new()
		crown_sprite.scale = Vector2(0.15, 0.15)
		crown_sprite.rotation_degrees = 25.0
		crown_sprite.offset = Vector2(150, -430)
		add_child(crown_sprite)
	crown_sprite.texture = crown_texture

func remove_crown() -> void:
	if crown_sprite != null:
		crown_sprite.queue_free()
		crown_sprite = null
