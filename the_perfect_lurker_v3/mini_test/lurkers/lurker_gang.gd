extends Node
class_name LurkerGang

@export var lurker_prefab: PackedScene
@onready var event_stream: EventStream = $'../event_stream'
@onready var track_manager: TrackManager = $"../track_manager"

var lurkers: Dictionary[String, Lurker] = {}
var crown_textures: Dictionary[int, Texture2D] = {}
var rankings: Array[String] = []

func _ready():
	event_stream.join_race_attempted.connect(self._on_join_race_attempted)
	event_stream.leave_race_attempted.connect(self._on_leave_race_attempted)
	event_stream.lurker_chat.connect(self._on_lurker_chat)
	event_stream.send_to_pit.connect(self._on_lurker_send_to_pit)
	event_stream.leave_the_pit.connect(self._on_lurker_leave_the_pit)
	event_stream.kick_user.connect(self._on_kick_user)

	_load_crown_textures()
func _on_join_race_attempted(username: String, profile_url: String):
	print(username, " is joining the race")
	if lurkers.has(username):
		lurkers[username].join_race()
		return

	self.load_profile_image(username, profile_url)

func image_type(url: String) -> String:
	var split = url.split('.')
	if split.size() <= 0:
		return ""

	var file_extentsion = split[split.size() - 1]
	return file_extentsion.to_lower()

func load_profile_image(username: String, url: String):
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(self._on_image_downloaded.bind(http_request, url, username))
	print("requesting profile image  ", username)
	var error = http_request.request(url)
	if error != OK:
		push_error("An error occurred in the HTTP request.")

func _on_image_downloaded(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http_request: HTTPRequest,
	url: String,
	username: String,
):
	print("handling profile image response")

	http_request.queue_free()
	if response_code != 200:
		push_error("invalid response code: ", response_code)
		return

	var image = Image.new()
	var err: Error

	var url_ext = image_type(url)
	match url_ext:
		'jpg', 'jpeg':
			err = image.load_jpg_from_buffer(body)
		'png':
			err = image.load_png_from_buffer(body)
		_:
			push_error("invalid image extension:", url_ext)
			return
		
	if err != OK:
		push_error("failed to load image: ", err)
		return

	self.spawn_lurker(username, url, image)

func spawn_lurker(username: String, url: String, image: Image):
	print("spawning lurker: ", username)
	
	var new_lurker = lurker_prefab.instantiate()
	track_manager.track.add_child(new_lurker)
	
	var lurker = new_lurker.get_node(".") as Lurker
	lurkers[username] = lurker
	
	var downloaded_image = ImageTexture.create_from_image(image)
	lurker.username = username
	lurker.profile_url = url
	lurker.profile_image = downloaded_image
	lurker.car_sprite.texture = downloaded_image
	lurker.name = username
	event_stream.joined_race.emit(lurker)

	lurker.lap_completed.connect(self._on_lurker_lap_completed)
	lurker.distance_updated.connect(self._on_lurker_distance_updated)
func _on_lurker_chat(username: String):
	if lurkers.has(username):
		lurkers[username].chat()

func _on_kick_user(username: String):
	if lurkers.has(username):
		lurkers[username]._kick(username)
		lurkers[username].queue_free()
		lurkers.erase(username)

func _on_leave_race_attempted(username: String):
	if lurkers.has(username):
		lurkers[username].leave_race()

func _on_lurker_send_to_pit(username: String):
	if lurkers.has(username):
		lurkers[username].enter_pit()

func _on_lurker_leave_the_pit(username: String):
	if lurkers.has(username):
		lurkers[username].leave_pit()

func _load_crown_textures() -> void:
	crown_textures[0] = load("res://crowns/gold.png")
	crown_textures[1] = load("res://crowns/silver.png")
	crown_textures[2] = load("res://crowns/bronze.png")

func _on_lurker_lap_completed(username: String, lap_count: int) -> void:
	print(username, " completed lap ", lap_count + 1)
	_update_rankings()
	_update_crowns()

func _on_lurker_distance_updated(_username: String, _total_distance: float) -> void:
	# distance updates are frequent; update rankings and crowns in response
	_update_rankings()
	_update_crowns()

func _update_rankings() -> void:
	rankings.clear()
	var racing_lurkers: Array[String] = []
	for username in lurkers.keys():
		var lurker = lurkers[username]
		if lurker.state != Lurker.RaceState.Out:
			racing_lurkers.append(username)

	# sort descending by total_distance using a simple stable selection sort
	var sorted_lurkers: Array[String] = []
	for uname in racing_lurkers:
		sorted_lurkers.append(uname)

	var n = sorted_lurkers.size()
	for i in range(n):
		var best = i
		for j in range(i + 1, n):
			if lurkers[sorted_lurkers[j]].total_distance > lurkers[sorted_lurkers[best]].total_distance:
				best = j
		if best != i:
			var tmp = sorted_lurkers[i]
			sorted_lurkers[i] = sorted_lurkers[best]
			sorted_lurkers[best] = tmp

	rankings = sorted_lurkers

func _compare_by_distance(a: String, b: String) -> int:
	var da = 0.0
	var db = 0.0
	if lurkers.has(a):
		da = lurkers[a].total_distance
	if lurkers.has(b):
		db = lurkers[b].total_distance
	if da > db:
		return -1
	elif da < db:
		return 1
	return 0

func _update_crowns() -> void:
	# Remove crowns from everyone first to avoid stale crowns
	for uname in lurkers.keys():
		lurkers[uname].remove_crown()

	var crown_order = [0, 1, 2]
	for i in range(min(3, rankings.size())):
		var username = rankings[i]
		if lurkers.has(username):
			var lurker = lurkers[username]
			lurker.set_crown(crown_textures[crown_order[i]])
