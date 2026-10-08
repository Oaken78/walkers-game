extends GutTest
## GDD 9.1 map rules, measured by raycasts (mask layer 1 only) against the BUILT valley collision.
## The layout data (outline, wash, sites, ruins) comes from ValleyLayout, the same file the builder reads.

const VALLEY_SCENE: String = "res://scenes/world/valley.tscn"
const WORLD_MASK: int = 1

var _valley: Valley = null
var _space: PhysicsDirectSpaceState3D = null
var _terrain_body: StaticBody3D = null
var _boulder_body: StaticBody3D = null
var _query: PhysicsRayQueryParameters3D = null
var _poly: PackedVector2Array = PackedVector2Array()


func before_all() -> void:
	_valley = (load(VALLEY_SCENE) as PackedScene).instantiate() as Valley
	add_child(_valley)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_space = _valley.get_world_3d().direct_space_state
	_terrain_body = _valley.get_node("Terrain") as StaticBody3D
	_boulder_body = _valley.get_node("Boulders") as StaticBody3D
	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = WORLD_MASK
	_poly = ValleyLayout.outline()


func after_all() -> void:
	if _valley != null:
		_valley.free()


# ---- helpers ---------------------------------------------------------------------------------------------


func _ray(from: Vector3, to: Vector3, exclude: Array[RID] = []) -> Dictionary:
	_query.from = from
	_query.to = to
	_query.exclude = exclude
	return _space.intersect_ray(_query)


## Downward ray at (x, z); returns the hit dictionary (empty when nothing is below).
func _down(x: float, z: float, exclude: Array[RID] = []) -> Dictionary:
	return _ray(Vector3(x, 200.0, z), Vector3(x, -200.0, z), exclude)


func _terrain_y(x: float, z: float) -> float:
	var hit: Dictionary = _down(x, z, [_boulder_body.get_rid()])
	if hit.is_empty():
		return -1000.0
	return (hit["position"] as Vector3).y


func _slope_deg(normal: Vector3) -> float:
	return rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))


## Outline samples every 5 m: [{"p": Vector2 on the edge, "n": outward unit normal}].
func _outline_samples() -> Array:
	var out: Array = []
	var m: int = _poly.size()
	for i in range(m):
		var a: Vector2 = _poly[i]
		var b: Vector2 = _poly[(i + 1) % m]
		var len: float = a.distance_to(b)
		var d: Vector2 = (b - a) / len
		var perp := Vector2(-d.y, d.x)
		var mid: Vector2 = a + d * (len * 0.5)
		if ValleyLayout.point_in_polygon(mid + perp * 0.5, _poly):
			perp = -perp
		var inset: float = minf(1.0, len * 0.5)
		var t: float = inset
		while t <= len - inset + 0.001:
			out.append({"p": a + d * t, "n": perp})
			t += 5.0
	return out


func _floor_y_at_sample(s: Dictionary) -> float:
	var p: Vector2 = s["p"]
	var n: Vector2 = s["n"]
	var q: Vector2 = p - n * 0.5
	return _terrain_y(q.x, q.y)


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


func _scrap_sites() -> Array:
	return get_tree().get_nodes_in_group("scrap_sites")


func _drone_sites() -> Array:
	return get_tree().get_nodes_in_group("drone_sites")


func _xz(node: Node3D) -> Vector2:
	return Vector2(node.global_position.x, node.global_position.z)


# ---- cliffs ----------------------------------------------------------------------------------------------


func test_every_cliff_sample_rises_30_m_within_17_3_m() -> void:
	var samples: Array = _outline_samples()
	assert_gt(samples.size(), 100, "outline is sampled")
	var bad: Array = []
	for s: Dictionary in samples:
		var p: Vector2 = s["p"]
		var n: Vector2 = s["n"]
		var y0: float = _floor_y_at_sample(s)
		var q: Vector2 = p + n * 17.3
		var rise: float = _terrain_y(q.x, q.y) - y0
		if rise < 30.0:
			bad.append("%s rise %.1f" % [p, rise])
	assert_eq(bad.size(), 0, "cliff samples under 30 m in 17.3 m: %s" % [bad.slice(0, 5)])


