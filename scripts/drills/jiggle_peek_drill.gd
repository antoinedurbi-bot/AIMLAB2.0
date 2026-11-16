extends "res://scripts/drills/drill_base.gd"
## Jiggle peek : le joueur est à couvert derrière un coin. Un adversaire (sphère
## magenta) est posté quelque part de l'autre côté. Il faut sortir juste assez
## pour l'apercevoir, puis revenir à couvert avant qu'il n'ait le temps de tirer.
## Pas de tir : c'est un exercice de prise d'information.
##
## « Exposé » = l'adversaire a une ligne de vue sur la tête ou une épaule du
## joueur. « Information » = le joueur a l'adversaire à l'écran. Les épaules
## dépassent avant que la caméra ne voie : c'est ce qui rend le geste exigeant.
##
## Mesures par sortie : durée d'exposition, information obtenue ou non,
## profondeur de la sortie et dépassement après l'obtention de l'information.

## Temps d'exposition continu au bout duquel l'adversaire « tire » (ms).
var enemy_reaction_ms: float = 350.0
var enemy_radius: float = 0.26
## Demi-largeur d'épaules exposée (m) et hauteur du torse (m).
var shoulder_offset: float = 0.3
var chest_height: float = 1.3

var _enemy_markers: PackedStringArray = PackedStringArray(["JiggleEnemy1", "JiggleEnemy2", "JiggleEnemy3"])
var _enemy: AimTarget
var _enemy_index: int = -1
var _cooldown: float = 0.0
var _corner_x: float = 0.0

var _exposed: bool = false
var _exposure_start_usec: int = 0
var _peek_has_info: bool = false
var _peek_failed: bool = false
var _peek_max_x: float = 0.0
var _peek_info_x: float = 0.0
var _last_peek_end_usec: int = 0

var _peeks: int = 0
var _successes: int = 0
var _fails: int = 0
var _empty_peeks: int = 0
## Durée d'exposition (ms) de chaque sortie, puis des seules sorties réussies.
var _exposures: PackedFloat32Array = PackedFloat32Array()
var _success_exposures: PackedFloat32Array = PackedFloat32Array()
## Distance parcourue après l'obtention de l'information (cm), sorties réussies.
var _overpeeks: PackedFloat32Array = PackedFloat32Array()
## Temps entre deux sorties (ms).
var _intervals: PackedFloat32Array = PackedFloat32Array()


func uses_movement() -> bool:
	return true


func uses_fire() -> bool:
	return false


func spawn_marker() -> String:
	return "JiggleSpawn"


func setup() -> void:
	_corner_x = marker("JiggleCorner").x
	hud.set_objective("Vois l'adversaire et reviens en moins de %d ms · pas de tir" % roundi(enemy_reaction_ms))
	hud.set_speed_gauge_visible(true)
	hud.set_side_stat("JIGGLES RÉUSSIS", "0")
	_place_enemy()


func update(delta: float) -> void:
	hud.set_speed(player.horizontal_speed(), PlayerController.ACCURATE_SPEED, PlayerController.RUN_SPEED)
	if _enemy == null:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_place_enemy()
		return

	var enemy_position := _enemy.global_position
	var exposed := _enemy_sees_player(enemy_position)
	var now := Time.get_ticks_usec()
	if exposed and not _exposed:
		_exposed = true
		_exposure_start_usec = now
		_peek_has_info = false
		_peek_failed = false
		_peek_max_x = player.global_position.x
		_peek_info_x = player.global_position.x
		if _last_peek_end_usec > 0:
			_intervals.append(float(now - _last_peek_end_usec) / 1000.0)
		Telemetry.log_event("peek_start", {"enemy": _enemy_index, "speed": player.horizontal_speed()})

	if not _exposed:
		return

	var exposure_ms := float(now - _exposure_start_usec) / 1000.0
	_peek_max_x = maxf(_peek_max_x, player.global_position.x)
	if not _peek_has_info and visible_to_player(enemy_position):
		_peek_has_info = true
		_peek_info_x = player.global_position.x
		Telemetry.log_event("peek_info", {"enemy": _enemy_index, "exposure_ms": exposure_ms})
	if not _peek_failed and exposure_ms >= enemy_reaction_ms:
		_peek_failed = true
		hud.show_feedback("TOUCHÉ · exposé trop longtemps", Hud.COLOR_BAD)
		hud.flash_miss()
		Sfx.play(&"fail")
	if not exposed:
		_exposed = false
		_last_peek_end_usec = now
		_finish_peek(exposure_ms)


