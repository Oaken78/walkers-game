class_name LoopPilot
extends Node
## A scripted player for the loop_full scenario (T12): walks the real walker along a fixed route with real input
## actions (proportional turning, forward held), stops to shoot drones that come within range, picks up the scrap
## they drop, and ends a route at the bench with an F tap. Nothing here is gameplay: Main ships it only so the
## scenario can find it. It does nothing until a route is started.
##
## A route is a list of entries:
##   "ScrapSite_..."  walk onto that scrap node (skipped when it is already depleted)
##   "CACHE"          walk onto the wreck cache
##   "HOME"           walk to the bench and tap F (the route is over once the workshop is up)
##   "!DIE"           deal lethal damage here (a forced death), the route is over once the workshop is up
## `route_finished(report)` carries the numbers: seconds, scrap picked, damage taken, seconds to the first drone.

signal route_finished(report: Dictionary)

enum Mode { IDLE, WALK, FIGHT, WAIT_HOME }

const ROUTES: Dictionary = {
	"exp1": ["ScrapSite_R0_Wash", "ScrapSite_R0_Off", "ScrapSite_R1_OffA", "ScrapSite_R1_Wash", "ScrapSite_R1_OffB", "HOME"],
	"exp2": ["ScrapSite_R1_OffA", "ScrapSite_R1_Wash", "ScrapSite_R1_OffB", "ScrapSite_R2_OffA", "HOME"],
	"exp3": ["ScrapSite_R1_OffA", "ScrapSite_R1_Wash", "ScrapSite_R2_Wash", "!DIE"],
	"reclaim": ["CACHE", "HOME"],
}
## Parts the pilot tries to buy, best first: part id, socket to mount it on.
const SHOPPING: Array = [
	[&"armor_plate", &"top_1"],
	[&"leg_short", &"leg_l3"],
]

## Stop this close to a scrap node (the pickup range is 2.5 m; a node is claimed on the way in).
@export var arrive_m: float = 1.5
## The bench is within the 4 m F range at this distance.
@export var home_arrive_m: float = 3.0
## Drones inside this range are shot at (the drones' own sight range is 35 m).
@export var fight_range_m: float = 40.0
@export var fight_max_s: float = 15.0
## A drone the pilot gave up on is left alone this long.
@export var ignore_s: float = 6.0
## Scrap pieces dropped by a drone are picked up when this close.
@export var loot_range_m: float = 18.0
## Stand still this long after a kill so the husk can land and drop its scrap (0.7-1.1 s).
@export var loot_hold_s: float = 1.6
## No progress in this long aborts the route.
@export var stuck_s: float = 12.0
@export var stuck_move_m: float = 0.6
## Proportional turning: full stick at this heading error, forward only inside the band (degrees).
@export var turn_full_deg: float = 25.0
@export var forward_band_deg: float = 50.0
## Ticks the F key is held for a tap (a tap is under 0.3 s = 18 ticks).
@export var tap_ticks: int = 6

var mode: Mode = Mode.IDLE
var route_name: String = ""
var kills: int = 0
var stuck: bool = false
## Expedition number of the first purchase (0: none yet), and what was bought.
var first_purchase_expedition: int = 0
var purchases: Array[String] = []

var _main: Main
var _route: Array = []
var _index: int = 0
var _ticks: int = 0
var _picked_at_start: int = 0
var _banked_at_start: int = 0
var _damage: float = 0.0
var _first_drone_tick: int = -1
var _fight_target: Drone = null
var _fight_ticks: int = 0
var _ignored: Dictionary = {}
var _hold_ticks: int = 0
var _tap_left: int = 0
var _tapped: bool = false
var _last_pos: Vector3 = Vector3.ZERO
var _last_move_tick: int = 0
var _expedition: int = 0
var _hp_before: float = 0.0


