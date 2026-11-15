extends Node3D
## Chef d'orchestre de la scène principale : états de jeu, mode Gridshot,
## score, effets visuels et liaison entre le joueur, l'UI et la télémétrie.
##
## Gridshot : une grille invisible fait face au joueur. `simultaneous_targets`
## sphères y sont présentes en permanence ; dès qu'une cible est détruite, une
## autre apparaît instantanément dans une cellule libre différente.

enum State { MENU, COUNTDOWN, PLAYING, RESULTS }

const TARGET_SCENE: PackedScene = preload("res://scenes/target.tscn")
const EXPLOSION_SCENE: PackedScene = preload("res://scenes/effects/target_explosion.tscn")
const IMPACT_SCENE: PackedScene = preload("res://scenes/effects/impact.tscn")
const TRACER_SCENE: PackedScene = preload("res://scenes/effects/tracer.tscn")

const PlayerController := preload("res://scripts/player.gd")
const AimTarget := preload("res://scripts/target.gd")
const Tracer := preload("res://scripts/tracer.gd")
const Hud := preload("res://ui/hud.gd")
const MainMenu := preload("res://ui/main_menu.gd")
const StatsDashboard := preload("res://ui/stats_dashboard.gd")

## Point situé derrière le mur du fond : les effets y sont instanciés une fois
## pendant le compte à rebours pour compiler leurs shaders hors champ.
const PREWARM_POSITION := Vector3(0.0, 4.0, -30.0)
## Plafond d'images appliqué hors session (menu, rapport) quand le FPS est illimité.
const MENU_MAX_FPS := 120

@export_group("Session")
@export var mode_name: String = "GRIDSHOT"
@export_range(5.0, 300.0, 1.0) var session_duration: float = 60.0
@export_range(0.0, 10.0, 0.5) var countdown_duration: float = 3.0

@export_group("Gridshot")
@export_range(2, 9) var grid_columns: int = 5
@export_range(2, 9) var grid_rows: int = 5
## Distance entre deux cellules voisines (m).
@export var cell_spacing: float = 1.0
## Distance entre les yeux du joueur et le plan de la grille (m).
@export var grid_distance: float = 9.0
@export var target_radius: float = 0.38
@export_range(1, 8) var simultaneous_targets: int = 3

@export_group("Score")
@export var hit_points: int = 100
## Bonus maximal accordé quand deux cibles sont détruites coup sur coup.
@export var speed_bonus_points: int = 100
@export var miss_penalty: int = 35

var state: int = State.MENU
var score: int = 0
var shots: int = 0
var hits: int = 0

## Vector2i (cellule) -> cible présente dans cette cellule.
var _occupied: Dictionary = {}
var _next_target_id: int = 0
var _session_start_usec: int = 0
var _countdown_end_usec: int = 0
var _last_hit_usec: int = 0
var _last_countdown_shown: int = -1
var _rng := RandomNumberGenerator.new()

@onready var arena: Node3D = $Arena
@onready var player: PlayerController = $Player
@onready var targets_root: Node3D = $Targets
@onready var effects_root: Node3D = $Effects
@onready var hud: Hud = $UI/HUD
@onready var main_menu: MainMenu = $UI/MainMenu
@onready var dashboard: StatsDashboard = $UI/StatsDashboard


func _ready() -> void:
	_rng.randomize()
	player.fired.connect(_on_player_fired)
	main_menu.play_requested.connect(start_session)
	main_menu.quit_requested.connect(_quit)
	dashboard.replay_requested.connect(start_session)
	dashboard.menu_requested.connect(_show_menu)
	GameSettings.graphics_changed.connect(_apply_graphics)
	_apply_graphics()
	_show_menu()


