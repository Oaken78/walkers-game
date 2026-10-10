class_name FieldHud
extends Control
## Field HUD (T20, GDD 12): chassis HP bottom left, carried and banked scrap top right, a compass strip top centre
## (workshop and wreck cache), "F  Workshop" and the recall hold centre-low, a toast below them. The top-left stays
## free for the F9 frame readout; the bottom-right corner and the screen centre belong to the aim marks and chevron.
## T12 calls bind / show_toast / set_enter_prompt / unbind. Every Control ignores the mouse. All sizes are 1080p
## reference pixels and scale with the viewport height (the same rule as the aim marks).

const REFERENCE_HEIGHT: float = 1080.0
const INK: Color = Color("14161A")
const ACCENT: Color = Color("FF8A3D")
const BODY: Color = Color("E6E1D6")
const SALVAGE: Color = Color("3DE0E8")
const MUTED: Color = Color("C9C5BB")

## Back plate: the same 60 % #14161A as the F9 readout.
@export var plate_color: Color = Color(0.0784, 0.0863, 0.1020, 0.6)
## Below this share of max HP the bar turns urgent (accent fill, pulse, "LOW" tag, notch).
@export_range(0.05, 0.5) var low_hp_fraction: float = 0.25
## Period of the urgent pulse in seconds (luma swing of the fill).
@export var low_pulse_period: float = 0.8
## The compass strip spans this many degrees either side of the camera heading; marks beyond it pin to the ends.
@export var compass_half_span_deg: float = 90.0
@export var toast_fade_in: float = 0.2
@export var toast_fade_out: float = 0.5
## Layout, 1080p reference pixels.
@export var margin_px: float = 32.0
@export var hp_size: Vector2 = Vector2(320, 64)
@export var scrap_size: Vector2 = Vector2(280, 92)
@export var compass_size: Vector2 = Vector2(560, 56)
@export var prompt_size: Vector2 = Vector2(220, 44)
@export var recall_size: Vector2 = Vector2(260, 44)
@export var toast_size: Vector2 = Vector2(640, 52)
## Vertical position (share of the screen height) of the centre-low stack: prompt, recall hold, toast.
@export var prompt_y: float = 0.72
@export var recall_y: float = 0.78
@export var toast_y: float = 0.86

## Bar fraction (0..1) of chassis HP, set on Health.changed only.
var hp_fraction: float = 1.0
var hp_text: String = ""
var carried_text: String = ""
var banked_text: String = ""
var recall_fraction: float = 0.0
var toast_text: String = ""

var _scale: float = 1.0
var _health: Health = null
var _economy: Economy = null
var _walker: Node3D = null
var _camera: Camera3D = null
var _home: Vector3 = Vector3.ZERO
var _recall: RecallHold = null
var _enter_prompt: bool = false
var _low: bool = false
var _pulse_t: float = 0.0
var _toast_queue: Array = []
var _toast_left: float = 0.0
var _toast_total: float = 0.0
var _cache_shown: bool = false

var _hp_plate: Panel
var _hp_back: ColorRect
var _hp_fill: ColorRect
var _hp_tick: ColorRect
var _hp_label: Label
var _hp_low_tag: Label
var _scrap_plate: Panel
var _scrap_icon: ColorRect
var _carried_tag: Label
var _carried_label: Label
var _banked_tag: Label
var _banked_label: Label
var _compass_plate: Panel
var _compass_centre: ColorRect
var _home_mark: ColorRect
var _home_letter: Label
var _home_dist: Label
var _cache_mark: ColorRect
var _cache_dist: Label
var _prompt_plate: Panel
var _prompt_label: Label
var _recall_plate: Panel
var _recall_back: ColorRect
var _recall_fill: ColorRect
var _recall_label: Label
var _toast_plate: Panel
var _toast_label: Label
var _labels: Array[Label] = []
var _label_sizes: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	apply_layout(get_viewport_rect().size)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_refresh_all()


