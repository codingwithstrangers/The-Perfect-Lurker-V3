'''
1. track manager to pick a random track,[done]
2. things that need a track, should reference the track manager,[done]
3. track manager should be able to move users from the normal track, to the pit track,
4. signal event for user being pit lurker,
5. signal event for user joining back after being in the pits,
6. handle user go to the pits,
7. handle user going out the pits,
8. handle the "I am still here channel points",
9. handle "user chat" reset my idle timer'''
extends Node
class_name TrackManager
@onready var event_stream: EventStream = $'../event_stream'
@onready var lurker_gang: LurkerGang = $"../lurker_gang"
@export var select_track: Node2D
var track: Path2D
var pit: Path2D
#this will get the tracks from the list and handle the turning on and off of tracks 
@export var tracks: Array[Node2D]
#	 We want to make this function select the track and turn on all logic with it
func _ready() -> void:
	event_stream.send_to_pit.connect(self.sendtopit)
	if select_track == null:
		select_track = tracks.pick_random()
	track = select_track.find_child('track_path')
	pit = select_track.find_child('track_path_pit')
	#turn off other tracks and logic 
	#for this a loop is best 
	for t in tracks:
		t.visible = t == select_track
		#if t != select_track:
			#t.visible = false
			
func sendtopit(username: String) -> void:
	#We have the user name from the signal now we want to move it to the pit (wwe already know the location and lurker stats this is not handled here )
	#You know have a reference to the lurker gang now you can use the lurkers 
	var lurker = lurker_gang.lurkers[username]
	lurker.reparent(pit)
	
