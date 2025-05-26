extends PathFollow2D
class_name Lurker

@export var max_speed: float
@export var acceleration_rate: float
@export var deceleration_rate: float
@export var target_rate: float

@onready var debugger: Debugger = $/root/debugger
@onready var car_sprite: Sprite2D = $lurker_sprite

var username: String
var profile_url: String
var profile_image: Texture2D

var speed = 0.0
var target_speed = 0.0
var score = 0
var active = true

var in_race: bool:
	set(v):
		target_speed = 0
		in_race = v
		debugger.report(self.username+"_in_race", str(v))

func _process(delta: float) -> void:
	if not active:
		return

	if self.speed < self.target_speed:
		speed = min(self.speed + self.acceleration_rate * delta, self.target_speed)
	else:
		speed = max(self.speed - self.deceleration_rate * delta, self.target_speed)
	
	if self.in_race:
		self.target_speed = min(self.target_speed + self.target_rate * delta, self.max_speed)
	
	self.progress += speed * delta
	self.score += speed * delta
	
	debugger.report(self.username+"_score", String.num(self.score, 1))
	debugger.report(self.username+"_speed", String.num(self.speed, 3))
	debugger.report(self.username+"_target_speed", String.num(self.target_speed, 3))

func chat():
	print(username, " sent a chat message and is slowing down")
	target_speed = 0

func hit_trap(slide_time: float):
	self.active = false
	var tween = self.create_tween()
	tween.set_parallel(true)
	
	var prog_tween = tween.tween_property(self, "progress", self.progress + self.speed * 0.5, slide_time)
	prog_tween.set_ease(Tween.EASE_IN)
	var rot_tween = tween.tween_property(self.car_sprite, "rotation", self.car_sprite.rotation+PI*4, slide_time)
	rot_tween.set_ease(Tween.EASE_IN_OUT)
	
	tween.tween_callback(func():
		self.active = true
		self.speed = 0
	)

func leave_race():
	print(username, " has left the race")
	self.in_race = false

func join_race():
	print(username, " has joined the race")
	self.in_race = true

func leave_pit():
	print(username, " has left the pit")
	self.in_race = false
	
func join_pit():
	print(username, " has joined the pit")
	self.in_race = true
