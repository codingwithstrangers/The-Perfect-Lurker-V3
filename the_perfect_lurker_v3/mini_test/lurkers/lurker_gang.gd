extends Node
class_name LurkerGang

const BROADCASTER_USERNAME = "codingwithstrangers"

@export var lurker_prefab: PackedScene
@export var broadcaster_icon_path: String = "res://icons/png gokart.png"
@export var broadcaster_icon_size: Vector2 = Vector2(400, 400)
@onready var event_stream: EventStream = $'../event_stream'
@onready var track_manager: TrackManager = $"../track_manager"
@onready var twitch_events: TwitchEvents = $'../twitch_events'

var lurkers: Dictionary[String, Lurker] = {}
var broadcaster_icon: Texture2D = null
var crown_textures: Dictionary[int, Texture2D] = {}
var rankings: Array[String] = []
var kicked_users: Dictionary = {}  # Dictionary used as a set (keys are usernames, values are true)
# Runtime output files for race telemetry/results.
# These use user:// so exported builds can always write data.
var kicked_users_csv_path: String = "user://results/kicked_users.csv"
var traps_csv_path: String = "user://results/traps_log.csv"
var race_events_csv_path: String = "user://results/race_events.csv"
var results_csv_path: String = "user://results/results.csv"
var live_results_csv_path: String = "user://results/live.csv"
var movement_log_csv_path: String = "user://results/movement_log.csv"
var last_result_timestamp: int = 0  # Track when !result was last run
var movement_timer: Timer
var current_run_id: String = ""

# Stats tracking dictionaries
var trap_hits_on_user: Dictionary = {}  # {username: {trap_type: count}}
var trap_throws_by_user: Dictionary = {}  # {username: {trap_type: count}}
var user_stats: Dictionary = {}  # {username: {races_joined, rejoin_count, leave_count, ban_count, miles, lap_count}}
var victim_details: Dictionary = {}  # {username: {"yellow_attack": {victim: count}, "red_shell": {victim: count}}}
var attacker_details: Dictionary = {}  # {username: {"yellow_attack": {attacker: count}, "red_shell": {attacker: count}}}
var placement_counts: Dictionary = {}  # {username: {1st: count, 2nd: count, 3rd: count}}
var shield_breaker_details: Dictionary = {}  # {username: {victim: count}} - tracks who broke final shield on whom
var shield_hit_details: Dictionary = {}  # {username: {trap_type: {victim: count}}} - all shield hits by user
var shield_hits_on_user: Dictionary = {}  # {username: {attacker: count}} - all shield hits received by user

func _ready():
	event_stream.join_race_attempted.connect(self._on_join_race_attempted)
	event_stream.leave_race_attempted.connect(self._on_leave_race_attempted)
	event_stream.lurker_chat.connect(self._on_lurker_chat)
	event_stream.send_to_pit.connect(self._on_lurker_send_to_pit)
	event_stream.leave_the_pit.connect(self._on_lurker_leave_the_pit)
	event_stream.kick_user.connect(self._on_kick_user)
	event_stream.unban_user.connect(self._on_unban_user)
	event_stream.trap_hit.connect(self._on_trap_hit)
	event_stream.trap_shield_hit.connect(self._on_trap_shield_hit)
	event_stream.grant_shield.connect(self._on_grant_shield)

	_load_crown_textures()
	_load_broadcaster_icon()
	_load_kicked_users()
	_load_placement_counts()
	_initialize_traps_csv()
	_initialize_race_events_csv()
	_initialize_movement_log_csv()
	current_run_id = str(int(Time.get_unix_time_from_system()))
	# Print resolved output locations once on startup for troubleshooting.
	_print_output_paths()
	_write_live_results_csv()

	movement_timer = Timer.new()
	movement_timer.one_shot = false
	movement_timer.wait_time = 5.0
	# Every tick writes live standings + movement history snapshots.
	movement_timer.timeout.connect(_on_movement_timer_timeout)
	add_child(movement_timer)
	movement_timer.start()
	
	# Monitor app close
	tree_exiting.connect(_on_tree_exiting)

func _on_join_race_attempted(user_name: String, profile_url: String):
	print(user_name, " is joining the race")
	if kicked_users.has(user_name):
		var message = "[BANNED] " + user_name + ": You have been kicked. Apologize with a gifted sub and maybe I will let you rejoin."
		print(message)
		event_stream.system_message.emit(message)
		return
	if lurkers.has(user_name):
		var lurker = lurkers[user_name]
		# Prevent rejoining via !join if already in race or in pit
		if lurker.state == Lurker.RaceState.InThePit or lurker.state == Lurker.RaceState.Pitting:
			var pit_message = user_name + " is already in the pit. Use the pit token to return to the track."
			print(pit_message)
			event_stream.system_message.emit(pit_message)
			return
		var message = user_name + " is already in the race."
		print(message)
		event_stream.system_message.emit(message)
		return

	# New user joining
	_init_user_stats(user_name)
	_log_race_event("join", user_name)
	self.load_profile_image(user_name, profile_url)

func image_type(url: String) -> String:
	var split = url.split('.')
	if split.size() <= 0:
		return ""

	var file_extentsion = split[split.size() - 1]
	return file_extentsion.to_lower()

func load_profile_image(user_name: String, url: String):
	if url.strip_edges() == "":
		var fallback_image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		fallback_image.fill(Color(1, 1, 1, 1))
		self.spawn_lurker(user_name, "", fallback_image)
		return

	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(self._on_image_downloaded.bind(http_request, url, user_name))
	print("requesting profile image  ", user_name)
	var error = http_request.request(url)
	if error != OK:
		push_error("An error occurred in the HTTP request.")
		var fallback_image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		fallback_image.fill(Color(1, 1, 1, 1))
		self.spawn_lurker(user_name, "", fallback_image)

func _on_image_downloaded(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http_request: HTTPRequest,
	url: String,
	user_name: String,
):
	print("handling profile image response")

	http_request.queue_free()
	if response_code != 200:
		push_error("invalid response code: ", response_code)
		var fallback_image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		fallback_image.fill(Color(1, 1, 1, 1))
		self.spawn_lurker(user_name, "", fallback_image)
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
		var fallback_image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		fallback_image.fill(Color(1, 1, 1, 1))
		self.spawn_lurker(user_name, "", fallback_image)
		return

	self.spawn_lurker(user_name, url, image)

func spawn_lurker(user_name: String, url: String, image: Image):
	print("spawning lurker: ", user_name)
	
	var new_lurker = lurker_prefab.instantiate()
	track_manager.track.add_child(new_lurker)
	
	var lurker = new_lurker.get_node(".") as Lurker
	lurkers[user_name] = lurker
	
	# Use broadcaster icon if username matches, otherwise use profile image
	var final_texture: Texture2D
	if user_name.to_lower() == _get_broadcaster_login() and broadcaster_icon != null:
		final_texture = broadcaster_icon
	else:
		final_texture = ImageTexture.create_from_image(image)
	
	lurker.username = user_name
	lurker.profile_url = url
	lurker.profile_image = final_texture
	lurker.car_sprite.texture = final_texture
	lurker.name = user_name
	event_stream.joined_race.emit(lurker)

	lurker.lap_completed.connect(self._on_lurker_lap_completed)
	lurker.distance_updated.connect(self._on_lurker_distance_updated)
	_log_movement_snapshot("join", user_name)
	_write_live_results_csv()