func test_no_cliff_foothold_between_1_m_and_30_m_above_the_floor() -> void:
	var bad: Array = []
	for s: Dictionary in _outline_samples():
		var p: Vector2 = s["p"]
		var n: Vector2 = s["n"]
		var y0: float = _floor_y_at_sample(s)
		var origin := Vector3(p.x - n.x * 0.25, 0.0, p.y - n.y * 0.25)
		var dir := Vector3(n.x, 0.0, n.y)
		for h: float in [1.5, 5.0, 10.0, 15.0, 20.0, 25.0, 29.5]:
			var o := Vector3(origin.x, y0 + h, origin.z)
			var hit: Dictionary = _ray(o, o + dir * 2.0)
			if hit.is_empty():
				bad.append("%s no wall at +%.1f" % [p, h])
			elif _slope_deg(hit["normal"]) < 60.0:
				bad.append("%s wall %.0f deg at +%.1f" % [p, _slope_deg(hit["normal"]), h])
		var step: float = 0.5
		while step <= 17.3:
			var q: Vector2 = p + n * step
			var top: Dictionary = _down(q.x, q.y)
			if not top.is_empty():
				var rel: float = (top["position"] as Vector3).y - y0
				if rel > 1.0 and rel < 30.0 and _slope_deg(top["normal"]) < 60.0:
					bad.append("%s foothold %.1f m up, %.0f deg" % [q, rel, _slope_deg(top["normal"])])
			step += 0.8
	assert_eq(bad.size(), 0, "cliff problems: %s" % [bad.slice(0, 5)])


func test_ruins_close_the_valley_between_270_and_300_m() -> void:
	var bad: Array = []
	var x: float = -99.0
	while x < 96.0:
		for rel: float in [3.0, 15.0, 29.0]:
			var y: float = ValleyLayout.tilt(270.0) + rel
			var hit: Dictionary = _ray(Vector3(x, y, 240.0), Vector3(x, y, 330.0))
			if hit.is_empty():
				bad.append("x %.0f open at +%.0f" % [x, rel])
			else:
				var z: float = (hit["position"] as Vector3).z
				if z < 269.9 or z > 300.0:
					bad.append("x %.0f wall at z %.1f" % [x, z])
		x += 2.0
	assert_eq(bad.size(), 0, "ruins line: %s" % [bad.slice(0, 5)])


# ---- floor -----------------------------------------------------------------------------------------------


func test_floor_is_at_least_150_m_wide_from_bench_to_ruins() -> void:
	var z: float = 0.0
	while z <= 260.0:
		var count: int = 0
		var x: float = -119.0
		while x < 120.0:
			var hit: Dictionary = _down(x, z)
			if not hit.is_empty() and (hit["position"] as Vector3).y < ValleyLayout.tilt(z) + 12.0:
				count += 1
			x += 2.0
		assert_gte(float(count) * 2.0, 150.0, "floor width at z=%.0f" % z)
		z += 10.0


func test_floor_slope_is_at_most_28_deg() -> void:
	var worst: float = 0.0
	var worst_at := Vector2.ZERO
	var checked: int = 0
	for j in range(0, 157):
		for i in range(0, 98):
			var odd: bool = (i + j) % 2 == 0
			var x: float = -100.0 + 2.0 * i + (1.4 if odd else 0.6)
			var z: float = -30.0 + 2.0 * j + (0.6 if odd else 1.4)
			if x > 94.0 or not ValleyLayout.point_in_polygon(Vector2(x, z), _poly):
				continue
			var hit: Dictionary = _down(x, z)
			if hit.is_empty() or hit["collider"] != _terrain_body:
				continue
			checked += 1
			var slope: float = _slope_deg(hit["normal"])
			if slope > worst:
				worst = slope
				worst_at = Vector2(x, z)
	gut.p("floor slope max %.1f deg at %s over %d rays" % [worst, worst_at, checked])
	assert_gt(checked, 10000, "enough floor rays")
	assert_lte(worst, 28.0, "steepest floor surface at %s" % worst_at)


