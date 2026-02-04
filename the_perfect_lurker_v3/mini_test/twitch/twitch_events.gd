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

func _ready() -> void:
	event_stream.send_chat.connect(chat)
	chat_message.connect(on_chat)
	event.connect(on_event)


func try_login(
	client_id_edit: String,
	client_secret_edit: String,
	channel_edit: String,
):
	await(authenticate(client_id_edit, client_secret_edit))
	var success = await(connect_to_irc())
	if (success):
		request_caps()
		join_channel(channel_edit)
		await(channel_data_received)
		
	await(connect_to_eventsub())	
	
	# Refer to https://dev.twitch.tv/docs/eventsub/eventsub-subscription-types/ for details on
	# what events exist, which API versions are available and which conditions are required.
	# Make sure your token has all required scopes for the event.
	await (subscribe_event(
		"channel.channel_points_custom_reward_redemption.add",
		1, { "broadcaster_user_id": user_id },
	)
	)
	
func on_chat(sender_data: SenderData, msg: String) -> void:
	if !text_commands_enabled:
		event_stream.lurker_chat.emit(sender_data.user)
		return
		
	match msg:
		"!join":
			var user_data = await user_data_by_name(sender_data.user)
			event_stream.join_race_attempted.emit(sender_data.user, user_data.profile_image_url)
		"!trap":
			event_stream.trap_drop_attempted.emit(sender_data.user)
		"!missle":
			event_stream.missle_launch_attempted.emit(sender_data.user)
		"!leave":
			event_stream.leave_race_attempted.emit(sender_data.user)
		"!kick":
			if sender_data.user == "codingwithstrangers":
				var parts = msg.split(" ")
				if parts.size() > 1:
					var target_user = parts[1].strip_edges().to_lower()
					if target_user != "codingwithstrangers":
						event_stream.kick_user.emit(target_user)
			event_stream.lurker_chat.emit(sender_data.user)
		"!unban":
			if sender_data.user == "codingwithstrangers":
				var parts = msg.split(" ")
				if parts.size() > 1:
					var target_user = parts[1].strip_edges().to_lower()
					event_stream.unban_user.emit(target_user)
			event_stream.lurker_chat.emit(sender_data.user)
		"!place":
			_handle_place_command(sender_data.user)
		"!trivial":
			_handle_trivial_command(sender_data.user)
		"!rivial":
			_handle_faaa_command(sender_data.user)
		"!snapshot":
			if sender_data.user == "codingwithstrangers":
				lurker_gang.create_snapshot()
			else:
				chat("Only the broadcaster can use !snapshot")
		"!result":
			if sender_data.user == "codingwithstrangers":
				lurker_gang.create_result()
			else:
				chat("Only the broadcaster can use !result")
		
		


func on_event(type: String, data: Dictionary) -> void:
	print(type,data)
	match type:
		"channel.channel_points_custom_reward_redemption.add":
			match data["reward"]["id"]:
				join_reward:
					var user_data = await user_data_by_name(data["user_name"])
					event_stream.join_race_attempted.emit(data["user_name"], user_data.profile_image_url)
				trap_reward:
					event_stream.trap_drop_attempted.emit(data["user_name"])
				missile_reward:
					event_stream.missle_launch_attempted.emit(data["user_name"])
				leave_pit_reward:
					event_stream.leave_the_pit.emit(data["user_name"])
func _handle_place_command(user_name: String) -> void:
	if not lurker_gang.lurkers.has(user_name):
		chat(user_name + " is not in the race!")
		return
	
	var current_place = lurker_gang.rankings.find(user_name) + 1
	var chasing = ""
	var chased_by = ""
	
	if current_place > 1 and current_place <= lurker_gang.rankings.size():
		chasing = lurker_gang.rankings[current_place - 2]
	
	if current_place < lurker_gang.rankings.size():
		chased_by = lurker_gang.rankings[current_place]
	
	var message = user_name + " is in place #" + str(current_place)
	if chasing:
		message += " - Chasing: " + chasing
	if chased_by:
		message += " - Chased by: " + chased_by
	
	chat(message)

func _handle_trivial_command(user_name: String) -> void:
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
	
	var message = user_name + " hit by: Yellow=" + str(yellow_total)
	if top_yellow_attacker and top_yellow_count > 0:
		message += " (mostly by " + top_yellow_attacker + ": " + str(top_yellow_count) + ")"
	message += " Red=" + str(red_total)
	if top_red_attacker and top_red_count > 0:
		message += " (mostly by " + top_red_attacker + ": " + str(top_red_count) + ")"
	
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
	
	var message = user_name + " threw: Yellow=" + str(yellow_total)
	if top_yellow_victim and top_yellow_count > 0:
		message += " (mostly at " + top_yellow_victim + ": " + str(top_yellow_count) + ")"
	message += " Red=" + str(red_total)
	if top_red_victim and top_red_count > 0:
		message += " (mostly at " + top_red_victim + ": " + str(top_red_count) + ")"
	
	chat(message)
