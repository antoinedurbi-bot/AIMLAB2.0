extends "res://scripts/drills/drill_base.gd"
## Dernière seconde : une charge armée est posée devant toi. Elle clignote et
## bipe de plus en plus vite ; aucun chronomètre n'est affiché. Lance le
## désamorçage (touche « utiliser ») le plus tard possible : il dure
## `defuse_seconds`, et une fois lancé il va jusqu'au bout. Trop tard, elle explose.
##
## Repère : sur 45 s avec 7 s de désamorçage, le dernier instant est 38 s. Les
## bips passent à quatre par seconde 10 s avant l'explosion : c'est le signal.
## La seconde manche se joue en abattant des cibles, comme en plein combat.
##
## Mesures : instant du lancement, marge restante, écart au dernier instant
## possible (négatif = trop tôt, positif = trop tard), explosions, effet de la pression.

enum Phase { BRIEFING, ARMED, RESULT }

const Bomb := preload("res://scripts/bomb.gd")
const BOMB_SCENE: PackedScene = preload("res://scenes/bomb.tscn")

var fuse_seconds: float = 45.0
var defuse_seconds: float = 7.0
## Une entrée par manche : vrai = cibles de distraction.
var rep_distraction: Array = [false, true]
var briefing_seconds: float = 3.0
var result_seconds: float = 3.0
var bomb_distance: float = 5.0
var distraction_radius: float = 0.34
var distraction_distance: float = 10.0

var _phase: int = Phase.BRIEFING
var _rep: int = -1
var _timer: float = 0.0
var _bomb: Bomb
var _defusing: bool = false
var _start_seconds: float = 0.0
var _under_pressure: bool = false
var _distraction_targets: Array[AimTarget] = []
var _distraction_kills: int = 0
var _explosions: int = 0

## Écart au dernier instant possible, par manche (s) : négatif = trop tôt.
var _errors: PackedFloat32Array = PackedFloat32Array()
var _ratios: PackedFloat32Array = PackedFloat32Array()
var _calm_errors: PackedFloat32Array = PackedFloat32Array()
var _pressure_errors: PackedFloat32Array = PackedFloat32Array()


func shows_clock() -> bool:
	return false


func setup() -> void:
	_bomb = BOMB_SCENE.instantiate() as Bomb
	_bomb.fuse_seconds = fuse_seconds
	_bomb.defuse_seconds = defuse_seconds
	add_child(_bomb)
	# Posée au sol devant le joueur : un rayon vers le bas trouve le sol.
	var above := player.eye_position() + Vector3(0.0, 0.0, -bomb_distance)
	var query := PhysicsRayQueryParameters3D.create(above, above + Vector3(0.0, -20.0, 0.0), WORLD_MASK)
	var ground := get_world_3d().direct_space_state.intersect_ray(query)
	var floor_point: Vector3 = ground.get("position", above + Vector3(0.0, -1.7, 0.0))
	_bomb.global_position = floor_point
	_bomb.exploded.connect(_on_exploded)
	_bomb.defused.connect(_on_defused)
	hud.set_objective("Désamorce au dernier moment · %s" % GameSettings.key_label("use"))
	hud.set_side_stat("MARGE", "—")
	hud.set_clock_text("—")


func begin() -> void:
	_start_briefing(0)


func update(delta: float) -> void:
	match _phase:
		Phase.BRIEFING:
			_timer -= delta
			if _timer <= 0.0:
				_arm()
		Phase.ARMED:
			_bomb.set_defusing(_defusing, true)
			if _defusing:
				hud.set_clock_text("%.1f / %d s" % [_bomb.defuse_progress, roundi(defuse_seconds)])
		Phase.RESULT:
			_timer -= delta
			if _timer <= 0.0:
				if _rep + 1 >= rep_distraction.size():
					finished = true
				else:
					_start_briefing(_rep + 1)


func on_action() -> void:
	if _phase != Phase.ARMED or _defusing:
		return
	_defusing = true
	_start_seconds = fuse_seconds - _bomb.time_left
	Sfx.play(&"tick")
	hud.show_feedback("DÉSAMORÇAGE…", Hud.COLOR_INFO, defuse_seconds)
	Telemetry.log_event("defuse_start", {"rep": _rep, "at_s": _start_seconds, "pressure": _under_pressure})


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	if _phase != Phase.ARMED or _distraction_targets.is_empty():
		return
	shots += 1
	var target := collider as AimTarget
	if target != null and target.alive:
		hits += 1
		_distraction_kills += 1
		score += 20
		record_shot(true, target, shot)
		var target_position := target.global_position
		_distraction_targets.erase(target)
		target.destroy()
		fx.explosion(target_position)
		_spawn_distraction()
		hud.flash_hit()
		Sfx.play(&"kill")
	else:
		record_shot(false, nearest_target(_distraction_targets), shot)
		if collider != null:
			fx.impact(hit_position, hit_normal)
		hud.flash_miss()
		Sfx.play(&"miss")


