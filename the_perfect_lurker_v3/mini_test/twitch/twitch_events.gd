extends Gift
class_name TwitchEvents

@export var text_commands_enabled: bool

@onready var event_stream: EventStream = $'../event_stream'
@onready var lurker_gang: LurkerGang = $'../lurker_gang'
#custom_id for channel points
var perfect_lurker_channel_id = "a374b031-d275-4660-9755-9a9977e7f3ae"
var talking_lurker_id = "d229fa01-0b61-46e7-9c3c-a1110a7d03d4"
var yellow_channel_point = "bb5f96f3-714d-4b09-9203-9b698a97aa7f"
var red_channel_point = "c72d18f9-4bbf-4b9d-8839-55c49042c22d"
var blue_channel_point = "6faf803c-b051-4533-b86a-95a5955eace3"
var shield_channel_point = "67313597-0928-46e8-97d3-f7241ec778ed"
var pit_channel_point = "ae1ee0c8-7e80-4ed5-bead-d083d0f64022"


var join_reward: String  #replace this with actual channel points
var trap_reward: String
var missile_reward: String
var leave_pit_reward: String
var score_board: String
@export_range(1.0, 60.0, 1.0, "suffix:min") var chat_sync_interval_minutes: float = 10.0
const RECONNECT_DELAY_SEC := 5.0
const HEALTHCHECK_INTERVAL_SEC := 30.0

var login_client_id: String = ""
var login_client_secret: String = ""
var login_channel: String = ""
var reconnect_in_progress: bool = false
var reconnect_timer: Timer
var health_timer: Timer
var chat_sync_timer: Timer
var status_layer: CanvasLayer
var status_label: Label
var active_chat_users: Dictionary = {}
var names_snapshot_users: Dictionary = {}
var names_refresh_in_progress: bool = false

func _ready() -> void:
	event_stream.send_chat.connect(chat)
	event_stream.system_message.connect(chat)
	chat_message.connect(on_chat)
	event.connect(on_event)
	unhandled_message.connect(_on_unhandled_irc_message)
	twitch_connected.connect(_on_twitch_connected)
	twitch_disconnected.connect(_on_twitch_disconnected)
	twitch_unavailable.connect(_on_twitch_unavailable)
	events_connected.connect(_on_events_connected)
	events_disconnected.connect(_on_events_disconnected)
	events_unavailable.connect(_on_events_unavailable)
	user_token_invalid.connect(_on_user_token_invalid)
	_setup_status_label()
	_update_status_label("Disconnected")

	reconnect_timer = Timer.new()
	reconnect_timer.one_shot = true
	reconnect_timer.wait_time = RECONNECT_DELAY_SEC
	reconnect_timer.timeout.connect(_on_reconnect_timer_timeout)
	add_child(reconnect_timer)

	health_timer = Timer.new()
	health_timer.one_shot = false
	health_timer.wait_time = HEALTHCHECK_INTERVAL_SEC
	health_timer.timeout.connect(_healthcheck_connection)
	add_child(health_timer)
	health_timer.start()

	chat_sync_timer = Timer.new()
	chat_sync_timer.one_shot = false
	chat_sync_timer.wait_time = chat_sync_interval_minutes * 60.0
	chat_sync_timer.timeout.connect(_on_chat_sync_timer_timeout)
	add_child(chat_sync_timer)
	chat_sync_timer.start()


func try_login(
	client_id_edit: String,
	client_secret_edit: String,
	channel_edit: String,
):
	login_client_id = client_id_edit
	login_client_secret = client_secret_edit
	login_channel = channel_edit.to_lower()
	reconnect_in_progress = false
	await _connect_and_subscribe()

func _connect_and_subscribe() -> void:
	_update_status_label("Connecting...")
	await(authenticate(login_client_id, login_client_secret))
	var success = await(connect_to_irc())
	if not success:
		_schedule_reconnect("IRC login failed")
		return

	request_caps()
	if not channels.has(login_channel):
		join_channel(login_channel)
		await(channel_data_received)
	_request_chat_names_refresh()

	await(connect_to_eventsub())
	await _subscribe_core_events()
	reconnect_in_progress = false
	_update_status_label("Connected")
	if login_channel != "":
		event_stream.system_message.emit("Twitch connection restored.")

func _subscribe_core_events() -> void:
	# Refer to https://dev.twitch.tv/docs/eventsub/eventsub-subscription-types/ for details on
	# what events exist, which API versions are available and which conditions are required.
	# Make sure your token has all required scopes for the event.
	await (subscribe_event(
		"channel.channel_points_custom_reward_redemption.add",
		1, { "broadcaster_user_id": user_id },
	)
	)

