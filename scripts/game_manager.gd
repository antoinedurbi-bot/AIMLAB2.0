extends Node3D
## Chef d'orchestre de la scène principale : états de jeu, chargement de la
## carte et de l'exercice choisis, liaison entre le joueur, l'UI, la télémétrie,
## l'historique et le coach.
##
## Déroulé d'une session : menu → compte à rebours (carte chargée, joueur placé,
## cibles en place) → exercice → rapport (statistiques, conseil, enregistrement).

enum State { MENU, COUNTDOWN, PLAYING, RESULTS }

const PlayerController := preload("res://scripts/player.gd")
const DrillBase := preload("res://scripts/drills/drill_base.gd")
const DrillCatalog := preload("res://scripts/drills/drill_catalog.gd")
const FxSpawner := preload("res://scripts/fx_spawner.gd")
const Coach := preload("res://scripts/coach.gd")
const Hud := preload("res://ui/hud.gd")
const MainMenu := preload("res://ui/main_menu.gd")
const StatsDashboard := preload("res://ui/stats_dashboard.gd")

## Plafond d'images appliqué hors session (menu, rapport) quand le FPS est illimité.
const MENU_MAX_FPS := 120
## Nombre de sessions précédentes utilisées pour situer la session en cours.
const HISTORY_WINDOW := 5
## Distance devant le joueur où les effets sont préchauffés, derrière les murs.
const PREWARM_DISTANCE := 45.0

@export_range(0.0, 10.0, 0.5) var countdown_duration: float = 3.0

var state: int = State.MENU

var _map: Node3D
var _map_path: String = DrillCatalog.MAP_RANGE
var _drill: DrillBase
var _drill_id: String = "gridshot"
## Carte choisie pour les exercices multi-cartes (vide sinon) et clé d'historique associée.
var _chosen_map_path: String = ""
var _chosen_map_name: String = ""
var _history_key: String = "gridshot"
## Position du joueur dans la scène principale : point d'apparition par défaut du stand de tir.
var _default_spawn: Vector3 = Vector3.ZERO
var _session_start_usec: int = 0
var _countdown_end_usec: int = 0
var _last_countdown_shown: int = -1
var _shown_score: int = -1
var _shown_shots: int = -1

@onready var player: PlayerController = $Player
@onready var drill_root: Node3D = $Drill
@onready var fx: FxSpawner = $Effects
@onready var hud: Hud = $UI/HUD
@onready var main_menu: MainMenu = $UI/MainMenu
@onready var dashboard: StatsDashboard = $UI/StatsDashboard


func _ready() -> void:
	_map = $Arena
	_default_spawn = player.global_position
	player.fired.connect(_on_player_fired)
	main_menu.play_requested.connect(start_session)
	main_menu.quit_requested.connect(_quit)
	dashboard.replay_requested.connect(_replay)
	dashboard.menu_requested.connect(_show_menu)
	GameSettings.graphics_changed.connect(_apply_graphics)
	_apply_graphics()
	_show_menu()


