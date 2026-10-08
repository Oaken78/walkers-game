class_name TerrainBuilder
extends RefCounted
## Builds the valley from ValleyLayout: a 2 m cell grid where each cell is floor, cliff plateau or ruin.
## Floor cells get heights (fall, dune, bump mounds, wash carve, flat pads); wherever two neighbouring cells
## differ in height a VERTICAL wall quad joins them. That is how the cliffs (40 m), the 0.8 m ledge face and
## the ruins get real vertical faces; a later art pass can add strata above 30 m without touching floor edges.

enum Surf { GROUND, ROCK, PLATEAU, RUINS }

const KIND_ROCK: int = 0
const KIND_FLOOR: int = 1
const KIND_LEDGE: int = 2
const KIND_TALUS: int = 3
const KIND_RUIN: int = 10

var nx: int = ValleyLayout.GRID_NX
var nz: int = ValleyLayout.GRID_NZ
var x0: float = ValleyLayout.GRID_X0
var z0: float = ValleyLayout.GRID_Z0

## Cell kind per cell (index iz * nx + ix).
var kinds: PackedByteArray = PackedByteArray()
## Floor height per vertex (index iz * (nx + 1) + ix), valid for floor kinds.
var heights: PackedFloat32Array = PackedFloat32Array()
var carve: PackedFloat32Array = PackedFloat32Array()
## Streak weight per vertex (0 = ground colour, 1 = streak colour): wash channel and bump skirts.
var streak: PackedFloat32Array = PackedFloat32Array()

## Ground colours (GDD 10 palette, sRGB) blended per vertex on the single ground surface.
var color_ground: Color = Color("#CAB294")
var color_streak: Color = Color("#B99F82")
## The visible streak starts at the workshop pad's front edge (z), not behind the workshop.
var streak_start_z: float = 10.5
## Wash half-width at its start and after taper_length metres of path (width 6 m -> 10 m).
var wash_half_width_start: float = 3.0
var wash_taper_length: float = 30.0

var _verts: Array = []
var _norms: Array = []
var _cols: Array = []
var _faces: PackedVector3Array = PackedVector3Array()


func build() -> void:
	for i in range(Surf.size()):
		_verts.append(PackedVector3Array())
		_norms.append(PackedVector3Array())
		_cols.append(PackedColorArray())
	_classify()
	_compute_heights()
	_emit_floor_cells()
	_emit_tops()
	_emit_walls()


## Mesh with one surface per material role (empty roles are skipped). materials is indexed by Surf.
func make_mesh(materials: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for i in range(Surf.size()):
		var v: PackedVector3Array = _verts[i]
		if v.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = _norms[i]
		var cols: PackedColorArray = _cols[i]
		if cols.size() == v.size():
			arrays[Mesh.ARRAY_COLOR] = cols
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[i] as Material)
	return mesh


func make_shape() -> ConcavePolygonShape3D:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_faces)
	return shape


func triangle_count() -> int:
	return _faces.size() / 3


## Surface height at (x, z) using the same triangle split as the mesh.
func height_at(x: float, z: float) -> float:
	var fx: float = (x - x0) / ValleyLayout.CELL
	var fz: float = (z - z0) / ValleyLayout.CELL
	var ix: int = clampi(int(floor(fx)), 0, nx - 1)
	var iz: int = clampi(int(floor(fz)), 0, nz - 1)
	var k: int = kinds[iz * nx + ix]
	if k == KIND_TALUS:
		return ValleyLayout.talus_y(x)
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iz)
	var xa: float = x0 + float(ix) * ValleyLayout.CELL
	var za: float = z0 + float(iz) * ValleyLayout.CELL
	var xb: float = xa + ValleyLayout.CELL
	var zb: float = za + ValleyLayout.CELL
	var stride: int = nx + 1
	var v: int = iz * stride + ix
	var ha: float = _corner_h(k, xa, za, v)
	var hb: float = _corner_h(k, xb, za, v + 1)
	var hc: float = _corner_h(k, xb, zb, v + stride + 1)
	var hd: float = _corner_h(k, xa, zb, v + stride)
	if tx >= tz:
		return ha + tx * (hb - ha) + tz * (hc - hb)
	return ha + tx * (hc - hd) + tz * (hd - ha)