func _schedule_reconnect(reason: String) -> void:
	if login_client_id == "" or login_client_secret == "" or login_channel == "":
		return
	if reconnect_in_progress:
		return
	reconnect_in_progress = true
	_update_status_label("Reconnecting...")
	print("[TWITCH] Scheduling reconnect: ", reason)
	if reconnect_timer.is_stopped():
		reconnect_timer.start()

func _on_reconnect_timer_timeout() -> void:
	print("[TWITCH] Attempting reconnect...")
	_update_status_label("Reconnecting...")
	await _connect_and_subscribe()
	if reconnect_in_progress:
		reconnect_timer.start()

func _healthcheck_connection() -> void:
	if login_client_id == "" or login_channel == "":
		return
	if reconnect_in_progress:
		return
	if websocket == null or websocket.get_ready_state() != WebSocketPeer.STATE_OPEN or not connected:
		_schedule_reconnect("IRC not connected")
		return
	if eventsub == null or eventsub.get_ready_state() != WebSocketPeer.STATE_OPEN or not eventsub_connected:
		_schedule_reconnect("EventSub not connected")

func _on_twitch_disconnected() -> void:
	_update_status_label("Disconnected")
	_schedule_reconnect("IRC disconnected")

func _on_twitch_unavailable() -> void:
	_update_status_label("Disconnected")
	_schedule_reconnect("IRC unavailable")

func _on_events_disconnected() -> void:
	_update_status_label("Disconnected")
	_schedule_reconnect("EventSub disconnected")

func _on_events_unavailable() -> void:
	_update_status_label("Disconnected")
	_schedule_reconnect("EventSub unavailable")

func _on_user_token_invalid() -> void:
	_update_status_label("Token Invalid")
	_schedule_reconnect("Token invalid")

func _on_chat_sync_timer_timeout() -> void:
	_request_chat_names_refresh()

func _on_twitch_connected() -> void:
	if eventsub_connected:
		_update_status_label("Connected")
	else:
		_update_status_label("Connecting...")

func _on_events_connected() -> void:
	if connected:
		_update_status_label("Connected")
	else:
		_update_status_label("Connecting...")

func _setup_status_label() -> void:
	status_layer = CanvasLayer.new()
	status_layer.layer = 100
	status_layer.name = "twitch_status_layer"
	add_child(status_layer)

	status_label = Label.new()
	status_label.name = "twitch_status_label"
	status_label.text = "Twitch: Disconnected"
	status_label.position = Vector2(12, 12)
	status_layer.add_child(status_label)

func _update_status_label(status_text: String) -> void:
	if status_label == null:
		return
	status_label.text = "Twitch: " + status_text

func _request_chat_names_refresh() -> void:
	if login_channel == "":
		return
	if websocket == null or websocket.get_ready_state() != WebSocketPeer.STATE_OPEN or not connected:
		_schedule_reconnect("IRC not connected for NAMES refresh")
		return
	names_refresh_in_progress = true
	names_snapshot_users.clear()
	send("NAMES #" + login_channel)

func _on_unhandled_irc_message(message: String, _tags: Dictionary) -> void:
	# Track real-time JOIN/PART updates
	if " JOIN #" in message:
		var join_name = _extract_irc_user_name(message)
		if join_name != "":
			active_chat_users[join_name] = true
		return
	if " PART #" in message:
		var part_name = _extract_irc_user_name(message)
		if part_name != "":
			active_chat_users.erase(part_name)
		return

	# NAMES payload chunks
	if " 353 " in message:
		var target_users = names_snapshot_users if names_refresh_in_progress else active_chat_users
		for user_name in _extract_names_users(message):
			target_users[user_name] = true
		return

	# End of NAMES list
	if " 366 " in message and names_refresh_in_progress:
		active_chat_users = names_snapshot_users.duplicate()
		names_refresh_in_progress = false
		_sync_lurkers_with_chat_presence()

func _extract_irc_user_name(message: String) -> String:
	if not message.begins_with(":"):
		return ""
	var bang_idx = message.find("!")
	if bang_idx <= 1:
		return ""
	return message.substr(1, bang_idx - 1).to_lower()

func _extract_names_users(message: String) -> Array[String]:
	var names_list: Array[String] = []
	var colon_idx = message.find(" :")
	if colon_idx == -1:
		return names_list
	var payload = message.substr(colon_idx + 2)
	for raw_name in payload.split(" ", false):
		var cleaned = raw_name.strip_edges()
		while cleaned.begins_with("@") or cleaned.begins_with("+") or cleaned.begins_with("%") or cleaned.begins_with("&") or cleaned.begins_with("~"):
			cleaned = cleaned.substr(1)
		cleaned = cleaned.to_lower()
		if cleaned != "":
			names_list.append(cleaned)
	return names_list