func test_wash_has_bumpy_patches_between_20_and_28_deg() -> void:
	var patches_near_wash: int = 0
	for patch: Array in ValleyLayout.BUMP_PATCHES:
		var worst: float = 0.0
		var centre := Vector2.ZERO
		for mound: Array in patch:
			centre += Vector2(mound[0], mound[1]) / float(patch.size())
			var r: float = mound[2]
			var x: float = mound[0] - r
			while x <= mound[0] + r:
				var z: float = mound[1] - r
				while z <= mound[1] + r:
					var hit: Dictionary = _down(x, z)
					if not hit.is_empty() and hit["collider"] == _terrain_body:
						worst = maxf(worst, _slope_deg(hit["normal"]))
					z += 1.0
				x += 1.0
		gut.p("patch at %s peak slope %.1f deg" % [centre, worst])
		assert_gte(worst, 20.0, "patch %s peak slope" % centre)
		assert_lte(worst, 28.0, "patch %s peak slope" % centre)
		if ValleyLayout.wash_nearest(centre)["dist"] <= 40.0:
			patches_near_wash += 1
	assert_gte(patches_near_wash, 2, "at least 2 patches on or beside the wash")


func test_workshop_pad_is_flat_and_20_to_40_m_from_the_head_wall() -> void:
	var worst: float = 0.0
	var y_min: float = 1000.0
	var y_max: float = -1000.0
	var x: float = -12.0
	while x <= 12.0:
		var z: float = -12.0
		while z <= 12.0:
			var hit: Dictionary = _down(x, z)
			worst = maxf(worst, _slope_deg(hit["normal"]))
			var y: float = (hit["position"] as Vector3).y
			y_min = minf(y_min, y)
			y_max = maxf(y_max, y)
			z += 2.0
		x += 2.0
	assert_lte(worst, 3.0, "pad slope")
	assert_lt(y_max - y_min, 0.05, "pad is level")
	var wall_z: float = 0.0
	var z2: float = 0.0
	while z2 > -80.0:
		var hit2: Dictionary = _down(0.0, z2)
		if (hit2["position"] as Vector3).y > ValleyLayout.tilt(z2) + 5.0:
			wall_z = -z2
			break
		z2 -= 0.5
	assert_between(wall_z, 20.0, 40.0, "workshop to head wall distance")
	var site: Marker3D = _valley.get_node("%WorkshopSite") as Marker3D
	assert_almost_eq(site.global_position, Vector3.ZERO, Vector3(0.05, 0.05, 0.05))


func test_workshop_site_faces_down_valley() -> void:
	var site: Marker3D = _valley.get_node("%WorkshopSite") as Marker3D
	var forward: Vector3 = -site.global_transform.basis.z
	assert_almost_eq(forward, Vector3(0.0, 0.0, 1.0), Vector3(0.01, 0.01, 0.01))


