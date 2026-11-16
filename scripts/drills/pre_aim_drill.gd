extends "res://scripts/drills/drill_base.gd"
## Pré-visée (clear d'angles) : le joueur traverse un parcours et doit abattre
## une cible à hauteur de tête cachée derrière chaque angle. À chaque angle, une
## position est tirée au sort parmi les candidates : impossible d'apprendre le
## parcours par cœur, il faut « trancher » chaque coin viseur en place.
##
## Mesure clé : l'erreur de pré-visée, c'est-à-dire l'écart entre le viseur et la
## cible à l'instant précis où elle devient visible. Un bon placement de viseur
## la rend quasi nulle : il ne reste qu'à cliquer.

var target_radius: float = 0.2
## Nombre d'angles du parcours (repères T1a/T1b ... TNa/TNb sur la carte).
var angle_count: int = 9
var candidate_suffixes: PackedStringArray = PackedStringArray(["a", "b"])

var _targets: Array[AimTarget] = []
## target_id -> instant (µs) de première visibilité.
var _seen_usec: Dictionary = {}
var _cleared: int = 0
var _finish_time: float = 0.0

## Erreur de pré-visée (°) de chaque cible, dans l'ordre de découverte.
var _errors: PackedFloat32Array = PackedFloat32Array()
## Composante verticale signée (° ; positif = viseur trop bas) et horizontale absolue.
var _vertical: PackedFloat32Array = PackedFloat32Array()
var _horizontal: PackedFloat32Array = PackedFloat32Array()
## Temps (ms) entre la première visibilité d'une cible et sa destruction.
var _exposure_ttk: PackedFloat32Array = PackedFloat32Array()
var _speeds_at_sight: PackedFloat32Array = PackedFloat32Array()


func uses_movement() -> bool:
	return true


func spawn_marker() -> String:
	return "Start"


func setup() -> void:
	for index in angle_count:
		var suffix := candidate_suffixes[rng.randi_range(0, candidate_suffixes.size() - 1)]
		var target := spawn_target(marker("T%d%s" % [index + 1, suffix]), target_radius)
		_targets.append(target)
	hud.set_objective("Viseur à hauteur de tête avant chaque angle")
	hud.set_speed_gauge_visible(true)
	hud.set_side_stat("ANGLES", "0 / %d" % angle_count)


func update(_delta: float) -> void:
	hud.set_speed(player.horizontal_speed(), PlayerController.ACCURATE_SPEED, PlayerController.RUN_SPEED)
	for target in _targets:
		if not is_instance_valid(target) or not target.alive or _seen_usec.has(target.target_id):
			continue
		if visible_to_player(target.global_position):
			_register_sight(target)


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	shots += 1
	var target := collider as AimTarget
	if target != null and target.alive:
		_register_kill(target, shot)
		return
	score = maxi(score - 15, 0)
	record_shot(false, nearest_target(_seen_targets()), shot)
	if collider != null:
		fx.impact(hit_position, hit_normal)
	hud.flash_miss()
	Sfx.play(&"miss")


