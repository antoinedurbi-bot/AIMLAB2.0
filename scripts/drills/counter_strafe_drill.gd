extends "res://scripts/drills/drill_base.gd"
## Strafe / contre-strafe : le joueur se déplace latéralement, s'arrête, tire.
## Un tir n'est précis que sous PlayerController.ACCURATE_SPEED ; au-dessus, il
## est dévié. Pour qu'un tir compte comme « propre » il faut avoir atteint la
## pleine vitesse depuis le tir précédent, puis tirer à l'arrêt.
##
## Mesures par tir : vitesse au moment du tir, temps d'arrêt (pleine vitesse →
## tir), méthode d'arrêt (contre-strafe ou simple relâchement), délai entre le
## relâchement d'une touche et l'appui sur l'opposée, tir trop tôt ou trop tard.

var target_radius: float = 0.24
var simultaneous_targets: int = 2
var grid_columns: int = 9
var grid_rows: int = 3
var spacing_x: float = 1.4
var spacing_y: float = 0.35

var _center: Vector3 = Vector3.ZERO
var _occupied: Dictionary = {}
var _last_shot_usec: int = 0

var _strafe_shots: int = 0
var _static_shots: int = 0
var _clean_shots: int = 0
var _clean_kills: int = 0
var _counter_stops: int = 0
var _release_stops: int = 0
var _too_early: int = 0
var _too_late: int = 0
## Vitesse (m/s) à chaque tir précédé d'un strafe.
var _speeds: PackedFloat32Array = PackedFloat32Array()
## Temps (ms) entre la sortie de la pleine vitesse et le tir, pour les tirs propres.
var _stop_times: PackedFloat32Array = PackedFloat32Array()
var _counter_stop_times: PackedFloat32Array = PackedFloat32Array()
var _release_stop_times: PackedFloat32Array = PackedFloat32Array()
## Délai (ms) entre le relâchement de la touche de strafe et l'appui sur l'opposée.
var _key_gaps: PackedFloat32Array = PackedFloat32Array()


func uses_movement() -> bool:
	return true


func spawn_marker() -> String:
	return "Spawn"


func setup() -> void:
	_center = marker("TargetCenter")
	hud.set_objective("Strafe, arrête-toi, tire")
	hud.set_speed_gauge_visible(true)
	_fill_grid()


func begin() -> void:
	_last_shot_usec = Time.get_ticks_usec()


func update(_delta: float) -> void:
	hud.set_speed(player.horizontal_speed(), PlayerController.ACCURATE_SPEED, PlayerController.RUN_SPEED)


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	shots += 1
	var speed: float = shot.get("speed", 0.0)
	var now: int = shot.get("time_usec", Time.get_ticks_usec())
	var full_speed_usec: int = shot.get("last_full_speed_usec", 0)
	var accurate: bool = speed <= PlayerController.ACCURATE_SPEED
	var strafed := full_speed_usec > _last_shot_usec
	_last_shot_usec = now

	var method := "none"
	var stop_ms := -1.0
	var key_gap_ms := 0.0
	var too_late := false
	if strafed:
		_strafe_shots += 1
		_speeds.append(speed)
		stop_ms = float(now - full_speed_usec) / 1000.0
		var direction: int = shot.get("full_speed_direction", 0)
		if direction != 0:
			var same_release: int = shot.get("left_release_usec" if direction < 0 else "right_release_usec", 0)
			var opposite_press: int = shot.get("right_press_usec" if direction < 0 else "left_press_usec", 0)
			# Contre-strafe : la touche opposée a été enfoncée au moment où le joueur
			# quittait la pleine vitesse (60 ms de marge) et avant le tir.
			if opposite_press >= full_speed_usec - 60000 and opposite_press <= now:
				method = "counter"
				_counter_stops += 1
				if same_release > 0:
					key_gap_ms = float(opposite_press - same_release) / 1000.0
					_key_gaps.append(key_gap_ms)
			else:
				method = "release"
				_release_stops += 1
			# Reparti dans l'autre sens : la touche opposée a été tenue trop longtemps.
			var lateral: float = shot.get("lateral_velocity", 0.0)
			too_late = not accurate and lateral * float(direction) < 0.0
		if accurate:
			_clean_shots += 1
			_stop_times.append(stop_ms)
			if method == "counter":
				_counter_stop_times.append(stop_ms)
			elif method == "release":
				_release_stop_times.append(stop_ms)
		elif too_late:
			_too_late += 1
		else:
			_too_early += 1
	else:
		_static_shots += 1

	var target := collider as AimTarget
	var killed := target != null and target.alive
	var details := {
		"strafed": strafed, "method": method, "stop_ms": stop_ms,
		"key_gap_ms": key_gap_ms, "too_late": too_late, "accurate": accurate,
	}
	if killed:
		hits += 1
		record_shot(true, target, shot, details)
		if strafed and accurate:
			_clean_kills += 1
			score += 150
		elif strafed:
			score += 60
		else:
			score += 40
		var freed_cell := target.grid_cell
		var target_position := target.global_position
		_occupied.erase(freed_cell)
		target.destroy()
		fx.explosion(target_position)
		_spawn_in_grid(freed_cell)
		hud.flash_hit()
		Sfx.play(&"kill")
	else:
		score = maxi(score - 15, 0)
		record_shot(false, nearest_target(_alive_targets()), shot, details)
		if collider != null:
			fx.impact(hit_position, hit_normal)
		hud.flash_miss()
		Sfx.play(&"miss")

	_show_shot_feedback(strafed, accurate, too_late, speed, stop_ms, method)


