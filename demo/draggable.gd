extends Area2D

## Each box owns a BoxData resource that tracks its click count. This demonstrates how SaveKitResources are serialized alongside nodes.
@export var data: BoxData

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _count_label: Label

func _ready() -> void:
	if not data:
		data = BoxData.new()
		data.label = name

	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.position = Vector2(-35, -35)
	_count_label.size = Vector2(70, 70)
	add_child(_count_label)
	_update_label()

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_dragging = true
			_drag_offset = global_position - get_global_mouse_position()
			data.click_count += 1
			_update_label()

func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_dragging = false
	elif event is InputEventMouseMotion:
		global_position = get_global_mouse_position() + _drag_offset

func load_from_dict(s: SaveKitDeserializer, dict: Dictionary) -> void:
	s.default_load_from_dict(self , dict)
	_update_label()

func _update_label() -> void:
	if _count_label and data:
		_count_label.text = "%s\n%d" % [data.label, data.click_count]