func _process(_delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_update_countdown()
		State.PLAYING:
			_update_session()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		if state != State.MENU:
			_show_menu()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_F11:
			GameSettings.fullscreen = not GameSettings.fullscreen
			GameSettings.commit_graphics()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Une session interrompue (alt-tab) fausserait les statistiques : on l'abandonne.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if state == State.COUNTDOWN or state == State.PLAYING:
			_show_menu()


# ---------------------------------------------------------------------------
# États de jeu
# ---------------------------------------------------------------------------

func start_session() -> void:
	if Telemetry.recording:
		Telemetry.cancel_session()
	_clear_targets()
	score = 0
	shots = 0
	hits = 0

	main_menu.visible = false
	dashboard.visible = false
	hud.visible = true
	hud.reset(mode_name, session_duration)

	player.reset_view()
	player.look_enabled = true
	player.fire_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_set_state(State.COUNTDOWN)
	_countdown_end_usec = Time.get_ticks_usec() + int(countdown_duration * 1000000.0)
	_last_countdown_shown = -1
	_fill_grid()
	_prewarm_effects()


func _update_countdown() -> void:
	var remaining := float(_countdown_end_usec - Time.get_ticks_usec()) / 1000000.0
	if remaining <= 0.0:
		_begin_play()
		return
	var shown := ceili(remaining)
	if shown != _last_countdown_shown:
		_last_countdown_shown = shown
		hud.show_countdown(str(shown))


func _begin_play() -> void:
	_set_state(State.PLAYING)
	_session_start_usec = Time.get_ticks_usec()
	_last_hit_usec = _session_start_usec
	player.fire_enabled = true
	hud.show_countdown("GO", 0.4)
	Telemetry.begin_session(mode_name, session_duration, player.camera)


func _update_session() -> void:
	var elapsed := float(Time.get_ticks_usec() - _session_start_usec) / 1000000.0
	var remaining := session_duration - elapsed
	hud.set_time_remaining(maxf(remaining, 0.0))
	if remaining <= 0.0:
		_finish_session()


func _finish_session() -> void:
	_set_state(State.RESULTS)
	player.look_enabled = false
	player.fire_enabled = false
	var report: Dictionary = Telemetry.end_session(score)
	_clear_targets()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	dashboard.show_report(report)


func _show_menu() -> void:
	if Telemetry.recording:
		Telemetry.cancel_session()
	_set_state(State.MENU)
	_clear_targets()
	player.look_enabled = false
	player.fire_enabled = false
	player.reset_view()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	dashboard.visible = false
	main_menu.visible = true


func _quit() -> void:
	get_tree().quit()


func _set_state(new_state: int) -> void:
	state = new_state
	_apply_frame_cap()


## En session : limite choisie par le joueur (0 = illimité, meilleure résolution
## temporelle pour la télémétrie). Hors session : plafonné pour ménager le GPU.
func _apply_frame_cap() -> void:
	var user_cap: int = GameSettings.max_fps
	var in_session := state == State.COUNTDOWN or state == State.PLAYING
	if in_session or (user_cap > 0 and user_cap <= MENU_MAX_FPS):
		Engine.max_fps = user_cap
	else:
		Engine.max_fps = MENU_MAX_FPS


# ---------------------------------------------------------------------------
# Gridshot
# ---------------------------------------------------------------------------

func _cell_position(cell: Vector2i) -> Vector3:
	var center := player.camera.global_position + Vector3(0.0, 0.0, -grid_distance)
	var offset_x := (float(cell.x) - float(grid_columns - 1) * 0.5) * cell_spacing
	var offset_y := (float(cell.y) - float(grid_rows - 1) * 0.5) * cell_spacing
	return center + Vector3(offset_x, offset_y, 0.0)


func _fill_grid() -> void:
	while _occupied.size() < simultaneous_targets:
		if not _spawn_target(Vector2i(-1, -1)):
			break


## Fait apparaître une cible dans une cellule libre tirée au hasard, différente
## de `excluded` (la cellule qui vient d'être libérée).
func _spawn_target(excluded: Vector2i) -> bool:
	var free_cells: Array[Vector2i] = []
	for column in grid_columns:
		for row in grid_rows:
			var candidate := Vector2i(column, row)
			if candidate != excluded and not _occupied.has(candidate):
				free_cells.append(candidate)
	if free_cells.is_empty():
		return false

	var chosen: Vector2i = free_cells[_rng.randi_range(0, free_cells.size() - 1)]
	var target := TARGET_SCENE.instantiate() as AimTarget
	target.configure(_next_target_id, chosen, target_radius)
	_next_target_id += 1
	target.position = _cell_position(chosen)
	targets_root.add_child(target)
	_occupied[chosen] = target
	return true


func _clear_targets() -> void:
	for value: Variant in _occupied.values():
		var target := value as AimTarget
		if is_instance_valid(target):
			target.destroy()
	_occupied.clear()


## Cible vivante la plus proche du viseur (en angle), ou null.
func _nearest_target() -> AimTarget:
	var best: AimTarget = null
	var best_angle := INF
	for value: Variant in _occupied.values():
		var candidate := value as AimTarget
		if not is_instance_valid(candidate) or not candidate.alive:
			continue
		var offset: Vector2 = Telemetry.angular_offset_to(candidate.global_position)
		var angle := offset.length()
		if angle < best_angle:
			best_angle = angle
			best = candidate
	return best


# ---------------------------------------------------------------------------
# Tirs
# ---------------------------------------------------------------------------

func _on_player_fired(collider: Object, hit_position: Vector3, hit_normal: Vector3, muzzle_position: Vector3) -> void:
	_spawn_tracer(muzzle_position, hit_position)
	if state != State.PLAYING:
		return
	shots += 1
	var target := collider as AimTarget
	if target != null and target.alive:
		_register_hit(target)
	else:
		_register_miss(collider != null, hit_position, hit_normal)
	hud.set_score(score)
	hud.set_accuracy(hits, shots)


func _register_hit(target: AimTarget) -> void:
	var now := Time.get_ticks_usec()
	var since_last_hit := float(now - _last_hit_usec) / 1000000.0
	_last_hit_usec = now
	hits += 1
	# Bonus de vitesse : complet sous 150 ms entre deux cibles, nul au-delà de 800 ms.
	var speed_factor := clampf(1.0 - (since_last_hit - 0.15) / 0.65, 0.0, 1.0)
	score += hit_points + roundi(float(speed_bonus_points) * speed_factor)

	var target_position := target.global_position
	Telemetry.record_shot(true, target_position, target.radius, target.target_id)

	var freed_cell := target.grid_cell
	_occupied.erase(freed_cell)
	target.destroy()
	_spawn_effect(EXPLOSION_SCENE, target_position, Vector3.ZERO)
	_spawn_target(freed_cell)
	hud.flash_hit()


func _register_miss(hit_world: bool, hit_position: Vector3, hit_normal: Vector3) -> void:
	score = maxi(score - miss_penalty, 0)
	var nearest := _nearest_target()
	if nearest != null:
		Telemetry.record_shot(false, nearest.global_position, nearest.radius, nearest.target_id)
	else:
		Telemetry.record_shot(false, Vector3.ZERO, 0.0, -1)
	if hit_world:
		_spawn_effect(IMPACT_SCENE, hit_position, hit_normal)
	hud.flash_miss()


# ---------------------------------------------------------------------------
# Effets
# ---------------------------------------------------------------------------

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var tracer := TRACER_SCENE.instantiate() as Tracer
	effects_root.add_child(tracer)
	tracer.fire(from, to)


## Instancie un effet ponctuel. Si `normal` est non nul, l'effet est orienté
## pour que son axe +Z local sorte de la surface touchée.
func _spawn_effect(scene: PackedScene, at: Vector3, normal: Vector3) -> void:
	var effect := scene.instantiate() as Node3D
	if normal.length_squared() > 0.5:
		var up := Vector3.UP if absf(normal.y) < 0.99 else Vector3.RIGHT
		effect.transform = Transform3D(Basis.looking_at(-normal, up), at + normal * 0.03)
	else:
		effect.position = at
	effects_root.add_child(effect)


func _prewarm_effects() -> void:
	_spawn_effect(EXPLOSION_SCENE, PREWARM_POSITION, Vector3.ZERO)
	_spawn_effect(IMPACT_SCENE, PREWARM_POSITION, Vector3.BACK)
	_spawn_tracer(PREWARM_POSITION, PREWARM_POSITION + Vector3(0.0, 0.0, -2.0))


# ---------------------------------------------------------------------------
# Graphismes
# ---------------------------------------------------------------------------

func _apply_graphics() -> void:
	var quality: int = GameSettings.quality
	var world_environment := arena.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world_environment != null and world_environment.environment != null:
		var environment := world_environment.environment
		environment.glow_enabled = true
		environment.ssao_enabled = quality >= GameSettings.Quality.QUALITY
		environment.ssr_enabled = quality >= GameSettings.Quality.ULTRA
		environment.sdfgi_enabled = quality >= GameSettings.Quality.ULTRA

	var viewport := get_viewport()
	if quality == GameSettings.Quality.PERFORMANCE:
		viewport.msaa_3d = Viewport.MSAA_DISABLED
	else:
		viewport.msaa_3d = Viewport.MSAA_4X

	var vsync_mode := DisplayServer.VSYNC_ENABLED if GameSettings.vsync else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vsync_mode)
	_apply_frame_cap()

	var window_mode := DisplayServer.window_get_mode()
	var is_fullscreen := window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or window_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var wants_fullscreen: bool = GameSettings.fullscreen
	if wants_fullscreen and not is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not wants_fullscreen and is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
