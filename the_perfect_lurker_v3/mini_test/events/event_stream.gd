extends Node
class_name EventStream

signal join_race_attempted(username: String, profile_url: String)
signal leave_race_attempted(username: String)
signal trap_drop_attempted(username: String)
signal missle_launch_attempted(username: String)
signal joined_race(lurker: Lurker)
signal lurker_chat(username: String)
signal send_chat(message: String)
signal send_to_pit(username: String)
#signal send_to_track(username: String)