func kind_at(x: float, z: float) -> int:
	var ix: int = clampi(int(floor((x - x0) / ValleyLayout.CELL)), 0, nx - 1)
	var iz: int = clampi(int(floor((z - z0) / ValleyLayout.CELL)), 0, nz - 1)
	return kinds[iz * nx + ix]


func _classify() -> void:
	kinds.resize(nx * nz)
	kinds.fill(KIND_ROCK)
	var poly: PackedVector2Array = ValleyLayout.outline()
	var m: int = poly.size()
	for iz in range(nz):
		var zc: float = z0 + (float(iz) + 0.5) * ValleyLayout.CELL
		var xs: Array = []
		for i in range(m):
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % m]
			if (a.y <= zc and b.y > zc) or (b.y <= zc and a.y > zc):
				xs.append(a.x + (zc - a.y) * (b.x - a.x) / (b.y - a.y))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var ia: int = int(ceil((float(xs[k]) - x0) / ValleyLayout.CELL - 0.5))
			var ib: int = int(floor((float(xs[k + 1]) - x0) / ValleyLayout.CELL - 0.5))
			for ix in range(maxi(ia, 0), mini(ib, nx - 1) + 1):
				kinds[iz * nx + ix] = KIND_FLOOR
	_fill_rect(
		ValleyLayout.WALL_LEFT_X - ValleyLayout.LEDGE_DEPTH, ValleyLayout.WALL_LEFT_X,
		ValleyLayout.LEDGE_Z0, ValleyLayout.LEDGE_Z1, KIND_LEDGE, false
	)
	_fill_rect(
		ValleyLayout.WALL_RIGHT_X, ValleyLayout.WALL_RIGHT_X + ValleyLayout.TALUS_DEPTH,
		ValleyLayout.TALUS_Z0, ValleyLayout.TALUS_Z1, KIND_TALUS, false
	)
	for i in range(ValleyLayout.RUIN_BLOCKS.size()):
		var b: Dictionary = ValleyLayout.RUIN_BLOCKS[i]
		_fill_rect(b["x0"], b["x1"], b["front"], ValleyLayout.RUINS_BACK_Z, KIND_RUIN + i, true)


func _fill_rect(xa: float, xb: float, za: float, zb: float, kind: int, rock_only: bool) -> void:
	var ia: int = int(round((xa - x0) / ValleyLayout.CELL))
	var ib: int = int(round((xb - x0) / ValleyLayout.CELL))
	var ja: int = int(round((za - z0) / ValleyLayout.CELL))
	var jb: int = int(round((zb - z0) / ValleyLayout.CELL))
	for iz in range(ja, jb):
		for ix in range(ia, ib):
			if rock_only and kinds[iz * nx + ix] != KIND_ROCK:
				continue
			kinds[iz * nx + ix] = kind


func _compute_heights() -> void:
	var stride: int = nx + 1
	heights.resize(stride * (nz + 1))
	carve.resize(stride * (nz + 1))
	carve.fill(0.0)
	streak.resize(stride * (nz + 1))
	streak.fill(0.0)
	for iz in range(nz + 1):
		var z: float = z0 + float(iz) * ValleyLayout.CELL
		var base: float = ValleyLayout.tilt(z) + ValleyLayout.dune(z)
		for ix in range(stride):
			heights[iz * stride + ix] = base
	for patch: Array in ValleyLayout.BUMP_PATCHES:
		for mound: Array in patch:
			_add_mound(mound[0], mound[1], mound[2], mound[3])
	_carve_wash()
	for iz in range(nz + 1):
		for ix in range(stride):
			heights[iz * stride + ix] -= carve[iz * stride + ix]
	for pad: Dictionary in ValleyLayout.pads():
		_apply_pad(pad)


