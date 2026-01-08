# faker is used to call a bunch of signals to fake chat messages

extends Node

@export var event_stream: EventStream
@export var timer: Timer
@export var enabled: bool

var index = 0
var steps = [
	func(): event_stream.join_race_attempted.emit("miniscruff", "https://static-cdn.jtvnw.net/jtv_user_pictures/19226552-258a-4158-9f31-7877da18875c-profile_image-300x300.png"),
	func(): event_stream.join_race_attempted.emit("codingwithstrangers", "https://static-cdn.jtvnw.net/jtv_user_pictures/dc386d21-87c4-498e-8d53-bad77fc23141-profile_image-300x300.png"),
	func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,
	func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,
	func(): event_stream.lurker_chat.emit("codingwithstrangers"),
	func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,
	func(): event_stream.trap_drop_attempted.emit("codingwithstrangers"),
	func(): event_stream.missle_launch_attempted.emit("codingwithstrangers"),
	func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,
	func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,
	func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,
	func(): event_stream.lurker_chat.emit("codingwithstrangers"),
	func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,
	func(): event_stream.leave_the_pit.emit("miniscruff"),
	func(): event_stream.leave_the_pit.emit("codingwithstrangers"),
	func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,
	func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,
	func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,
	func(): event_stream.send_to_track.emit("codingwithstrangers"),
	func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,
	func(): event_stream.leave_the_pit.emit("miniscruff"),
	func(): event_stream.send_to_track.emit("miniscruff"),
	func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,func(): pass,
	func(): event_stream.kick_user.emit("miniscruff"),
	func(): event_stream.leave_race_attempted.emit("codingwithstrangers"),
	
]

func _ready():
	timer.timeout.connect(_on_timer_tick)

func _on_timer_tick() -> void:
	if not self.enabled:
		return

	steps[index].call()
	index += 1
	if index >= steps.size():
		timer.stop()
		print("faker complete")