func _ready() -> void:
	process_physics_priority = 400
	_main = get_parent() as Main
	set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if _main == null or not _main.is_in_field() and mode != Mode.WAIT_HOME:
		return
	_ticks += 1
	_track_damage()
	match mode:
		Mode.WALK:
			_walk()
		Mode.FIGHT:
			_fight()
		Mode.WAIT_HOME:
			_wait_home()


# --- Scenario API -----------------------------------------------------------------------------------------------


## Starts a named route (ROUTES). Call in the field.
func start_named(name_of_route: String) -> void:
	if not ROUTES.has(name_of_route):
		push_error("LoopPilot: unknown route %s" % name_of_route)
		return
	route_name = name_of_route
	if name_of_route.begins_with("exp"):
		_expedition += 1
	_route = ROUTES[name_of_route].duplicate()
	_index = 0
	_ticks = 0
	_picked_at_start = _main.economy.total_picked_up
	_banked_at_start = _main.economy.banked_scrap
	_damage = 0.0
	_hp_before = _main.health.hp
	_first_drone_tick = -1
	kills = 0
	stuck = false
	_ignored.clear()
	_tapped = false
	_tap_left = 0
	_hold_ticks = 0
	_last_pos = _main.walker().global_position
	_last_move_tick = 0
	mode = Mode.WALK
	if not _main.workshop_entered.is_connected(_on_workshop_entered):
		_main.workshop_entered.connect(_on_workshop_entered)
	set_physics_process(true)


## Buys the best affordable part on SHOPPING and mounts it, in the open workshop. Returns what was bought ("" nothing).
func shop() -> String:
	var workshop: Workshop = _main.current_workshop()
	if workshop == null:
		return ""
	for entry: Array in SHOPPING:
		var part: StringName = entry[0]
		if not workshop.buy(part):
			continue
		if not workshop.place_on(entry[1]):
			push_error("LoopPilot: bought %s but could not mount it on %s" % [part, entry[1]])
			return ""
		purchases.append(String(part))
		if first_purchase_expedition == 0:
			first_purchase_expedition = _expedition
		return String(part)
	return ""


## Leaves the workshop (the Tab key's path).
func leave_workshop() -> void:
	var workshop: Workshop = _main.current_workshop()
	if workshop != null:
		workshop.request_exit()


func release_all() -> void:
	for action: StringName in [&"move_forward", &"turn_left", &"turn_right", &"fire", &"interact"]:
		Input.action_release(action)


# --- Warp steps (the lean scenario teleports between stations) -----------------------------------------------


## Puts the walker `distance` m down-valley of a scrap node, facing it.
func warp_to_site(site_name: String, distance: float) -> void:
	var pickup: ScrapPickup = _main.salvage_field().pickup_for(site_name)
	_warp(pickup.global_position + Vector3(0.0, 0.0, distance))


func warp_to_cache(distance: float) -> void:
	_warp(_main.economy.cache_position + Vector3(0.0, 0.0, distance))


## Within the F range of the bench.
func warp_home(distance: float = 3.0) -> void:
	_warp(_main.bench_position() + Vector3(0.0, 0.0, distance))


func hurt(amount: float) -> void:
	_main.health.damage(amount)


func _warp(at: Vector3) -> void:
	at.y = _main.valley().floor_height(at.x, at.z) + 1.0
	_main.walker().teleport(Transform3D(Basis.IDENTITY, at))
	_main.orbit().snap()


var carried: int:
	get:
		return _main.economy.carried_scrap
var banked: int:
	get:
		return _main.economy.banked_scrap
var cache: int:
	get:
		return _main.economy.cache_amount
var lost: int:
	get:
		return _main.economy.lost
var spent: int:
	get:
		return _main.economy.spent
var conserved: bool:
	get:
		return _main.economy.is_conserved()
var hp_full: bool:
	get:
		return _main.health.hp >= _main.health.max_hp
var hp_now: float:
	get:
		return _main.health.hp
var in_field: bool:
	get:
		return _main.is_in_field()
var state_name: String:
	get:
		return GameFlow.State.keys()[_main.flow.state]
var cache_nodes: int:
	get:
		return 1 if _main.salvage_field().cache() != null else 0