func _vertex_range(c: float, r: float, origin: float, count: int) -> Vector2i:
	var lo: int = maxi(int(floor((c - r - origin) / ValleyLayout.CELL)), 0)
	var hi: int = mini(int(ceil((c + r - origin) / ValleyLayout.CELL)), count)
	return Vector2i(lo, hi)


func _add_mound(cx: float, cz: float, radius: float, amp: float) -> void:
	var stride: int = nx + 1
	var rx: Vector2i = _vertex_range(cx, radius, x0, nx)
	var rz: Vector2i = _vertex_range(cz, radius, z0, nz)
	for iz in range(rz.x, rz.y + 1):
		for ix in range(rx.x, rx.y + 1):
			var dx: float = x0 + float(ix) * ValleyLayout.CELL - cx
			var dz: float = z0 + float(iz) * ValleyLayout.CELL - cz
			var r: float = sqrt(dx * dx + dz * dz)
			if r < radius:
				var t: float = 0.5 * (1.0 + cos(PI * r / radius))
				heights[iz * stride + ix] += amp * t
				streak[iz * stride + ix] = maxf(streak[iz * stride + ix], 0.8 * t)


func _carve_wash() -> void:
	var stride: int = nx + 1
	var pts: PackedVector2Array = ValleyLayout.wash_points()
	var arcs: PackedFloat32Array = ValleyLayout.wash_arcs()
	var hw_full: float = ValleyLayout.WASH_HALF_WIDTH
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var fade: float = smoothstep(0.0, 8.0, arcs[i])
		# The channel widens from the bench: half-width (and depth, so the bank slope stays put) taper in.
		var grow: float = clampf(arcs[i] / wash_taper_length, 0.0, 1.0)
		var hw: float = lerpf(wash_half_width_start, hw_full, grow)
		var depth_scale: float = hw / hw_full
		var mid: Vector2 = (a + b) * 0.5
		var rx: Vector2i = _vertex_range(mid.x, hw + 3.0, x0, nx)
		var rz: Vector2i = _vertex_range(mid.y, hw + 3.0, z0, nz)
		for iz in range(rz.x, rz.y + 1):
			for ix in range(rx.x, rx.y + 1):
				var p := Vector2(x0 + float(ix) * ValleyLayout.CELL, z0 + float(iz) * ValleyLayout.CELL)
				var c: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
				var r: float = p.distance_to(c)
				if r < hw:
					var profile: float = 0.5 * (1.0 + cos(PI * r / hw))
					var d: float = ValleyLayout.WASH_DEPTH * depth_scale * profile * fade
					var vi: int = iz * stride + ix
					carve[vi] = maxf(carve[vi], d)
					# Solid streak colour in the core, blended only over the outer 30 % of the half-width.
					var core: float = 1.0 - smoothstep(0.7 * hw, hw, r)
					var w: float = core * smoothstep(streak_start_z - 1.0, streak_start_z + 1.0, p.y)
					streak[vi] = maxf(streak[vi], w)


func _apply_pad(pad: Dictionary) -> void:
	var stride: int = nx + 1
	var c: Vector2 = pad["c"]
	var half: Vector2 = pad["h"]
	var blend: float = pad["blend"]
	var target: float = pad["y"]
	var rx: Vector2i = _vertex_range(c.x, half.x + blend, x0, nx)
	var rz: Vector2i = _vertex_range(c.y, half.y + blend, z0, nz)
	for iz in range(rz.x, rz.y + 1):
		for ix in range(rx.x, rx.y + 1):
			var qx: float = maxf(absf(x0 + float(ix) * ValleyLayout.CELL - c.x) - half.x, 0.0)
			var qz: float = maxf(absf(z0 + float(iz) * ValleyLayout.CELL - c.y) - half.y, 0.0)
			var d: float = sqrt(qx * qx + qz * qz)
			if d < blend:
				var w: float = 1.0 - smoothstep(0.0, blend, d)
				var vi: int = iz * stride + ix
				heights[vi] = lerpf(heights[vi], target, w)


