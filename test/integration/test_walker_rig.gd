extends GutTest
## Integration tests for the walker scene (scenes load, under 1 s each): rest stance, teleport and apply_build.

const WALKER_SCENE: PackedScene = preload("res://scenes/walker/walker.tscn")


func _world() -> Node3D:
	var root := Node3D.new()
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(80.0, 1.0, 80.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	return root


func _add_wall(root: Node3D, z: float) -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 3.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 1.5, z)
	root.add_child(wall)


func _mixed_build(short_rows: Array[int]) -> WalkerBuild:
	var build := WalkerBuild.new()
	for row in 4:
		for side in ["l", "r"]:
			var socket := StringName("leg_%s%d" % [side, row])
			if row in short_rows:
				build.place(socket, PartCatalog.LEG_SHORT)
			elif row < 3 or not short_rows.is_empty():
				build.place(socket, PartCatalog.LEG_MEDIUM)
	build.place(&"top_0", PartCatalog.PULSE_CANNON)
	return build


func test_every_rest_foot_is_within_0_75_of_its_own_reach_for_mixed_builds() -> void:
	var root := _world()
	add_child_autofree(root)
	var walker: WalkerBody = WALKER_SCENE.instantiate()
	root.add_child(walker)
	walker.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, 0.0)))
	# Scout with its rear pair short (6 legs), and 6 medium + 2 short (8 legs).
	var six: WalkerBuild = WalkerBuild.new()
	for socket: StringName in [&"leg_l0", &"leg_l1", &"leg_r0", &"leg_r1"]:
		six.place(socket, PartCatalog.LEG_MEDIUM)
	for socket: StringName in [&"leg_l2", &"leg_r2"]:
		six.place(socket, PartCatalog.LEG_SHORT)
	six.place(&"top_0", PartCatalog.PULSE_CANNON)
	var eight: WalkerBuild = _mixed_build([3])
	for build in [six, eight]:
		assert_true(build.is_valid(), build.invalid_reason())
		walker.apply_build(build)
		for i in walker.leg_count():
			assert_lte(walker.rest_distance_ratio(i), 0.75, "leg %d of %d" % [i, walker.leg_count()])


func test_teleport_before_the_walker_enters_the_tree_is_kept() -> void:
	var root := _world()
	add_child_autofree(root)
	var walker: WalkerBody = WALKER_SCENE.instantiate()
	walker.teleport(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(5.0, 1.5, 7.0)))
	root.add_child(walker)
	assert_almost_eq(walker.global_position.x, 5.0, 0.01)
	assert_almost_eq(walker.global_position.z, 7.0, 0.01)
	assert_almost_eq(walker.yaw_radians(), PI * 0.5, 0.01)


func test_apply_build_pushes_a_bigger_body_out_of_a_wall() -> void:
	var root := _world()
	_add_wall(root, -5.0)
	add_child_autofree(root)
	var walker: WalkerBody = WALKER_SCENE.instantiate()
	root.add_child(walker)
	# A Scout 1.0 m in front of the wall face (wall face at z = -4.5).
	walker.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, -3.5)))
	walker.apply_build(WalkerBuild.strider())
	Input.action_press("move_forward")
	simulate(walker, 10, 1.0 / 60.0)
	Input.action_release("move_forward")
	assert_false(walker.is_overlapping_world(), "no overlap after a few ticks")


func test_scout_pressed_into_a_wall_backs_off_again() -> void:
	var root := _world()
	_add_wall(root, -12.0)
	add_child_autofree(root)
	var walker: WalkerBody = WALKER_SCENE.instantiate()
	root.add_child(walker)
	walker.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, -2.0)))
	Input.action_press("move_forward")
	simulate(walker, 300, 1.0 / 60.0)
	Input.action_release("move_forward")
	var at_wall: Vector3 = walker.global_position
	Input.action_press("move_back")
	simulate(walker, 120, 1.0 / 60.0)
	Input.action_release("move_back")
	assert_gt(walker.global_position.distance_to(at_wall), 1.0, "moved away from the wall")