## How far the wreck cache sits from the floor under it (m); 99 when there is none.
var cache_height_error: float:
	get:
		var c: WreckCache = _main.salvage_field().cache()
		if c == null:
			return 99.0
		return absf(c.global_position.y - _main.valley().floor_height(c.global_position.x, c.global_position.z))
var walker_collapsed: bool:
	get:
		return _main.walker().is_collapsed()


# --- Route ------------------------------------------------------------------------------------------------------


func _walk() -> void:
	var walker: WalkerBody = _main.walker()
	_check_stuck(walker)
	var drone: Drone = _nearest_drone()
	if _first_drone_tick < 0 and drone != null and _distance(walker.global_position, drone.global_position) <= DroneBrain.SIGHT_RANGE_M:
		_first_drone_tick = _ticks
	if drone != null and _distance(walker.global_position, drone.global_position) <= fight_range_m:
		_begin_fight(drone)
		return
	if _hold_ticks > 0:
		_hold_ticks -= 1
		_stop_walking()
		return
	var entry: String = _current_entry()
	if entry == "":
		return
	if entry == "!DIE":
		_stop_walking()
		mode = Mode.WAIT_HOME
		_main.health.damage(_main.health.max_hp * 10.0)
		return
	var goal: Vector3 = _goal_of(entry)
	var loose: LooseScrap = _nearest_loose(walker.global_position)
	if loose != null:
		goal = loose.global_position
	var flat: float = _distance(walker.global_position, goal)
	if loose == null:
		var limit: float = home_arrive_m if entry == "HOME" else arrive_m
		if flat <= limit:
			_arrived(entry)
			return
	_steer_to(walker, goal)


func _arrived(entry: String) -> void:
	if entry == "HOME":
		_stop_walking()
		mode = Mode.WAIT_HOME
		_tap_left = tap_ticks
		return
	_index += 1


## The next entry still worth walking to (depleted nodes are skipped, a missing cache ends the walk).
func _current_entry() -> String:
	while _index < _route.size():
		var entry: String = _route[_index]
		if entry.begins_with("ScrapSite_"):
			var pickup: ScrapPickup = _main.salvage_field().pickup_for(entry)
			if pickup == null or pickup.depleted:
				_index += 1
				continue
		if entry == "CACHE" and not _main.economy.has_cache():
			_index += 1
			continue
		return entry
	return ""


func _goal_of(entry: String) -> Vector3:
	if entry == "HOME":
		return _main.bench_position()
	if entry == "CACHE":
		return _main.economy.cache_position
	return _main.salvage_field().pickup_for(entry).global_position


func _wait_home() -> void:
	if _tap_left > 0:
		Input.action_press(&"interact")
		_tap_left -= 1
		if _tap_left == 0:
			Input.action_release(&"interact")
			_tapped = true


func _on_workshop_entered(_kind: int) -> void:
	if mode != Mode.WAIT_HOME:
		return
	mode = Mode.IDLE
	set_physics_process(false)
	release_all()
	route_finished.emit(report())


func report() -> Dictionary:
	var seconds: float = float(_ticks) / float(Engine.physics_ticks_per_second)
	var first_drone: float = -1.0
	if _first_drone_tick >= 0:
		first_drone = float(_first_drone_tick) / float(Engine.physics_ticks_per_second)
	return {
		"route": route_name,
		"seconds": seconds,
		"picked": _main.economy.total_picked_up - _picked_at_start,
		"banked": _main.economy.banked_scrap - _banked_at_start,
		"damage": _damage,
		"first_drone_s": first_drone,
		"kills": kills,
		"stuck": stuck,
	}


# --- Walking and shooting ---------------------------------------------------------------------------------------


func _steer_to(walker: WalkerBody, goal: Vector3) -> void:
	var error: float = _heading_error(walker, goal)
	var strength: float = clampf(absf(error) / turn_full_deg, 0.0, 1.0)
	_press(&"turn_left", strength if error > 0.0 else 0.0)
	_press(&"turn_right", strength if error < 0.0 else 0.0)
	_press(&"move_forward", 1.0 if absf(error) < forward_band_deg else 0.0)