## Top height of a cell kind at world (x, z); v is the vertex index (only used by floor cells).
func _corner_h(kind: int, x: float, z: float, v: int) -> float:
	if kind == KIND_FLOOR:
		return heights[v]
	if kind == KIND_ROCK:
		return ValleyLayout.plateau_y(z, x)
	if kind == KIND_LEDGE:
		return ValleyLayout.ledge_floor_y()
	if kind == KIND_TALUS:
		return ValleyLayout.talus_y(x)
	return ValleyLayout.ruin_top_y(kind - KIND_RUIN)


func _grid_normal(ix: int, iz: int) -> Vector3:
	var stride: int = nx + 1
	var hl: float = heights[iz * stride + maxi(ix - 1, 0)]
	var hr: float = heights[iz * stride + mini(ix + 1, nx)]
	var hu: float = heights[maxi(iz - 1, 0) * stride + ix]
	var hd: float = heights[mini(iz + 1, nz) * stride + ix]
	return Vector3(hl - hr, 2.0 * ValleyLayout.CELL, hu - hd).normalized()


func _emit_floor_cells() -> void:
	var stride: int = nx + 1
	var cell: float = ValleyLayout.CELL
	var slope_n := Vector3(-sin(deg_to_rad(ValleyLayout.TALUS_DEG)), cos(deg_to_rad(ValleyLayout.TALUS_DEG)), 0.0)
	var slope_end_x: float = ValleyLayout.WALL_RIGHT_X + ValleyLayout.TALUS_SLOPE_LEN
	for iz in range(nz):
		var za: float = z0 + float(iz) * cell
		var zb: float = za + cell
		for ix in range(nx):
			var k: int = kinds[iz * nx + ix]
			if k < KIND_FLOOR or k > KIND_TALUS:
				continue
			var xa: float = x0 + float(ix) * cell
			var xb: float = xa + cell
			if k == KIND_TALUS:
				# The slope ends mid-cell: split at the break so every piece is planar.
				var cuts: Array = [xa]
				if xa < slope_end_x - 0.001 and xb > slope_end_x + 0.001:
					cuts.append(slope_end_x)
				cuts.append(xb)
				for ci in range(cuts.size() - 1):
					var sx0: float = cuts[ci]
					var sx1: float = cuts[ci + 1]
					var sn: Vector3 = slope_n if sx1 <= slope_end_x + 0.001 else Vector3.UP
					var q0 := Vector3(sx0, ValleyLayout.talus_y(sx0), za)
					var q1 := Vector3(sx1, ValleyLayout.talus_y(sx1), za)
					var q2 := Vector3(sx1, ValleyLayout.talus_y(sx1), zb)
					var q3 := Vector3(sx0, ValleyLayout.talus_y(sx0), zb)
					_add_tri(Surf.GROUND, q0, q1, q2, sn, sn, sn)
					_add_tri(Surf.GROUND, q0, q2, q3, sn, sn, sn)
				continue
			var v: int = iz * stride + ix
			var ha: float = _corner_h(k, xa, za, v)
			var hb: float = _corner_h(k, xb, za, v + 1)
			var hc: float = _corner_h(k, xb, zb, v + stride + 1)
			var hd: float = _corner_h(k, xa, zb, v + stride)
			var na: Vector3 = Vector3.UP
			var nb: Vector3 = Vector3.UP
			var nc: Vector3 = Vector3.UP
			var nd: Vector3 = Vector3.UP
			var cla: Color = color_ground
			var clb: Color = color_ground
			var clc: Color = color_ground
			var cld: Color = color_ground
			if k == KIND_FLOOR:
				na = _grid_normal(ix, iz)
				nb = _grid_normal(ix + 1, iz)
				nc = _grid_normal(ix + 1, iz + 1)
				nd = _grid_normal(ix, iz + 1)
				cla = color_ground.lerp(color_streak, streak[v])
				clb = color_ground.lerp(color_streak, streak[v + 1])
				clc = color_ground.lerp(color_streak, streak[v + stride + 1])
				cld = color_ground.lerp(color_streak, streak[v + stride])
			var pa := Vector3(xa, ha, za)
			var pb := Vector3(xb, hb, za)
			var pc := Vector3(xb, hc, zb)
			var pd := Vector3(xa, hd, zb)
			_add_tri(Surf.GROUND, pa, pb, pc, na, nb, nc, cla, clb, clc)
			_add_tri(Surf.GROUND, pa, pc, pd, na, nc, nd, cla, clc, cld)


