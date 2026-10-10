class_name FootFx
extends Node3D
## Foot plant read (GDD 10 rule 1, Pillar 2): every plant kicks up a 0.8 s dust puff (size from weight per leg) and leaves a dark contact decal
## that fades over 2 s. Both come from fixed pools built in _ready (no node is made or freed afterwards); at capacity
## the oldest is reused. Child of the WalkerBody; listens to its foot_planted signal. Puffs are 5 soft sprites in one MultiMesh.
## Time is counted in advance(), driven from _physics_process, so tests can step it by hand.

## Dust (GDD 10 rule 1): width W = clamp(width_per_kg_per_leg x mass per leg / 50 kg, min, max). Mass per leg is the build's
## mass / leg count (read through get_build(), recomputed on build_applied). Height of the whole puff is half of W.
@export var puff_width_ref_m: float = 0.5
@export var puff_ref_mass_per_leg_kg: float = 50.0
@export var puff_width_min_m: float = 0.25
@export var puff_width_max_m: float = 1.0
## Mass per leg used when there is no walker (a lone FootFx in a test or a scene).
@export var puff_default_mass_per_leg_kg: float = 50.0
## Soft sprites per puff, each puff_sprite_share x W across and started within puff_spread_share x W of the pad.
@export_range(2, 8) var puff_sprites: int = 5
@export var puff_sprite_share: float = 0.5
@export var puff_spread_share: float = 0.3
## Sprites burst outward at this speed (m/s), slowing linearly to 0 at puff_burst_s.
@export var puff_burst_speed: float = 0.8
@export var puff_burst_s: float = 0.4
## The puff reaches its full height at puff_rise_s, then sinks by puff_sink_share while it fades.
@export var puff_rise_s: float = 0.3
@export_range(0.0, 1.0) var puff_sink_share: float = 0.3
## Share of the full height at the plant.
@export_range(0.0, 1.0) var puff_start_height_share: float = 0.6
@export var puff_life_s: float = 0.8
## Dust tone: the ground family (ground is #CAB294), a touch under the spec #D9C7AE so the overlap of 5 sprites stays <= 0.85 luma. Unshaded: does not darken in shadow.
@export var puff_color: Color = Color("D5C3AA")
## Opacity at the peak, reached at puff_peak_s; puff_mid_alpha at puff_burst_s; 0 at the end of the life.
@export_range(0.0, 1.0) var puff_peak_alpha: float = 0.45
@export var puff_peak_s: float = 0.08
@export_range(0.0, 1.0) var puff_mid_alpha: float = 0.22
## 28 puffs cover the Crawler at top speed (about 29 plants/s x 0.8 s = 23 live) with margin.
@export var puff_pool_size: int = 28
@export var puff_seed: int = 23
## Contact decal box (m): x and z cover the pad (0.30 x 0.34) plus a margin; y is thin so it never reaches the pad's top.
@export var decal_size_m: Vector3 = Vector3(0.44, 0.10, 0.48)
@export var decal_life_s: float = 2.0
## Dark value of the mark, at full opacity.
@export var decal_color: Color = Color(0.07, 0.06, 0.05)
## Opacity of the texture at the pad's middle at full life.
@export_range(0.0, 1.0) var decal_peak_alpha: float = 0.40
## Crawler measured peak 60 live decals; the pool is >= 1.25x the highest peak.
@export var decal_pool_size: int = 80
## Surfaces turned away from the decal's up axis fade out: the pad's sides and the legs are not stained.
@export_range(0.0, 1.0) var decal_normal_fade: float = 0.5
## No puff or decal this long after build_applied or a teleport (a spawn plants every foot at once).
@export var quiet_after_build_s: float = 0.2
## A decal centre this far (m) from the drawn pad 0.1 s after the plant counts as a snap mismatch.
@export var snap_check_m: float = 0.1
## Plants this high count as ledge-top plants for the alignment check (flat tops).
@export var ledge_y_m: float = 1.0

## Plants heard, plants shown (a puff and a decal each) and plants ignored in the quiet time.
var plants_seen: int = 0
var puffs_spawned: int = 0
var decals_spawned: int = 0
var plants_ignored: int = 0
var peak_live_decals: int = 0
## Lifetime in ticks of the decals that ran out by themselves (min and max; 120 +- 1 at 60 Hz for 2 s).
var decal_ticks_min: int = 1 << 30
var decal_ticks_max: int = 0
## Snap check: plants whose decal centre was > snap_check_m from the drawn pad 0.1 s later, and the worst distance (m).
var snap_mismatches: int = 0
var snap_max_m: float = 0.0