func _get_broadcaster_login() -> String:
	if twitch_events != null and twitch_events.login_channel != "":
		return twitch_events.login_channel.to_lower()
	return BROADCASTER_USERNAME.to_lower()

func _on_lurker_chat(user_name: String):
	if lurkers.has(user_name):
		lurkers[user_name].chat()

func _on_kick_user(user_name: String):
	kicked_users[user_name] = true
	_save_kicked_users()
	_log_race_event("ban", user_name)
	if lurkers.has(user_name):
		lurkers[user_name]._kick(user_name)
		lurkers[user_name].queue_free()
		lurkers.erase(user_name)
		_log_movement_snapshot("ban", user_name)
		_write_live_results_csv()
		var message = user_name + " was kicked from the race."
		print(message)
		event_stream.system_message.emit(message)

func _on_unban_user(user_name: String):
	if kicked_users.has(user_name):
		kicked_users.erase(user_name)
		_save_kicked_users()
		var message = user_name + " has been unbanned and can rejoin!"
		print(message)

func _on_grant_shield(user_name: String) -> void:
	if lurkers.has(user_name):
		lurkers[user_name].set_shield(3)
		var msg = user_name + " granted shield (3)"
		print(msg)
		event_stream.system_message.emit(msg)
	else:
		var msg = user_name + " is not in the race."
		print(msg)
		event_stream.system_message.emit(msg)

func _on_leave_race_attempted(user_name: String):
	if lurkers.has(user_name):
		lurkers[user_name].queue_free()
		lurkers.erase(user_name)
		_log_race_event("leave", user_name)
		_log_movement_snapshot("leave", user_name)
		_write_live_results_csv()
		var message = user_name + " left the race."
		print(message)
		event_stream.system_message.emit(message)

func _on_lurker_send_to_pit(user_name: String):
	if lurkers.has(user_name):
		lurkers[user_name].enter_pit()
		_log_movement_snapshot("pit", user_name)

func _on_lurker_leave_the_pit(user_name: String):
	if lurkers.has(user_name):
		lurkers[user_name].leave_pit()
		_log_movement_snapshot("leave_pit", user_name)

func _load_crown_textures() -> void:
	crown_textures[0] = load("res://crowns/gold.png")
	crown_textures[1] = load("res://crowns/silver.png")
	crown_textures[2] = load("res://crowns/bronze.png")

func _load_broadcaster_icon() -> void:
	var source_texture = load(broadcaster_icon_path) as Texture2D
	if source_texture == null:
		push_error("Broadcaster icon not found or failed to import: " + broadcaster_icon_path)
		return

	var image = source_texture.get_image()
	if image == null:
		push_error("Failed to read broadcaster icon image data: " + broadcaster_icon_path)
		return

	# Resize to broadcaster_icon_size
	image.resize(int(broadcaster_icon_size.x), int(broadcaster_icon_size.y))
	broadcaster_icon = ImageTexture.create_from_image(image)
	print("Loaded broadcaster icon: ", broadcaster_icon_path)

func _on_lurker_lap_completed(user_name: String, lap_count: int) -> void:
	print(user_name, " completed lap ", lap_count + 1)
	_update_rankings()
	_update_crowns()
	_log_movement_snapshot("lap", user_name)
	_write_live_results_csv()

func _on_lurker_distance_updated(_username: String, _total_distance: float) -> void:
	# distance updates are frequent; update rankings and crowns in response
	_update_rankings()
	_update_crowns()

func _update_rankings() -> void:
	rankings.clear()
	var racing_lurkers: Array[String] = []
	for user_name in lurkers.keys():
		var lurker = lurkers[user_name]
		# Exclude broadcaster from rankings
		if lurker.state != Lurker.RaceState.Out and user_name.to_lower() != _get_broadcaster_login():
			racing_lurkers.append(user_name)

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
		var user_name = rankings[i]
		if lurkers.has(user_name):
			var lurker = lurkers[user_name]
			lurker.set_crown(crown_textures[crown_order[i]])

func _load_kicked_users() -> void:
	var read_path = _resolve_existing_results_file_path(kicked_users_csv_path)
	var file = FileAccess.open(read_path, FileAccess.READ)
	if file == null:
		return
	
	var line = file.get_line()
	while line != "":
		if line != "username":
			kicked_users[line.strip_edges()] = true
		line = file.get_line()

