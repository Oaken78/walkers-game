class_name Main
extends Node3D
## The game (GDD 3, 12): boots into the workshop with the Scout, Tab leaves for the valley, and every trip home (F at
## the bench, death, recall) is a workshop visit. GameFlow decides who may do what; this node does the scene work.
##
## Scene work, in design terms:
##   - The workshop brings its own camera, environment, lights and walker, so it is instanced on every visit and
##     freed on exit. It sits 1000 m below the valley (so its floor never meets the valley collision) and is the
##     first child, so its WorldEnvironment wins while it is there.
##   - The field (walker, drones, pickups, camera, rig) lives under `Actors`. During a workshop visit `Actors` is
##     process-disabled and hidden, the valley is hidden, and nothing in the field moves.
##   - A return home always ends in Economy.bank(): Economy.banked repairs the walker, respawns the drones, and
##     SalvageField refills ring 1-2 nodes.

## The player is in the workshop and the scene is ready.
signal level_started
## The player left the workshop for the field.
signal field_entered
## A trip home finished and the workshop is up again. `kind` is a GameFlow.Kind.
signal workshop_entered(kind: int)

const WORKSHOP_SCENE: PackedScene = preload("res://scenes/workshop/workshop.tscn")
## The workshop hangs this far below the world origin.
const WORKSHOP_OFFSET: Vector3 = Vector3(0.0, -1000.0, 0.0)
## The walker spawns this far down-valley (+Z) of the bench, facing down-valley.
const SPAWN_AHEAD_M: float = 3.0
## Drop height of a spawned walker above the floor (m); it settles by itself.
const SPAWN_HEIGHT_M: float = 1.0
const TOAST_SECONDS: float = 4.0

var economy: Economy = Economy.new()
var inventory: Inventory = Inventory.new()
var build: WalkerBuild = WalkerBuild.scout()
var health: Health = Health.new(100.0)
var flow: GameFlow

var _workshop: Workshop = null
var _toast_left: float = 0.0
var _in_field: bool = false

@onready var _valley: Valley = %Valley
@onready var _actors: Node3D = %Actors
@onready var _walker: WalkerBody = %Walker
@onready var _collector: Collector = %Collector
@onready var _hurtbox: PlayerHurtbox = %PlayerHurtbox
@onready var _salvage: SalvageField = %SalvageField
@onready var _drones: DroneField = %DroneField
@onready var _orbit: OrbitCamera = %OrbitCamera
@onready var _rig: WeaponRig = %WeaponRig
@onready var _recall: RecallHold = %RecallHold
@onready var _hud: CanvasLayer = %Hud
@onready var _fade: ColorRect = %Fade
@onready var _toast: Label = %Toast
@onready var _pause: PauseGate = %PauseGate


func _ready() -> void:
	# After the walker (0), the collector (10), the drones (50), the rig (100) and the hurtbox (100).
	process_physics_priority = 300
	flow = GameFlow.new(economy)
	flow.field_started.connect(_on_field_started)
	flow.collapse_started.connect(_on_collapse_started)
	flow.fade_out_started.connect(_on_fade_out_started)
	flow.arrived_home.connect(_on_arrived_home)
	_orbit.capture_mouse = false
	_salvage.setup(economy)
	_collector.target = _walker
	_collector.economy = economy
	_drones.target = _walker
	_drones.spawn_sites()
	_hurtbox.health = health
	health.depleted.connect(_on_health_depleted)
	economy.banked.connect(_on_banked)
	_recall.target = _walker
	_recall.recall_requested.connect(_on_recall_requested)
	_recall.tapped.connect(_on_interact_tapped)
	_pause.pause_changed.connect(_on_pause_changed)
	_toast.visible = false
	_set_field_active(false)
	_show_workshop()
	level_started.emit()


func _physics_process(delta: float) -> void:
	flow.tick(delta)
	_pause.allowed = not flow.is_busy()


func _process(delta: float) -> void:
	_fade.color.a = flow.fade_alpha()
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.visible = false


# --- Read by the pilot and the scenarios ------------------------------------------------------------------------


func walker() -> WalkerBody:
	return _walker


func orbit() -> OrbitCamera:
	return _orbit


func drone_field() -> DroneField:
	return _drones


func salvage_field() -> SalvageField:
	return _salvage


func valley() -> Valley:
	return _valley


func current_workshop() -> Workshop:
	return _workshop


func is_in_field() -> bool:
	return _in_field