func finalize(report: Dictionary) -> void:
	var clean_rate := Stats.percent(_clean_shots, _strafe_shots)
	var counter_rate := Stats.percent(_counter_stops, _counter_stops + _release_stops)
	report["strafe_shots"] = _strafe_shots
	report["static_shots"] = _static_shots
	report["clean_shots"] = _clean_shots
	report["clean_kills"] = _clean_kills
	report["clean_rate"] = clean_rate
	report["avg_speed_at_strafe_shot"] = Stats.mean(_speeds)
	report["avg_stop_ms"] = Stats.mean(_stop_times)
	report["avg_counter_stop_ms"] = Stats.mean(_counter_stop_times)
	report["avg_release_stop_ms"] = Stats.mean(_release_stop_times)
	report["counter_stops"] = _counter_stops
	report["release_stops"] = _release_stops
	report["counter_rate"] = counter_rate
	report["avg_key_gap_ms"] = Stats.mean(_key_gaps)
	report["too_early_shots"] = _too_early
	report["too_late_shots"] = _too_late

	add_kpi(report, "TIRS PROPRES", "%d %%" % roundi(clean_rate) if _strafe_shots > 0 else "—",
			"%d sur %d tirs après strafe, à l'arrêt" % [_clean_shots, _strafe_shots])
	add_kpi(report, "VITESSE AU TIR", "%.1f m/s" % Stats.mean(_speeds) if _strafe_shots > 0 else "—",
			"précis sous %.1f m/s" % PlayerController.ACCURATE_SPEED)
	add_kpi(report, "TEMPS D'ARRÊT", "%d ms" % roundi(Stats.mean(_stop_times)) if _clean_shots > 0 else "—",
			"pleine vitesse → tir propre")
	add_kpi(report, "CONTRE-STRAFE", "%d %%" % roundi(counter_rate) if _counter_stops + _release_stops > 0 else "—",
			"%d contre-strafes · %d relâchements" % [_counter_stops, _release_stops])
	add_kpi(report, "TROP TÔT / TROP TARD", "%d / %d" % [_too_early, _too_late],
			"tir avant l'arrêt / reparti en sens inverse")
	add_kpi(report, "ÉLIMINATIONS PROPRES", str(_clean_kills), "%d tirs sans strafe préalable" % _static_shots)
	add_shooting_kpis(report)
	add_kpi(report, "DÉLAI ENTRE TOUCHES", "%+d ms" % roundi(Stats.mean(_key_gaps)) if not _key_gaps.is_empty() else "—",
			"relâchement → touche opposée (négatif = chevauchement)")
	set_chart(report, "VITESSE AU MOMENT DU TIR (m/s)", _speeds, "m/s", PlayerController.ACCURATE_SPEED, true)
	set_panels(report, ["chart", "heatmap"])


# ---------------------------------------------------------------------------

func _show_shot_feedback(strafed: bool, accurate: bool, too_late: bool, speed: float, stop_ms: float, method: String) -> void:
	if not strafed:
		hud.show_feedback("SANS STRAFE · déplace-toi avant de tirer", Hud.COLOR_INFO)
	elif accurate:
		var method_text := "contre-strafe" if method == "counter" else "relâchement"
		hud.show_feedback("PROPRE · arrêt en %d ms (%s)" % [roundi(stop_ms), method_text], Hud.COLOR_GOOD)
	elif too_late:
		hud.show_feedback("TROP TARD · tu repars en sens inverse (%.1f m/s)" % speed, Hud.COLOR_BAD)
	else:
		hud.show_feedback("TROP TÔT · encore %.1f m/s" % speed, Hud.COLOR_BAD)


func _cell_position(cell: Vector2i) -> Vector3:
	var offset_x := (float(cell.x) - float(grid_columns - 1) * 0.5) * spacing_x
	var offset_y := (float(cell.y) - float(grid_rows - 1) * 0.5) * spacing_y
	return _center + Vector3(offset_x, offset_y, 0.0)


func _fill_grid() -> void:
	while _occupied.size() < simultaneous_targets:
		if not _spawn_in_grid(Vector2i(-1, -1)):
			break


func _spawn_in_grid(excluded: Vector2i) -> bool:
	var free_cells: Array[Vector2i] = []
	for column in grid_columns:
		for row in grid_rows:
			var candidate := Vector2i(column, row)
			if candidate != excluded and not _occupied.has(candidate):
				free_cells.append(candidate)
	if free_cells.is_empty():
		return false
	var chosen: Vector2i = free_cells[rng.randi_range(0, free_cells.size() - 1)]
	var target := spawn_target(_cell_position(chosen), target_radius)
	target.grid_cell = chosen
	_occupied[chosen] = target
	return true


func _alive_targets() -> Array[AimTarget]:
	var result: Array[AimTarget] = []
	for value: Variant in _occupied.values():
		var target := value as AimTarget
		if is_instance_valid(target) and target.alive:
			result.append(target)
	return result