func _save_kicked_users() -> void:
	var file = FileAccess.open(kicked_users_csv_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open kicked_users.csv for writing")
		return
	
	file.store_line("username")
	for user_name in kicked_users.keys():
		file.store_line(user_name)

func _load_placement_counts() -> void:
	var read_path = _resolve_existing_results_file_path(results_csv_path)
	var file = FileAccess.open(read_path, FileAccess.READ)
	if file == null:
		return
	
	# Skip header
	var _header = file.get_line()
	var line = file.get_line()
	
	while line != "":
		var parts = line.split(",")
		if parts.size() >= 3:
			var user_name = parts[1]
			var place = int(parts[2])
			
			if not placement_counts.has(user_name):
				placement_counts[user_name] = {"1st": 0, "2nd": 0, "3rd": 0}
			
			# Count finishes
			if place == 1:
				placement_counts[user_name]["1st"] += 1
			elif place == 2:
				placement_counts[user_name]["2nd"] += 1
			elif place == 3:
				placement_counts[user_name]["3rd"] += 1
		
		line = file.get_line()

func _initialize_traps_csv() -> void:
	var file = FileAccess.open(traps_csv_path, FileAccess.READ)
	if file == null:
		# File doesn't exist, create it with header
		file = FileAccess.open(traps_csv_path, FileAccess.WRITE)
		if file == null:
			push_error("Failed to create traps_log.csv")
			return
		file.store_line("timestamp,trap_type,hit_by,dropped_by,shield_hit,shield_breaker")

func _log_trap_hit(trap_type: String, hit_by: String, dropped_by: String) -> void:
	var file = FileAccess.open(traps_csv_path, FileAccess.READ_WRITE)
	if file == null:
		push_error("Failed to open traps_log.csv for appending")
		return
	
	# Seek to end of file
	file.seek_end()
	
	var timestamp = Time.get_ticks_msec()
	var line = str(timestamp) + "," + trap_type + "," + hit_by + "," + dropped_by + ",0,0"
	file.store_line(line)

func _log_shield_hit(trap_type: String, dropped_by: String, hit_by: String, shield_level_before: int) -> void:
	var file = FileAccess.open(traps_csv_path, FileAccess.READ_WRITE)
	if file == null:
		push_error("Failed to open traps_log.csv for appending")
		return
	
	# Seek to end of file
	file.seek_end()
	
	var timestamp = Time.get_ticks_msec()
	var shield_breaker = 1 if shield_level_before == 1 else 0
	var line = str(timestamp) + "," + trap_type + "," + hit_by + "," + dropped_by + ",1," + str(shield_breaker)
	file.store_line(line)

func _on_trap_hit(trap_type: String, hit_by: String, dropped_by: String) -> void:
	print("Trap hit - Type: ", trap_type, " Hit by: ", hit_by, " Dropped by: ", dropped_by)
	_log_trap_hit(trap_type, hit_by, dropped_by)
	
	# Track trap hits on user
	if not trap_hits_on_user.has(hit_by):
		trap_hits_on_user[hit_by] = {}
	if not trap_hits_on_user[hit_by].has(trap_type):
		trap_hits_on_user[hit_by][trap_type] = 0
	trap_hits_on_user[hit_by][trap_type] += 1
	
	# Track trap throws by user
	if not trap_throws_by_user.has(dropped_by):
		trap_throws_by_user[dropped_by] = {}
	if not trap_throws_by_user[dropped_by].has(trap_type):
		trap_throws_by_user[dropped_by][trap_type] = 0
	trap_throws_by_user[dropped_by][trap_type] += 1
	
	# Track WHO hit WHO with WHAT trap type
	if not attacker_details.has(hit_by):
		attacker_details[hit_by] = {}
	if not attacker_details[hit_by].has(trap_type):
		attacker_details[hit_by][trap_type] = {}
	if not attacker_details[hit_by][trap_type].has(dropped_by):
		attacker_details[hit_by][trap_type][dropped_by] = 0
	attacker_details[hit_by][trap_type][dropped_by] += 1
	
	# Track WHO threw WHAT trap type at WHO
	if not victim_details.has(dropped_by):
		victim_details[dropped_by] = {}
	if not victim_details[dropped_by].has(trap_type):
		victim_details[dropped_by][trap_type] = {}
	if not victim_details[dropped_by][trap_type].has(hit_by):
		victim_details[dropped_by][trap_type][hit_by] = 0
	victim_details[dropped_by][trap_type][hit_by] += 1

func _on_trap_shield_hit(trap_type: String, dropped_by: String, hit_by: String, shield_level_before: int, shield_level_after: int) -> void:
	print("Shield hit - Type: ", trap_type, " Hit by: ", hit_by, " Dropped by: ", dropped_by, " Before: ", shield_level_before, " After: ", shield_level_after)
	_log_shield_hit(trap_type, dropped_by, hit_by, shield_level_before)
	
	# Track shield breaker (if this was the last shield hit - level 1 before)
	if shield_level_before == 1:
		if not shield_breaker_details.has(dropped_by):
			shield_breaker_details[dropped_by] = {}
		if not shield_breaker_details[dropped_by].has(hit_by):
			shield_breaker_details[dropped_by][hit_by] = 0
		shield_breaker_details[dropped_by][hit_by] += 1
	
	# Track all shield hits by attacker (WHO threw at WHO)
	if not shield_hit_details.has(dropped_by):
		shield_hit_details[dropped_by] = {}
	if not shield_hit_details[dropped_by].has(trap_type):
		shield_hit_details[dropped_by][trap_type] = {}
	if not shield_hit_details[dropped_by][trap_type].has(hit_by):
		shield_hit_details[dropped_by][trap_type][hit_by] = 0
	shield_hit_details[dropped_by][trap_type][hit_by] += 1
	
	# Track all shield hits on user (WHO was hit)
	if not shield_hits_on_user.has(hit_by):
		shield_hits_on_user[hit_by] = {}
	if not shield_hits_on_user[hit_by].has(dropped_by):
		shield_hits_on_user[hit_by][dropped_by] = 0
	shield_hits_on_user[hit_by][dropped_by] += 1

func _initialize_race_events_csv() -> void:
	var file = FileAccess.open(race_events_csv_path, FileAccess.READ)
	if file == null:
		# File doesn't exist, create it with header
		file = FileAccess.open(race_events_csv_path, FileAccess.WRITE)
		if file == null:
			push_error("Failed to create race_events.csv")
			return
		file.store_line("timestamp,event_type,username")

func _initialize_movement_log_csv() -> void:
	if not DirAccess.dir_exists_absolute(movement_log_csv_path.get_base_dir()):
		DirAccess.make_dir_recursive_absolute(movement_log_csv_path.get_base_dir())

	var file = FileAccess.open(movement_log_csv_path, FileAccess.READ)
	if file == null and movement_log_csv_path.begins_with("res://"):
		var fallback_path = "user://results/" + movement_log_csv_path.get_file()
		if not DirAccess.dir_exists_absolute("user://results"):
			DirAccess.make_dir_recursive_absolute("user://results")
		var fallback_read = FileAccess.open(fallback_path, FileAccess.READ)
		if fallback_read != null:
			movement_log_csv_path = fallback_path
			file = fallback_read
			print("[CSV] movement_log fallback path in use: ", movement_log_csv_path)

	if file == null:
		file = FileAccess.open(movement_log_csv_path, FileAccess.WRITE)
		if file == null and movement_log_csv_path.begins_with("res://"):
			var fallback_path = "user://results/" + movement_log_csv_path.get_file()
			if not DirAccess.dir_exists_absolute("user://results"):
				DirAccess.make_dir_recursive_absolute("user://results")
			file = FileAccess.open(fallback_path, FileAccess.WRITE)
			if file != null:
				movement_log_csv_path = fallback_path
				print("[CSV] movement_log fallback path in use: ", movement_log_csv_path)
		if file == null:
			push_error("Failed to create movement_log.csv")
			return
		file.store_line("run_id,datetime,timestamp,event_type,username,place,miles,laps,state")

func _state_to_text(lurker: Lurker) -> String:
	match lurker.state:
		Lurker.RaceState.Racing:
			return "racing"
		Lurker.RaceState.LeavingThePit:
			return "leaving_pit"
		Lurker.RaceState.Pitting:
			return "pitting"
		Lurker.RaceState.InThePit:
			return "in_pit"
		Lurker.RaceState.Stunned:
			return "stunned"
		_:
			return "out"

func _log_movement_snapshot(event_type: String, user_name: String = "") -> void:
	var file = FileAccess.open(movement_log_csv_path, FileAccess.READ_WRITE)
	if file == null and movement_log_csv_path.begins_with("res://"):
		var fallback_path = "user://results/" + movement_log_csv_path.get_file()
		if not DirAccess.dir_exists_absolute("user://results"):
			DirAccess.make_dir_recursive_absolute("user://results")
		file = FileAccess.open(fallback_path, FileAccess.READ_WRITE)
		if file != null:
			movement_log_csv_path = fallback_path
			print("[CSV] movement_log fallback path in use: ", movement_log_csv_path)

	if file == null:
		push_error("Failed to open movement_log.csv")
		return
	file.seek_end()
	var timestamp = Time.get_ticks_msec()
	var dt = Time.get_datetime_string_from_system()
	if user_name != "":
		if lurkers.has(user_name):
			var snapshot = _get_lurker_snapshot(user_name)
			var state = _state_to_text(lurkers[user_name])
			file.store_line(current_run_id + "," + dt + "," + str(timestamp) + "," + event_type + "," + user_name + "," + str(snapshot["place"]) + "," + snapshot["miles"] + "," + str(snapshot["laps"]) + "," + state)
		else:
			file.store_line(current_run_id + "," + dt + "," + str(timestamp) + "," + event_type + "," + user_name + ",999,0.00,0,out")
		return

	for uname in rankings:
		if not lurkers.has(uname):
			continue
		var tick_snapshot = _get_lurker_snapshot(uname)
		var tick_state = _state_to_text(lurkers[uname])
		file.store_line(current_run_id + "," + dt + "," + str(timestamp) + "," + event_type + "," + uname + "," + str(tick_snapshot["place"]) + "," + tick_snapshot["miles"] + "," + str(tick_snapshot["laps"]) + "," + tick_state)

func _write_live_results_csv() -> void:
	if not DirAccess.dir_exists_absolute(live_results_csv_path.get_base_dir()):
		DirAccess.make_dir_recursive_absolute(live_results_csv_path.get_base_dir())

	var file = FileAccess.open(live_results_csv_path, FileAccess.WRITE)
	if file == null and live_results_csv_path.begins_with("res://"):
		var fallback_path = "user://results/" + live_results_csv_path.get_file()
		if not DirAccess.dir_exists_absolute("user://results"):
			DirAccess.make_dir_recursive_absolute("user://results")
		file = FileAccess.open(fallback_path, FileAccess.WRITE)
		if file != null:
			live_results_csv_path = fallback_path
			print("[CSV] live.csv fallback path in use: ", live_results_csv_path)

	if file == null:
		push_error("Failed to write live.csv at path: " + live_results_csv_path)
		return
	file.store_line("run_id,datetime,timestamp,username,place,miles,laps,state")
	var timestamp = Time.get_ticks_msec()
	var dt = Time.get_datetime_string_from_system()
	for uname in rankings:
		if not lurkers.has(uname):
			continue
		var snapshot = _get_lurker_snapshot(uname)
		var state = _state_to_text(lurkers[uname])
		file.store_line(current_run_id + "," + dt + "," + str(timestamp) + "," + uname + "," + str(snapshot["place"]) + "," + snapshot["miles"] + "," + str(snapshot["laps"]) + "," + state)

func _on_movement_timer_timeout() -> void:
	_update_rankings()
	_update_crowns()
	_log_movement_snapshot("tick")
	_write_live_results_csv()

func _print_output_paths() -> void:
	var results_dir = results_csv_path.get_base_dir()
	print("[CSV] results dir: ", results_dir, " -> ", ProjectSettings.globalize_path(results_dir))
	print("[CSV] movement log: ", movement_log_csv_path, " -> ", ProjectSettings.globalize_path(movement_log_csv_path))
	print("[CSV] live csv: ", live_results_csv_path, " -> ", ProjectSettings.globalize_path(live_results_csv_path))

func _log_race_event(event_type: String, user_name: String) -> void:
	var file = FileAccess.open(race_events_csv_path, FileAccess.READ_WRITE)
	if file == null:
		push_error("Failed to open race_events.csv")
		return
	
	file.seek_end()
	var timestamp = Time.get_ticks_msec()
	var line = str(timestamp) + "," + event_type + "," + user_name
	file.store_line(line)

func _init_user_stats(user_name: String) -> void:
	if not user_stats.has(user_name):
		user_stats[user_name] = {
			"races_joined": 1,
			"rejoin_count": 0,
			"leave_count": 0,
			"ban_count": 0
		}
	else:
		user_stats[user_name]["races_joined"] += 1
	
	if not trap_hits_on_user.has(user_name):
		trap_hits_on_user[user_name] = {}
	if not trap_throws_by_user.has(user_name):
		trap_throws_by_user[user_name] = {}
	if not victim_details.has(user_name):
		victim_details[user_name] = {}
	if not attacker_details.has(user_name):
		attacker_details[user_name] = {}

func _get_lurker_snapshot(user_name: String) -> Dictionary:
	var lurker = lurkers.get(user_name)
	var stats = user_stats.get(user_name, {})
	var distance = lurker.total_distance if lurker else 0.0
	var miles = distance / 1000.0
	var lap_count = lurker.lap_count if lurker else 0
	
	# Find current place based on rankings
	var place = rankings.find(user_name) + 1 if rankings.has(user_name) else 999
	
	return {
		"username": user_name,
		"place": place,
		"miles": String.num(miles, 2),
		"laps": lap_count,
		"races_joined": stats.get("races_joined", 0),
		"rejoin_count": stats.get("rejoin_count", 0),
		"leave_count": stats.get("leave_count", 0),
		"ban_count": stats.get("ban_count", 0),
		"yellow_hits": trap_hits_on_user.get(user_name, {}).get("yellow_attack", 0),
		"red_hits": trap_hits_on_user.get(user_name, {}).get("red_shell", 0),
		"yellow_throws": trap_throws_by_user.get(user_name, {}).get("yellow_attack", 0),
		"red_throws": trap_throws_by_user.get(user_name, {}).get("red_shell", 0),
	}

func get_top_3_lurkers() -> Array:
	var sorted_lurkers = rankings.duplicate()
	var top_3 = sorted_lurkers.slice(0, 3)
	return top_3

func create_snapshot() -> void:
	var top_3 = get_top_3_lurkers()
	var summary_parts = []
	var broadcaster_login = _get_broadcaster_login()
	var broadcaster_user_name = ""
	for racer_name in lurkers.keys():
		if racer_name.to_lower() == broadcaster_login:
			broadcaster_user_name = racer_name
			break
	
	for i in range(top_3.size()):
		var username = top_3[i]
		var snapshot = _get_lurker_snapshot(username)
		summary_parts.append("%d) %s L%d M%s" % [snapshot["place"], snapshot["username"], snapshot["laps"], snapshot["miles"]])
		var filename = "user://lurker_%d.txt" % (i + 1)
		
		var file = FileAccess.open(filename, FileAccess.WRITE)
		if file == null:
			push_error("Failed to create snapshot file: ", filename)
			continue
		
		file.store_line("=== LURKER %d SNAPSHOT ===" % (i + 1))
		file.store_line("Username: " + snapshot["username"])
		file.store_line("Place: %d" % snapshot["place"])
		file.store_line("Miles: " + snapshot["miles"])
		file.store_line("Laps: %d" % snapshot["laps"])
		file.store_line("Races Joined: %d" % snapshot["races_joined"])
		file.store_line("Rejoin Count: %d" % snapshot["rejoin_count"])
		file.store_line("Leave Count: %d" % snapshot["leave_count"])
		file.store_line("Ban Count: %d" % snapshot["ban_count"])
		file.store_line("Yellow Traps Hit: %d" % snapshot["yellow_hits"])
		file.store_line("Red Traps Hit: %d" % snapshot["red_hits"])
		file.store_line("Yellow Traps Thrown: %d" % snapshot["yellow_throws"])
		file.store_line("Red Traps Thrown: %d" % snapshot["red_throws"])

	# Host should be visible in snapshots, but never ranked/crowned as top-3.
	if broadcaster_user_name != "":
		var host_snapshot = _get_lurker_snapshot(broadcaster_user_name)
		summary_parts.append("Host %s L%d M%s" % [host_snapshot["username"], host_snapshot["laps"], host_snapshot["miles"]])
		var host_filename = "user://lurker_host.txt"
		var host_file = FileAccess.open(host_filename, FileAccess.WRITE)
		if host_file == null:
			push_error("Failed to create host snapshot file: ", host_filename)
		else:
			host_file.store_line("=== HOST SNAPSHOT ===")
			host_file.store_line("Username: " + host_snapshot["username"])
			host_file.store_line("Place: Excluded from ranking")
			host_file.store_line("Miles: " + host_snapshot["miles"])
			host_file.store_line("Laps: %d" % host_snapshot["laps"])
			host_file.store_line("Races Joined: %d" % host_snapshot["races_joined"])
			host_file.store_line("Rejoin Count: %d" % host_snapshot["rejoin_count"])
			host_file.store_line("Leave Count: %d" % host_snapshot["leave_count"])
			host_file.store_line("Ban Count: %d" % host_snapshot["ban_count"])
			host_file.store_line("Yellow Traps Hit: %d" % host_snapshot["yellow_hits"])
			host_file.store_line("Red Traps Hit: %d" % host_snapshot["red_hits"])
			host_file.store_line("Yellow Traps Thrown: %d" % host_snapshot["yellow_throws"])
			host_file.store_line("Red Traps Thrown: %d" % host_snapshot["red_throws"])
	
	var message = "Snapshot: no active racers."
	if summary_parts.size() > 0:
		message = "Snapshot | "
		for i in range(summary_parts.size()):
			if i > 0:
				message += " | "
			message += summary_parts[i]
	print(message)
	event_stream.system_message.emit(message)

func _build_ranked_list(data: Dictionary) -> String:
	# Sort by count descending, format as "name(count), name(count)..."
	var items = []
	for item_name in data.keys():
		items.append({"name": item_name, "count": data[item_name]})
	
	# Sort by count descending
	items.sort_custom(func(a, b): return a["count"] > b["count"])
	
	var result = ""
	
	for i in range(items.size()):
		var item_str = items[i]["name"] + "(" + str(items[i]["count"]) + ")"
		if i == 0:
			result = item_str
		else:
			result += ", " + item_str
	
	return result

func _parse_ranked_list(text: String) -> Dictionary:
	# Parse values like "playerA(2), playerB(1)" into {playerA:2, playerB:1}.
	var parsed: Dictionary = {}
	var src = text.strip_edges()
	if src == "":
		return parsed
	for part in src.split(","):
		var item = part.strip_edges()
		if item == "":
			continue
		var l = item.rfind("(")
		var r = item.rfind(")")
		if l == -1 or r == -1 or r <= l:
			continue
		var parsed_name = item.substr(0, l).strip_edges()
		var count_str = item.substr(l + 1, r - l - 1).strip_edges()
		var count = int(count_str)
		if parsed_name == "":
			continue
		if not parsed.has(parsed_name):
			parsed[parsed_name] = 0
		parsed[parsed_name] += count
	return parsed

func _now_day_hour_string() -> String:
	var d = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d" % [
		int(d.get("year", 0)),
		int(d.get("month", 0)),
		int(d.get("day", 0)),
		int(d.get("hour", 0)),
		int(d.get("minute", 0))
	]

