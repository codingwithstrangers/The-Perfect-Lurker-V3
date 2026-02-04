extends Node
class_name LurkerGang

@export var lurker_prefab: PackedScene
@onready var event_stream: EventStream = $'../event_stream'
@onready var track_manager: TrackManager = $"../track_manager"

var lurkers: Dictionary[String, Lurker] = {}
var crown_textures: Dictionary[int, Texture2D] = {}
var rankings: Array[String] = []
var kicked_users: Dictionary = {}  # Dictionary used as a set (keys are usernames, values are true)
var kicked_users_csv_path: String = "user://kicked_users.csv"
var traps_csv_path: String = "user://traps_log.csv"
var race_events_csv_path: String = "user://race_events.csv"
var results_csv_path: String = "user://results.csv"
var last_result_timestamp: int = 0  # Track when !result was last run

# Stats tracking dictionaries
var trap_hits_on_user: Dictionary = {}  # {username: {trap_type: count}}
var trap_throws_by_user: Dictionary = {}  # {username: {trap_type: count}}
var user_stats: Dictionary = {}  # {username: {races_joined, rejoin_count, leave_count, ban_count, miles, lap_count}}
var victim_details: Dictionary = {}  # {username: {"yellow_attack": {victim: count}, "red_shell": {victim: count}}}
var attacker_details: Dictionary = {}  # {username: {"yellow_attack": {attacker: count}, "red_shell": {attacker: count}}}
var placement_counts: Dictionary = {}  # {username: {1st: count, 2nd: count, 3rd: count}}

func _ready():
	event_stream.join_race_attempted.connect(self._on_join_race_attempted)
	event_stream.leave_race_attempted.connect(self._on_leave_race_attempted)
	event_stream.lurker_chat.connect(self._on_lurker_chat)
	event_stream.send_to_pit.connect(self._on_lurker_send_to_pit)
	event_stream.leave_the_pit.connect(self._on_lurker_leave_the_pit)
	event_stream.kick_user.connect(self._on_kick_user)
	event_stream.unban_user.connect(self._on_unban_user)
	event_stream.trap_hit.connect(self._on_trap_hit)

	_load_crown_textures()
	_load_kicked_users()
	_load_placement_counts()
	_initialize_traps_csv()
	_initialize_race_events_csv()
	
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
		# User is rejoining - always send them to the main track to race
		var lurker = lurkers[user_name]
		lurker.rejoin_race()
		# Always reparent to track (not pit) when rejoining
		track_manager.send_to_track(user_name)
		_log_race_event("rejoin", user_name)
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
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(self._on_image_downloaded.bind(http_request, url, user_name))
	print("requesting profile image  ", user_name)
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
	user_name: String,
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

	self.spawn_lurker(user_name, url, image)

func spawn_lurker(user_name: String, url: String, image: Image):
	print("spawning lurker: ", user_name)
	
	var new_lurker = lurker_prefab.instantiate()
	track_manager.track.add_child(new_lurker)
	
	var lurker = new_lurker.get_node(".") as Lurker
	lurkers[user_name] = lurker
	
	var downloaded_image = ImageTexture.create_from_image(image)
	lurker.username = user_name
	lurker.profile_url = url
	lurker.profile_image = downloaded_image
	lurker.car_sprite.texture = downloaded_image
	lurker.name = user_name
	event_stream.joined_race.emit(lurker)

	lurker.lap_completed.connect(self._on_lurker_lap_completed)
	lurker.distance_updated.connect(self._on_lurker_distance_updated)
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

func _on_unban_user(user_name: String):
	if kicked_users.has(user_name):
		kicked_users.erase(user_name)
		_save_kicked_users()
		var message = user_name + " has been unbanned and can rejoin!"
		print(message)
		event_stream.system_message.emit(message)
	else:
		var message = user_name + " is not on the ban list."
		print(message)
		event_stream.system_message.emit(message)

