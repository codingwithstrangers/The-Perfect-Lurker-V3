extends Node
class_name Login

@onready var twitch_events: TwitchEvents = $'../../managers/twitch_events'
@onready var ui_root: Node = $'..'
@onready var client_id_edit: LineEdit = $login_root/client_id_edit
@onready var client_secret_edit: LineEdit = $login_root/client_secret_edit
@onready var channel_edit: LineEdit = $login_root/channel_edit
@onready var join_reward_edit: LineEdit = $rewards_root/join_reward_edit
@onready var trap_reward_edit: LineEdit = $rewards_root/trap_reward_edit
@onready var missle_reward_edit: LineEdit = $rewards_root/missle_edit

var settings: AdminSettings

func _ready() -> void:
	settings = AdminSettings.load_from_file()
	client_id_edit.text = settings.client_id
	client_secret_edit.text = settings.client_secret
	channel_edit.text = settings.channel
	join_reward_edit.text = settings.join_reward
	trap_reward_edit.text = settings.trap_reward
	missle_reward_edit.text = settings.missle_reward

func _on_login_attempt():
	settings.client_id = client_id_edit.text
	settings.client_secret = client_secret_edit.text
	settings.channel = channel_edit.text
	settings.save()
	
	twitch_events.try_login(
		client_id_edit.text,
		client_secret_edit.text,
		channel_edit.text,
	)
	
func _on_rewards_saved():
	settings.join_reward = join_reward_edit.text
	settings.trap_reward = trap_reward_edit.text
	settings.missle_reward = missle_reward_edit.text
	settings.save()
	twitch_events.join_reward = settings.join_reward
	twitch_events.trap_reward = settings.trap_reward
	twitch_events.missile_reward = settings.missle_reward
	self.ui_root.visible = false

class AdminSettings extends Resource:
	var client_id: String
	var client_secret: String
	var channel: String
	var join_reward: String
	var trap_reward: String
	var missle_reward: String
	
	const settings_path := "user://settings.dat"
	
	func save():
		var f = FileAccess.open(settings_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({
			"client_id": self.client_id,
			"client_secret": self.client_secret,
			"channel": self.channel,
			"join_reward": self.join_reward,
			"trap_reward": self.trap_reward,
			"missle_reward": self.missle_reward,
		}))
		f.close()
	
	static func load_from_file() -> AdminSettings:
		var settings := AdminSettings.new()
		if not FileAccess.file_exists(settings_path):
			return settings
		
		var f = FileAccess.open(settings_path, FileAccess.READ)
		
		var c = JSON.parse_string(f.get_as_text())
		settings.client_id = c.client_id
		settings.client_secret = c.client_secret
		settings.channel = c.channel
		settings.join_reward = c.join_reward
		settings.trap_reward = c.trap_reward
		settings.missle_reward = c.missle_reward
		return settings


func _on_twitch_events_twitch_connected() -> void:
	pass # Replace with function body.
