extends RigidBody2D

func save_to_dict() -> Dictionary:
	return {
		"transform": JSON.from_native(transform),
		"linear_velocity": JSON.from_native(linear_velocity),
	}

func load_from_dict(data: Dictionary) -> void:
	if "transform" in data:
		var transform_to_set: Transform2D = JSON.to_native(data["transform"])
		PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, transform_to_set)

	if "linear_velocity" in data:
		linear_velocity = JSON.to_native(data["linear_velocity"])