func _add_tri(
	surf: int, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
	ca: Color = Color.TRANSPARENT, cb: Color = Color.TRANSPARENT, cc: Color = Color.TRANSPARENT
) -> void:
	var vs: PackedVector3Array = _verts[surf]
	var ns: PackedVector3Array = _norms[surf]
	if surf == Surf.GROUND:
		var cs: PackedColorArray = _cols[surf]
		cs.push_back(color_ground if ca.a == 0.0 else ca)
		cs.push_back(color_ground if cb.a == 0.0 else cb)
		cs.push_back(color_ground if cc.a == 0.0 else cc)
	vs.push_back(a)
	vs.push_back(b)
	vs.push_back(c)
	ns.push_back(na)
	ns.push_back(nb)
	ns.push_back(nc)
	_faces.push_back(a)
	_faces.push_back(b)
	_faces.push_back(c)


## Quad p0..p3 (a planar quad) facing `normal`; winding is fixed up so the front face points along it.
func _add_quad(surf: int, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, normal: Vector3) -> void:
	var g: Vector3 = (p1 - p0).cross(p2 - p0)
	if g.dot(normal) > 0.0:
		var t: Vector3 = p1
		p1 = p3
		p3 = t
	_add_tri(surf, p0, p1, p2, normal, normal, normal)
	_add_tri(surf, p0, p2, p3, normal, normal, normal)


## Plateau and ruin tops, merged into one quad per row run (their height only varies with z, so quads are planar).
func _emit_tops() -> void:
	var cell: float = ValleyLayout.CELL
	for iz in range(nz):
		var za: float = z0 + float(iz) * cell
		var zb: float = za + cell
		var ix: int = 0
		while ix < nx:
			var k: int = kinds[iz * nx + ix]
			if k != KIND_ROCK and k < KIND_RUIN:
				ix += 1
				continue
			var jx: int = ix
			while jx < nx and kinds[iz * nx + jx] == k:
				jx += 1
			if k == KIND_ROCK and za < ValleyLayout.HEAD_WOBBLE_END_Z:
				# Head-wall zone: the top varies with x, so emit one quad per cell (corner heights differ).
				for cx in range(ix, jx):
					var qa: float = x0 + float(cx) * cell
					var qb: float = qa + cell
					var p0 := Vector3(qa, _corner_h(k, qa, za, 0), za)
					var p1 := Vector3(qb, _corner_h(k, qb, za, 0), za)
					var p2 := Vector3(qb, _corner_h(k, qb, zb, 0), zb)
					var p3 := Vector3(qa, _corner_h(k, qa, zb, 0), zb)
					_add_tri(Surf.PLATEAU, p0, p1, p2, Vector3.UP, Vector3.UP, Vector3.UP)
					_add_tri(Surf.PLATEAU, p0, p2, p3, Vector3.UP, Vector3.UP, Vector3.UP)
				ix = jx
				continue
			var xa: float = x0 + float(ix) * cell
			var xb: float = x0 + float(jx) * cell
			var ha: float = _corner_h(k, xa, za, 0)
			var hb: float = _corner_h(k, xa, zb, 0)
			var surf: int = Surf.PLATEAU if k == KIND_ROCK else Surf.RUINS
			var pa := Vector3(xa, ha, za)
			var pb := Vector3(xb, ha, za)
			var pc := Vector3(xb, hb, zb)
			var pd := Vector3(xa, hb, zb)
			_add_tri(surf, pa, pb, pc, Vector3.UP, Vector3.UP, Vector3.UP)
			_add_tri(surf, pa, pc, pd, Vector3.UP, Vector3.UP, Vector3.UP)
			ix = jx