func test_wash_path_runs_from_the_workshop_to_the_ruins() -> void:
	var path: Path3D = _valley.get_node("%WashPath") as Path3D
	var curve: Curve3D = path.curve
	var n: int = curve.point_count
	assert_gt(n, 50, "wash has many points")
	var first: Vector3 = curve.get_point_position(0)
	var last: Vector3 = curve.get_point_position(n - 1)
	assert_lte(Vector2(first.x, first.z).length(), 10.0, "starts within 10 m of the workshop")
	var best: float = INF
	for b: Dictionary in ValleyLayout.RUIN_BLOCKS:
		var rect := Rect2(b["x0"], b["front"], float(b["x1"]) - float(b["x0"]), 20.0)
		var nearest := Vector2(
			clampf(last.x, rect.position.x, rect.end.x), clampf(last.z, rect.position.y, rect.end.y)
		)
		best = minf(best, Vector2(last.x, last.z).distance_to(nearest))
	assert_lte(best, 15.0, "ends within 15 m of the ruins")
	var worst_off: float = 0.0
	var deepest: float = 0.0
	for i in range(n):
		var p: Vector3 = curve.get_point_position(i)
		worst_off = maxf(worst_off, absf(p.y - _terrain_y(p.x, p.z)))
		deepest = maxf(deepest, ValleyLayout.tilt(p.z) + ValleyLayout.dune(p.z) - p.y)
	assert_lte(worst_off, 0.25, "path points sit on the floor")
	assert_lte(deepest, 1.0, "wash is at most 1 m deep")
	assert_gt(last.z - first.z, 230.0, "wash runs down-valley")


# ---- ledge pocket ----------------------------------------------------------------------------------------


func test_ledge_rise_is_0_8_m_along_the_whole_entrance() -> void:
	var z: float = ValleyLayout.LEDGE_Z0 + 0.5
	var count: int = 0
	while z < ValleyLayout.LEDGE_Z1:
		var front: float = _terrain_y(ValleyLayout.WALL_LEFT_X + 0.3, z)
		var behind: float = _terrain_y(ValleyLayout.WALL_LEFT_X - 0.3, z)
		assert_between(behind - front, 0.75, 0.85, "ledge rise at z=%.1f" % z)
		count += 1
		z += 1.0
	assert_eq(count, 16, "rays along the 16 m entrance")


func test_ledge_face_is_vertical_and_its_apron_flat() -> void:
	var apron_y: float = ValleyLayout.ledge_apron_y()
	var z: float = ValleyLayout.LEDGE_Z0 + 1.0
	while z < ValleyLayout.LEDGE_Z1:
		var o := Vector3(ValleyLayout.WALL_LEFT_X + 6.0, apron_y + 0.4, z)
		var hit: Dictionary = _ray(o, o + Vector3(-12.0, 0.0, 0.0))
		assert_false(hit.is_empty(), "face hit at z=%.0f" % z)
		if not hit.is_empty():
			assert_gte(_slope_deg(hit["normal"]), 80.0, "ledge face angle")
			assert_almost_eq((hit["position"] as Vector3).x, ValleyLayout.WALL_LEFT_X, 0.05)
		z += 2.0
	var lo: float = INF
	var hi: float = -INF
	var x: float = ValleyLayout.WALL_LEFT_X
	while x <= ValleyLayout.WALL_LEFT_X + 10.0:
		var z2: float = ValleyLayout.LEDGE_Z0
		while z2 <= ValleyLayout.LEDGE_Z1:
			var y: float = _terrain_y(x + 0.01, z2)
			lo = minf(lo, y)
			hi = maxf(hi, y)
			z2 += 2.0
		x += 2.0
	assert_lte(hi - lo, 0.1, "apron height variation over 10 m x 16 m")
	var worst: float = 0.0
	var ax: float = ValleyLayout.WALL_LEFT_X - 13.0
	while ax < ValleyLayout.WALL_LEFT_X - 1.0:
		var az: float = ValleyLayout.LEDGE_Z0 + 1.0
		while az < ValleyLayout.LEDGE_Z1:
			worst = maxf(worst, _slope_deg(_down(ax, az)["normal"]))
			az += 2.0
		ax += 2.0
	assert_lte(worst, 10.0, "alcove floor slope")