## Plants heard that got neither a puff nor an ignore (always 0: a scenario asserts it).
var unaccounted_plants: int:
	get:
		return plants_seen - puffs_spawned - plants_ignored

## Draw calls the puffs cost (one MultiMesh).
var puff_draw_calls: int:
	get:
		return 1
## Decals showing now.
var live_decal_count: int:
	get:
		return live_decals()
## Plants at y >= ledge_y_m (a ledge top) and the worst angle (deg) between their decal's up axis and world up.
var ledge_plants: int = 0
var ledge_align_err_deg: float = 0.0
## Decals that ran out by themselves, and the highest plant point seen (m).
var decals_expired: int = 0
var highest_plant_y: float = -INF

var _decals: Array[Decal] = []
var _decal_age: PackedFloat32Array = PackedFloat32Array()
var _decal_ticks: PackedInt32Array = PackedInt32Array()
## One MultiMesh holds every sprite of every puff (one draw call); puff i owns instances i*puff_sprites ...
var _mm: MultiMesh
var _puff_age: PackedFloat32Array = PackedFloat32Array()
var _puff_pos: PackedVector3Array = PackedVector3Array()
var _puff_width: PackedFloat32Array = PackedFloat32Array()
## Per sprite: start offset from the pad (x, z) and the unit direction it bursts along.
var _sprite_off: PackedVector2Array = PackedVector2Array()
var _sprite_dir: PackedVector2Array = PackedVector2Array()
var _sprite_world: PackedVector3Array = PackedVector3Array()
var _rng := RandomNumberGenerator.new()
var _width_m: float = 0.5
## Set at the start and on build_applied; the width is read from the build when next needed (the walker's build is not there yet in _ready).
var _width_dirty: bool = true
var peak_live_puffs: int = 0
var _freeze_armed: bool = false
var _freeze_left: float = -1.0
var _quiet_left: float = 0.0
var _teleports: int = 0
## Pending snap checks: [leg, centre, time left].
var _checks: Array = []
var _body: Node


func _ready() -> void:
	top_level = true
	_build_pools()
	_body = get_parent()
	if _body != null and _body.has_signal("foot_planted"):
		_body.foot_planted.connect(_on_foot_planted)
		if _body.has_signal("build_applied"):
			_body.build_applied.connect(_on_build_applied)
	if _body != null and "teleport_count" in _body:
		_teleports = _body.teleport_count


func _physics_process(delta: float) -> void:
	_sync_teleports()
	advance(delta)


## Screenshot aid: pauses the tree `seconds` after the next real plant (the still of "a foot just landed").
func arm_freeze_after_plant(seconds: float) -> void:
	_freeze_armed = true
	_freeze_left = seconds


## Screenshot aid: `count` plants on the ground in a row ahead of the walker (local -z, `step_m` apart, `side_m` to the
## right), so one still shows the puff and decal over both floor tones. Needs a physics frame to have run.
func demo_row(count: int, first_m: float, step_m: float, side_m: float) -> void:
	if not (_body is Node3D):
		return
	var body: Node3D = _body
	for i in count:
		var spot: Vector3 = body.global_position + body.global_basis * Vector3(side_m, 0.0, -(first_m + step_m * i))
		var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 5.0, spot + Vector3.DOWN * 5.0, 1)
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			plant(hit["position"], hit["normal"])


func release_freeze() -> void:
	_freeze_armed = false
	_freeze_left = -1.0
	get_tree().paused = false


## Prints the counters for the scenario report.
func report(label: String) -> void:
	print(
		"FOOTFX %s plants=%d puffs=%d decals=%d ignored=%d peak_decals=%d/%d expired=%d life_ticks=%d..%d snap_mismatches=%d snap_max_m=%.3f ledge_plants=%d ledge_align_err_deg=%.3f highest_y=%.2f"
		% [
			label, plants_seen, puffs_spawned, decals_spawned, plants_ignored, peak_live_decals, decal_pool_size,
			decals_expired, decal_ticks_min, decal_ticks_max, snap_mismatches, snap_max_m, ledge_plants, ledge_align_err_deg,
			highest_plant_y
		]
	)
	print(
		"FOOTFX %s puff_width_m=%.3f peak_live_puffs=%d/%d puff_draw_calls=%d"
		% [label, puff_width(), peak_live_puffs, puff_pool_size, puff_draw_calls]
	)