func finalize(report: Dictionary) -> void:
	var success_rate := Stats.percent(_successes, _successes + _fails)
	report["peeks"] = _peeks
	report["jiggle_success"] = _successes
	report["jiggle_fail"] = _fails
	report["empty_peeks"] = _empty_peeks
	report["jiggle_success_rate"] = success_rate
	report["avg_exposure_ms"] = Stats.mean(_exposures)
	report["avg_success_exposure_ms"] = Stats.mean(_success_exposures)
	report["best_exposure_ms"] = Stats.minimum(_success_exposures)
	report["exposure_std_ms"] = Stats.deviation(_exposures)
	report["avg_overpeek_cm"] = Stats.mean(_overpeeks)
	report["avg_peek_interval_ms"] = Stats.mean(_intervals)
	report["enemy_reaction_ms"] = enemy_reaction_ms

	add_kpi(report, "JIGGLES RÉUSSIS", str(_successes), "information obtenue sans se faire toucher")
	add_kpi(report, "EXPOSITION MOYENNE", "%d ms" % roundi(Stats.mean(_success_exposures)) if _successes > 0 else "—",
			"sorties réussies · meilleure %d ms" % roundi(Stats.minimum(_success_exposures)))
	add_kpi(report, "TOUCHÉ", str(_fails), "exposé plus de %d ms" % roundi(enemy_reaction_ms))
	add_kpi(report, "SORTIES SANS INFO", str(_empty_peeks), "exposé sans avoir vu l'adversaire")
	add_kpi(report, "DÉPASSEMENT", "%d cm" % roundi(Stats.mean(_overpeeks)) if _successes > 0 else "—",
			"distance parcourue après avoir vu l'adversaire")
	add_kpi(report, "RÉGULARITÉ", "± %d ms" % roundi(Stats.deviation(_exposures)) if _peeks > 1 else "—",
			"écart-type de la durée d'exposition")
	set_chart(report, "DURÉE D'EXPOSITION PAR SORTIE (ms)", _exposures, "ms", enemy_reaction_ms, true)
	set_panels(report, ["chart"])


# ---------------------------------------------------------------------------

## Vrai si l'adversaire a une ligne de vue sur la tête ou l'une des épaules du joueur.
func _enemy_sees_player(enemy_position: Vector3) -> bool:
	if line_of_sight(enemy_position, player.eye_position()):
		return true
	var chest := player.global_position + Vector3(0.0, chest_height, 0.0)
	var side: Vector3 = player.global_transform.basis.x * shoulder_offset
	return line_of_sight(enemy_position, chest + side) or line_of_sight(enemy_position, chest - side)


func _place_enemy() -> void:
	var index := rng.randi_range(0, _enemy_markers.size() - 1)
	if index == _enemy_index:
		index = (index + 1) % _enemy_markers.size()
	_enemy_index = index
	_enemy = spawn_target(marker(_enemy_markers[index]), enemy_radius, true)
	_enemy.set_hittable(false)
	_exposed = false
	Telemetry.log_event("enemy_placed", {"enemy": index})


func _finish_peek(exposure_ms: float) -> void:
	_peeks += 1
	_exposures.append(exposure_ms)
	var overpeek_cm := maxf(_peek_max_x - _peek_info_x, 0.0) * 100.0
	Telemetry.log_event("peek_end", {
		"enemy": _enemy_index, "exposure_ms": exposure_ms, "info": _peek_has_info, "failed": _peek_failed,
		"depth_m": _peek_max_x - _corner_x, "overpeek_cm": overpeek_cm,
	})

	if _peek_failed:
		_fails += 1
		score = maxi(score - 50, 0)
		_next_enemy()
	elif _peek_has_info:
		_successes += 1
		hits += 1
		_success_exposures.append(exposure_ms)
		_overpeeks.append(overpeek_cm)
		# 100 points + jusqu'à 100 selon la brièveté (complet sous 150 ms).
		var brevity := clampf(1.0 - (exposure_ms - 150.0) / maxf(enemy_reaction_ms - 150.0, 1.0), 0.0, 1.0)
		score += 100 + roundi(100.0 * brevity)
		hud.show_feedback("INFO · exposé %d ms" % roundi(exposure_ms), Hud.COLOR_GOOD)
		hud.flash_hit()
		Sfx.play(&"success")
		_next_enemy()
	else:
		_empty_peeks += 1
		hud.show_feedback("TROP COURT · adversaire non vu (exposé %d ms)" % roundi(exposure_ms), Hud.COLOR_INFO)
	hud.set_side_stat("JIGGLES RÉUSSIS", "%d · touché %d" % [_successes, _fails])


func _next_enemy() -> void:
	if _enemy != null:
		_enemy.destroy()
		_enemy = null
	_cooldown = 0.6