## Signed heading error in degrees: positive means the goal is to the left (turn_left).
func _heading_error(walker: WalkerBody, goal: Vector3) -> float:
	var bearing: float = rad_to_deg(AimMath.bearing_to(walker.global_position, goal))
	return wrapf(bearing - rad_to_deg(walker.yaw_radians()), -180.0, 180.0)


func _stop_walking() -> void:
	_press(&"move_forward", 0.0)
	_press(&"turn_left", 0.0)
	_press(&"turn_right", 0.0)


func _press(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


func _begin_fight(drone: Drone) -> void:
	_fight_target = drone
	_fight_ticks = 0
	mode = Mode.FIGHT


func _fight() -> void:
	var walker: WalkerBody = _main.walker()
	if not is_instance_valid(_fight_target) or _fight_target.is_dead():
		if is_instance_valid(_fight_target):
			kills += 1
		_end_fight(true)
		return
	_fight_ticks += 1
	if float(_fight_ticks) / float(Engine.physics_ticks_per_second) > fight_max_s:
		_ignored[_fight_target] = _ticks + int(ignore_s * float(Engine.physics_ticks_per_second))
		_end_fight(false)
		return
	_press(&"move_forward", 0.0)
	var error: float = _heading_error(walker, _fight_target.global_position)
	var strength: float = clampf(absf(error) / turn_full_deg, 0.0, 1.0)
	_press(&"turn_left", strength if error > 0.0 else 0.0)
	_press(&"turn_right", strength if error < 0.0 else 0.0)
	var orbit: OrbitCamera = _main.orbit()
	var to: Vector3 = _fight_target.global_position - (walker.global_position + orbit.target_offset)
	var flat: float = Vector2(to.x, to.z).length()
	orbit.set_angles(rad_to_deg(atan2(-to.x, -to.z)), -rad_to_deg(atan2(to.y, flat)))
	Input.action_press(&"fire")


func _end_fight(killed: bool) -> void:
	Input.action_release(&"fire")
	_stop_walking()
	_fight_target = null
	if killed:
		_hold_ticks = int(loot_hold_s * float(Engine.physics_ticks_per_second))
	mode = Mode.WALK


func _nearest_drone() -> Drone:
	var best: Drone = null
	var best_d: float = INF
	var origin: Vector3 = _main.walker().global_position
	for encounter: DroneEncounter in _main.drone_field().encounters:
		for drone: Drone in encounter.drones:
			if not is_instance_valid(drone) or drone.is_dead():
				continue
			if _ignored.has(drone) and int(_ignored[drone]) > _ticks:
				continue
			var d: float = _distance(origin, drone.global_position)
			if d < best_d:
				best_d = d
				best = drone
	return best


func _nearest_loose(origin: Vector3) -> LooseScrap:
	var best: LooseScrap = null
	var best_d: float = loot_range_m
	for encounter: DroneEncounter in _main.drone_field().encounters:
		for child: Node in encounter.get_children():
			var piece := child as LooseScrap
			if piece == null or piece.is_queued_for_deletion() or not piece.visible:
				continue
			var d: float = _distance(origin, piece.global_position)
			if d < best_d:
				best_d = d
				best = piece
	return best


func _check_stuck(walker: WalkerBody) -> void:
	if _distance(walker.global_position, _last_pos) >= stuck_move_m:
		_last_pos = walker.global_position
		_last_move_tick = _ticks
		return
	if float(_ticks - _last_move_tick) / float(Engine.physics_ticks_per_second) > stuck_s:
		stuck = true
		_stop_walking()
		mode = Mode.IDLE
		set_physics_process(false)
		route_finished.emit(report())


func _track_damage() -> void:
	var hp: float = _main.health.hp
	if hp < _hp_before:
		_damage += _hp_before - hp
	_hp_before = hp


func _distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
