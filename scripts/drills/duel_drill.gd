extends "res://scripts/drills/drill_base.gd"
## Duel : une cible humanoïde strafe de façon erratique à moyenne distance. Il
## faut l'éliminer avant la fin du temps imparti (sinon le duel est perdu).
## Tir automatique avec recul, imprécision en mouvement : comme un vrai duel,
## il faut s'arrêter, viser la tête et contrôler sa rafale.
##
## Dégâts : tête = élimination immédiate, corps = trois balles.
## La difficulté adaptative accélère la cible et raccourcit le temps imparti.

const Humanoid := preload("res://scripts/humanoid_target.gd")
const HUMANOID_SCENE: PackedScene = preload("res://scenes/humanoid_target.tscn")

## Temps accordé pour gagner un duel au niveau de difficulté 1 (s).
var base_time_limit: float = 2.6
var respawn_delay: float = 0.6
var strafe_half_width: float = 6.0
## Décalage en profondeur de la cible (négatif = plus loin) et facteur sur sa vitesse.
var enemy_depth: float = 0.0
var strafe_scale: float = 1.0

var _enemy: Humanoid
var _enemy_spawn_usec: int = 0
var _enemy_bullets: int = 0
var _cooldown: float = 0.0
var _lane_center: Vector3 = Vector3.ZERO
var _time_limit: float = 2.6

var _wins: int = 0
var _losses: int = 0
var _head_hits: int = 0
var _body_hits: int = 0
var _headshot_kills: int = 0
var _kill_times: PackedFloat32Array = PackedFloat32Array()
var _bullets_per_kill: PackedFloat32Array = PackedFloat32Array()
var _bursts: int = 0
var _crouched_shots: int = 0


func uses_movement() -> bool:
	return true


func spawn_marker() -> String:
	return "Spawn"


func setup() -> void:
	var center := marker("TargetCenter")
	_lane_center = Vector3(center.x, 0.0, center.z)
	_time_limit = base_time_limit / difficulty
	player.automatic = true
	player.recoil_enabled = true
	hud.set_objective("Élimine la cible en %.1f s · arrête-toi pour tirer" % _time_limit)
	hud.set_speed_gauge_visible(true)
	hud.set_side_stat("DUELS", "0 gagnés · 0 perdus")
	_spawn_enemy()


func update(delta: float) -> void:
	hud.set_speed(player.horizontal_speed(), PlayerController.ACCURATE_SPEED, PlayerController.RUN_SPEED)
	if _enemy == null:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_spawn_enemy()
		return
	var alive_seconds := float(Time.get_ticks_usec() - _enemy_spawn_usec) / 1000000.0
	if alive_seconds >= _time_limit:
		_losses += 1
		score = maxi(score - 50, 0)
		hud.show_feedback("DUEL PERDU · trop lent", Hud.COLOR_BAD)
		hud.flash_miss()
		Sfx.play(&"fail")
		Telemetry.log_event("duel_lost", {"bullets": _enemy_bullets})
		_remove_enemy()


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	shots += 1
	var speed: float = shot.get("speed", 0.0)
	var details := {"spray_index": shot.get("spray_index", 0), "deviation": shot.get("deviation", Vector2.ZERO)}
	if int(shot.get("spray_index", 0)) == 0:
		_bursts += 1
	if bool(shot.get("crouched", false)):
		_crouched_shots += 1
	if _enemy == null:
		Telemetry.record_shot(false, Vector3.ZERO, 0.0, -1, speed, details)
		return
	_enemy_bullets += 1
	var struck := collider as Humanoid
	if struck != _enemy:
		Telemetry.record_shot(false, _enemy.head_position(), Humanoid.HEAD_RADIUS, _enemy.target_id, speed, details)
		if collider != null:
			fx.impact(hit_position, hit_normal)
		hud.flash_miss()
		return

	hits += 1
	var head := _enemy.is_head_hit(hit_position)
	details["head"] = head
	details["enemy_speed"] = _enemy.current_speed()
	Telemetry.record_shot(true, _enemy.head_position(), Humanoid.HEAD_RADIUS, _enemy.target_id, speed, details)
	if head:
		_head_hits += 1
	else:
		_body_hits += 1
	hud.flash_hit()
	Sfx.play(&"hit")
	if _enemy.apply_damage(player.weapon_damage(head)):
		_register_win(head, shot)