## Zeroes the counters (a scenario starts counting after the quiet time).
func reset_counts() -> void:
	plants_seen = 0
	puffs_spawned = 0
	decals_spawned = 0
	plants_ignored = 0
	peak_live_decals = live_decals()
	peak_live_puffs = live_puffs()
	decal_ticks_min = 1 << 30
	decal_ticks_max = 0
	snap_mismatches = 0
	snap_max_m = 0.0
	ledge_plants = 0
	ledge_align_err_deg = 0.0
	decals_expired = 0
	highest_plant_y = -INF
	_checks.clear()


## Opacity of a decal of age `age` (1 at the plant, 0 at `life`).
static func decal_opacity(age: float, life: float) -> float:
	return clampf(1.0 - age / life, 0.0, 1.0)


## Number of decals showing now.
func live_decals() -> int:
	var n: int = 0
	for age in _decal_age:
		if age >= 0.0:
			n += 1
	return n


func live_puffs() -> int:
	var n: int = 0
	for age in _puff_age:
		if age >= 0.0:
			n += 1
	return n


func decal_nodes() -> Array[Decal]:
	return _decals


## Puff width W (m) for a mass per leg (kg): clamp(0.5 m x w / 50 kg, 0.25, 1.0).
func puff_width_for(mass_per_leg_kg: float) -> float:
	return clampf(puff_width_ref_m * mass_per_leg_kg / puff_ref_mass_per_leg_kg, puff_width_min_m, puff_width_max_m)


## Width W (m) the next puff gets, from the walker's build.
func puff_width() -> float:
	_update_width()
	return _width_m




## Opacity of a puff of age `age`: 0 -> peak at puff_peak_s, down to puff_mid_alpha at puff_burst_s, 0 at the end.
func puff_alpha(age: float) -> float:
	if age <= 0.0 or age >= puff_life_s:
		return 0.0
	if age < puff_peak_s:
		return puff_peak_alpha * age / puff_peak_s
	if age < puff_burst_s:
		return lerpf(puff_peak_alpha, puff_mid_alpha, (age - puff_peak_s) / (puff_burst_s - puff_peak_s))
	return lerpf(puff_mid_alpha, 0.0, (age - puff_burst_s) / (puff_life_s - puff_burst_s))


## Distance (m) a sprite has burst out by `age`: speed falls linearly to 0 at puff_burst_s.
func puff_burst_distance(age: float) -> float:
	var t: float = minf(age, puff_burst_s)
	return puff_burst_speed * (t - t * t / (2.0 * puff_burst_s))


## Height share of the puff's full height at `age`: rises to 1 at puff_rise_s, then sinks by puff_sink_share by the end.
func puff_height_share(age: float) -> float:
	if age < puff_rise_s:
		return lerpf(puff_start_height_share, 1.0, sqrt(age / puff_rise_s))
	return 1.0 - puff_sink_share * (age - puff_rise_s) / (puff_life_s - puff_rise_s)


## World position of sprite `k` of puff `i` now (m).
func puff_sprite_position(i: int, k: int) -> Vector3:
	return _sprite_world[i * puff_sprites + k]


func puff_sprite_size(i: int) -> float:
	return _puff_width[i] * puff_sprite_share


func puff_age(i: int) -> float:
	return _puff_age[i]


## Ages every puff and decal by `delta` seconds and frees the ones that ran out.
func advance(delta: float) -> void:
	_quiet_left = maxf(_quiet_left - delta, 0.0)
	for i in _decals.size():
		if _decal_age[i] < 0.0:
			continue
		_decal_age[i] += delta
		_decal_ticks[i] += 1
		if _decal_age[i] >= decal_life_s - 0.0001:
			decal_ticks_min = mini(decal_ticks_min, _decal_ticks[i])
			decal_ticks_max = maxi(decal_ticks_max, _decal_ticks[i])
			decals_expired += 1
			_decal_age[i] = -1.0
			_decals[i].visible = false
		else:
			_decals[i].modulate.a = decal_opacity(_decal_age[i], decal_life_s)
	for i in _puff_age.size():
		if _puff_age[i] < 0.0:
			continue
		_puff_age[i] += delta
		if _puff_age[i] >= puff_life_s - 0.0001:
			_puff_age[i] = -1.0
			_hide_puff(i)
		else:
			_pose_puff(i)
	if _freeze_left >= 0.0 and not _freeze_armed:
		_freeze_left -= delta
		if _freeze_left <= 0.0:
			_freeze_left = -1.0
			get_tree().paused = true
	var k: int = 0
	while k < _checks.size():
		_checks[k][2] -= delta
		if _checks[k][2] <= 0.0:
			_run_check(_checks[k])
			_checks.remove_at(k)
		else:
			k += 1


