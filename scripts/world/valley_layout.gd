class_name ValleyLayout
extends RefCounted
## Authored data and pure math for the M0 valley (GDD 9.1). Fixed numbers, no random worlds.
## The terrain builder, the valley scene and test_valley_geometry.gd all read this file, so the test
## checks the BUILT collision against the same numbers the builder used.
## Frame: 1 unit = 1 m, workshop at the origin, down-valley is +Z, the ledge pocket is on -X, the talus on +X.

const CELL: float = 2.0
const GRID_X0: float = -200.0
const GRID_Z0: float = -60.0
const GRID_NX: int = 200
const GRID_NZ: int = 220

## Overall fall of the valley floor down-valley (degrees, GDD range 0-10).
const FALL_DEG: float = 2.0
## Cliff plateau height above the local floor line: 42 m plus a slow wobble (range 38..46 m).
const PLATEAU_BASE: float = 42.0
## Far end: the floor stops at the ruins; the cliff behind them begins here.
const RUINS_BACK_Z: float = 286.0
## Dune bank in front of the ruins: height at the ruins and the z where it starts.
const DUNE_HEIGHT: float = 8.0
const DUNE_START_Z: float = 236.0

const HEAD_WALL_Z: float = -30.0
const HEAD_WOBBLE_FULL_Z: float = -30.0
const HEAD_WOBBLE_END_Z: float = -10.0
const WALL_LEFT_X: float = -100.0
const WALL_RIGHT_X: float = 96.0

## Ledge pocket (west wall, -X): entrance on x = -100, alcove 14 m deep, floor LEDGE_RISE above the apron.
const LEDGE_Z0: float = 182.0
const LEDGE_Z1: float = 198.0
const LEDGE_DEPTH: float = 14.0
const LEDGE_RISE: float = 1.2
## Talus pocket (east wall, +X): entrance on x = 96, 12 m wide, 40 deg slope 6 m long, then a flat shelf.
const TALUS_Z0: float = 164.0
const TALUS_Z1: float = 176.0
const TALUS_DEPTH: float = 18.0
const TALUS_SLOPE_LEN: float = 4.9
const TALUS_DEG: float = 40.0

const WASH_HALF_WIDTH: float = 5.0
const WASH_DEPTH: float = 1.0

## Ruin blocks, west to east: x0, x1, front z (where the floor ends), top height above the floor line at the
## ruins. Blocks touch, so there are no slots a foot or the camera could snag in.
const RUIN_BLOCKS: Array = [
	{"x0": -100.0, "x1": -76.0, "front": 272.0, "h": 44.0},
	{"x0": -76.0, "x1": -50.0, "front": 278.0, "h": 40.0},
	{"x0": -50.0, "x1": -24.0, "front": 270.0, "h": 66.0},
	{"x0": -24.0, "x1": 4.0, "front": 276.0, "h": 40.0},
	{"x0": 4.0, "x1": 28.0, "front": 270.0, "h": 52.0},
	{"x0": 28.0, "x1": 52.0, "front": 280.0, "h": 40.0},
	{"x0": 52.0, "x1": 76.0, "front": 272.0, "h": 72.0},
	{"x0": 76.0, "x1": 96.0, "front": 276.0, "h": 42.0},
]

## Crowns on the two tallest towers (separate bodies on top of the blocks, far above the 30 m cliff band):
## block index, x centre, width (x), depth (z), height, lean about Z in degrees. Leaning pieces and the
## gap between two crowns give the notched, ruined skyline.
const RUIN_CROWNS: Array = [
	{"block": 2, "x": -42.0, "w": 8.0, "d": 10.0, "h": 14.0, "lean": 7.0},
	{"block": 2, "x": -31.0, "w": 8.0, "d": 10.0, "h": 5.0, "lean": 0.0},
	{"block": 6, "x": 57.0, "w": 8.0, "d": 10.0, "h": 8.0, "lean": 0.0},
	{"block": 6, "x": 68.0, "w": 8.0, "d": 10.0, "h": 17.0, "lean": -8.0},
]

## Bump mounds (cosine bumps): x, z, radius, amplitude. Peak slope = amplitude * PI / (2 * radius).
const BUMP_PATCHES: Array = [
	[[56.0, 72.0, 8.0, 2.1], [58.0, 92.0, 8.0, 2.1], [64.0, 110.0, 8.0, 2.1]],
	[[-64.0, 198.0, 8.0, 2.1], [-62.0, 216.0, 8.0, 2.1], [-24.0, 222.0, 8.0, 2.1]],
	[[-2.0, 178.0, 8.0, 2.1], [-14.0, 196.0, 8.0, 2.1]],
]

