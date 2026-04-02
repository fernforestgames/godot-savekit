extends RigidBody2D

const Deserializer := preload("res://addons/savekit/deserializer.gd")
const Serializer := preload("res://addons/savekit/serializer.gd")

func save_to_dict(s: Serializer) -> Dictionary:
	return {
		"transform": s.encode_var(transform),
		"linear_velocity": s.encode_var(linear_velocity),
	}

func load_from_dict(s: Deserializer, data: Dictionary) -> void:
	if "transform" in data:
		var transform_to_set: Transform2D = s.decode_var(data["transform"], TYPE_TRANSFORM2D)
		PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, transform_to_set)

	if "linear_velocity" in data:
		linear_velocity = s.decode_var(data["linear_velocity"], TYPE_VECTOR2)