func _resolve_writable_results_dir() -> String:
	# Prefer mini_test/results for exported MVP runs when possible.
	var candidates: Array[String] = []
	if OS.has_feature("editor"):
		candidates.append("res://results")
	else:
		var exe_dir = OS.get_executable_path().get_base_dir()
		candidates.append(exe_dir.path_join("../results").simplify_path())
		candidates.append(exe_dir.path_join("results").simplify_path())

	# Keep configured path + user fallback as final options.
	candidates.append(results_csv_path.get_base_dir())
	candidates.append("user://results")

	for candidate in candidates:
		if candidate == "":
			continue
		if not DirAccess.dir_exists_absolute(candidate):
			DirAccess.make_dir_recursive_absolute(candidate)
		var probe_path = candidate.path_join(".write_probe.tmp")
		var probe = FileAccess.open(probe_path, FileAccess.WRITE)
		if probe != null:
			probe.store_line("ok")
			probe = null
			DirAccess.remove_absolute(probe_path)
			return candidate

	return "user://results"

func _resolve_existing_results_file_path(primary_path: String) -> String:
	# Read priority: primary path -> user://results -> legacy res://results.
	if FileAccess.open(primary_path, FileAccess.READ) != null:
		return primary_path

	var filename = primary_path.get_file()
	var user_path = "user://results/" + filename
	if FileAccess.open(user_path, FileAccess.READ) != null:
		return user_path

	var legacy_res_path = "res://results/" + filename
	if FileAccess.open(legacy_res_path, FileAccess.READ) != null:
		return legacy_res_path

	return primary_path

