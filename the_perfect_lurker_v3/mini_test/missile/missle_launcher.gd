extends Node
class_name MissleLauncher

@export var missle_prefab: PackedScene
@export var missle_textures: Array[Texture2D]

@onready var event_stream: EventStream = $'../event_stream'
@onready var lurker_gang: LurkerGang = $'../lurker_gang'
@onready var track_manager: TrackManager = $"../track_manager"

func _ready() -> void:
	event_stream.missle_launch_attempted.connect(self._on_missle_launch_attempted)
	
func _on_missle_launch_attempted(username: String):
	if not lurker_gang.lurkers.has(username):
		print("lurker is not in race: ", username)
		return
		
	var lurker = lurker_gang.lurkers[username] as Lurker
	if lurker.state != Lurker.RaceState.Racing:
		print("lurker is not in race: ", username)
		return
		
	print("missle is launching: ", username)
	
	# Check if launcher is in 1st place
	var is_first_place = false
	if lurker_gang.rankings.size() > 0 and lurker_gang.rankings[0] == username:
		is_first_place = true
		print(username, " is in 1st place - missile will boomerang!")
	
	var new_missle = missle_prefab.instantiate()
	track_manager.track.add_child(new_missle)
	lurker.idle_timer = 0
	var missle = new_missle.get_node(".") as Missle
	
	missle.name = username + "_missle"
	missle.sprite.texture = self.missle_textures[randi_range(0, self.missle_textures.size()-1)]
	missle.progress = lurker.progress
	missle.initial_progress = lurker.progress
	missle.is_boomerang = is_first_place
	missle.trap.dropped_by = username
	missle.trap.dropped_on_lap = lurker.lap_count  # Store launcher's lap for consistency
	missle.trap.trap_type = "red_shell"
	missle.trap.allow_self_damage = is_first_place  # Only boomerangs can hit their launcher
#
#func _on_missle_launch_attempted(username: String):
	#if not lurker_gang.lurkers.has(username):
		#print("lurker is not in race: ", username)
		#return
#
	#print("missle is launching: ", username)
#
	#var new_missle = missle_prefab.instantiate()
	#track_manager.track.add_child(new_missle)
	#var lurker = lurker_gang.lurkers[username] as Lurker
	#var missle = new_missle.get_node(".") as Missle # Assuming the root of missle_prefab is the Missle script
	#var animated_sprite = new_missle.get_node("AnimatedSprite") as AnimatedSprite2D # Get the AnimatedSprite node
#
	#missle.name = username + "_missle"
	## Instead of setting a single texture, we'll configure the animation frames
#
	#var frames = SpriteFrames.new()
	#var animation_name = "fly"
	#frames.add_animation(animation_name)
	#for texture in self.missle_textures:
		#frames.add_frame(animation_name, texture)
#
	#animated_sprite.sprite_frames = frames
	#animated_sprite.play(animation_name) # Start playing the animation
#
	#missle.progress = lurker.progress
	#missle.trap.dropped_by = username