func _on_leave_race_attempted(user_name: String):
	if lurkers.has(user_name):
		lurkers[user_name].leave_race()
		_log_race_event("leave", user_name)

func _on_lurker_send_to_pit(user_name: String):
	if lurkers.has(user_name):
		lurkers[user_name].enter_pit()

func _on_lurker_leave_the_pit(user_name: String):
	if lurkers.has(user_name):
		lurkers[user_name].leave_pit()

func _load_crown_textures() -> void:
	crown_textures[0] = load("res://crowns/gold.png")
	crown_textures[1] = load("res://crowns/silver.png")
	crown_textures[2] = load("res://crowns/bronze.png")

func _on_lurker_lap_completed(user_name: String, lap_count: int) -> void:
	print(user_name, " completed lap ", lap_count + 1)
	_update_rankings()
	_update_crowns()

func _on_lurker_distance_updated(_username: String, _total_distance: float) -> void:
	# distance updates are frequent; update rankings and crowns in response
	_update_rankings()
	_update_crowns()

func _update_rankings() -> void:
	rankings.clear()
	var racing_lurkers: Array[String] = []
	for user_name in lurkers.keys():
		var lurker = lurkers[user_name]
		if lurker.state != Lurker.RaceState.Out:
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
	var file = FileAccess.open(kicked_users_csv_path, FileAccess.READ)
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
	var file = FileAccess.open(results_csv_path, FileAccess.READ)
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
		file.store_line("timestamp,trap_type,hit_by,dropped_by")

func _log_trap_hit(trap_type: String, hit_by: String, dropped_by: String) -> void:
	var file = FileAccess.open(traps_csv_path, FileAccess.READ_WRITE)
	if file == null:
		push_error("Failed to open traps_log.csv for appending")
		return
	
	# Seek to end of file
	file.seek_end()
	
	var timestamp = Time.get_ticks_msec()
	var line = str(timestamp) + "," + trap_type + "," + hit_by + "," + dropped_by
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

func _initialize_race_events_csv() -> void:
	var file = FileAccess.open(race_events_csv_path, FileAccess.READ)
	if file == null:
		# File doesn't exist, create it with header
		file = FileAccess.open(race_events_csv_path, FileAccess.WRITE)
		if file == null:
			push_error("Failed to create race_events.csv")
			return
		file.store_line("timestamp,event_type,username")

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
	
	for i in range(top_3.size()):
		var username = top_3[i]
		var snapshot = _get_lurker_snapshot(username)
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
	
	var message = "Snapshot created for top 3 lurkers!"
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

