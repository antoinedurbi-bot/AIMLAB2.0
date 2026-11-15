extends "res://scripts/drills/drill_base.gd"
## Cibles multiples : des vagues de `wave_size` silhouettes qui strafent
## lentement. Il faut toutes les éliminer en enchaînant — idéalement dans la
## même rafale (transfert de spray) — et choisir un ordre qui limite les trajets.
##
## Mesures : temps par vague, temps de transfert d'une cible à la suivante,
## balles par élimination, part de tirs à la tête, amplitude des transferts.

const Humanoid := preload("res://scripts/humanoid_target.gd")
const HUMANOID_SCENE: PackedScene = preload("res://scenes/humanoid_target.tscn")

var wave_size: int = 3
var strafe_speed: float = 2.4
var wave_delay: float = 0.7
## Temps de référence pour une vague au niveau de difficulté 1 (s).
var par_time: float = 4.0

var _enemies: Array[Humanoid] = []
var _center: Vector3 = Vector3.ZERO
var _cooldown: float = 0.0
var _wave_start_usec: int = 0
var _last_kill_usec: int = 0
var _bullets_since_kill: int = 0
var _waves: int = 0
var _kills: int = 0
var _head_hits: int = 0
var _body_hits: int = 0
var _wave_times: PackedFloat32Array = PackedFloat32Array()
var _transfers: PackedFloat32Array = PackedFloat32Array()
var _bullets_per_kill: PackedFloat32Array = PackedFloat32Array()
var _same_spray_transfers: int = 0
var _last_kill_spray: int = -1


func uses_movement() -> bool:
	return true


func spawn_marker() -> String:
	return "Spawn"


func setup() -> void:
	var anchor := marker("TargetCenter")
	_center = Vector3(anchor.x, 0.0, anchor.z)
	player.automatic = true
	player.recoil_enabled = true
	hud.set_objective("Élimine les %d cibles de chaque vague en enchaînant : transfère ta rafale de l'une à l'autre." % wave_size)
	hud.set_speed_gauge_visible(true)
	hud.set_side_stat("VAGUES", "0")
	_spawn_wave()


func update(delta: float) -> void:
	hud.set_speed(player.horizontal_speed(), PlayerController.ACCURATE_SPEED, PlayerController.RUN_SPEED)
	if _enemies.is_empty():
		_cooldown -= delta
		if _cooldown <= 0.0:
			_spawn_wave()


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	shots += 1
	_bullets_since_kill += 1
	var speed: float = shot.get("speed", 0.0)
	var spray_index: int = shot.get("spray_index", 0)
	var struck := collider as Humanoid
	if struck == null or not _enemies.has(struck):
		var nearest := _nearest_enemy()
		if nearest != null:
			Telemetry.record_shot(false, nearest.head_position(), Humanoid.HEAD_RADIUS, nearest.target_id, speed, {"spray_index": spray_index})
		else:
			Telemetry.record_shot(false, Vector3.ZERO, 0.0, -1, speed, {})
		if collider != null:
			fx.impact(hit_position, hit_normal)
		hud.flash_miss()
		return
	hits += 1
	var head := struck.is_head_hit(hit_position)
	Telemetry.record_shot(true, struck.head_position(), Humanoid.HEAD_RADIUS, struck.target_id, speed, {"spray_index": spray_index, "head": head})
	if head:
		_head_hits += 1
	else:
		_body_hits += 1
	hud.flash_hit()
	Sfx.play(&"hit")
	if not struck.apply_damage(player.weapon_damage(head)):
		return

	var now: int = shot.get("time_usec", Time.get_ticks_usec())
	_kills += 1
	_bullets_per_kill.append(float(_bullets_since_kill))
	_bullets_since_kill = 0
	if _enemies.size() < wave_size:
		# Pas la première cible de la vague : c'est un transfert.
		_transfers.append(float(now - _last_kill_usec) / 1000.0)
		if spray_index > _last_kill_spray and _last_kill_spray >= 0:
			_same_spray_transfers += 1
	_last_kill_usec = now
	_last_kill_spray = spray_index
	score += 100 + (30 if head else 0)
	fx.explosion(struck.head_position())
	Sfx.play(&"kill")
	_enemies.erase(struck)
	struck.destroy()
	if _enemies.is_empty():
		var wave_seconds := float(now - _wave_start_usec) / 1000000.0
		_waves += 1
		_wave_times.append(wave_seconds)
		score += roundi(200.0 * clampf(1.0 - (wave_seconds - 1.5) / (par_time / difficulty), 0.0, 1.0))
		hud.show_feedback("VAGUE NETTOYÉE · %.2f s" % wave_seconds, Hud.COLOR_GOOD)
		hud.set_side_stat("VAGUES", str(_waves))
		_cooldown = wave_delay
		_last_kill_spray = -1


