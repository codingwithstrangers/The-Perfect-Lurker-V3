extends Node
class_name Debugger

@export var debug_line_prefab: PackedScene
@onready var line_parent: Node = $scroll_container/vertical_container

# key: name of line
# value: DebugLine
var lines = {}


func _on_clear_pressed():
	lines.clear()
	for i in range(1, line_parent.get_child_count()):
		line_parent.get_child(i).queue_free()


func _on_close_pressed():
	self.visible = false


func _on_enable_all_pressed():
	for line in lines.values():
		(line as DebugLine).enabled = true


func _on_disable_all_pressed():
	for line in lines.values():
		(line as DebugLine).enabled = false


func _process(_delta: float):
	if Input.is_action_just_pressed('ui_undo'):
		self.visible = !self.visible


func create_line(key: String):
	var new_line = debug_line_prefab.instantiate()
	line_parent.add_child(new_line)
	new_line.name = key
	
	var line = new_line.get_node(".") as DebugLine
	lines[key] = line
	line.key = key


func report(key: String, value: String):
	if !lines.has(key):
		self.create_line(key)

	var line = lines[key] as DebugLine
	line.value = value
