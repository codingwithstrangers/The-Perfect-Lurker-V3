extends Gift
class_name TwitchEvents

@export var text_commands_enabled: bool

@onready var event_stream: EventStream = $'../event_stream'

var join_reward: String
var trap_reward: String
var missle_reward: String

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
	subscribe_event(
		"channel.channel_points_custom_reward_redemption.add",
		1, { "broadcaster_user_id": user_id },
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
		_:
			event_stream.lurker_chat.emit(sender_data.user)


func on_event(type: String, data: Dictionary) -> void:
	match type:
		"channel.channel_points_custom_reward_redemption.add":
			match data["event"]["reward"]["id"]:
				join_reward:
					var user_data = await user_data_by_name(data["event"]["user_name"])
					event_stream.join_race_attempted.emit(data["event"]["user_name"], user_data.profile_image_url)
				trap_reward:
					event_stream.trap_drop_attempted.emit(data["event"]["user_name"])
				missle_reward:
					event_stream.missle_launch_attempted.emit(data["event"]["user_name"])