func _emit_walls() -> void:
	var stride: int = nx + 1
	var cell: float = ValleyLayout.CELL
	for iz in range(nz):
		var za: float = z0 + float(iz) * cell
		var zb: float = za + cell
		for ix in range(nx):
			var k: int = kinds[iz * nx + ix]
			var xa: float = x0 + float(ix) * cell
			var xb: float = xa + cell
			var v: int = iz * stride + ix
			if ix + 1 < nx:
				var k2: int = kinds[iz * nx + ix + 1]
				if k2 != k:
					var a0: float = _corner_h(k, xb, za, v + 1)
					var a1: float = _corner_h(k, xb, zb, v + stride + 1)
					var b0: float = _corner_h(k2, xb, za, v + 1)
					var b1: float = _corner_h(k2, xb, zb, v + stride + 1)
					_wall_x(k, k2, xb, za, zb, a0, a1, b0, b1)
			if iz + 1 < nz:
				var k3: int = kinds[(iz + 1) * nx + ix]
				if k3 != k:
					var c0: float = _corner_h(k, xa, zb, v + stride)
					var c1: float = _corner_h(k, xb, zb, v + stride + 1)
					var d0: float = _corner_h(k3, xa, zb, v + stride)
					var d1: float = _corner_h(k3, xb, zb, v + stride + 1)
					_wall_z(k, k3, zb, xa, xb, c0, c1, d0, d1)


## Wall on the plane x = xe between the west cell (heights a0, a1 at za, zb) and the east cell (b0, b1).
func _wall_x(ka: int, kb: int, xe: float, za: float, zb: float, a0: float, a1: float, b0: float, b1: float) -> void:
	if absf(a0 - b0) < 0.001 and absf(a1 - b1) < 0.001:
		return
	var west_lower: bool = (a0 + a1) < (b0 + b1)
	var lo0: float = a0 if west_lower else b0
	var lo1: float = a1 if west_lower else b1
	var hi0: float = b0 if west_lower else a0
	var hi1: float = b1 if west_lower else a1
	var normal: Vector3 = Vector3.LEFT if west_lower else Vector3.RIGHT
	var surf: int = Surf.RUINS if (ka >= KIND_RUIN or kb >= KIND_RUIN) else Surf.ROCK
	_add_quad(surf, Vector3(xe, lo0, za), Vector3(xe, lo1, zb), Vector3(xe, hi1, zb), Vector3(xe, hi0, za), normal)


## Wall on the plane z = ze between the north cell (heights a0, a1 at xa, xb) and the south cell (b0, b1).
func _wall_z(ka: int, kb: int, ze: float, xa: float, xb: float, a0: float, a1: float, b0: float, b1: float) -> void:
	if absf(a0 - b0) < 0.001 and absf(a1 - b1) < 0.001:
		return
	var north_lower: bool = (a0 + a1) < (b0 + b1)
	var lo0: float = a0 if north_lower else b0
	var lo1: float = a1 if north_lower else b1
	var hi0: float = b0 if north_lower else a0
	var hi1: float = b1 if north_lower else a1
	var normal: Vector3 = Vector3.FORWARD if north_lower else Vector3.BACK
	var surf: int = Surf.RUINS if (ka >= KIND_RUIN or kb >= KIND_RUIN) else Surf.ROCK
	_add_quad(surf, Vector3(xa, lo0, ze), Vector3(xb, lo1, ze), Vector3(xb, hi1, ze), Vector3(xa, hi0, ze), normal)