## Dry wash centreline waypoints (x, z). Smoothed with Catmull-Rom into a dense polyline.
## Arc length s is measured from the first waypoint everywhere (curve, sites, boulders, nearest-point).
const WASH_WAYPOINTS: Array = [
	[2.0, 8.0],
	[10.0, 34.0],
	[30.0, 60.0],
	[46.0, 86.0],
	[44.0, 114.0],
	[24.0, 140.0],
	[-8.0, 160.0],
	[-34.0, 182.0],
	[-44.0, 210.0],
	[-30.0, 236.0],
	[-10.0, 250.0],
	[4.0, 262.0],
]

## Scrap sites. Either "pos" (x, z) or "wash_s" (arc length along the wash) plus a sideways "offset".
const SCRAP_SITES: Array = [
	{"name": "ScrapSite_R0_Wash", "ring": 0, "amount": 5, "respawns": false, "wash_s": 40.0, "offset": 2.5},
	{"name": "ScrapSite_R0_Off", "ring": 0, "amount": 5, "respawns": false, "pos": [-40.0, 28.0]},
	{"name": "ScrapSite_R1_Wash", "ring": 1, "amount": 10, "respawns": true, "wash_s": 120.0, "offset": -3.0},
	{"name": "ScrapSite_R1_OffA", "ring": 1, "amount": 10, "respawns": true, "pos": [-12.0, 84.0]},
	{"name": "ScrapSite_R1_OffB", "ring": 1, "amount": 10, "respawns": true, "pos": [84.0, 100.0]},
	{"name": "ScrapSite_R2_Wash", "ring": 2, "amount": 20, "respawns": true, "wash_s": 200.0, "offset": 3.0},
	{"name": "ScrapSite_R2_OffA", "ring": 2, "amount": 20, "respawns": true, "pos": [14.0, 196.0]},
	{"name": "ScrapSite_R2_OffB", "ring": 2, "amount": 20, "respawns": true, "pos": [20.0, 236.0]},
	{"name": "ScrapSite_Ledge", "ring": 2, "amount": 60, "respawns": true, "pos": [-107.0, 190.0], "in_pocket": true},
	{"name": "ScrapSite_Talus", "ring": 2, "amount": 60, "respawns": true, "pos": [103.5, 170.0], "in_pocket": true},
]

const DRONE_SITES: Array = [
	{"name": "DroneSite_R1_Wash", "ring": 1, "min": 1, "max": 2, "wash_s": 148.0, "offset": 3.0},
	{"name": "DroneSite_R2_WashA", "ring": 2, "min": 2, "max": 3, "wash_s": 225.0, "offset": -3.0},
	{"name": "DroneSite_R2_WashB", "ring": 2, "min": 2, "max": 3, "wash_s": 285.0, "offset": 3.0},
	{"name": "DroneSite_R2_LedgeGuard", "ring": 2, "min": 1, "max": 1, "pos": [-84.0, 190.0]},
]

## Boulder clusters beside the wash: arc length, signed sideways offset. Three boulders each.
const BOULDER_CLUSTERS: Array = [
	[30.0, 11.0], [70.0, -12.0], [105.0, 13.0], [140.0, -11.0],
	[175.0, 12.0], [210.0, -14.0], [250.0, 11.0], [290.0, -12.0],
]
## Nominal heights (m): every side of every boulder must stay inside 0.4-0.9 m (GDD 9.1 with margin).
const BOULDER_HEIGHTS: Array = [0.5, 0.62, 0.74, 0.8, 0.55, 0.68, 0.78, 0.6, 0.7]

static var _wash_pts: PackedVector2Array = PackedVector2Array()
static var _wash_arc: PackedFloat32Array = PackedFloat32Array()


## Floor line height at z (the 2 deg fall; the workshop pad is at y = 0).
static func tilt(z: float) -> float:
	return -z * tan(deg_to_rad(FALL_DEG))


## Top of the cliff plateau at z (always >= 38 m above the floor line).
static func plateau_y(z: float, x: float = 0.0) -> float:
	return tilt(z) + PLATEAU_BASE + 2.5 * sin(0.045 * z) + 1.5 * sin(0.11 * z + 1.0) + head_wobble(x, z)


## Extra rise (0..9 m, never negative so the cliff rule only gets safer) along the head wall's top, so it
## does not read as a dead-flat dam. Full for z <= HEAD_WOBBLE_FULL_Z, gone by HEAD_WOBBLE_END_Z.
static func head_wobble(x: float, z: float) -> float:
	var w: float = 1.0 - smoothstep(HEAD_WOBBLE_FULL_Z, HEAD_WOBBLE_END_Z, z)
	if w <= 0.0:
		return 0.0
	return w * (3.0 * (1.0 + sin(0.06 * x + 0.5)) + 1.5 * (1.0 + sin(0.17 * x + 2.0)))


