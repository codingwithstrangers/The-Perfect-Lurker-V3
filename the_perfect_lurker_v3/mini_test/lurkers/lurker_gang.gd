extends Node
class_name LurkerGang

@export var lurker_prefab: PackedScene
@onready var event_stream: EventStream = $'../event_stream'
@onready var track_manager: TrackManager = $"../track_manager"


# string: Lurker
var lurkers = {}

func _ready():
	event_stream.join_race_attempted.connect(self._on_join_race_attempted)
	event_stream.leave_race_attempted.connect(self._on_leave_race_attempted)
	event_stream.lurker_chat.connect(self._on_lurker_chat)
	

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
	lurker.in_race = true
	lurker.name = username

	event_stream.joined_race.emit(lurker)

func _on_lurker_chat(username: String):
	if lurkers.has(username):
		lurkers[username].chat()

func _on_leave_race_attempted(username: String):
	if lurkers.has(username):
		lurkers[username].leave_race()
