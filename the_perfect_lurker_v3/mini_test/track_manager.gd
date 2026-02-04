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
signal track_selected(track_node: Node2D)

@onready var event_stream: EventStream = $'../event_stream'
@onready var lurker_gang: LurkerGang = $"../lurker_gang"
@export var select_track: Node2D
var track: Path2D
var pit: Path2D
#this will get the tracks from the list and handle the turning on and off of tracks 
@export var tracks: Array[Node2D]
var track_selection_ui: Control
var is_track_selected: bool = false

#	 We want to make this function select the track and turn on all logic with it
func _ready() -> void:
	event_stream.send_to_pit.connect(self.send_to_pit)
	event_stream.send_to_track.connect(self.send_to_track)
	#event_stream.leave_the_pit.connect(self.send_to_track)
	
	# If a track is already exported, use it. Otherwise wait for selection via UI
	if select_track != null:
		_initialize_track(select_track)
	else:
		# Show track selection UI
		_show_track_selection_ui()

func _show_track_selection_ui() -> void:
	# Get or create the track selection UI
	track_selection_ui = get_tree().root.get_node_or_null("root/track_selection_ui")
	if track_selection_ui == null:
		track_selection_ui = _create_track_selection_ui()
		get_tree().root.get_node("root").add_child(track_selection_ui)
	
	track_selection_ui.visible = true
	#track_selected.connect(_on_track_selected)

func _create_track_selection_ui() -> Control:
	var ui = Control.new()
	ui.name = "track_selection_ui"
	ui.anchors_preset = Control.PRESET_CENTER
	ui.custom_minimum_size = Vector2(400, 300)
	
	# Background panel
	var panel = PanelContainer.new()
	panel.anchors_preset = Control.PRESET_CENTER
	panel.custom_minimum_size = Vector2(400, 300)
	ui.add_child(panel)
	
	# Container for title and buttons
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "Select a Track"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	
	# Button container
	var button_container = VBoxContainer.new()
	button_container.add_theme_constant_override("separation", 5)
	vbox.add_child(button_container)
	
	# Create buttons for each track
	for i in range(tracks.size()):
		var track_node = tracks[i]
		var button = Button.new()
		button.text = "Track %d" % (i + 1)
		button.custom_minimum_size = Vector2(380, 40)
		button.pressed.connect(_on_track_button_pressed.bind(track_node))
		button_container.add_child(button)
	
	return ui

func _on_track_button_pressed(track_node: Node2D) -> void:
	select_track = track_node
	_initialize_track(track_node)
	if track_selection_ui:
		track_selection_ui.visible = false
	track_selected.emit(track_node)

func _initialize_track(track_node: Node2D) -> void:
	if is_track_selected:
		return
	is_track_selected = true
	
	track = track_node.find_child('track_path')
	pit = track_node.find_child('track_path_pit')
	#turn off other tracks and logic 
	#for this a loop is best 
	for t in tracks:
		t.visible = t == track_node
		if t != track_node:
			t.visible = false
			
func send_to_pit(username: String) -> void:
	# Send lurker to pit_lane area instead of pit track
	var lurker = lurker_gang.lurkers[username]
	var pit_lane = select_track.find_child('pit_lane')
	if pit_lane:
		# Position lurker at pit_lane location with random offset to avoid overlapping
		var random_offset = Vector2(randf_range(-50, 50), randf_range(-50, 50))
		lurker.global_position = pit_lane.global_position + random_offset
		lurker.enter_pit()

func send_to_track(username: String) -> void:
	# Return lurker to track from pit_lane
	var lurker = lurker_gang.lurkers[username]
	# Reparent to track if needed (in case they were elsewhere)
	if lurker.get_parent() != track:
		lurker.call_deferred("reparent", track)
	lurker.leave_pit()