## The workshop bench on the valley floor: ring distances and the F range are measured from it.
func bench_position() -> Vector3:
	return (_valley.get_node("WorkshopSite") as Marker3D).global_position


## Metres on the ground between the walker and the bench.
func distance_to_bench() -> float:
	var d: Vector3 = _walker.global_position - bench_position()
	return Vector2(d.x, d.z).length()


var _mark: Vector3 = Vector3.ZERO

## Straight-line distance the walker moved since mark_walker() (scenarios).
var moved_since_mark: float:
	get:
		return _walker.global_position.distance_to(_mark)


func mark_walker() -> void:
	_mark = _walker.global_position


## Shows `text` for `seconds` at the top of the screen. (The field HUD takes this over once it is wired in.)
func show_toast(text: String, seconds: float = TOAST_SECONDS) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_left = seconds


# --- Workshop visit ---------------------------------------------------------------------------------------------


func _show_workshop() -> void:
	_in_field = false
	_set_field_active(false)
	if _workshop != null:
		_workshop.queue_free()
	_workshop = WORKSHOP_SCENE.instantiate()
	_workshop.position = WORKSHOP_OFFSET
	add_child(_workshop)
	move_child(_workshop, 0)
	_workshop.setup(build, inventory, economy)
	_workshop.exit_requested.connect(_on_exit_requested)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_exit_requested(requested: WalkerBuild) -> void:
	flow.request_exit(requested.is_valid())


func _on_field_started() -> void:
	# The workshop is done: its camera, environment and lights go with it.
	if _workshop != null:
		_workshop.queue_free()
		_workshop = null
	_in_field = true
	_set_field_active(true)
	health.set_max_hp(float(BuildStats.of(build)["hp"]))
	_walker.apply_build(build)
	_place_walker_at_bench()
	_unlock_player()
	_orbit.camera().make_current()
	_orbit.set_angles(OrbitMath.behind_yaw(-_walker.global_basis.z), _orbit.start_pitch_deg)
	_walker.reset_physics_interpolation()
	_orbit.snap()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	field_entered.emit()


func _place_walker_at_bench() -> void:
	var at: Vector3 = bench_position() + Vector3(0.0, 0.0, SPAWN_AHEAD_M)
	at.y = _valley.floor_height(at.x, at.z) + SPAWN_HEIGHT_M
	# Facing down-valley (+Z).
	_walker.teleport(Transform3D(Basis(Vector3.UP, PI), at))


## Everything in the field that moves, thinks or draws is on or off together.
func _set_field_active(active: bool) -> void:
	_actors.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	_actors.visible = active
	_valley.visible = active
	_hud.visible = active
	_recall.read_input = active
	_recall.reset()


func _lock_player() -> void:
	_walker.input_enabled = false
	_collector.enabled = false
	_rig.input_enabled = false
	_recall.read_input = false
	_recall.reset()
	# A hit in the same physics step must not reach the hurtbox again.
	_hurtbox.set_deferred("monitorable", false)


func _unlock_player() -> void:
	_walker.input_enabled = true
	_collector.enabled = true
	_rig.input_enabled = true
	_recall.read_input = true
	_recall.reset()
	_hurtbox.monitorable = true


# --- Trips home -------------------------------------------------------------------------------------------------


func _on_health_depleted() -> void:
	flow.request_death(_walker.global_position)


func _on_collapse_started() -> void:
	_lock_player()
	# Health.depleted can fire inside a physics callback (a bolt hit): the collapse queries the world, so wait.
	_walker.collapse.call_deferred(GameFlow.COLLAPSE_S)


func _on_fade_out_started(kind: GameFlow.Kind) -> void:
	if kind != GameFlow.Kind.DEATH:
		_lock_player()


func _on_recall_requested(position: Vector3) -> void:
	flow.request_recall(position)


func _on_interact_tapped() -> void:
	flow.request_enter(distance_to_bench())


## Economy.banked, also for 0 carried scrap: a bank repairs the walker and puts the drones back.
func _on_banked(_amount: int) -> void:
	health.repair_full()
	_drones.respawn_all()


func _on_arrived_home(kind: GameFlow.Kind, cache_amount: int, cache_position: Vector3) -> void:
	_show_workshop()
	if kind != GameFlow.Kind.ENTER and cache_amount > 0:
		var d: Vector3 = cache_position - bench_position()
		show_toast("Wreck cache: %d scrap at %d m" % [cache_amount, roundi(Vector2(d.x, d.z).length())])
	workshop_entered.emit(kind)


func _on_pause_changed(paused: bool) -> void:
	if paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif _in_field:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