func _process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_update_countdown()
		State.PLAYING:
			_update_session(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		if state == State.PLAYING and _drill != null and _drill.ends_on_cancel():
			_finish_session()
			get_viewport().set_input_as_handled()
		elif state != State.MENU:
			_show_menu()
			get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F11:
		GameSettings.fullscreen = not GameSettings.fullscreen
		GameSettings.commit_graphics()
		get_viewport().set_input_as_handled()
		return
	# Touche « utiliser » : action propre à l'exercice (désamorcer, valider).
	if state == State.PLAYING and _drill != null and event.is_pressed() and not event.is_echo():
		if GameSettings.action_for(GameSettings.event_code(event)) == "use":
			_drill.on_action()


func _notification(what: int) -> void:
	# Une session interrompue (alt-tab) fausserait les statistiques : on l'abandonne.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if state == State.COUNTDOWN or state == State.PLAYING:
			_show_menu()


# ---------------------------------------------------------------------------
# États de jeu
# ---------------------------------------------------------------------------

## Charge la carte de l'exercice, l'instancie et lance le compte à rebours.
func start_session(drill_id: String, chosen_map_path: String = "", chosen_map_name: String = "") -> void:
	_abort_session()
	var entry: Dictionary = DrillCatalog.find(drill_id)
	_drill_id = entry.get("id", "gridshot")
	_chosen_map_path = chosen_map_path
	_chosen_map_name = chosen_map_name
	_history_key = _drill_id if chosen_map_name == "" else "%s@%s" % [_drill_id, chosen_map_name]
	var map_path: String = entry.get("map", DrillCatalog.MAP_RANGE)
	if chosen_map_path != "":
		map_path = chosen_map_path
	_load_map(map_path)

	var drill_script := entry.get("script") as GDScript
	var drill := drill_script.new() as DrillBase
	drill.drill_id = _drill_id
	drill.title = entry.get("title", "")
	if chosen_map_name != "":
		drill.title = "%s · %s" % [drill.title, chosen_map_name.to_upper()]
	drill.duration = entry.get("duration", 60.0)
	drill.player = player
	drill.hud = hud
	drill.fx = fx
	drill.map_root = _map
	drill.difficulty = PlayerProfile.difficulty(_drill_id)
	var params: Dictionary = entry.get("params", {})
	for key: Variant in params:
		drill.set(str(key), params[key])
	_drill = drill
	drill_root.add_child(drill)

	main_menu.visible = false
	dashboard.visible = false
	hud.visible = true
	hud.reset(drill.title, drill.duration)
	_shown_score = -1
	_shown_shots = -1

	# Le joueur est placé avant setup() : les exercices s'appuient sur sa position.
	var spawn_name := drill.spawn_marker()
	if spawn_name == "":
		player.teleport(_default_spawn, 0.0)
	else:
		player.teleport(drill.marker(spawn_name), drill.marker_yaw(spawn_name))
	player.look_enabled = true
	player.fire_enabled = false
	player.move_enabled = false
	player.movement_inaccuracy = drill.uses_movement()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_set_state(State.COUNTDOWN)
	_countdown_end_usec = Time.get_ticks_usec() + int(countdown_duration * 1000000.0)
	_last_countdown_shown = -1
	drill.setup()
	var forward: Vector3 = -player.camera.global_transform.basis.z
	fx.prewarm(player.eye_position() + forward * PREWARM_DISTANCE + Vector3(0.0, 2.0, 0.0))


func _replay() -> void:
	start_session(_drill_id, _chosen_map_path, _chosen_map_name)


func _update_countdown() -> void:
	var remaining := float(_countdown_end_usec - Time.get_ticks_usec()) / 1000000.0
	if remaining <= 0.0:
		_begin_play()
		return
	var shown := ceili(remaining)
	if shown != _last_countdown_shown:
		_last_countdown_shown = shown
		hud.show_countdown(str(shown))
		Sfx.play(&"tick")


func _begin_play() -> void:
	_set_state(State.PLAYING)
	_session_start_usec = Time.get_ticks_usec()
	player.fire_enabled = _drill.uses_fire()
	player.move_enabled = _drill.uses_movement()
	hud.show_countdown("GO", 0.4)
	Sfx.play(&"go")
	Telemetry.begin_session(_drill.title, _drill.duration, player.camera, player)
	_drill.begin()


func _update_session(delta: float) -> void:
	var elapsed := float(Time.get_ticks_usec() - _session_start_usec) / 1000000.0
	_drill.elapsed = elapsed
	_drill.update(delta)

	if _drill.score != _shown_score:
		_shown_score = _drill.score
		hud.set_score(_drill.score)
	if _drill.shots != _shown_shots:
		_shown_shots = _drill.shots
		hud.set_accuracy(_drill.hits, _drill.shots)
	if _drill.shows_clock():
		hud.set_time_remaining(maxf(_drill.duration - elapsed, 0.0))

	if _drill.finished or elapsed >= _drill.duration:
		_finish_session()


func _finish_session() -> void:
	_set_state(State.RESULTS)
	player.look_enabled = false
	player.fire_enabled = false
	player.move_enabled = false
	player.reset_input()

	var report: Dictionary = Telemetry.end_session(_drill.score)
	report["drill"] = _drill_id
	_drill.finalize(report)

	report["map"] = _chosen_map_name
	report["weapon"] = GameSettings.weapon
	report["loud_distance_m"] = player.loud_distance
	# Difficulté adaptative et avancement de la routine du jour.
	if report.has("success_ratio"):
		var success: float = report.get("success_ratio", 0.5)
		report["next_difficulty_level"] = PlayerProfile.adjust_difficulty(_drill_id, success)
	PlayerProfile.mark_session(_drill_id)
	var previous: Array[Dictionary] = SessionHistory.recent(_history_key, HISTORY_WINDOW)
	var advice: Array[Dictionary] = Coach.build_advice(_drill_id, report, previous)
	if not advice.is_empty():
		report["advice"] = advice[0].get("title", "")
	if GameSettings.export_raw_telemetry:
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		var exported: String = Telemetry.export_raw("%s_%s" % [stamp, _drill_id], report)
		if exported != "":
			report["export_path"] = ProjectSettings.globalize_path(exported)
	SessionHistory.add_session(_history_key, report)

	var drill_title := _drill.title
	_free_drill()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	dashboard.show_report(drill_title, report, advice, previous)
	Sfx.play(&"success")


func _show_menu() -> void:
	_abort_session()
	_set_state(State.MENU)
	player.look_enabled = false
	player.fire_enabled = false
	player.move_enabled = false
	player.reset_input()
	player.reset_view()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	dashboard.visible = false
	main_menu.visible = true


## Abandonne la session en cours (télémétrie annulée, exercice libéré).
func _abort_session() -> void:
	if Telemetry.recording:
		Telemetry.cancel_session()
	_free_drill()


func _free_drill() -> void:
	if _drill != null:
		_drill.queue_free()
		_drill = null


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
# Carte
# ---------------------------------------------------------------------------

## Remplace la carte courante par celle de `path` (sans effet si elle est déjà chargée).
func _load_map(path: String) -> void:
	if path == _map_path and is_instance_valid(_map):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("KINETIC // AIM : carte introuvable : %s" % path)
		return
	if is_instance_valid(_map):
		remove_child(_map)
		_map.queue_free()
	_map = packed.instantiate() as Node3D
	_map.name = "Arena"
	add_child(_map)
	move_child(_map, 0)
	_map_path = path
	_apply_graphics()


# ---------------------------------------------------------------------------
# Tirs
# ---------------------------------------------------------------------------

func _on_player_fired(collider: Object, hit_position: Vector3, hit_normal: Vector3, muzzle_position: Vector3, shot: Dictionary) -> void:
	fx.tracer(muzzle_position, hit_position)
	Sfx.play(&"shot")
	if state == State.PLAYING and _drill != null:
		_drill.on_shot(collider, hit_position, hit_normal, shot)


# ---------------------------------------------------------------------------
# Graphismes
# ---------------------------------------------------------------------------

func _apply_graphics() -> void:
	var quality: int = GameSettings.quality
	if is_instance_valid(_map):
		var world_environment := _map.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
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
