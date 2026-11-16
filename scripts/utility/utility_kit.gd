extends Node3D
## Utilitaires génériques du joueur, à ajouter comme enfant d'un exercice.
##
##   1 — FUMIGÈNE : ouvre la mini-carte ; un clic gauche pose le fumigène à cet
##       endroit (clic droit ou 1 pour annuler). Il bloque la vue — la tienne
##       et celle des bots — mais pas les balles.
##   2 — INCENDIAIRE et 3 — FLASH : sélection, puis clic droit pour lancer dans
##       la direction du viseur (trajectoire balistique, rebonds).
##       L'incendiaire couvre une zone au sol qui blesse quiconque s'y trouve.
##       Le flash aveugle ceux qui l'ont dans leur champ de vision, toi compris.
##
## Ce sont des utilitaires génériques, pas les compétences d'un personnage précis.

signal detonated(kind: int, at: Vector3)

enum Kind { SMOKE, INCENDIARY, FLASH }

const PlayerController := preload("res://scripts/player.gd")
const Hud := preload("res://ui/hud.gd")
const NavGrid := preload("res://scripts/ai/nav_grid.gd")
const Grenade := preload("res://scripts/utility/grenade.gd")
const TacticalMap := preload("res://ui/tactical_map.gd")

const NAMES := ["FUMIGÈNE", "INCENDIAIRE", "FLASH"]
const NAV_BOUNDS := Rect2(-76.0, -74.0, 152.0, 148.0)
## Couche de collision des fumigènes : vue seulement, jamais les balles.
const SMOKE_LAYER := 8
const SMOKE_RADIUS := 4.0
const SMOKE_SECONDS := 15.0
const SMOKE_DELAY := 1.0
const FIRE_RADIUS := 3.5
const FIRE_SECONDS := 7.0
const FIRE_DAMAGE_PER_SECOND := 35.0
const FLASH_RANGE := 35.0
const FLASH_SECONDS := 2.2
const THROW_SPEED := 22.0

var player: PlayerController
var hud: Hud
## Nombre de charges par utilitaire ; -1 = illimité.
var charges: Array[int] = [2, 2, 2]
var selected: int = Kind.INCENDIARY
var throws: Array[int] = [0, 0, 0]

var _nav := NavGrid.new()
var _map: TacticalMap
var _smokes: Array[Node3D] = []
var _smoke_timers: Array[float] = []
var _fires: Array[Node3D] = []
var _fire_timers: Array[float] = []
var _pending_smokes: Array[Vector3] = []
var _pending_timers: Array[float] = []


## À appeler dans setup() de l'exercice.
func start(player_node: PlayerController, hud_node: Hud, map_root: Node3D, charge_count: int) -> void:
	player = player_node
	hud = hud_node
	charges = [charge_count, charge_count, charge_count]
	_nav.build(map_root, NAV_BOUNDS)
	_map = TacticalMap.new()
	_map.visible = false
	hud.add_child(_map)
	_map.set_nav(_nav)
	_map.position_chosen.connect(_on_map_position_chosen)
	_map.cancelled.connect(close_map)
	player.utility_key_pressed.connect(_on_utility_key)
	player.utility_throw_requested.connect(_on_throw_requested)
	player.utility_enabled = true
	_announce()


func _exit_tree() -> void:
	if _map != null and is_instance_valid(_map):
		_map.queue_free()
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and player != null and player.look_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_tick(_smokes, _smoke_timers, delta)
	_tick(_fires, _fire_timers, delta)
	for index in range(_pending_timers.size() - 1, -1, -1):
		_pending_timers[index] -= delta
		if _pending_timers[index] <= 0.0:
			_spawn_smoke(_pending_smokes[index])
			_pending_smokes.remove_at(index)
			_pending_timers.remove_at(index)
	if _map != null and _map.visible:
		_map.update_state(player.global_position, player.yaw_deg, smoke_positions(), SMOKE_RADIUS,
				"FUMIGÈNE · clic gauche : poser · %s : fermer · reste %s" % [GameSettings.key_label("util1"), _charge_text(Kind.SMOKE)])


func is_map_open() -> bool:
	return _map != null and _map.visible


## Vrai si `world_position` est dans une zone incendiaire active.
func is_burning(world_position: Vector3) -> bool:
	for fire in _fires:
		var offset := Vector2(world_position.x - fire.global_position.x, world_position.z - fire.global_position.z)
		if offset.length() <= FIRE_RADIUS and absf(world_position.y - fire.global_position.y) < 2.5:
			return true
	return false


func smoke_positions() -> PackedVector3Array:
	var positions := PackedVector3Array()
	for smoke in _smokes:
		positions.append(smoke.global_position)
	return positions


func close_map() -> void:
	if _map == null or not _map.visible:
		return
	_map.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------------------