## Shows a puff and a decal at `pos` on a surface with `normal`. Returns false in the quiet time.
func plant(pos: Vector3, normal: Vector3, leg: int = -1) -> bool:
	_sync_teleports()
	plants_seen += 1
	if _quiet_left > 0.0:
		plants_ignored += 1
		return false
	if _freeze_armed:
		_freeze_armed = false
	var n: Vector3 = normal.normalized()
	_show_puff(pos)
	var decal: Decal = _show_decal(pos, n)
	if leg >= 0 and _body != null and _body.has_method("pad_mesh_center"):
		_checks.append([leg, decal.global_position, 0.1])
	return true


func _on_foot_planted(leg: int, pos: Vector3, normal: Vector3) -> void:
	plant(pos, normal, leg)


func _on_build_applied() -> void:
	_width_dirty = true
	_quiet_left = quiet_after_build_s
	_checks.clear()


## A teleport starts the quiet time (checked every tick and at every plant: the plant can come before the next tick).
func _sync_teleports() -> void:
	if _body != null and "teleport_count" in _body and _body.teleport_count != _teleports:
		_teleports = _body.teleport_count
		_quiet_left = quiet_after_build_s
		_checks.clear()


func _run_check(check: Array) -> void:
	var leg: int = check[0]
	if leg >= _body.leg_count():
		return
	var pad: Vector3 = _body.pad_mesh_center(leg)
	# The drawn pad box centre sits half its height (0.1 m) above the plant point.
	var d: float = (pad - Vector3.UP * 0.1).distance_to(check[1])
	snap_max_m = maxf(snap_max_m, d)
	if d > snap_check_m:
		snap_mismatches += 1


func _oldest(ages: PackedFloat32Array) -> int:
	var best: int = 0
	for i in ages.size():
		if ages[i] < 0.0:
			return i
		if ages[i] > ages[best]:
			best = i
	return best


func _show_decal(pos: Vector3, n: Vector3) -> Decal:
	var i: int = _oldest(_decal_age)
	var decal: Decal = _decals[i]
	# Local up is the surface normal; local x follows the walker's side so the mark lines up with the pad.
	var side: Vector3 = Vector3.RIGHT
	if _body is Node3D:
		side = (_body as Node3D).global_basis.x
	side = side - n * side.dot(n)
	if side.length() < 0.001:
		side = n.cross(Vector3.FORWARD)
	side = side.normalized()
	decal.global_transform = Transform3D(Basis(side, n, side.cross(n)), pos)
	if pos.y >= ledge_y_m:
		ledge_plants += 1
		ledge_align_err_deg = maxf(ledge_align_err_deg, rad_to_deg(decal.global_basis.y.angle_to(Vector3.UP)))
	highest_plant_y = maxf(highest_plant_y, pos.y)
	decal.modulate = Color(1, 1, 1, 1)
	decal.visible = true
	_decal_age[i] = 0.0
	_decal_ticks[i] = 0
	decals_spawned += 1
	peak_live_decals = maxi(peak_live_decals, live_decals())
	return decal


func _show_puff(pos: Vector3) -> void:
	var i: int = _oldest(_puff_age)
	_puff_pos[i] = pos
	_puff_age[i] = 0.0
	_update_width()
	_puff_width[i] = _width_m
	for k in puff_sprites:
		# Seeded: spread within puff_spread_share x W of the pad, bursting outward along the same bearing.
		var angle: float = _rng.randf() * TAU
		var radius: float = sqrt(_rng.randf()) * puff_spread_share * _width_m
		var dir := Vector2(cos(angle), sin(angle))
		_sprite_dir[i * puff_sprites + k] = dir
		_sprite_off[i * puff_sprites + k] = dir * radius
	puffs_spawned += 1
	peak_live_puffs = maxi(peak_live_puffs, live_puffs())
	_pose_puff(i)