## Dune bank rise at z (0 before DUNE_START_Z, DUNE_HEIGHT at the ruins).
static func dune(z: float) -> float:
	return DUNE_HEIGHT * smoothstep(DUNE_START_Z, RUINS_BACK_Z - 2.0, z)


## Flat pads: centre, half size, blend distance, target height.
static func pads() -> Array:
	return [
		{"c": Vector2(0.0, 0.0), "h": Vector2(12.0, 12.0), "blend": 14.0, "y": 0.0},
		{"c": Vector2(-92.0, 190.0), "h": Vector2(8.0, 14.0), "blend": 8.0, "y": ledge_apron_y()},
		{"c": Vector2(87.0, 170.0), "h": Vector2(9.0, 16.0), "blend": 8.0, "y": talus_apron_y()},
	]


static func ledge_apron_y() -> float:
	return tilt(0.5 * (LEDGE_Z0 + LEDGE_Z1))


static func talus_apron_y() -> float:
	return tilt(0.5 * (TALUS_Z0 + TALUS_Z1))


static func ledge_floor_y() -> float:
	return ledge_apron_y() + LEDGE_RISE


## Talus surface height at x (slope from the entrance, then the shelf).
static func talus_y(x: float) -> float:
	var run: float = clampf(x - WALL_RIGHT_X, 0.0, TALUS_SLOPE_LEN)
	return talus_apron_y() + run * tan(deg_to_rad(TALUS_DEG))


## Top height of ruin block i.
static func ruin_top_y(i: int) -> float:
	return tilt(RUINS_BACK_Z) + float(RUIN_BLOCKS[i]["h"])


## The floor outline: a closed XZ polygon including both pocket alcoves and the crenellated ruins edge.
## The two pocket entrances are NOT polygon edges (the alcoves are open); see entrances().
static func outline() -> PackedVector2Array:
	var p := PackedVector2Array()
	p.append(Vector2(WALL_LEFT_X, HEAD_WALL_Z))
	p.append(Vector2(WALL_RIGHT_X, HEAD_WALL_Z))
	p.append(Vector2(WALL_RIGHT_X, TALUS_Z0))
	p.append(Vector2(WALL_RIGHT_X + TALUS_DEPTH, TALUS_Z0))
	p.append(Vector2(WALL_RIGHT_X + TALUS_DEPTH, TALUS_Z1))
	p.append(Vector2(WALL_RIGHT_X, TALUS_Z1))
	# Ruins edge, east to west.
	var n: int = RUIN_BLOCKS.size()
	for k in range(n - 1, -1, -1):
		var b: Dictionary = RUIN_BLOCKS[k]
		var x1: float = b["x1"]
		var x0: float = b["x0"]
		var fz: float = b["front"]
		if k == n - 1:
			p.append(Vector2(x1, fz))
		else:
			var nb: Dictionary = RUIN_BLOCKS[k + 1]
			var gap_x1: float = nb["x0"]
			if gap_x1 > x1:
				# 2 m slot between this block and the next one to the east.
				p.append(Vector2(gap_x1, RUINS_BACK_Z))
				p.append(Vector2(x1, RUINS_BACK_Z))
				p.append(Vector2(x1, fz))
			else:
				p.append(Vector2(x1, fz))
		p.append(Vector2(x0, fz))
	p.append(Vector2(WALL_LEFT_X, LEDGE_Z1))
	p.append(Vector2(WALL_LEFT_X - LEDGE_DEPTH, LEDGE_Z1))
	p.append(Vector2(WALL_LEFT_X - LEDGE_DEPTH, LEDGE_Z0))
	p.append(Vector2(WALL_LEFT_X, LEDGE_Z0))
	return p


## Pocket entrances: name, a, b (the open segment between the valley floor and the alcove).
static func entrances() -> Array:
	return [
		{"name": "ledge", "a": Vector2(WALL_LEFT_X, LEDGE_Z0), "b": Vector2(WALL_LEFT_X, LEDGE_Z1)},
		{"name": "talus", "a": Vector2(WALL_RIGHT_X, TALUS_Z0), "b": Vector2(WALL_RIGHT_X, TALUS_Z1)},
	]


static func entrance_center(which: String) -> Vector2:
	for e: Dictionary in entrances():
		if e["name"] == which:
			return (e["a"] as Vector2).lerp(e["b"], 0.5)
	return Vector2.ZERO


