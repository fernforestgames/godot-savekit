extends Area2D

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_dragging = true
			_drag_offset = global_position - get_global_mouse_position()


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_dragging = false
	elif event is InputEventMouseMotion:
		global_position = get_global_mouse_position() + _drag_offset