func _sync_lurkers_with_chat_presence() -> void:
	for user_name in lurker_gang.lurkers.keys():
		var lurker = lurker_gang.lurkers[user_name]
		var in_chat = active_chat_users.has(user_name.to_lower())
		if in_chat:
			if lurker.state == Lurker.RaceState.InThePit:
				event_stream.leave_the_pit.emit(user_name)
		else:
			if lurker.state == Lurker.RaceState.Racing or lurker.state == Lurker.RaceState.LeavingThePit or lurker.state == Lurker.RaceState.Stunned:
				event_stream.send_to_pit.emit(user_name)
	
func on_chat(sender_data: SenderData, msg: String) -> void:
	var user_key = sender_data.user.to_lower()
	if _is_channel_point_message(sender_data):
		if OS.is_debug_build():
			var reward_id = str(sender_data.tags.get("custom-reward-id", ""))
			print("[REWARD CHAT SKIP] ", user_key, " reward_id=", reward_id, " msg=", msg)
		return
	if !text_commands_enabled:
		event_stream.lurker_chat.emit(user_key)
		return

	if msg.begins_with("!"):
		print("[COMMAND] ", sender_data.user, ": ", msg)

	var parts = msg.split(" ", false)
	var command = msg
	if parts.size() > 0:
		command = parts[0].to_lower()

	match command:
		"!join":
			var user_data = await user_data_by_name(sender_data.user)
			event_stream.join_race_attempted.emit(user_key, user_data.profile_image_url)
		"!trap":
			event_stream.trap_drop_attempted.emit(user_key)
		"!missile", "!missle":
			event_stream.missle_launch_attempted.emit(user_key)
		"!leave":
			event_stream.leave_race_attempted.emit(user_key)
		"!kick":
			if sender_data.user.to_lower() == "codingwithstrangers":
				if parts.size() > 1:
					var target_user = parts[1].strip_edges().to_lower()
					if target_user != "codingwithstrangers":
						event_stream.kick_user.emit(target_user)
			event_stream.lurker_chat.emit(user_key)
		"!unban":
			if sender_data.user.to_lower() == "codingwithstrangers":
				if parts.size() > 1:
					var target_user = parts[1].strip_edges().to_lower()
					event_stream.unban_user.emit(target_user)
			event_stream.lurker_chat.emit(user_key)
		"!place":
			_handle_place_command(user_key)
		"!defense":
			_handle_defense_command(user_key)
		"!rival", "!rivial":
			_handle_faaa_command(user_key)
		"!snapshot":
			if sender_data.user.to_lower() == "codingwithstrangers":
				lurker_gang.create_snapshot()
			else:
				chat("Only the broadcaster can use !snapshot")
		"!result":
			if sender_data.user.to_lower() == "codingwithstrangers":
				lurker_gang.create_result()
			else:
				chat("Only the broadcaster can use !result")
		"!lurkerhelp":
			_handle_lurker_help_command()
		_:
			# Any non-command chat message - emit lurker_chat to reset idle timer
			event_stream.lurker_chat.emit(user_key)
		
		


func on_event(type: String, data: Dictionary) -> void:
	print(type,data)
	match type:
		"channel.channel_points_custom_reward_redemption.add":
			var user_login = data["user_login"].to_lower()
			match data["reward"]["id"]:
				join_reward:
					var user_data = await user_data_by_name(data["user_name"])
					event_stream.join_race_attempted.emit(user_login, user_data.profile_image_url)
				trap_reward:
					event_stream.trap_drop_attempted.emit(user_login)
				missile_reward:
					event_stream.missle_launch_attempted.emit(user_login)
				leave_pit_reward:
					event_stream.leave_the_pit.emit(user_login)
				shield_channel_point:
					event_stream.grant_shield.emit(user_login)
func _is_channel_point_message(sender_data: SenderData) -> bool:
	if not sender_data.tags.has("custom-reward-id"):
		return false
	var reward_id = str(sender_data.tags.get("custom-reward-id", "")).strip_edges()
	return reward_id != ""

func _handle_lurker_help_command() -> void:
	chat("Lurker Help | Anyone: !join !trap !missile(!missle) !leave !place !defense !rival(!rivial) !lurkerhelp")
	chat("Broadcaster only: !kick <user> !unban <user> !snapshot !result")
	chat("Tip: channel point rewards also support join/trap/missile/leave pit/shield")