func test_ledge_pocket_is_160_to_240_m_out_on_the_right_hand_wall() -> void:
	var c: Vector2 = ValleyLayout.entrance_center("ledge")
	assert_between(c.length(), 160.0, 240.0, "entrance distance")
	assert_lt(c.x, 0.0, "ledge is on the -X (right-hand, looking down-valley) wall")
	assert_gte(c.y, 0.0, "down-valley of the workshop")
	var width: float = ValleyLayout.LEDGE_Z1 - ValleyLayout.LEDGE_Z0
	assert_gte(width, 15.0, "alcove width")
	assert_gte(ValleyLayout.LEDGE_DEPTH, 12.0, "alcove depth")
	var floor_y: float = _terrain_y(c.x - 6.0, c.y)
	assert_almost_eq(floor_y, ValleyLayout.ledge_apron_y() + 0.8, 0.02, "alcove floor measured")
	var hit: Dictionary = _ray(Vector3(c.x - 6.0, floor_y + 1.0, c.y), Vector3(c.x - 40.0, floor_y + 1.0, c.y))
	assert_false(hit.is_empty(), "alcove is closed at the back")
	assert_gte(absf((hit["position"] as Vector3).x - c.x), 12.0, "alcove at least 12 m deep (measured)")
	var area: Area3D = _valley.get_node("%LedgePocket") as Area3D
	assert_not_null(area)


# ---- talus pocket ----------------------------------------------------------------------------------------


func test_talus_face_is_38_to_42_deg_and_rises_at_least_4_m() -> void:
	var width_hits: int = 0
	var z: float = ValleyLayout.TALUS_Z0 + 0.5
	while z < ValleyLayout.TALUS_Z1:
		var x: float = ValleyLayout.WALL_RIGHT_X + 0.25
		while x < ValleyLayout.WALL_RIGHT_X + ValleyLayout.TALUS_SLOPE_LEN:
			var hit: Dictionary = _down(x, z)
			assert_between(_slope_deg(hit["normal"]), 38.0, 42.0, "talus surface at (%.2f, %.1f)" % [x, z])
			x += 0.75
		width_hits += 1
		z += 1.0
	assert_gte(float(width_hits), 10.0, "talus is at least 10 m wide")
	var apron: float = _terrain_y(ValleyLayout.WALL_RIGHT_X - 4.0, 170.0)
	var shelf: float = _terrain_y(ValleyLayout.WALL_RIGHT_X + 12.0, 170.0)
	assert_gte(shelf - apron, 4.0, "shelf height above the apron")
	var shelf_hit: Dictionary = _down(ValleyLayout.WALL_RIGHT_X + 12.0, 170.0)
	assert_lte(_slope_deg(shelf_hit["normal"]), 3.0, "shelf is flat")


func test_talus_has_no_lip_over_0_3_m() -> void:
	var prev: float = _terrain_y(ValleyLayout.WALL_RIGHT_X - 6.0, 170.0)
	var x: float = ValleyLayout.WALL_RIGHT_X - 5.75
	var biggest: float = 0.0
	while x <= ValleyLayout.WALL_RIGHT_X + 10.0:
		var y: float = _terrain_y(x, 170.0)
		biggest = maxf(biggest, absf(y - prev))
		prev = y
		x += 0.25
	assert_lte(biggest, 0.3, "largest height change per 0.25 m")


func test_talus_pocket_is_150_to_220_m_out_on_the_left_hand_wall() -> void:
	var c: Vector2 = ValleyLayout.entrance_center("talus")
	assert_between(c.length(), 150.0, 220.0, "entrance distance")
	assert_gt(c.x, 0.0, "talus is on the +X (left-hand) wall")
	var area: Area3D = _valley.get_node("%TalusPocket") as Area3D
	assert_not_null(area)


# ---- boulders --------------------------------------------------------------------------------------------


func _boulder_shapes() -> Array:
	var out: Array = []
	for child: Node in _boulder_body.get_children():
		if child is CollisionShape3D:
			out.append(child)
	return out


func test_boulders_are_0_3_to_1_0_m_tall() -> void:
	var shapes: Array = _boulder_shapes()
	assert_gte(shapes.size(), 20, "at least 20 boulders")
	var exclude: Array[RID] = [_boulder_body.get_rid()]
	for cs: CollisionShape3D in shapes:
		var p: Vector3 = cs.global_position
		var top: Dictionary = _down(p.x, p.z)
		assert_eq(top["collider"], _boulder_body, "ray hits the boulder %s" % cs.name)
		var ground: Dictionary = _down(p.x, p.z, exclude)
		var h: float = (top["position"] as Vector3).y - (ground["position"] as Vector3).y
		assert_between(h, 0.29, 1.01, "%s height" % cs.name)