## Wires the HUD to the game. Any argument may be null; the HUD then shows its idle state for that part.
func bind(
	health: Health, economy: Economy, walker: Node3D, camera: Camera3D, home: Vector3, recall: RecallHold
) -> void:
	unbind()
	_health = health
	_economy = economy
	_walker = walker
	_camera = camera
	_home = home
	_recall = recall
	if _health != null:
		_health.changed.connect(_on_health_changed)
		_on_health_changed(_health.hp, _health.max_hp)
	if _economy != null:
		_economy.changed.connect(_on_economy_changed)
		_economy.cache_changed.connect(_on_cache_changed)
	_refresh_all()


## Disconnects everything and drops every reference; call before the walker or economy is freed.
func unbind() -> void:
	if _health != null:
		_health.changed.disconnect(_on_health_changed)
	if _economy != null:
		_economy.changed.disconnect(_on_economy_changed)
		_economy.cache_changed.disconnect(_on_cache_changed)
	_health = null
	_economy = null
	_walker = null
	_camera = null
	_recall = null
	recall_fraction = 0.0
	_refresh_all()


## Queues a toast; one shows at a time, the next starts when the current one has faded out.
func show_toast(text: String, seconds: float = 4.0) -> void:
	_toast_queue.append([text, maxf(seconds, 0.0)])
	if _toast_left <= 0.0:
		_next_toast()


func set_enter_prompt(shown: bool) -> void:
	_enter_prompt = shown
	_apply_visibility()


## Toasts waiting behind the one on screen.
func toast_queue_size() -> int:
	return _toast_queue.size()


func toast_alpha() -> float:
	return _toast_plate.modulate.a if _toast_plate.visible else 0.0


func is_low() -> bool:
	return _low


func cache_mark_visible() -> bool:
	return _cache_mark.visible


func compass_pad_px() -> float:
	return 40.0


## Strip-local x (reference pixels) of a bearing (degrees, right positive); beyond the span it pins to the ends.
func compass_x(bearing_deg_value: float) -> float:
	var half: float = compass_size.x * 0.5 - compass_pad_px()
	return compass_size.x * 0.5 + clampf(bearing_deg_value / compass_half_span_deg, -1.0, 1.0) * half


## Strip-local centre x (reference pixels) of a compass mark ("home" or "cache"), after the last layout.
func mark_x(which: String) -> float:
	var mark: ColorRect = _home_mark if which == "home" else _cache_mark
	return (mark.position.x + mark.size.x * 0.5) / _scale


## Signed angle (degrees, right positive) from the camera heading to a world point, on the ground plane.
static func bearing_deg(cam_basis: Basis, from: Vector3, to: Vector3) -> float:
	var forward := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z)
	var right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z)
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if forward.length() < 0.0001 or d.length() < 0.0001:
		return 0.0
	return rad_to_deg(atan2(d.dot(right.normalized()), d.dot(forward.normalized())))


## The visible elements as screen rects at this viewport size (lays out first).
func element_rects(view: Vector2) -> Array[Rect2]:
	apply_layout(view)
	var out: Array[Rect2] = []
	for plate: Panel in [_hp_plate, _scrap_plate, _compass_plate, _prompt_plate, _recall_plate, _toast_plate]:
		if plate.visible:
			out.append(Rect2(plate.position, plate.size))
	return out


## Sum of the visible element areas over the screen area.
func area_fraction(view: Vector2) -> float:
	var total: float = 0.0
	for r: Rect2 in element_rects(view):
		total += r.get_area()
	return total / (view.x * view.y)


## Every Control in the HUD, for the mouse_filter check.
func all_controls() -> Array[Control]:
	var out: Array[Control] = [self]
	for node: Node in find_children("*", "Control", true, false):
		out.append(node as Control)
	return out


