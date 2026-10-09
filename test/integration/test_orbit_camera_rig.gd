extends GutTest
## Integration tests for the OrbitCamera rig scene (scenes/camera/orbit_camera.tscn): needs a tree, a world and frames.


func _make_rig(target: Node3D) -> OrbitCamera:
	var rig: OrbitCamera = load("res://scenes/camera/orbit_camera.tscn").instantiate()
	rig.capture_mouse = false
	rig.target = target
	add_child_autofree(rig)
	return rig


func test_freed_target_is_survived() -> void:
	var target := Node3D.new()
	add_child(target)
	var rig: OrbitCamera = _make_rig(target)
	await wait_frames(2)
	target.free()
	await wait_frames(2)
	rig.snap()
	assert_true(is_instance_valid(rig), "rig still running after its target was freed")


func test_aim_point_ignores_things_between_the_camera_and_the_player() -> void:
	var target := Node3D.new()
	add_child_autofree(target)
	var rig: OrbitCamera = _make_rig(target)
	rig.set_angles(0.0, 0.0)
	var behind := _box(Vector3(0.0, 1.5, 4.0))
	var ahead := _box(Vector3(0.0, 1.5, -10.0))
	await wait_physics_frames(3)
	var hit: Vector3 = rig.aim_point(100.0)
	assert_almost_eq(hit.z, -9.0, 0.05, "hits the box ahead (face at z=-9), not the enemy behind the player")
	behind.free()
	ahead.free()


func _box(pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = pos
	return body
