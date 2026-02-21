yupextends Node
class_name RuntimeLogger

@export var event_stream: NodePath
@export var twitch_events: NodePath
@export var lurker_gang: NodePath
@export var ui_root: NodePath

var _log_file: FileAccess
var _log_path: String = ""

func _ready() -> void:
	_open_log_file()
	_log("INFO", "Runtime logger started", {
		"godot": Engine.get_version_info().get("string", "unknown"),
		"os": OS.get_name(),
		"platform": OS.get_distribution_name()
	})
	_connect_backend_signals()
	_connect_frontend_signals()

func _open_log_file() -> void:
	if not DirAccess.dir_exists_absolute("user://logs"):
		DirAccess.make_dir_recursive_absolute("user://logs")
	var stamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	_log_path = "user://logs/runtime_" + stamp + ".log"
	_log_file = FileAccess.open(_log_path, FileAccess.WRITE)
	print("[LOGGER] writing runtime logs to: ", _log_path)

func _log(level: String, message: String, details: Variant = null) -> void:
	var now = Time.get_datetime_string_from_system()
	var line = "[" + now + "] [" + level + "] " + message
	if details != null:
		line += " | " + str(details)
	print(line)
	if _log_file != null:
		_log_file.store_line(line)
		_log_file.flush()

func _connect_backend_signals() -> void:
	var event_stream_node = get_node_or_null(event_stream)
	if event_stream_node != null:
		_safe_connect(event_stream_node, "join_race_attempted", func(username, _profile_url): _log("EVENT", "join_race_attempted", {"user": username}))
		_safe_connect(event_stream_node, "leave_race_attempted", func(username): _log("EVENT", "leave_race_attempted", {"user": username}))
		_safe_connect(event_stream_node, "trap_drop_attempted", func(username): _log("EVENT", "trap_drop_attempted", {"user": username}))
		_safe_connect(event_stream_node, "missle_launch_attempted", func(username): _log("EVENT", "missle_launch_attempted", {"user": username}))
		_safe_connect(event_stream_node, "kick_user", func(username): _log("EVENT", "kick_user", {"user": username}))
		_safe_connect(event_stream_node, "unban_user", func(username): _log("EVENT", "unban_user", {"user": username}))
		_safe_connect(event_stream_node, "system_message", func(message): _log("SYSTEM", "system_message", {"message": message}))
		_safe_connect(event_stream_node, "send_chat", func(message): _log("CHAT_OUT", "send_chat", {"message": message}))
		_safe_connect(event_stream_node, "trap_hit", func(trap_type, hit_by, dropped_by): _log("EVENT", "trap_hit", {"trap_type": trap_type, "hit_by": hit_by, "dropped_by": dropped_by}))
		_safe_connect(event_stream_node, "trap_shield_hit", func(trap_type, dropped_by, hit_by, before, after): _log("EVENT", "trap_shield_hit", {"trap_type": trap_type, "dropped_by": dropped_by, "hit_by": hit_by, "before": before, "after": after}))
	else:
		_log("WARN", "event_stream node not found", null)

	var twitch_node = get_node_or_null(twitch_events)
	if twitch_node != null:
		_safe_connect(twitch_node, "twitch_connected", func(): _log("TWITCH", "twitch_connected", null))
		_safe_connect(twitch_node, "twitch_disconnected", func(): _log("TWITCH", "twitch_disconnected", null))
		_safe_connect(twitch_node, "twitch_unavailable", func(): _log("TWITCH", "twitch_unavailable", null))
		_safe_connect(twitch_node, "events_connected", func(): _log("TWITCH", "events_connected", null))
		_safe_connect(twitch_node, "events_disconnected", func(): _log("TWITCH", "events_disconnected", null))
		_safe_connect(twitch_node, "events_unavailable", func(): _log("TWITCH", "events_unavailable", null))
		_safe_connect(twitch_node, "user_token_valid", func(): _log("TOKEN", "user_token_valid", null))
		_safe_connect(twitch_node, "user_token_invalid", func(): _log("TOKEN", "user_token_invalid", null))
		_safe_connect(twitch_node, "token_refresh_status", func(status, details): _log("TOKEN_REFRESH", status, details))
		_safe_connect(twitch_node, "login_attempt", func(success): _log("TWITCH", "login_attempt", {"success": success}))
		_safe_connect(twitch_node, "chat_message", func(sender_data, message): _log("CHAT_IN", "chat_message", {"user": sender_data.user, "message": message}))
		_safe_connect(twitch_node, "event", func(event_type, data): _log("EVENTSUB", "event", {"type": event_type, "keys": data.keys()}))
	else:
		_log("WARN", "twitch_events node not found", null)

func _connect_frontend_signals() -> void:
	var ui_node = get_node_or_null(ui_root)
	if ui_node == null:
		_log("WARN", "ui_root node not found", null)
		return

	var login_button = ui_node.get_node_or_null("form_root/login_root/login_button")
	if login_button != null:
		_safe_connect(login_button, "pressed", func(): _log("UI", "login_button pressed", null))

	var start_button = ui_node.get_node_or_null("form_root/rewards_root/start_button")
	if start_button != null:
		_safe_connect(start_button, "pressed", func(): _log("UI", "start_button pressed", null))

func _safe_connect(emitter: Object, signal_name: String, callback: Callable) -> void:
	if emitter == null:
		return
	if not emitter.has_signal(signal_name):
		return
	var err = emitter.connect(signal_name, callback)
	if err != OK and err != ERR_ALREADY_IN_USE:
		_log("WARN", "failed to connect signal", {"signal": signal_name, "error": err})