func test_no_boulder_near_the_wash_centreline_or_a_pocket_entrance() -> void:
	for cs: CollisionShape3D in _boulder_shapes():
		var p := Vector2(cs.global_position.x, cs.global_position.z)
		assert_gte(float(ValleyLayout.wash_nearest(p)["dist"]), 4.0, "%s vs wash" % cs.name)
		for e: Dictionary in ValleyLayout.entrances():
			assert_gte(_dist_to_segment(p, e["a"], e["b"]), 15.0, "%s vs %s entrance" % [cs.name, e["name"]])


# ---- markers ---------------------------------------------------------------------------------------------


func test_scrap_sites_match_the_ring_table() -> void:
	var rings: Dictionary = {0: [], 1: [], 2: [], 3: []}
	var names: Dictionary = {}
	for node: Node in _scrap_sites():
		var s := node as ScrapSite
		assert_false(names.has(s.name), "unique name %s" % s.name)
		names[s.name] = true
		assert_eq(s.ring, ValleyLayout.ring_of(_xz(s).length()), "%s ring matches distance" % s.name)
		if s.in_pocket:
			rings[3].append(s)
		else:
			rings[s.ring].append(s)
	assert_eq(rings[0].size(), 2, "ring 0 sites")
	assert_eq(rings[1].size(), 3, "ring 1 sites")
	assert_eq(rings[2].size(), 3, "ring 2 sites")
	assert_eq(rings[3].size(), 2, "pocket sites")
	for s: ScrapSite in rings[0]:
		assert_eq(s.amount, 5)
		assert_false(s.respawns)
	for s: ScrapSite in rings[1]:
		assert_eq(s.amount, 10)
		assert_true(s.respawns)
	for s: ScrapSite in rings[2]:
		assert_eq(s.amount, 20)
		assert_true(s.respawns)


func test_each_pocket_holds_one_60_scrap_site() -> void:
	for pocket: String in ["%LedgePocket", "%TalusPocket"]:
		var area: Area3D = _valley.get_node(pocket) as Area3D
		var shape: CollisionShape3D = area.get_node("Shape") as CollisionShape3D
		var box: BoxShape3D = shape.shape as BoxShape3D
		var found: int = 0
		for node: Node in _scrap_sites():
			var s := node as ScrapSite
			var local: Vector3 = shape.global_transform.affine_inverse() * s.global_position
			if absf(local.x) <= box.size.x * 0.5 and absf(local.y) <= box.size.y * 0.5 and absf(local.z) <= box.size.z * 0.5:
				found += 1
				assert_eq(s.amount, 60, "%s amount" % pocket)
				assert_true(s.in_pocket, "%s flagged" % pocket)
		assert_eq(found, 1, "%s holds one site" % pocket)
		assert_eq(area.collision_layer, 64, "%s is on layer 7" % pocket)
		assert_eq(area.collision_mask, 2, "%s watches layer 2" % pocket)


func test_wash_scrap_sites_are_70_to_110_m_apart_along_the_path() -> void:
	var on_wash: Array = []
	for node: Node in _scrap_sites():
		var s := node as ScrapSite
		var near: Dictionary = ValleyLayout.wash_nearest(_xz(s))
		var d: float = near["dist"]
		if d <= 8.0:
			on_wash.append(float(near["s"]))
		elif not s.in_pocket:
			assert_between(d, 20.0, 70.0, "%s off-wash distance" % s.name)
	assert_gte(on_wash.size(), 3, "at least 3 sites on the wash")
	on_wash.sort()
	for i in range(1, on_wash.size()):
		assert_between(float(on_wash[i]) - float(on_wash[i - 1]), 70.0, 110.0, "wash spacing %d" % i)