func _hide_puff(i: int) -> void:
	for k in puff_sprites:
		_mm.set_instance_transform(i * puff_sprites + k, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		_mm.set_instance_color(i * puff_sprites + k, Color(1, 1, 1, 0))


func _pose_puff(i: int) -> void:
	var age: float = _puff_age[i]
	var width: float = _puff_width[i]
	var size: float = width * puff_sprite_share
	# The puff is width * 0.5 high: its sprites sit with their lower edge near the ground at full height.
	var centre_y: float = size * 0.5 * puff_height_share(age)
	var burst: float = puff_burst_distance(age)
	var color := Color(puff_color.r, puff_color.g, puff_color.b, puff_alpha(age))
	for k in puff_sprites:
		var idx: int = i * puff_sprites + k
		var flat: Vector2 = _sprite_off[idx] + _sprite_dir[idx] * burst
		var p: Vector3 = _puff_pos[i] + Vector3(flat.x, centre_y, flat.y)
		_sprite_world[idx] = p
		_mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3(size, size, size)), p))
		_mm.set_instance_color(idx, color)


## Recomputes the puff width W from the build: mass / leg count. No walker -> puff_default_mass_per_leg_kg.
func _update_width() -> void:
	if not _width_dirty:
		return
	_width_dirty = false
	var per_leg: float = puff_default_mass_per_leg_kg
	if _body != null and _body.has_method("get_build"):
		var build: WalkerBuild = _body.get_build()
		var legs: int = build.leg_count()
		if legs > 0:
			per_leg = float(build.stats()["mass"]) / float(legs)
	_width_m = puff_width_for(per_leg)

func _build_pools() -> void:
	var decal_tex: Texture2D = make_decal_texture()
	for i in decal_pool_size:
		var d := Decal.new()
		d.size = decal_size_m
		d.texture_albedo = decal_tex
		d.albedo_mix = 1.0
		d.normal_fade = decal_normal_fade
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		d.visible = false
		d.top_level = true
		d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(d)
		_decals.append(d)
		_decal_age.append(-1.0)
		_decal_ticks.append(0)
	_rng.seed = puff_seed
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	# Unshaded flat ground tone: a lit camera-facing sprite read as grey smudges in the valley light. Billboard: each sprite faces the camera.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = make_puff_texture()
	quad.material = m
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = quad
	_mm.instance_count = puff_pool_size * puff_sprites
	var holder := MultiMeshInstance3D.new()
	holder.multimesh = _mm
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The instances move through the world; the box must not cull them.
	holder.custom_aabb = AABB(Vector3(-5000, -100, -5000), Vector3(10000, 1000, 10000))
	holder.top_level = true
	holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(holder)
	_sprite_off.resize(_mm.instance_count)
	_sprite_dir.resize(_mm.instance_count)
	_sprite_world.resize(_mm.instance_count)
	for i in puff_pool_size:
		_puff_age.append(-1.0)
		_puff_pos.append(Vector3.ZERO)
		_puff_width.append(_width_m)
		_hide_puff(i)

## Soft rounded rectangle, dark, full alpha over the pad's footprint and a soft edge out to the box.
func make_decal_texture() -> Texture2D:
	var res: int = 64
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	var half := Vector2(0.30 / decal_size_m.x, 0.34 / decal_size_m.z) * 0.5 * float(res)
	var corner: float = 11.0
	for y in res:
		for x in res:
			var p := Vector2(x + 0.5 - res * 0.5, y + 0.5 - res * 0.5).abs() - half + Vector2(corner, corner)
			var dist: float = Vector2(maxf(p.x, 0.0), maxf(p.y, 0.0)).length() + minf(maxf(p.x, p.y), 0.0) - corner
			var a: float = 1.0 - smoothstep(-2.0, 8.0, dist)
			img.set_pixel(x, y, Color(decal_color.r, decal_color.g, decal_color.b, a * decal_peak_alpha))
	return ImageTexture.create_from_image(img)


## Soft round sprite, white: alpha (1 - r^2)^2 of the radius r, so it is 0.036 at 0.9 and 0 at the rim.
func make_puff_texture() -> Texture2D:
	var res: int = 64
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	for y in res:
		for x in res:
			var r: float = Vector2(x + 0.5 - res * 0.5, y + 0.5 - res * 0.5).length() / (res * 0.5)
			var a: float = 0.0 if r >= 1.0 else pow(1.0 - r * r, 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)