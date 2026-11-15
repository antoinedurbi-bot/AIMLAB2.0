extends "res://scripts/drills/drill_base.gd"
## Défense de la charge (après la pose) : la charge est posée sur un site tiré
## au sort. Des adversaires arrivent un à un, marchent jusqu'à elle et la
## désamorcent s'ils l'atteignent. Il faut les éliminer avant la fin du
## désamorçage et tenir jusqu'à l'explosion.
##
## Victoire : la charge explose. Défaite : un adversaire la désamorce.
## Mesures : adversaires éliminés, combien ont atteint la charge, progression
## maximale du désamorçage adverse, temps pour éliminer, tirs à la tête.

const Humanoid := preload("res://scripts/humanoid_target.gd")
const Bomb := preload("res://scripts/bomb.gd")
const HUMANOID_SCENE: PackedScene = preload("res://scenes/humanoid_target.tscn")
const BOMB_SCENE: PackedScene = preload("res://scenes/bomb.tscn")

var fuse_seconds: float = 45.0
var defuse_seconds: float = 7.0
## Délai avant le premier adversaire, puis entre deux arrivées au niveau 1 (s).
var first_wave_delay: float = 7.0
var wave_interval: float = 6.0
var enemy_speed: float = 4.2
## Distance minimale d'apparition par rapport à la charge (m).
var min_spawn_distance: float = 9.0

var _site: String = ""
var _bomb: Bomb
var _bomb_position: Vector3 = Vector3.ZERO
var _enemies: Array[Humanoid] = []
var _spawn_usec: Dictionary = {}
var _wave_timer: float = 0.0
var _result: String = ""

var _kills: int = 0
var _reached: int = 0
var _head_hits: int = 0
var _body_hits: int = 0
var _max_defuse: float = 0.0
var _kill_times: PackedFloat32Array = PackedFloat32Array()


func uses_movement() -> bool:
	return true


func spawn_marker() -> String:
	if _site == "":
		_choose_site()
	return "Lobby" + _site


func setup() -> void:
	if _site == "":
		_choose_site()
	duration = fuse_seconds + 1.0
	_bomb_position = marker("Site" + _site)
	_bomb = BOMB_SCENE.instantiate() as Bomb
	_bomb.fuse_seconds = fuse_seconds
	_bomb.defuse_seconds = defuse_seconds
	_bomb.position = _bomb_position
	add_child(_bomb)
	_bomb.exploded.connect(_on_bomb_exploded)
	_bomb.defused.connect(_on_bomb_defused)
	player.automatic = true
	player.recoil_enabled = true
	_wave_timer = first_wave_delay
	hud.set_objective("Charge posée sur le site %s. Rejoins-la et empêche les adversaires de la désamorcer jusqu'à l'explosion (%d s)." % [_site, roundi(fuse_seconds)])
	hud.set_speed_gauge_visible(true)
	hud.set_side_stat("ADVERSAIRES", "0 éliminés")


func begin() -> void:
	_bomb.arm()


func update(delta: float) -> void:
	hud.set_speed(player.horizontal_speed(), PlayerController.ACCURATE_SPEED, PlayerController.RUN_SPEED)
	if _result != "":
		return
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = wave_interval / difficulty
		_spawn_enemy()

	# Un adversaire arrivé sur la charge la désamorce tant qu'il est en vie.
	var someone_defusing := false
	for enemy in _enemies:
		if enemy.has_arrived():
			someone_defusing = true
	_bomb.set_defusing(someone_defusing, false)
	if someone_defusing:
		_max_defuse = maxf(_max_defuse, _bomb.defuse_progress)
		hud.set_clock_text("DÉSAMORÇAGE %.1f / %.0f s" % [_bomb.defuse_progress, defuse_seconds])


func shows_clock() -> bool:
	return not (_bomb != null and _bomb.is_being_defused())


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	shots += 1
	var speed: float = shot.get("speed", 0.0)
	var struck := collider as Humanoid
	if struck == null or not _enemies.has(struck):
		var nearest := _nearest_enemy()
		if nearest != null:
			Telemetry.record_shot(false, nearest.head_position(), Humanoid.HEAD_RADIUS, nearest.target_id, speed, {})
		else:
			Telemetry.record_shot(false, Vector3.ZERO, 0.0, -1, speed, {})
		if collider != null:
			fx.impact(hit_position, hit_normal)
		hud.flash_miss()
		return
	hits += 1
	var head := struck.is_head_hit(hit_position)
	Telemetry.record_shot(true, struck.head_position(), Humanoid.HEAD_RADIUS, struck.target_id, speed, {"head": head, "defusing": struck.has_arrived()})
	if head:
		_head_hits += 1
	else:
		_body_hits += 1
	hud.flash_hit()
	Sfx.play(&"hit")
	if struck.apply_damage(player.weapon_damage(head)):
		var now: int = shot.get("time_usec", Time.get_ticks_usec())
		var born: int = _spawn_usec.get(struck.target_id, now)
		_kills += 1
		_kill_times.append(float(now - born) / 1000.0)
		score += 150 + (50 if head else 0) + (100 if struck.has_arrived() else 0)
		fx.explosion(struck.head_position())
		Sfx.play(&"kill")
		hud.show_feedback("DÉSAMORÇAGE STOPPÉ" if struck.has_arrived() else "ÉLIMINÉ", Hud.COLOR_GOOD)
		hud.set_side_stat("ADVERSAIRES", "%d éliminés" % _kills)
		_enemies.erase(struck)
		struck.destroy()