func _resolve_results_csv_for_read() -> String:
	return _resolve_existing_results_file_path(results_csv_path)

func _load_historical_totals_from_results() -> Dictionary:
	# Aggregate all-time miles/laps from previously written results.csv.
	var totals: Dictionary = {}
	var read_path = _resolve_results_csv_for_read()
	var file = FileAccess.open(read_path, FileAccess.READ)
	if file == null:
		return totals

	# Skip header
	if not file.eof_reached():
		file.get_line()

	while not file.eof_reached():
		var line = file.get_line()
		if line.strip_edges() == "":
			continue
		var parts = line.split(",")
		if parts.size() < 5:
			continue

		var user_name = parts[1]
		var miles = float(parts[3])
		var laps = int(parts[4])

		if not totals.has(user_name):
			totals[user_name] = {"miles": 0.0, "laps": 0}
		totals[user_name]["miles"] += miles
		totals[user_name]["laps"] += laps

	return totals

func _write_result_view_file(file: FileAccess, snapshot: Dictionary, all_time_miles: float, all_time_laps: int, placement_data: Dictionary) -> void:
	if file == null:
		return
	file.store_line(snapshot["username"])
	file.store_line("Session Laps: " + str(snapshot["laps"]))
	file.store_line("Session Miles: " + snapshot["miles"])
	file.store_line("Total Miles (All Time): " + String.num(all_time_miles, 2))
	file.store_line("Total Laps (All Time): " + str(all_time_laps))
	file.store_line("1st x " + str(placement_data.get("1st", 0)) + ", 2nd x " + str(placement_data.get("2nd", 0)) + ", 3rd x " + str(placement_data.get("3rd", 0)))

