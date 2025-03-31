extends Node
class_name DebugLine

@onready var enable_check: CheckButton = $debug_enable
@onready var key_label: Label = $debug_key
@onready var value_label: Label = $debug_value

var enabled: bool:
	set(v):
		value_label.visible = v
		enable_check.button_pressed = v
		enabled = v

var key: String:
	set(v):
		key_label.text = v
		key = v

var value: String:
	set(v):
		value_label.text = v
		value = v

func _on_enable_pressed(v: bool):
	self.enabled = v