func finalize(report: Dictionary) -> void:
	if _bomb != null:
		_bomb.stop()
	var mean_abs := Stats.mean_abs(_errors)
	var mean_signed := Stats.mean(_errors)
	var calm_abs := Stats.mean_abs(_calm_errors)
	var pressure_abs := Stats.mean_abs(_pressure_errors)
	var last_error := _errors[_errors.size() - 1] if not _errors.is_empty() else 0.0
	report["timer_reps"] = _errors.size()
	report["timer_mean_abs_error_s"] = mean_abs
	report["timer_mean_signed_error_s"] = mean_signed
	report["timer_rate_percent"] = (Stats.mean(_ratios) - 1.0) * 100.0 if not _ratios.is_empty() else 0.0
	report["timer_calm_abs_error_s"] = calm_abs
	report["timer_pressure_abs_error_s"] = pressure_abs
	report["timer_has_pressure_reps"] = not _pressure_errors.is_empty()
	report["timer_last_error_s"] = last_error
	report["timer_consistency_percent"] = Stats.deviation(_ratios) * 100.0
	report["timer_explosions"] = _explosions
	report["distraction_kills"] = _distraction_kills

	var none := _errors.is_empty()
	add_kpi(report, "DÉSAMORCÉES", "%d / %d" % [_errors.size() - _explosions, rep_distraction.size()], "%d explosion(s)" % _explosions)
	add_kpi(report, "ÉCART MOYEN", "—" if none else "%.1f s" % mean_abs, "au dernier instant possible")
	add_kpi(report, "TENDANCE", "—" if none else _signed_text(mean_signed), "")
	add_kpi(report, "AU CALME", "—" if _calm_errors.is_empty() else "%.1f s" % calm_abs, "")
	add_kpi(report, "SOUS PRESSION", "—" if _pressure_errors.is_empty() else "%.1f s" % pressure_abs, "%d cibles abattues" % _distraction_kills)
	set_chart(report, "ÉCART PAR MANCHE (s) · négatif = trop tôt", _errors, "s", 1.5, true, true)
	set_panels(report, ["chart"])


# ---------------------------------------------------------------------------

func _signed_text(seconds: float) -> String:
	if absf(seconds) < 0.05:
		return "pile"
	return "%.1f s trop %s" % [absf(seconds), "tard" if seconds > 0.0 else "tôt"]


func _start_briefing(rep_index: int) -> void:
	_rep = rep_index
	_phase = Phase.BRIEFING
	_timer = briefing_seconds
	_defusing = false
	_under_pressure = bool(rep_distraction[_rep])
	hud.set_clock_text("MANCHE %d/%d" % [_rep + 1, rep_distraction.size()])
	if _under_pressure:
		hud.set_objective("Même chose en abattant les cibles · %s" % GameSettings.key_label("use"))


func _arm() -> void:
	_phase = Phase.ARMED
	_bomb.arm()
	Sfx.play(&"go")
	hud.show_feedback("CHARGE ARMÉE", Hud.COLOR_BAD)
	hud.set_clock_text("?")
	Telemetry.log_event("charge_armed", {"rep": _rep, "fuse_s": fuse_seconds})
	if _under_pressure:
		for index in 3:
			_spawn_distraction()


func _on_defused(_by_player: bool) -> void:
	var margin := _bomb.time_left
	score += 100 + roundi(400.0 * clampf(1.0 - margin / 10.0, 0.0, 1.0))
	hud.set_side_stat("MARGE", "%.1f s" % margin)
	hud.show_feedback("DÉSAMORCÉE · %.1f s de marge" % margin, Hud.COLOR_GOOD, result_seconds)
	Sfx.play(&"success")
	_end_rep()


func _on_exploded() -> void:
	_explosions += 1
	fx.explosion(_bomb.global_position + Vector3(0.0, 0.5, 0.0))
	var text := "EXPLOSION · jamais lancé"
	if _defusing:
		text = "EXPLOSION · lancé %.1f s trop tard" % (_start_seconds - (fuse_seconds - defuse_seconds))
	else:
		_start_seconds = fuse_seconds
	hud.set_side_stat("MARGE", "0 s")
	hud.show_feedback(text, Hud.COLOR_BAD, result_seconds)
	Sfx.play(&"fail")
	_end_rep()


func _end_rep() -> void:
	var ideal := fuse_seconds - defuse_seconds
	var error := _start_seconds - ideal
	_errors.append(error)
	_ratios.append(_start_seconds / ideal)
	if _under_pressure:
		_pressure_errors.append(error)
	else:
		_calm_errors.append(error)
	Telemetry.log_event("charge_result", {"rep": _rep, "start_s": _start_seconds, "error_s": error, "pressure": _under_pressure})
	for target in _distraction_targets:
		if is_instance_valid(target):
			target.destroy()
	_distraction_targets.clear()
	_defusing = false
	_bomb.set_defusing(false, true)
	_phase = Phase.RESULT
	_timer = result_seconds
	hud.set_clock_text("—")


func _spawn_distraction() -> void:
	var center := player.eye_position() + Vector3(0.0, 0.0, -distraction_distance)
	var offset := Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-0.4, 1.8), 0.0)
	_distraction_targets.append(spawn_target(center + offset, distraction_radius))