func finalize(report: Dictionary) -> void:
	if _bomb != null:
		_bomb.stop()
	var won := _result == "exploded"
	report["bomb_site"] = _site
	report["bomb_defended"] = won
	report["bomb_enemies_killed"] = _kills
	report["bomb_enemies_reached"] = _reached
	report["bomb_max_enemy_defuse_s"] = _max_defuse
	report["bomb_avg_kill_ms"] = Stats.mean(_kill_times)
	report["headshot_rate"] = Stats.percent(_head_hits, _head_hits + _body_hits)
	report["difficulty_level"] = difficulty
	report["success_ratio"] = 1.0 if won and _reached <= 1 else (0.6 if won else 0.2)

	add_kpi(report, "CHARGE", "DÉFENDUE" if won else "DÉSAMORCÉE", "site %s" % _site)
	add_kpi(report, "ADVERSAIRES ÉLIMINÉS", str(_kills), "%d ont atteint la charge" % _reached)
	add_kpi(report, "DÉSAMORÇAGE ADVERSE MAX", "%.1f s" % _max_defuse, "sur %d s nécessaires" % roundi(defuse_seconds))
	add_kpi(report, "TEMPS POUR ÉLIMINER", "%d ms" % roundi(Stats.mean(_kill_times)) if _kills > 0 else "—", "de l'apparition à l'élimination")
	add_kpi(report, "TIRS À LA TÊTE", "%d %%" % roundi(Stats.percent(_head_hits, _head_hits + _body_hits)) if hits > 0 else "—", "")
	add_shooting_kpis(report)
	set_chart(report, "TEMPS POUR ÉLIMINER CHAQUE ADVERSAIRE (ms)", _kill_times, "ms", 3000.0, true)
	set_panels(report, ["chart", "heatmap"])


# ---------------------------------------------------------------------------

func _on_bomb_exploded() -> void:
	_result = "exploded"
	score += 400
	hud.show_feedback("LA CHARGE A EXPLOSÉ · site défendu", Hud.COLOR_GOOD, 2.0)
	Sfx.play(&"success")
	finished = true


func _on_bomb_defused(_by_player: bool) -> void:
	_result = "defused"
	hud.show_feedback("CHARGE DÉSAMORCÉE PAR L'ADVERSAIRE", Hud.COLOR_BAD, 2.0)
	Sfx.play(&"fail")
	finished = true


func _choose_site() -> void:
	var available := PackedStringArray()
	for letter in ["A", "B", "C"]:
		if has_marker("Site%s_01" % letter):
			available.append(letter)
	_site = "A" if available.is_empty() else available[rng.randi_range(0, available.size() - 1)]


## Fait apparaître un adversaire à une position candidate d'où il peut marcher
## en ligne droite jusqu'à la charge (aucun obstacle à hauteur de genou).
func _spawn_enemy() -> void:
	var spots: Array[Vector3] = []
	var index := 1
	while has_marker("Site%s_%02d" % [_site, index]):
		var spot := marker("Site%s_%02d" % [_site, index])
		var ground := Vector3(spot.x, 0.0, spot.z)
		var far_enough := ground.distance_to(_bomb_position) >= min_spawn_distance
		if far_enough and line_of_sight(ground + Vector3(0.0, 0.5, 0.0), _bomb_position + Vector3(0.0, 0.5, 0.0)):
			spots.append(ground)
		index += 1
	if spots.is_empty():
		return
	var enemy := HUMANOID_SCENE.instantiate() as Humanoid
	enemy.target_id = _next_target_id
	_next_target_id += 1
	enemy.position = spots[rng.randi_range(0, spots.size() - 1)]
	enemy.walk_speed = enemy_speed * clampf(difficulty, 0.8, 1.4)
	add_child(enemy)
	enemy.walk_to(_bomb_position)
	enemy.arrived.connect(_on_enemy_arrived)
	_enemies.append(enemy)
	_spawn_usec[enemy.target_id] = Time.get_ticks_usec()
	Telemetry.log_event("defuser_spawned", {"target": enemy.target_id})


func _on_enemy_arrived() -> void:
	_reached += 1
	hud.show_feedback("UN ADVERSAIRE DÉSAMORCE", Hud.COLOR_BAD)
	Sfx.play(&"fail")


func _nearest_enemy() -> Humanoid:
	var best: Humanoid = null
	var best_angle := INF
	for enemy in _enemies:
		var offset: Vector2 = Telemetry.angular_offset_to(enemy.head_position())
		if offset.length() < best_angle:
			best_angle = offset.length()
			best = enemy
	return best