func finalize(report: Dictionary) -> void:
	var par := par_time / difficulty
	var fast_waves := 0
	for value in _wave_times:
		if value <= par:
			fast_waves += 1
	report["waves"] = _waves
	report["wave_kills"] = _kills
	report["avg_wave_time_s"] = Stats.mean(_wave_times)
	report["avg_transfer_ms"] = Stats.mean(_transfers)
	report["same_spray_transfers"] = _same_spray_transfers
	report["bullets_per_kill"] = Stats.mean(_bullets_per_kill)
	report["headshot_rate"] = Stats.percent(_head_hits, _head_hits + _body_hits)
	report["difficulty_level"] = difficulty
	report["success_ratio"] = Stats.percent(fast_waves, maxi(_waves, 1)) / 100.0

	add_kpi(report, "VAGUES NETTOYÉES", str(_waves), "%d éliminations" % _kills)
	add_kpi(report, "TEMPS PAR VAGUE", "%.2f s" % Stats.mean(_wave_times) if _waves > 0 else "—", "référence : %.1f s" % par)
	add_kpi(report, "TRANSFERT", "%d ms" % roundi(Stats.mean(_transfers)) if not _transfers.is_empty() else "—",
			"d'une élimination à la suivante")
	add_kpi(report, "TRANSFERTS DANS LA RAFALE", str(_same_spray_transfers), "éliminations enchaînées sans relâcher le clic")
	add_kpi(report, "BALLES PAR ÉLIMINATION", "%.1f" % Stats.mean(_bullets_per_kill) if _kills > 0 else "—", "")
	add_kpi(report, "TIRS À LA TÊTE", "%d %%" % roundi(Stats.percent(_head_hits, _head_hits + _body_hits)) if hits > 0 else "—", "")
	add_shooting_kpis(report)
	set_chart(report, "TEMPS DE TRANSFERT ENTRE DEUX CIBLES (ms)", _transfers, "ms", 600.0, true)
	set_panels(report, ["chart", "heatmap"])


func _spawn_wave() -> void:
	var spacing := 9.0 / float(maxi(wave_size - 1, 1))
	for index in wave_size:
		var enemy := HUMANOID_SCENE.instantiate() as Humanoid
		enemy.target_id = _next_target_id
		_next_target_id += 1
		enemy.strafe_speed = strafe_speed * clampf(difficulty, 0.7, 1.5)
		var slot_x := _center.x - 4.5 + spacing * float(index) + rng.randf_range(-0.8, 0.8)
		enemy.min_x = slot_x - 1.5
		enemy.max_x = slot_x + 1.5
		enemy.position = Vector3(slot_x, 0.0, _center.z + rng.randf_range(-3.0, 3.0))
		add_child(enemy)
		_enemies.append(enemy)
	_wave_start_usec = Time.get_ticks_usec()
	_last_kill_usec = _wave_start_usec


func _nearest_enemy() -> Humanoid:
	var best: Humanoid = null
	var best_angle := INF
	for enemy in _enemies:
		var offset: Vector2 = Telemetry.angular_offset_to(enemy.head_position())
		if offset.length() < best_angle:
			best_angle = offset.length()
			best = enemy
	return best