## Positions and sizes everything for a viewport of this size.
func apply_layout(view: Vector2) -> void:
	_scale = view.y / REFERENCE_HEIGHT
	var s: float = _scale
	var m: float = margin_px * s
	_place(_hp_plate, Vector2(m, view.y - m - hp_size.y * s), hp_size * s)
	_place(_scrap_plate, Vector2(view.x - m - scrap_size.x * s, m), scrap_size * s)
	_place(_compass_plate, Vector2((view.x - compass_size.x * s) * 0.5, m), compass_size * s)
	_place(_prompt_plate, Vector2((view.x - prompt_size.x * s) * 0.5, view.y * prompt_y), prompt_size * s)
	_place(_recall_plate, Vector2((view.x - recall_size.x * s) * 0.5, view.y * recall_y), recall_size * s)
	_place(_toast_plate, Vector2((view.x - toast_size.x * s) * 0.5, view.y * toast_y), toast_size * s)
	# HP plate contents
	_place(_hp_label, Vector2(14, 2) * s, Vector2(160, 30) * s)
	_place(_hp_low_tag, Vector2(hp_size.x - 14 - 80, 2) * s, Vector2(80, 30) * s)
	var bar_w: float = (hp_size.x - 28) * s
	_hp_tick.size = Vector2(2 * s, 22 * s)
	_hp_tick.position = Vector2(14 * s + bar_w * low_hp_fraction - s, 36 * s)
	_place_hp_fill()
	# scrap plate contents
	_scrap_icon.size = Vector2(14, 14) * s
	_scrap_icon.pivot_offset = _scrap_icon.size * 0.5
	_scrap_icon.rotation = PI * 0.25
	_scrap_icon.position = Vector2(16, 17) * s
	_place(_carried_tag, Vector2(38, 14) * s, Vector2(100, 22) * s)
	_place(_carried_label, Vector2(120, 4) * s, Vector2(scrap_size.x - 134, 40) * s)
	_place(_banked_tag, Vector2(14, 58) * s, Vector2(100, 22) * s)
	_place(_banked_label, Vector2(120, 52) * s, Vector2(scrap_size.x - 134, 32) * s)
	# compass contents
	_compass_centre.size = Vector2(2, 8) * s
	_compass_centre.position = Vector2(compass_size.x * 0.5 - 1, 0) * s
	_place_compass_marks()
	# prompts
	_place(_prompt_label, Vector2.ZERO, prompt_size * s)
	_place(_recall_label, Vector2(12, 8) * s, Vector2(80, 28) * s)
	_recall_back.position = Vector2(96, 15) * s
	_recall_back.size = Vector2(recall_size.x - 96 - 14, 14) * s
	_recall_fill.position = _recall_back.position
	_place_recall_fill()
	_place(_toast_label, Vector2.ZERO, toast_size * s)
	for label: Label in _labels:
		label.add_theme_font_size_override("font_size", maxi(roundi(float(_label_sizes[label]) * s), 8))
		label.add_theme_constant_override("outline_size", maxi(roundi(3.0 * s), 2))