func _save_top_3_lurker_images(top_place_users: Dictionary) -> void:
	var output_dir = "user://lurker_image"
	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_recursive_absolute(output_dir)

	var place_to_file = {
		1: "1st.png",
		2: "2nd.png",
		3: "3rd.png"
	}

	for place in [1, 2, 3]:
		var texture: Texture2D = null
		if top_place_users.has(place):
			var user_name = str(top_place_users[place])
			if lurkers.has(user_name):
				var lurker = lurkers[user_name]
				texture = lurker.profile_image if lurker.profile_image != null else lurker.car_sprite.texture

		if texture == null:
			var crown_index = place - 1
			if crown_textures.has(crown_index):
				texture = crown_textures[crown_index]

		if texture == null:
			continue
		var image = texture.get_image()
		if image == null:
			continue
		var output_path = output_dir + "/" + place_to_file[place]
		var save_err = image.save_png(output_path)
		if save_err != OK:
			push_error("Failed to save top place image: " + output_path)

func _write_latest_place_files(results_dir: String, sorted_rows: Array) -> void:
	var place_files = ["1st_place.txt", "2nd_place.txt", "3rd_place.txt"]
	for i in range(place_files.size()):
		var place_path = results_dir + "/" + place_files[i]
		var place_file = FileAccess.open(place_path, FileAccess.WRITE)
		if place_file == null:
			push_error("Failed to create place file: " + place_path)
			continue

		if i < sorted_rows.size():
			var row = sorted_rows[i]
			var username = str(row["username"])
			var rival = _get_top_attacker_for_user(username)
			var bully = _get_top_victim_for_user(username)
			place_file.store_line(username)
			place_file.store_line("Place: " + str(row["place"]))
			place_file.store_line("Points: " + str(row["laps"]))
			place_file.store_line("Rival: " + rival)
			place_file.store_line("Bully: " + bully)
		else:
			place_file.store_line("N/A")
			place_file.store_line("Place: N/A")
			place_file.store_line("Points: 0")
			place_file.store_line("Rival: N/A")
			place_file.store_line("Bully: N/A")

func _get_top_attacker_for_user(username: String) -> String:
	if not attacker_details.has(username):
		return "N/A"
	var combined: Dictionary = {}
	for trap_type in attacker_details[username].keys():
		var per_attacker = attacker_details[username][trap_type]
		for attacker in per_attacker.keys():
			if not combined.has(attacker):
				combined[attacker] = 0
			combined[attacker] += int(per_attacker[attacker])
	if combined.is_empty():
		return "N/A"
	var top_name = "N/A"
	var top_count = -1
	for attacker_name in combined.keys():
		var count = int(combined[attacker_name])
		if count > top_count:
			top_count = count
			top_name = str(attacker_name)
	return top_name

func _get_top_victim_for_user(username: String) -> String:
	if not victim_details.has(username):
		return "N/A"
	var combined: Dictionary = {}
	for trap_type in victim_details[username].keys():
		var per_victim = victim_details[username][trap_type]
		for victim in per_victim.keys():
			if not combined.has(victim):
				combined[victim] = 0
			combined[victim] += int(per_victim[victim])
	if combined.is_empty():
		return "N/A"
	var top_name = "N/A"
	var top_count = -1
	for victim_name in combined.keys():
		var count = int(combined[victim_name])
		if count > top_count:
			top_count = count
			top_name = str(victim_name)
	return top_name

func _sum_count_map(values: Dictionary) -> int:
	var total := 0
	for k in values.keys():
		total += int(values[k])
	return total

func _merge_shield_hit_targets(attacker_name: String) -> Dictionary:
	var merged: Dictionary = {}
	if not shield_hit_details.has(attacker_name):
		return merged
	for trap_type in shield_hit_details[attacker_name].keys():
		var victims = shield_hit_details[attacker_name][trap_type]
		for victim in victims.keys():
			merged[victim] = int(merged.get(victim, 0)) + int(victims[victim])
	return merged

func _shield_fail_by_for_user(username: String) -> Dictionary:
	# Inverse view of shield_breaker_details: who broke this user's final shields.
	var broken_by: Dictionary = {}
	for attacker in shield_breaker_details.keys():
		var victims = shield_breaker_details[attacker]
		if victims.has(username):
			broken_by[attacker] = int(broken_by.get(attacker, 0)) + int(victims[username])
	return broken_by

func _split_csv_line(line: String) -> Array[String]:
	# Minimal CSV parser supporting quoted fields with commas and escaped quotes.
	var out: Array[String] = []
	var current := ""
	var in_quotes := false
	var i := 0
	while i < line.length():
		var ch := line[i]
		if ch == '"':
			if in_quotes and i + 1 < line.length() and line[i + 1] == '"':
				current += '"'
				i += 1
			else:
				in_quotes = not in_quotes
		elif ch == "," and not in_quotes:
			out.append(current)
			current = ""
		else:
			current += ch
		i += 1
	out.append(current)
	return out