static func point_in_polygon(pt: Vector2, poly: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(pt, poly)


static func ring_of(dist: float) -> int:
	if dist < 60.0:
		return 0
	if dist < 150.0:
		return 1
	return 2


## Dense wash polyline (Catmull-Rom through WASH_WAYPOINTS, about 3 m spacing) and its arc lengths.
static func wash_points() -> PackedVector2Array:
	_build_wash()
	return _wash_pts


static func wash_arcs() -> PackedFloat32Array:
	_build_wash()
	return _wash_arc


static func wash_length() -> float:
	_build_wash()
	return _wash_arc[_wash_arc.size() - 1]


static func _build_wash() -> void:
	if _wash_pts.size() > 0:
		return
	var w: Array = WASH_WAYPOINTS
	var n: int = w.size()
	var pts := PackedVector2Array()
	for i in range(n - 1):
		var p0: Vector2 = _wp(maxi(i - 1, 0))
		var p1: Vector2 = _wp(i)
		var p2: Vector2 = _wp(i + 1)
		var p3: Vector2 = _wp(mini(i + 2, n - 1))
		var steps: int = maxi(int(ceil(p1.distance_to(p2) / 3.0)), 1)
		for k in range(steps):
			var t: float = float(k) / float(steps)
			pts.append(_catmull(p0, p1, p2, p3, t))
	pts.append(_wp(n - 1))
	var arcs := PackedFloat32Array()
	var s: float = 0.0
	for i in range(pts.size()):
		if i > 0:
			s += pts[i].distance_to(pts[i - 1])
		arcs.append(s)
	_wash_pts = pts
	_wash_arc = arcs


static func _wp(i: int) -> Vector2:
	var a: Array = WASH_WAYPOINTS[i]
	return Vector2(a[0], a[1])


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3
	)


## Point on the wash at arc length s (clamped).
static func wash_at(s: float) -> Vector2:
	var pts: PackedVector2Array = wash_points()
	var arcs: PackedFloat32Array = wash_arcs()
	s = clampf(s, 0.0, arcs[arcs.size() - 1])
	for i in range(1, pts.size()):
		if arcs[i] >= s:
			var span: float = arcs[i] - arcs[i - 1]
			var f: float = 0.0 if span < 0.0001 else (s - arcs[i - 1]) / span
			return pts[i - 1].lerp(pts[i], f)
	return pts[pts.size() - 1]


## Unit sideways direction of the wash at arc length s.
static func wash_side(s: float) -> Vector2:
	var a: Vector2 = wash_at(s - 1.5)
	var b: Vector2 = wash_at(s + 1.5)
	var d: Vector2 = (b - a).normalized()
	return Vector2(-d.y, d.x)


## Nearest point of the wash: {"dist": m, "s": arc length, "point": Vector2}.
static func wash_nearest(p: Vector2) -> Dictionary:
	var pts: PackedVector2Array = wash_points()
	var arcs: PackedFloat32Array = wash_arcs()
	var best: float = INF
	var best_s: float = 0.0
	var best_pt: Vector2 = pts[0]
	for i in range(1, pts.size()):
		var c: Vector2 = Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i])
		var d: float = p.distance_to(c)
		if d < best:
			best = d
			best_pt = c
			best_s = arcs[i - 1] + pts[i - 1].distance_to(c)
	return {"dist": best, "s": best_s, "point": best_pt}


## XZ position of a site spec.
static func site_xz(spec: Dictionary) -> Vector2:
	if spec.has("wash_s"):
		var s: float = spec["wash_s"]
		return wash_at(s) + wash_side(s) * float(spec["offset"])
	var a: Array = spec["pos"]
	return Vector2(a[0], a[1])


## Boulder specs: [{"pos": Vector2, "size": Vector3 (w, h, d), "yaw": float}], fixed seed, same every run.
static func boulders() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var poly: PackedVector2Array = outline()
	var out: Array = []
	var hi: int = 0
	for c: Array in BOULDER_CLUSTERS:
		var s: float = c[0]
		var off: float = c[1]
		var centre: Vector2 = wash_at(s) + wash_side(s) * off
		for k in range(3):
			var jitter := Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
			var pos: Vector2 = centre + jitter
			if not point_in_polygon(pos, poly):
				continue
			var h: float = BOULDER_HEIGHTS[hi % BOULDER_HEIGHTS.size()]
			hi += 1
			var w: float = rng.randf_range(0.9, 1.6)
			var d: float = rng.randf_range(0.9, 1.6)
			out.append({"pos": pos, "size": Vector3(w, h, d), "yaw": rng.randf_range(0.0, PI)})
	return out