func test_drone_sites_match_gdd_9_1() -> void:
	var by_ring: Dictionary = {0: 0, 1: 0, 2: 0}
	var wash_sites: int = 0
	var guard: int = 0
	var ledge_c: Vector2 = ValleyLayout.entrance_center("ledge")
	var dists: Array = []
	for node: Node in _drone_sites():
		var d := node as DroneSite
		var dist: float = _xz(d).length()
		assert_eq(d.ring, ValleyLayout.ring_of(dist), "%s ring matches distance" % d.name)
		by_ring[d.ring] += 1
		if float(ValleyLayout.wash_nearest(_xz(d))["dist"]) <= 15.0:
			wash_sites += 1
			dists.append(dist)
			if d.ring == 1:
				assert_between(dist, 130.0, 148.0, "ring 1 drone site distance")
				assert_gte(d.min_drones, 1)
				assert_lte(d.max_drones, 2)
			else:
				assert_gte(d.min_drones, 2)
				assert_lte(d.max_drones, 3)
		if _xz(d).distance_to(ledge_c) <= 25.0:
			guard += 1
			assert_eq(d.min_drones, 1)
			assert_eq(d.max_drones, 1)
	assert_eq(by_ring[0], 0, "no ring 0 drones")
	assert_eq(wash_sites, 3, "three wash drone sites")
	assert_eq(guard, 1, "one ledge guard drone")
	var in_180_200: bool = false
	var in_225_245: bool = false
	for dist: float in dists:
		if dist >= 180.0 and dist <= 200.0:
			in_180_200 = true
		if dist >= 225.0 and dist <= 245.0:
			in_225_245 = true
	assert_true(in_180_200, "a drone site at 180-200 m")
	assert_true(in_225_245, "a drone site at 225-245 m")


func test_markers_sit_on_the_floor() -> void:
	var markers: Array = _scrap_sites() + _drone_sites()
	assert_eq(markers.size(), 14, "10 scrap + 4 drone sites")
	for node: Node in markers:
		var m := node as Marker3D
		var hit: Dictionary = _down(m.global_position.x, m.global_position.z)
		var above: float = m.global_position.y - (hit["position"] as Vector3).y
		assert_between(above, -0.01, 0.2, "%s height above collision" % m.name)


# ---- far end, smoke, layers -----------------------------------------------------------------------------


func test_smoke_column_is_visible_from_the_workshop() -> void:
	var smoke: MeshInstance3D = _valley.get_node("Smoke") as MeshInstance3D
	assert_between(smoke.global_position.z, 330.0, 370.0, "smoke distance")
	var cyl: CylinderMesh = smoke.mesh as CylinderMesh
	assert_gte(cyl.height, 80.0, "smoke height")
	var base_y: float = smoke.global_position.y - 0.5 * cyl.height
	var target := Vector3(0.0, base_y + 60.0, smoke.global_position.z)
	var hit: Dictionary = _ray(Vector3(0.0, 3.0, 0.0), target)
	assert_true(hit.is_empty(), "nothing on layer 1 blocks the view of the column")
	assert_eq(smoke.find_children("*", "CollisionObject3D", true, false).size(), 0, "smoke has no collision")


func test_world_bodies_use_layer_1_only_and_pocket_areas_layer_7() -> void:
	var bodies: Array = _valley.find_children("*", "StaticBody3D", true, false)
	assert_gte(bodies.size(), 2)
	for b: Node in bodies:
		var body := b as StaticBody3D
		assert_eq(body.collision_layer, 1, "%s layer" % body.name)
	var areas: Array = _valley.find_children("*", "Area3D", true, false)
	assert_eq(areas.size(), 2, "two pocket areas")
	for a: Node in areas:
		var area := a as Area3D
		assert_eq(area.collision_layer, 64, "%s layer" % area.name)
		assert_eq(area.collision_mask, 2, "%s mask" % area.name)