func finalize(report: Dictionary) -> void:
	var duels := _wins + _losses
	var win_rate := Stats.percent(_wins, duels)
	var headshot_rate := Stats.percent(_head_hits, _head_hits + _body_hits)
	report["duels"] = duels
	report["duel_wins"] = _wins
	report["duel_losses"] = _losses
	report["duel_win_rate"] = win_rate
	report["headshot_rate"] = headshot_rate
	report["headshot_kills"] = _headshot_kills
	report["avg_duel_time_ms"] = Stats.mean(_kill_times)
	report["bullets_per_kill"] = Stats.mean(_bullets_per_kill)
	report["duel_time_limit_s"] = _time_limit
	report["avg_burst_length"] = float(shots) / float(maxi(_bursts, 1))
	report["crouched_shot_rate"] = Stats.percent(_crouched_shots, shots)
	report["difficulty_level"] = difficulty
	report["success_ratio"] = win_rate / 100.0

	add_kpi(report, "DUELS GAGNÉS", "%d / %d" % [_wins, duels], "%d %% de victoires" % roundi(win_rate))
	add_kpi(report, "TIRS À LA TÊTE", "%d %%" % roundi(headshot_rate) if _head_hits + _body_hits > 0 else "—",
			"%d éliminations d'une balle dans la tête" % _headshot_kills)
	add_kpi(report, "TEMPS POUR ÉLIMINER", "%d ms" % roundi(Stats.mean(_kill_times)) if _wins > 0 else "—",
			"limite : %d ms" % roundi(_time_limit * 1000.0))
	add_kpi(report, "BALLES PAR ÉLIMINATION", "%.1f" % Stats.mean(_bullets_per_kill) if _wins > 0 else "—", "1 = tête au premier tir")
	add_shooting_kpis(report)
	add_kpi(report, "TIRS EN MOUVEMENT", "%d %%" % roundi(Stats.percent(int(report.get("shots_moving", 0)), shots)) if shots > 0 else "—",
			"déviés car tirés au-dessus de %.1f m/s" % PlayerController.ACCURATE_SPEED)
	add_kpi(report, "LONGUEUR DES RAFALES", "%.1f balles" % (float(shots) / float(maxi(_bursts, 1))) if shots > 0 else "—",
			"%d %% des tirs accroupi" % roundi(Stats.percent(_crouched_shots, shots)))
	add_kpi(report, "NIVEAU DE DIFFICULTÉ", "× %.2f" % difficulty, "s'ajuste à chaque session")
	set_chart(report, "TEMPS POUR ÉLIMINER PAR DUEL GAGNÉ (ms)", _kill_times, "ms", _time_limit * 600.0, true)
	set_panels(report, ["chart", "heatmap"])


# ---------------------------------------------------------------------------

func _spawn_enemy() -> void:
	var enemy := HUMANOID_SCENE.instantiate() as Humanoid
	enemy.target_id = _next_target_id
	_next_target_id += 1
	enemy.strafe_speed = 5.4 * strafe_scale * clampf(difficulty, 0.7, 1.4)
	enemy.min_x = _lane_center.x - strafe_half_width
	enemy.max_x = _lane_center.x + strafe_half_width
	enemy.position = _lane_center + Vector3(rng.randf_range(-strafe_half_width, strafe_half_width), 0.0, enemy_depth + rng.randf_range(-2.0, 3.0))
	add_child(enemy)
	_enemy = enemy
	_enemy_spawn_usec = Time.get_ticks_usec()
	_enemy_bullets = 0
	Telemetry.log_event("duel_start", {"target": enemy.target_id})


func _register_win(head: bool, shot: Dictionary) -> void:
	var shot_usec: int = shot.get("time_usec", Time.get_ticks_usec())
	var duel_ms := float(shot_usec - _enemy_spawn_usec) / 1000.0
	_wins += 1
	_kill_times.append(duel_ms)
	_bullets_per_kill.append(float(_enemy_bullets))
	if head and _enemy_bullets == 1:
		_headshot_kills += 1
	# 150 points, +50 si la tête, + jusqu'à 100 selon la rapidité.
	var quickness := clampf(1.0 - duel_ms / (_time_limit * 1000.0), 0.0, 1.0)
	score += 150 + (50 if head else 0) + roundi(100.0 * quickness)
	fx.explosion(_enemy.head_position())
	hud.show_feedback("%s · %d ms · %d balle(s)" % ["TÊTE" if head else "ÉLIMINÉ", roundi(duel_ms), _enemy_bullets], Hud.COLOR_GOOD)
	Sfx.play(&"kill")
	Telemetry.log_event("duel_won", {"ms": duel_ms, "bullets": _enemy_bullets, "head": head})
	_remove_enemy()


func _remove_enemy() -> void:
	if _enemy != null:
		_enemy.destroy()
		_enemy = null
	_cooldown = respawn_delay
	hud.set_side_stat("DUELS", "%d gagnés · %d perdus" % [_wins, _losses])
