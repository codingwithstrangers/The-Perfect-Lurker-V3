extends PathFollow2D
class_name Lurker

enum RaceState { Out, Racing, Pitting, InThePit, LeavingThePit, Stunned }

@export var max_speed: float
@export var acceleration_rate: float
@export var deceleration_rate: float
@export var target_rate: float
@export_range(0, 60, 1, "suffix:minutes") var idle_time_before_pitting: float

@onready var debugger: Debugger = $/root/debugger
@onready var car_sprite: Sprite2D = $lurker_sprite
@onready var event_stream: EventStream = $/root/root/managers/event_stream
@onready var area: Area2D = $lurker_area

var username: String
var profile_url: String
var profile_image: Texture2D

var speed = 0.0
var target_speed = 0.0
var score = 0
var idle_timer: float = 0

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
	self.score += speed * delta
	self.idle_timer += delta
	
	debugger.report(self.username+"_score", String.num(self.score, 1))
	debugger.report(self.username+"_speed", String.num(self.speed, 3))
	debugger.report(self.username+"_target_speed", String.num(self.target_speed, 3))
	debugger.report(self.username+"_state", RaceState.keys()[state])

func chat():
	print(username, " sent a chat message and is slowing down")
	target_speed = 0
	idle_timer = 0

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

func leave_race():
	print(username, " has left the race")
	state = RaceState.Out

func join_race():
	print(username, " has joined the race")
	idle_timer = 0
	state = RaceState.Racing
	
func _area_entered(hit_area: Area2D) -> void:
	if hit_area.get_meta("pit_enter", false) and self.idle_timer > idle_time_before_pitting * 60:
		print(username, " should enter the pits")
		event_stream.send_to_pit.emit(username)
	elif hit_area.get_meta("pit_exit", false) and state == RaceState.LeavingThePit:
		print(username, " should exit the pits")
		event_stream.send_to_track.emit(username)
		state = RaceState.Racing

func leave_pit():
	print(username, " is leaving the pit")
	state = RaceState.LeavingThePit
	idle_timer = 0
	
func enter_pit():
	print(username, " has entered the pit")
	state = RaceState.Pitting