func finalize(report: Dictionary) -> void:
	var shot_count: int = report.get("shots", 0)
	var moving_shots: int = report.get("shots_moving", 0)
	var course_time := _finish_time if finished else elapsed
	var mean_error := Stats.mean(_errors)
	var mean_vertical := Stats.mean(_vertical)
	report["angles_total"] = angle_count
	report["angles_cleared"] = _cleared
	report["course_completed"] = finished
	report["course_time_s"] = course_time
	report["preaim_error_deg"] = mean_error
	report["preaim_vertical_deg"] = mean_vertical
	report["preaim_horizontal_deg"] = Stats.mean(_horizontal)
	report["exposure_ttk_ms"] = Stats.mean(_exposure_ttk)
	report["speed_at_sight"] = Stats.mean(_speeds_at_sight)
	report["shots_moving_rate"] = Stats.percent(moving_shots, shot_count)

	add_kpi(report, "ANGLES NETTOYÉS", "%d / %d" % [_cleared, angle_count],
			"en %.1f s" % course_time if finished else "parcours inachevé")
	add_kpi(report, "ERREUR DE PRÉ-VISÉE", "%.1f°" % mean_error if not _errors.is_empty() else "—",
			"écart viseur → tête à la découverte de la cible")
	add_kpi(report, "HAUTEUR DU VISEUR", _vertical_text(mean_vertical) if not _vertical.is_empty() else "—",
			"par rapport à la tête, en moyenne")
	add_kpi(report, "ÉCART HORIZONTAL", "%.1f°" % Stats.mean(_horizontal) if not _horizontal.is_empty() else "—",
			"distance latérale viseur → tête")
	add_kpi(report, "TEMPS POUR ABATTRE", "%d ms" % roundi(Stats.mean(_exposure_ttk)) if not _exposure_ttk.is_empty() else "—",
			"de la découverte de la cible à sa destruction")
	add_kpi(report, "TIRS EN MOUVEMENT", "%d %%" % roundi(Stats.percent(moving_shots, shot_count)) if shot_count > 0 else "—",
			"tirs déclenchés au-dessus de %.1f m/s" % PlayerController.ACCURATE_SPEED)
	add_shooting_kpis(report)
	set_chart(report, "ERREUR DE PRÉ-VISÉE PAR ANGLE (°)", _errors, "°", 2.0, true)
	set_panels(report, ["chart", "heatmap"])


# ---------------------------------------------------------------------------

func _vertical_text(mean_vertical: float) -> String:
	if absf(mean_vertical) < 0.3:
		return "à hauteur"
	if mean_vertical > 0.0:
		return "%.1f° trop bas" % mean_vertical
	return "%.1f° trop haut" % -mean_vertical


func _register_sight(target: AimTarget) -> void:
	_seen_usec[target.target_id] = Time.get_ticks_usec()
	# Position de la cible par rapport au viseur : y > 0 = cible au-dessus (viseur trop bas).
	var offset: Vector2 = Telemetry.angular_offset_to(target.global_position)
	_errors.append(offset.length())
	_vertical.append(offset.y)
	_horizontal.append(absf(offset.x))
	_speeds_at_sight.append(player.horizontal_speed())
	Telemetry.log_event("target_sighted", {
		"target": target.target_id, "offset_deg": offset, "speed": player.horizontal_speed(),
	})


func _register_kill(target: AimTarget, shot: Dictionary) -> void:
	hits += 1
	_cleared += 1
	if not _seen_usec.has(target.target_id):
		_register_sight(target)
	var shot_usec: int = shot.get("time_usec", Time.get_ticks_usec())
	var seen_usec: int = _seen_usec[target.target_id]
	var ttk_ms := float(shot_usec - seen_usec) / 1000.0
	_exposure_ttk.append(ttk_ms)

	var offset: Vector2 = Telemetry.angular_offset_to(target.global_position)
	# 100 points + bonus de rapidité après découverte (complet sous 250 ms, nul au-delà de 1 s).
	score += 100 + roundi(100.0 * clampf(1.0 - (ttk_ms - 250.0) / 750.0, 0.0, 1.0))
	record_shot(true, target, shot, {"exposure_ttk_ms": ttk_ms, "final_offset_deg": offset})
	fx.explosion(target.global_position)
	target.destroy()
	hud.flash_hit()
	hud.show_feedback("%d ms après découverte" % roundi(ttk_ms), Hud.COLOR_GOOD if ttk_ms <= 450.0 else Hud.COLOR_INFO)
	hud.set_side_stat("ANGLES", "%d / %d" % [_cleared, angle_count])
	Sfx.play(&"kill")

	if _cleared >= angle_count:
		_finish_time = elapsed
		# Bonus de fin : 5 points par seconde restante.
		score += roundi(maxf(duration - elapsed, 0.0) * 5.0)
		finished = true


## Cibles vivantes déjà découvertes (celles que le joueur a pu vouloir viser).
func _seen_targets() -> Array[AimTarget]:
	var result: Array[AimTarget] = []
	for target in _targets:
		if is_instance_valid(target) and target.alive and _seen_usec.has(target.target_id):
			result.append(target)
	return result