func _build() -> void:
	_hp_plate = _plate()
	_hp_label = _label(_hp_plate, "", 24, BODY, HORIZONTAL_ALIGNMENT_LEFT)
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_low_tag = _label(_hp_plate, "LOW", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_hp_low_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_back = _rect(_hp_plate, "HpBack", Color(1, 1, 1, 0.18))
	_hp_fill = _rect(_hp_plate, "HpFill", BODY)
	_hp_tick = _rect(_hp_plate, "HpNotch", BODY)

	_scrap_plate = _plate()
	_scrap_icon = _rect(_scrap_plate, "ScrapIcon", SALVAGE)
	_carried_tag = _label(_scrap_plate, "CARRIED", 16, MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	_carried_label = _label(_scrap_plate, "0", 36, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_carried_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banked_tag = _label(_scrap_plate, "BANKED", 16, MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	_banked_label = _label(_scrap_plate, "0", 24, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_banked_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_compass_plate = _plate()
	_compass_centre = _rect(_compass_plate, "CompassCentre", Color(1, 1, 1, 0.5))
	# Workshop: a square with a letter; cache: a diamond in the accent. Different shape and value, not only hue.
	_home_mark = _rect(_compass_plate, "HomeMark", BODY)
	_home_letter = Label.new()
	_home_letter.text = "W"
	_home_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_home_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_home_letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home_letter.add_theme_color_override("font_color", INK)
	_home_mark.add_child(_home_letter)
	_cache_mark = _rect(_compass_plate, "CacheMark", ACCENT)
	_home_dist = _label(_compass_plate, "", 16, BODY, HORIZONTAL_ALIGNMENT_CENTER)
	_cache_dist = _label(_compass_plate, "", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)

	_prompt_plate = _plate()
	_prompt_label = _label(_prompt_plate, "F  Workshop", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_recall_plate = _plate()
	_recall_label = _label(_recall_plate, "Recall", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_recall_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_recall_back = _rect(_recall_plate, "RecallBack", Color(1, 1, 1, 0.18))
	_recall_fill = _rect(_recall_plate, "RecallFill", BODY)

	_toast_plate = _plate()
	_toast_label = _label(_toast_plate, "", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _plate() -> Panel:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = plate_color
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel


func _rect(parent: Control, node_name: String, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _label(parent: Control, text: String, size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	parent.add_child(label)
	_labels.append(label)
	_label_sizes[label] = size
	return label


func _place(c: Control, pos: Vector2, sz: Vector2) -> void:
	c.position = pos
	c.size = sz


func _place_hp_fill() -> void:
	var s: float = _scale
	var bar_w: float = (hp_size.x - 28) * s
	_hp_back.position = Vector2(14, 36) * s
	_hp_back.size = Vector2(bar_w, 22 * s)
	_hp_fill.position = _hp_back.position
	_hp_fill.size = Vector2(bar_w * hp_fraction, 22 * s)


func _place_recall_fill() -> void:
	_recall_fill.size = Vector2(_recall_back.size.x * recall_fraction, _recall_back.size.y)


func _place_compass_marks() -> void:
	var s: float = _scale
	var mark := Vector2(18, 18) * s
	var home_b: float = 0.0
	var cache_b: float = 0.0
	if _camera != null and is_instance_valid(_camera) and _walker != null and is_instance_valid(_walker):
		home_b = bearing_deg(_camera.global_transform.basis, _walker.global_position, _home)
		if _economy != null and _economy.has_cache():
			cache_b = bearing_deg(_camera.global_transform.basis, _walker.global_position, _economy.cache_position)
	_home_mark.size = mark
	_home_mark.position = Vector2(compass_x(home_b) * s - mark.x * 0.5, 10 * s)
	_home_letter.position = Vector2.ZERO
	_home_letter.size = mark
	_home_letter.add_theme_font_size_override("font_size", maxi(roundi(14 * s), 8))
	var dsize := Vector2(76, 20) * s
	_home_dist.size = dsize
	_home_dist.position = Vector2(_home_mark.position.x + mark.x * 0.5 - dsize.x * 0.5, 32 * s)
	_cache_mark.size = mark * 0.8
	_cache_mark.pivot_offset = _cache_mark.size * 0.5
	_cache_mark.rotation = PI * 0.25
	_cache_mark.position = Vector2(compass_x(cache_b) * s - _cache_mark.size.x * 0.5, 11 * s)
	_cache_dist.size = dsize
	_cache_dist.position = Vector2(_cache_mark.position.x + _cache_mark.size.x * 0.5 - dsize.x * 0.5, 32 * s)
	# Two distance labels that would overlap are pushed apart (workshop left, cache right), never past the strip.
	var overlap: float = dsize.x * 0.7 - absf(_cache_dist.position.x - _home_dist.position.x)
	if _cache_mark.visible and overlap > 0.0:
		var dir: float = 1.0 if _cache_dist.position.x >= _home_dist.position.x else -1.0
		_cache_dist.position.x += dir * overlap * 0.5
		_home_dist.position.x -= dir * overlap * 0.5


func _on_viewport_resized() -> void:
	apply_layout(get_viewport_rect().size)


func _on_health_changed(hp: float, max_hp: float) -> void:
	hp_fraction = clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
	hp_text = "%d / %d" % [ceili(hp), roundi(max_hp)]
	_low = hp_fraction < low_hp_fraction
	_pulse_t = 0.0
	if _hp_plate != null:
		_refresh_hp()


func _on_economy_changed() -> void:
	if _hp_plate != null:
		_refresh_scrap()


func _on_cache_changed() -> void:
	if _hp_plate != null:
		_refresh_cache()


func _refresh_hp() -> void:
	_hp_label.text = hp_text
	_hp_fill.color = ACCENT if _low else BODY
	_hp_fill.modulate = Color.WHITE
	_hp_low_tag.visible = _low
	_place_hp_fill()


func _refresh_scrap() -> void:
	carried_text = str(_economy.carried_scrap) if _economy != null else "0"
	banked_text = str(_economy.banked_scrap) if _economy != null else "0"
	_carried_label.text = carried_text
	_banked_label.text = banked_text


func _refresh_cache() -> void:
	_cache_shown = _economy != null and _economy.has_cache()
	_apply_visibility()
	_update_compass()


func _refresh_all() -> void:
	if _hp_plate == null:
		return
	if _health == null:
		hp_fraction = 1.0
		hp_text = "-- / --"
		_low = false
	_refresh_hp()
	_refresh_scrap()
	_refresh_cache()


func _apply_visibility() -> void:
	if _hp_plate == null:
		return
	_prompt_plate.visible = _enter_prompt
	_recall_plate.visible = recall_fraction > 0.0
	_cache_mark.visible = _cache_shown
	_cache_dist.visible = _cache_shown
	_toast_plate.visible = _toast_left > 0.0
	_compass_plate.visible = _camera != null and _walker != null


func _next_toast() -> void:
	if _toast_queue.is_empty():
		_toast_left = 0.0
		_apply_visibility()
		return
	var item: Array = _toast_queue.pop_front()
	toast_text = item[0]
	_toast_total = float(item[1]) + toast_fade_in + toast_fade_out
	_toast_left = maxf(_toast_total, 0.001)
	_toast_label.text = toast_text
	_toast_plate.modulate.a = 0.0
	_apply_visibility()


func _update_compass() -> void:
	if _camera == null or _walker == null or not is_instance_valid(_camera) or not is_instance_valid(_walker):
		return
	_place_compass_marks()
	var from: Vector3 = _walker.global_position
	_home_dist.text = "%d m" % roundi(Vector2(_home.x - from.x, _home.z - from.z).length())
	if _cache_shown and _economy != null:
		var c: Vector3 = _economy.cache_position
		_cache_dist.text = "%d m" % roundi(Vector2(c.x - from.x, c.z - from.z).length())


func _process(delta: float) -> void:
	if _hp_plate == null:
		return
	if _low:
		_pulse_t += delta
		var wave: float = 0.5 + 0.5 * sin(_pulse_t / low_pulse_period * TAU)
		_hp_fill.color = ACCENT.lerp(Color.WHITE, wave)
	var tracking: bool = _camera != null and is_instance_valid(_camera) and _walker != null and is_instance_valid(_walker)
	_compass_plate.visible = tracking
	if tracking:
		_update_compass()
	var prog: float = 0.0
	if _recall != null and is_instance_valid(_recall):
		prog = _recall.progress
	if not is_equal_approx(prog, recall_fraction):
		recall_fraction = prog
		_place_recall_fill()
	_recall_plate.visible = recall_fraction > 0.0
	if _toast_left > 0.0:
		_toast_left -= delta
		var elapsed: float = _toast_total - _toast_left
		var a: float = 1.0
		if elapsed < toast_fade_in:
			a = elapsed / maxf(toast_fade_in, 0.001)
		elif _toast_left < toast_fade_out:
			a = _toast_left / maxf(toast_fade_out, 0.001)
		_toast_plate.modulate.a = clampf(a, 0.0, 1.0)
		if _toast_left <= 0.0:
			_next_toast()