func create_result() -> void:
	# Initialize results CSV if it doesn't exist
	var file = FileAccess.open(results_csv_path, FileAccess.READ)
	if file == null:
		file = FileAccess.open(results_csv_path, FileAccess.WRITE)
		if file == null:
			push_error("Failed to create results.csv")
			return
		file.store_line("timestamp,username,place,miles,laps,races_joined,rejoin_count,leave_count,ban_count,1st_place_count,2nd_place_count,3rd_place_count,yellow_victims,red_victims,yellow_attackers,red_attackers")
	
	# Create result row for each player
	file = FileAccess.open(results_csv_path, FileAccess.READ_WRITE)
	if file == null:
		push_error("Failed to open results.csv")
		return
	
	file.seek_end()
	
	var timestamp = Time.get_ticks_msec()
	
	# Create the 3 result text files
	var result_1_file = FileAccess.open("user://result_1.txt", FileAccess.WRITE)
	var result_2_file = FileAccess.open("user://result_2.txt", FileAccess.WRITE)
	var result_3_file = FileAccess.open("user://result_3.txt", FileAccess.WRITE)
	
	if result_1_file == null or result_2_file == null or result_3_file == null:
		push_error("Failed to create result txt files")
		return
	
	# Write headers to txt files
	result_1_file.store_line("=== 1ST PLACE ===")
	result_2_file.store_line("=== 2ND PLACE ===")
	result_3_file.store_line("=== 3RD PLACE ===")
	
	for user_name in lurkers.keys():
		var snapshot = _get_lurker_snapshot(user_name)
		var place = snapshot["place"]
		
		# Ensure placement counts exist
		if not placement_counts.has(user_name):
			placement_counts[user_name] = {"1st": 0, "2nd": 0, "3rd": 0}
		
		# Update placement counts
		if place == 1:
			placement_counts[user_name]["1st"] += 1
		elif place == 2:
			placement_counts[user_name]["2nd"] += 1
		elif place == 3:
			placement_counts[user_name]["3rd"] += 1
		
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
		
		# Escape quotes for CSV (no newline wrapping)
		var escape_csv = func(s: String) -> String:
			s = s.replace("\"", "\"\"")
			return "\"" + s + "\""
		
		# Build CSV line with placement counts
		var line = str(timestamp) + "," + user_name + "," + str(place) + "," + snapshot["miles"] + "," + str(snapshot["laps"]) + "," + str(snapshot["races_joined"]) + "," + str(snapshot["rejoin_count"]) + "," + str(snapshot["leave_count"]) + "," + str(snapshot["ban_count"]) + ","
		line += str(placement_counts[user_name]["1st"]) + ","
		line += str(placement_counts[user_name]["2nd"]) + ","
		line += str(placement_counts[user_name]["3rd"]) + ","
		line += escape_csv.call(yellow_vict_list) + ","
		line += escape_csv.call(red_vict_list) + ","
		line += escape_csv.call(yellow_att_list) + ","
		line += escape_csv.call(red_att_list)
		
		file.store_line(line)
		
		# Write to appropriate result txt file
		var txt_content = "Player: " + user_name + "\n"
		txt_content += "Miles: " + snapshot["miles"] + "\n"
		txt_content += "Laps: " + str(snapshot["laps"]) + "\n"
		txt_content += "Races Joined: " + str(snapshot["races_joined"]) + "\n"
		txt_content += "Rejoin Count: " + str(snapshot["rejoin_count"]) + "\n"
		txt_content += "Leave Count: " + str(snapshot["leave_count"]) + "\n"
		txt_content += "Ban Count: " + str(snapshot["ban_count"]) + "\n"
		txt_content += "1st Place Finishes: " + str(placement_counts[user_name]["1st"]) + "\n"
		txt_content += "2nd Place Finishes: " + str(placement_counts[user_name]["2nd"]) + "\n"
		txt_content += "3rd Place Finishes: " + str(placement_counts[user_name]["3rd"]) + "\n"
		txt_content += "Yellow Traps Hit: " + str(snapshot["yellow_hits"]) + "\n"
		txt_content += "Red Traps Hit: " + str(snapshot["red_hits"]) + "\n"
		txt_content += "Yellow Traps Thrown: " + str(snapshot["yellow_throws"]) + "\n"
		txt_content += "Red Traps Thrown: " + str(snapshot["red_throws"]) + "\n"
		txt_content += "\n"
		
		# Write to appropriate file based on placement
		if place == 1:
			result_1_file.store_line(txt_content)
		elif place == 2:
			result_2_file.store_line(txt_content)
		elif place == 3:
			result_3_file.store_line(txt_content)
	
	last_result_timestamp = Time.get_ticks_msec()
	var message = "Results saved! Files created: result_1.txt, result_2.txt, result_3.txt"
	print(message)
	event_stream.system_message.emit(message)

func should_auto_save_on_close() -> bool:
	var time_since_result = Time.get_ticks_msec() - last_result_timestamp
	var three_mins_ms = 3 * 60 * 1000
	return time_since_result > three_mins_ms

func _on_tree_exiting() -> void:
	# On app close, auto-save results if !result wasn't run in last 3 mins
	if should_auto_save_on_close():
		print("Auto-saving results on app close...")
		create_result()
