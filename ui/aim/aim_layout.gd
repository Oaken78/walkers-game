class_name AimLayout
extends RefCounted
## Sizes and screen geometry of the aim marks (GDD 12). Numbers are at 1080p and scale with the screen height. Pure,
## so unit tests cover the placement rules without drawing anything.

const REFERENCE_HEIGHT: float = 1080.0
const DOT_PX: float = 6.0
const DOT_OUTLINE_PX: float = 1.0
const RING_PX: float = 28.0
const RING_STROKE_PX: float = 3.0
const RING_STROKE_ENEMY_PX: float = 5.0
const RING_OUTLINE_PX: float = 2.0
const PIP_PX: float = 4.0
const MERGE_PX: float = 12.0
const DASH_COUNT: int = 8
## Share of each dash slot that is drawn (the rest is the gap).
const DASH_FILL: float = 0.6
const CHEVRON_PX: float = 32.0
const CHEVRON_INSET_PX: float = 24.0

const INK: Color = Color("14161A")
const ACCENT: Color = Color("FF8A3D")
const BODY: Color = Color("E6E1D6")


## Pixels per reference pixel for a viewport of this height.
static func ui_scale(viewport_height: float) -> float:
	return viewport_height / REFERENCE_HEIGHT


## Radius of the ring's centre line: the stroke's outer edge makes the 28 px across.
static func ring_radius(scale: float, stroke_px: float) -> float:
	return (RING_PX * 0.5 - stroke_px * 0.5) * scale


## The ring merges into the pip when its centre is this close to the dot.
static func is_merged(ring_centre: Vector2, dot_centre: Vector2, scale: float) -> bool:
	return ring_centre.distance_to(dot_centre) <= MERGE_PX * scale


static func on_screen(point: Vector2, viewport: Vector2) -> bool:
	return point.x >= 0.0 and point.y >= 0.0 and point.x <= viewport.x and point.y <= viewport.y


## Where the chevron sits: from the screen centre along `direction`, on the rectangle inset by 24 px.
static func chevron_position(direction: Vector2, viewport: Vector2, scale: float) -> Vector2:
	var centre: Vector2 = viewport * 0.5
	var dir: Vector2 = direction.normalized() if direction.length() > 0.0001 else Vector2.RIGHT
	var half: Vector2 = centre - Vector2.ONE * CHEVRON_INSET_PX * scale
	var t: float = INF
	if absf(dir.x) > 0.0001:
		t = minf(t, half.x / absf(dir.x))
	if absf(dir.y) > 0.0001:
		t = minf(t, half.y / absf(dir.y))
	return centre + dir * t


## Arc segments (start, end angle in radians) of the dashed ring: 8 dashes, each filling DASH_FILL of its slot.
static func dash_arcs() -> Array[Vector2]:
	var arcs: Array[Vector2] = []
	var slot: float = TAU / float(DASH_COUNT)
	for i in DASH_COUNT:
		var start: float = slot * float(i)
		arcs.append(Vector2(start, start + slot * DASH_FILL))
	return arcs


## The chevron polygon, pointing along `direction`, centred on `at`, 32 px long at 1080p.
static func chevron_points(at: Vector2, direction: Vector2, scale: float) -> PackedVector2Array:
	var forward: Vector2 = direction.normalized() if direction.length() > 0.0001 else Vector2.RIGHT
	var side: Vector2 = forward.orthogonal()
	var half: float = CHEVRON_PX * 0.5 * scale
	return PackedVector2Array(
		[
			at + forward * half,
			at - forward * half + side * half,
			at - forward * half * 0.25,
			at - forward * half - side * half,
		]
	)