func _handle_place_command(user_name: String) -> void:
	if not lurker_gang.lurkers.has(user_name):
		chat(user_name + " is not in the race!")
		return
	
	if lurker_gang.rankings.is_empty():
		chat("Rankings are empty - no one has data yet!")
		return
	
	var rank_index = lurker_gang.rankings.find(user_name)
	if rank_index == -1:
		chat(user_name + " not found in rankings!")
		return
	
	var current_place = rank_index + 1
	var chasing = ""
	var chased_by = ""
	
	if current_place > 1 and rank_index > 0:
		chasing = lurker_gang.rankings[rank_index - 1]
	
	if current_place < lurker_gang.rankings.size():
		chased_by = lurker_gang.rankings[rank_index + 1]
	
	var message = user_name + " is in place #" + str(current_place)
	if chasing:
		message += " - Chasing: " + chasing
	if chased_by:
		message += " - Chased by: " + chased_by
	
	print("!place command output: ", message)
	chat(message)

func _handle_defense_command(user_name: String) -> void:
	if not lurker_gang.attacker_details.has(user_name):
		chat(user_name + " has not been hit by any traps!")
		return
	
	var attacker_data = lurker_gang.attacker_details[user_name]
	var yellow_attackers = attacker_data.get("yellow_attack", {})
	var red_attackers = attacker_data.get("red_shell", {})
	
	# Find top attacker for each trap type
	var top_yellow_attacker = ""
	var top_yellow_count = 0
	var top_red_attacker = ""
	var top_red_count = 0
	
	for attacker in yellow_attackers.keys():
		var count = yellow_attackers[attacker]
		if count > top_yellow_count:
			top_yellow_attacker = attacker
			top_yellow_count = count
	
	for attacker in red_attackers.keys():
		var count = red_attackers[attacker]
		if count > top_red_count:
			top_red_attacker = attacker
			top_red_count = count
	
	var yellow_total = yellow_attackers.values().reduce(func(a, b): return a + b, 0) if yellow_attackers else 0
	var red_total = red_attackers.values().reduce(func(a, b): return a + b, 0) if red_attackers else 0
	
	# Calculate shield hits
	var shield_hits_received = lurker_gang.shield_hits_on_user.get(user_name, {}).values().reduce(func(a, b): return a + b, 0) if lurker_gang.shield_hits_on_user.has(user_name) else 0
	
	var message = user_name + " hit by: Yellow=" + str(yellow_total)
	if top_yellow_attacker and top_yellow_count > 0:
		message += " (mostly by " + top_yellow_attacker + ": " + str(top_yellow_count) + ")"
	message += " Red=" + str(red_total)
	if top_red_attacker and top_red_count > 0:
		message += " (mostly by " + top_red_attacker + ": " + str(top_red_count) + ")"
	message += " | Shield Hit: " + str(shield_hits_received)
	
	chat(message)

func _handle_faaa_command(user_name: String) -> void:
	if not lurker_gang.victim_details.has(user_name):
		chat(user_name + " has not thrown any traps!")
		return
	
	var victim_data = lurker_gang.victim_details[user_name]
	var yellow_victims = victim_data.get("yellow_attack", {})
	var red_victims = victim_data.get("red_shell", {})
	
	# Find top victim for each trap type
	var top_yellow_victim = ""
	var top_yellow_count = 0
	var top_red_victim = ""
	var top_red_count = 0
	
	for victim in yellow_victims.keys():
		var count = yellow_victims[victim]
		if count > top_yellow_count:
			top_yellow_victim = victim
			top_yellow_count = count
	
	for victim in red_victims.keys():
		var count = red_victims[victim]
		if count > top_red_count:
			top_red_victim = victim
			top_red_count = count
	
	var yellow_total = yellow_victims.values().reduce(func(a, b): return a + b, 0) if yellow_victims else 0
	var red_total = red_victims.values().reduce(func(a, b): return a + b, 0) if red_victims else 0
	
	# Calculate shield breakers and shield hits
	var shield_breakers = lurker_gang.shield_breaker_details.get(user_name, {}).values().reduce(func(a, b): return a + b, 0) if lurker_gang.shield_breaker_details.has(user_name) else 0
	var shield_hits_total = 0
	if lurker_gang.shield_hit_details.has(user_name):
		for trap_type in lurker_gang.shield_hit_details[user_name].values():
			shield_hits_total += trap_type.values().reduce(func(a, b): return a + b, 0)
	
	var message = user_name + " threw: Yellow=" + str(yellow_total)
	if top_yellow_victim and top_yellow_count > 0:
		message += " (mostly at " + top_yellow_victim + ": " + str(top_yellow_count) + ")"
	message += " Red=" + str(red_total)
	if top_red_victim and top_red_count > 0:
		message += " (mostly at " + top_red_victim + ": " + str(top_red_count) + ")"
	message += " | Shield Breaker: " + str(shield_breakers) + " Shield Hits: " + str(shield_hits_total)
	
	chat(message)