func _append_or_accumulate(agg: Dictionary, row: Dictionary) -> void:
	# Merge one row into per-user historical totals.
	var username = str(row.get("username", "")).strip_edges().to_lower()
	if username == "":
		return
	if not agg.has(username):
		agg[username] = {
			"timestamp": str(row.get("timestamp", "")),
			"username": username,
			"place": 0,
			"miles": 0.0,
			"laps": 0,
			"races_joined": 0,
			"rejoin_count": 0,
			"leave_count": 0,
			"ban_count": 0,
			"1st_place_count": 0,
			"2nd_place_count": 0,
			"3rd_place_count": 0,
			"shield_hit_count": 0,
			"shield_defense_count": 0,
			"shield_breaker_count": 0,
			"shield_fail_count": 0,
			"yellow_victims_map": {},
			"red_victims_map": {},
			"yellow_attackers_map": {},
			"red_attackers_map": {},
			"shield_hit_map": {},
			"shield_defense_map": {},
			"shield_breaker_map": {},
			"shield_fail_map": {}
		}

	var dst = agg[username]
	dst["timestamp"] = str(row.get("timestamp", dst["timestamp"]))
	dst["miles"] += float(row.get("miles", 0.0))
	dst["laps"] += int(row.get("laps", 0))
	dst["races_joined"] += int(row.get("races_joined", 0))
	dst["rejoin_count"] += int(row.get("rejoin_count", 0))
	dst["leave_count"] += int(row.get("leave_count", 0))
	dst["ban_count"] += int(row.get("ban_count", 0))
	dst["shield_hit_count"] += int(row.get("shield_hit_count", 0))
	dst["shield_defense_count"] += int(row.get("shield_defense_count", 0))
	dst["shield_breaker_count"] += int(row.get("shield_breaker_count", 0))
	dst["shield_fail_count"] += int(row.get("shield_fail_count", 0))

	var place = int(row.get("place", 0))
	if place == 1:
		dst["1st_place_count"] += 1
	elif place == 2:
		dst["2nd_place_count"] += 1
	elif place == 3:
		dst["3rd_place_count"] += 1

	# Merge trap interaction summaries into all-time dictionaries.
	for k in _parse_ranked_list(str(row.get("yellow_victims", ""))).keys():
		var m = dst["yellow_victims_map"]
		m[k] = int(m.get(k, 0)) + int(_parse_ranked_list(str(row.get("yellow_victims", ""))).get(k, 0))
	for k in _parse_ranked_list(str(row.get("red_victims", ""))).keys():
		var m2 = dst["red_victims_map"]
		m2[k] = int(m2.get(k, 0)) + int(_parse_ranked_list(str(row.get("red_victims", ""))).get(k, 0))
	for k in _parse_ranked_list(str(row.get("yellow_attackers", ""))).keys():
		var m3 = dst["yellow_attackers_map"]
		m3[k] = int(m3.get(k, 0)) + int(_parse_ranked_list(str(row.get("yellow_attackers", ""))).get(k, 0))
	for k in _parse_ranked_list(str(row.get("red_attackers", ""))).keys():
		var m4 = dst["red_attackers_map"]
		m4[k] = int(m4.get(k, 0)) + int(_parse_ranked_list(str(row.get("red_attackers", ""))).get(k, 0))
	for k in _parse_ranked_list(str(row.get("shield_hit_targets", ""))).keys():
		var m5 = dst["shield_hit_map"]
		m5[k] = int(m5.get(k, 0)) + int(_parse_ranked_list(str(row.get("shield_hit_targets", ""))).get(k, 0))
	for k in _parse_ranked_list(str(row.get("shield_defense_by", ""))).keys():
		var m6 = dst["shield_defense_map"]
		m6[k] = int(m6.get(k, 0)) + int(_parse_ranked_list(str(row.get("shield_defense_by", ""))).get(k, 0))
	for k in _parse_ranked_list(str(row.get("shield_breaker_targets", ""))).keys():
		var m7 = dst["shield_breaker_map"]
		m7[k] = int(m7.get(k, 0)) + int(_parse_ranked_list(str(row.get("shield_breaker_targets", ""))).get(k, 0))
	for k in _parse_ranked_list(str(row.get("shield_fail_by", ""))).keys():
		var m8 = dst["shield_fail_map"]
		m8[k] = int(m8.get(k, 0)) + int(_parse_ranked_list(str(row.get("shield_fail_by", ""))).get(k, 0))

func _row_to_csv_line(row: Dictionary) -> String:
	var escape_csv = func(s: String) -> String:
		s = s.replace("\"", "\"\"")
		return "\"" + s + "\""
	var line = str(row.get("timestamp", "")) + ","
	line += str(row.get("username", "")) + ","
	line += str(row.get("place", 0)) + ","
	line += str(row.get("miles", "0")) + ","
	line += str(row.get("laps", 0)) + ","
	line += str(row.get("races_joined", 0)) + ","
	line += str(row.get("rejoin_count", 0)) + ","
	line += str(row.get("leave_count", 0)) + ","
	line += str(row.get("ban_count", 0)) + ","
	line += str(row.get("1st_place_count", 0)) + ","
	line += str(row.get("2nd_place_count", 0)) + ","
	line += str(row.get("3rd_place_count", 0)) + ","
	line += str(row.get("shield_hit_count", 0)) + ","
	line += escape_csv.call(str(row.get("shield_hit_targets", ""))) + ","
	line += str(row.get("shield_defense_count", 0)) + ","
	line += escape_csv.call(str(row.get("shield_defense_by", ""))) + ","
	line += str(row.get("shield_breaker_count", 0)) + ","
	line += escape_csv.call(str(row.get("shield_breaker_targets", ""))) + ","
	line += str(row.get("shield_fail_count", 0)) + ","
	line += escape_csv.call(str(row.get("shield_fail_by", ""))) + ","
	line += escape_csv.call(str(row.get("yellow_victims", ""))) + ","
	line += escape_csv.call(str(row.get("red_victims", ""))) + ","
	line += escape_csv.call(str(row.get("yellow_attackers", ""))) + ","
	line += escape_csv.call(str(row.get("red_attackers", "")) )
	return line