func _on_utility_key(index: int) -> void:
	if index == Kind.SMOKE:
		if is_map_open():
			close_map()
		elif _has_charge(Kind.SMOKE):
			_map.visible = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			hud.show_feedback("Plus de fumigène", Hud.COLOR_BAD)
		return
	selected = index
	_announce()


func _on_map_position_chosen(world_position: Vector3) -> void:
	_use_charge(Kind.SMOKE)
	_pending_smokes.append(world_position)
	_pending_timers.append(SMOKE_DELAY)
	close_map()
	hud.show_feedback("FUMIGÈNE EN ROUTE · reste %s" % _charge_text(Kind.SMOKE), Hud.COLOR_INFO)
	Telemetry.log_event("utility", {"kind": "smoke", "at": world_position})


func _on_throw_requested(origin: Vector3, direction: Vector3) -> void:
	if is_map_open() or selected == Kind.SMOKE:
		return
	if not _has_charge(selected):
		hud.show_feedback("Plus de %s" % str(NAMES[selected]).to_lower(), Hud.COLOR_BAD)
		return
	_use_charge(selected)
	var grenade := Grenade.new()
	grenade.kind = Grenade.Kind.INCENDIARY if selected == Kind.INCENDIARY else Grenade.Kind.FLASH
	grenade.velocity = (direction + Vector3(0.0, 0.12, 0.0)).normalized() * THROW_SPEED
	grenade.position = origin + direction * 0.6
	add_child(grenade)
	grenade.detonated.connect(_on_grenade_detonated)
	_announce()
	Telemetry.log_event("utility", {"kind": str(NAMES[selected]).to_lower(), "from": origin})


func _on_grenade_detonated(grenade_kind: int, at: Vector3) -> void:
	if grenade_kind == Grenade.Kind.INCENDIARY:
		_spawn_fire(at)
		detonated.emit(Kind.INCENDIARY, at)
	else:
		_flash_player(at)
		detonated.emit(Kind.FLASH, at)
	Sfx.play(&"kill", 0.6)


func _spawn_smoke(at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = SMOKE_LAYER
	body.collision_mask = 0
	body.position = Vector3(at.x, SMOKE_RADIUS * 0.6, at.z)
	var shape := SphereShape3D.new()
	shape.radius = SMOKE_RADIUS
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var mesh := SphereMesh.new()
	mesh.radius = SMOKE_RADIUS
	mesh.height = SMOKE_RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.78, 0.82, 0.88, 0.97)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(visual)
	add_child(body)
	_smokes.append(body)
	_smoke_timers.append(SMOKE_SECONDS)
	detonated.emit(Kind.SMOKE, at)
	Sfx.play(&"beep", 0.5)


func _spawn_fire(at: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = FIRE_RADIUS
	mesh.bottom_radius = FIRE_RADIUS
	mesh.height = 0.12
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.35, 0.05, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(1.0, 0.4, 0.05)
	material.emission_energy_multiplier = 2.5
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.position = at + Vector3(0.0, 0.07, 0.0)
	add_child(visual)
	_fires.append(visual)
	_fire_timers.append(FIRE_SECONDS)


## Aveugle le joueur si l'explosion est dans son champ de vision et non masquée.
func _flash_player(at: Vector3) -> void:
	var eye := player.eye_position()
	if eye.distance_to(at) > FLASH_RANGE:
		return
	var offset: Vector2 = Telemetry.angular_offset_to(at)
	if absf(offset.x) > 70.0 or absf(offset.y) > 50.0:
		return
	var query := PhysicsRayQueryParameters3D.create(eye, at, 1 | SMOKE_LAYER)
	if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		hud.flash_screen(FLASH_SECONDS)


func _tick(nodes: Array[Node3D], timers: Array[float], delta: float) -> void:
	for index in range(timers.size() - 1, -1, -1):
		timers[index] -= delta
		if timers[index] <= 0.0:
			nodes[index].queue_free()
			nodes.remove_at(index)
			timers.remove_at(index)


func _has_charge(kind: int) -> bool:
	return charges[kind] != 0


func _use_charge(kind: int) -> void:
	throws[kind] += 1
	if charges[kind] > 0:
		charges[kind] -= 1


func _charge_text(kind: int) -> String:
	return "∞" if charges[kind] < 0 else str(charges[kind])


func _announce() -> void:
	hud.show_feedback("%s · %s pour lancer  (%s fumigène %s · %s incendiaire %s · %s flash %s)" % [
		str(NAMES[selected]).to_upper(), GameSettings.key_label("throw"),
		GameSettings.key_label("util1"), _charge_text(Kind.SMOKE), GameSettings.key_label("util2"), _charge_text(Kind.INCENDIARY),
		GameSettings.key_label("util3"), _charge_text(Kind.FLASH)], Hud.COLOR_INFO, 2.2)