func create_result() -> void:
	# Rebuild results.csv with two sections:
	# 1) Latest run top-3 racers.
	# 2) Historical cumulative totals for all racers up to now.
	_update_rankings()
	var top_place_users: Dictionary = {}
	var results_dir = _resolve_writable_results_dir()
	results_csv_path = results_dir + "/results.csv"
	var csv_header = "timestamp,username,place,miles,laps,races_joined,rejoin_count,leave_count,ban_count,1st_place_count,2nd_place_count,3rd_place_count,shield_hit_count,shield_hit_targets,shield_defense_count,shield_defense_by,shield_breaker_count,shield_breaker_targets,shield_fail_count,shield_fail_by,yellow_victims,red_victims,yellow_attackers,red_attackers"

	# Read existing CSV rows so they can be folded into cumulative totals.
	var historical_rows: Array = []
	var existing_path = _resolve_results_csv_for_read()
	var existing_file = FileAccess.open(existing_path, FileAccess.READ)
	if existing_file != null:
		if not existing_file.eof_reached():
			existing_file.get_line()
		while not existing_file.eof_reached():
			var old_line = existing_file.get_line()
			if old_line.strip_edges() == "":
				continue
			var p = _split_csv_line(old_line)
			if p.size() < 16:
				continue
			var has_shield_cols = p.size() >= 24
			historical_rows.append({
				"timestamp": p[0],
				"username": p[1],
				"place": int(p[2]),
				"miles": float(p[3]),
				"laps": int(p[4]),
				"races_joined": int(p[5]),
				"rejoin_count": int(p[6]),
				"leave_count": int(p[7]),
				"ban_count": int(p[8]),
				"1st_place_count": int(p[9]),
				"2nd_place_count": int(p[10]),
				"3rd_place_count": int(p[11]),
				"shield_hit_count": int(p[12]) if has_shield_cols else 0,
				"shield_hit_targets": p[13] if has_shield_cols else "",
				"shield_defense_count": int(p[14]) if has_shield_cols else 0,
				"shield_defense_by": p[15] if has_shield_cols else "",
				"shield_breaker_count": int(p[16]) if has_shield_cols else 0,
				"shield_breaker_targets": p[17] if has_shield_cols else "",
				"shield_fail_count": int(p[18]) if has_shield_cols else 0,
				"shield_fail_by": p[19] if has_shield_cols else "",
				"yellow_victims": p[20] if has_shield_cols else p[12],
				"red_victims": p[21] if has_shield_cols else p[13],
				"yellow_attackers": p[22] if has_shield_cols else p[14],
				"red_attackers": p[23] if has_shield_cols else p[15]
			})

	# Fresh rewrite preserves deterministic section order every !result call.
	var file = FileAccess.open(results_csv_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to create/open results.csv")
		return

	file.store_line(csv_header)

	var timestamp = _now_day_hour_string()
	var current_rows: Array = []
	var aggregate_by_user: Dictionary = {}

	# Seed aggregate totals from prior CSV rows.
	for old_row in historical_rows:
		_append_or_accumulate(aggregate_by_user, old_row)
	
	for user_name in lurkers.keys():
		# Skip broadcaster from results
		if user_name.to_lower() == _get_broadcaster_login():
			continue
		
		var snapshot = _get_lurker_snapshot(user_name)
		var place = snapshot["place"]
		
		# Ensure cumulative placement counters exist before incrementing.
		if not placement_counts.has(user_name):
			placement_counts[user_name] = {"1st": 0, "2nd": 0, "3rd": 0}
		
		# Update placement counts
		if place == 1:
			placement_counts[user_name]["1st"] += 1
			top_place_users[1] = user_name
		elif place == 2:
			placement_counts[user_name]["2nd"] += 1
			top_place_users[2] = user_name
		elif place == 3:
			placement_counts[user_name]["3rd"] += 1
			top_place_users[3] = user_name
		
		# Get victim/attacker data for this user
		var user_victims = victim_details.get(user_name, {})
		var user_attackers = attacker_details.get(user_name, {})
		
		var yellow_vict = user_victims.get("yellow_attack", {})
		var red_vict = user_victims.get("red_shell", {})
		var yellow_att = user_attackers.get("yellow_attack", {})
		var red_att = user_attackers.get("red_shell", {})
		
		# Build ranked lists (no wrapping, separate cells for each list)
		var yellow_vict_list = _build_ranked_list(yellow_vict)
		var red_vict_list = _build_ranked_list(red_vict)
		var yellow_att_list = _build_ranked_list(yellow_att)
		var red_att_list = _build_ranked_list(red_att)
		var shield_hit_targets = _merge_shield_hit_targets(user_name)
		var shield_defense_by = shield_hits_on_user.get(user_name, {})
		var shield_breaker_targets = shield_breaker_details.get(user_name, {})
		var shield_fail_by = _shield_fail_by_for_user(user_name)

		var row = {
			"timestamp": timestamp,
			"username": user_name,
			"place": place,
			"miles": snapshot["miles"],
			"laps": snapshot["laps"],
			"races_joined": snapshot["races_joined"],
			"rejoin_count": snapshot["rejoin_count"],
			"leave_count": snapshot["leave_count"],
			"ban_count": snapshot["ban_count"],
			"1st_place_count": placement_counts[user_name]["1st"],
			"2nd_place_count": placement_counts[user_name]["2nd"],
			"3rd_place_count": placement_counts[user_name]["3rd"],
			"shield_hit_count": _sum_count_map(shield_hit_targets),
			"shield_hit_targets": _build_ranked_list(shield_hit_targets),
			"shield_defense_count": _sum_count_map(shield_defense_by),
			"shield_defense_by": _build_ranked_list(shield_defense_by),
			"shield_breaker_count": _sum_count_map(shield_breaker_targets),
			"shield_breaker_targets": _build_ranked_list(shield_breaker_targets),
			"shield_fail_count": _sum_count_map(shield_fail_by),
			"shield_fail_by": _build_ranked_list(shield_fail_by),
			"yellow_victims": yellow_vict_list,
			"red_victims": red_vict_list,
			"yellow_attackers": yellow_att_list,
			"red_attackers": red_att_list
		}

		current_rows.append(row)
		_append_or_accumulate(aggregate_by_user, row)

	# Keep first section strictly to latest top 3 from current run.
	current_rows.sort_custom(func(a, b): return int(a["place"]) < int(b["place"]))
	for i in range(min(3, current_rows.size())):
		top_place_users[i + 1] = current_rows[i]["username"]
		file.store_line(_row_to_csv_line(current_rows[i]))

	# Section separator + second header for cumulative historical view.
	file.store_line("")
	file.store_line(csv_header)

	var aggregated_rows: Array = []
	for uname in aggregate_by_user.keys():
		var a = aggregate_by_user[uname]
		aggregated_rows.append({
			"timestamp": timestamp,
			"username": uname,
			"place": 0,
			"miles": String.num(float(a["miles"]), 2),
			"laps": int(a["laps"]),
			"races_joined": int(a["races_joined"]),
			"rejoin_count": int(a["rejoin_count"]),
			"leave_count": int(a["leave_count"]),
			"ban_count": int(a["ban_count"]),
			"1st_place_count": int(a["1st_place_count"]),
			"2nd_place_count": int(a["2nd_place_count"]),
			"3rd_place_count": int(a["3rd_place_count"]),
			"shield_hit_count": int(a["shield_hit_count"]),
			"shield_hit_targets": _build_ranked_list(a["shield_hit_map"]),
			"shield_defense_count": int(a["shield_defense_count"]),
			"shield_defense_by": _build_ranked_list(a["shield_defense_map"]),
			"shield_breaker_count": int(a["shield_breaker_count"]),
			"shield_breaker_targets": _build_ranked_list(a["shield_breaker_map"]),
			"shield_fail_count": int(a["shield_fail_count"]),
			"shield_fail_by": _build_ranked_list(a["shield_fail_map"]),
			"yellow_victims": _build_ranked_list(a["yellow_victims_map"]),
			"red_victims": _build_ranked_list(a["red_victims_map"]),
			"yellow_attackers": _build_ranked_list(a["yellow_attackers_map"]),
			"red_attackers": _build_ranked_list(a["red_attackers_map"])
		})

	aggregated_rows.sort_custom(func(a, b): return float(a["miles"]) > float(b["miles"]))
	for row in aggregated_rows:
		file.store_line(_row_to_csv_line(row))

	_write_latest_place_files(results_dir, current_rows)

	_save_top_3_lurker_images(top_place_users)
	
	last_result_timestamp = Time.get_ticks_msec()
	print("Results saved in ", results_dir, " (", ProjectSettings.globalize_path(results_dir), ")")
	event_stream.system_message.emit("Results updated.")

func should_auto_save_on_close() -> bool:
	var time_since_result = Time.get_ticks_msec() - last_result_timestamp
	var three_mins_ms = 3 * 60 * 1000
	return time_since_result > three_mins_ms

func _on_tree_exiting() -> void:
	# On app close, auto-save results if !result wasn't run in last 3 mins
	if should_auto_save_on_close():
		print("Auto-saving results on app close...")
		create_result()
