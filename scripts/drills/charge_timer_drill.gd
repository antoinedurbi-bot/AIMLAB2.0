extends "res://scripts/drills/drill_base.gd"
## Chrono de la charge : entraîne l'horloge interne. À chaque manche, un bip
## marque la pose de la charge ; le joueur doit appuyer sur ESPACE à l'instant
## exact demandé, sans aucun chronomètre à l'écran. Les dernières manches se
## jouent « sous pression » : des cibles à abattre détournent l'attention,
## comme en plein combat.
##
## Repère utile : sur une charge de 45 s avec un désamorçage de 7 s, 38 s est le
## dernier instant pour commencer à désamorcer.
##
## Mesures : erreur signée de chaque manche, biais (trop tôt / trop tard),
## rythme interne (rapport temps estimé / temps réel) et effet de la distraction.

enum Phase { BRIEFING, COUNTING, RESULT }

## Durée à estimer pour chaque manche (s) et présence de cibles de distraction.
var rep_seconds: PackedFloat32Array = PackedFloat32Array([10.0, 20.0, 20.0, 38.0])
var rep_distraction: Array = [false, false, true, true]
var briefing_seconds: float = 3.5
var result_seconds: float = 2.8
var distraction_radius: float = 0.34
var distraction_distance: float = 10.0

var _phase: int = Phase.BRIEFING
var _rep: int = -1
var _timer: float = 0.0
var _count_start_usec: int = 0
var _distraction_targets: Array[AimTarget] = []
var _distraction_kills: int = 0

## Erreur signée de chaque manche (s) : négatif = trop tôt, positif = trop tard.
var _errors: PackedFloat32Array = PackedFloat32Array()
## Rapport temps estimé / temps réel de chaque manche.
var _ratios: PackedFloat32Array = PackedFloat32Array()
var _calm_errors: PackedFloat32Array = PackedFloat32Array()
var _pressure_errors: PackedFloat32Array = PackedFloat32Array()


func shows_clock() -> bool:
	return false


func setup() -> void:
	hud.set_objective("Compte de tête. Aucun chronomètre : seul ton rythme interne compte.")
	hud.set_side_stat("ERREUR MOYENNE", "—")
	hud.set_clock_text("—")


func begin() -> void:
	_start_briefing(0)


func update(delta: float) -> void:
	match _phase:
		Phase.BRIEFING:
			_timer -= delta
			if _timer <= 0.0:
				_start_counting()
		Phase.COUNTING:
			# Oubli manifeste : on valide d'office bien après l'instant demandé.
			var target_seconds := rep_seconds[_rep]
			if _counted_seconds() > target_seconds * 1.6 + 4.0:
				_commit()
		Phase.RESULT:
			_timer -= delta
			if _timer <= 0.0:
				if _rep + 1 >= rep_seconds.size():
					finished = true
				else:
					_start_briefing(_rep + 1)


func on_action() -> void:
	if _phase == Phase.COUNTING:
		_commit()


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	# Les tirs ne comptent que pendant les manches sous pression.
	if _phase != Phase.COUNTING or _distraction_targets.is_empty():
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
	var mean_abs := Stats.mean_abs(_errors)
	var mean_signed := Stats.mean(_errors)
	var rate_percent := (Stats.mean(_ratios) - 1.0) * 100.0 if not _ratios.is_empty() else 0.0
	var calm_abs := Stats.mean_abs(_calm_errors)
	var pressure_abs := Stats.mean_abs(_pressure_errors)
	var last_error := _errors[_errors.size() - 1] if not _errors.is_empty() else 0.0
	report["timer_reps"] = _errors.size()
	report["timer_mean_abs_error_s"] = mean_abs
	report["timer_mean_signed_error_s"] = mean_signed
	report["timer_rate_percent"] = rate_percent
	report["timer_calm_abs_error_s"] = calm_abs
	report["timer_pressure_abs_error_s"] = pressure_abs
	report["timer_has_pressure_reps"] = not _pressure_errors.is_empty()
	report["timer_last_error_s"] = last_error
	report["timer_consistency_percent"] = Stats.deviation(_ratios) * 100.0
	report["distraction_kills"] = _distraction_kills

	add_kpi(report, "ERREUR MOYENNE", "%.2f s" % mean_abs if not _errors.is_empty() else "—",
			"écart absolu moyen sur %d manches" % _errors.size())
	add_kpi(report, "BIAIS", _signed_text(mean_signed) if not _errors.is_empty() else "—", "erreur signée moyenne")
	add_kpi(report, "RYTHME INTERNE", "%+.1f %%" % rate_percent if not _ratios.is_empty() else "—",
			"positif = tu comptes trop lentement")
	add_kpi(report, "AU CALME", "%.2f s" % calm_abs if not _calm_errors.is_empty() else "—", "erreur sans distraction")
	add_kpi(report, "SOUS PRESSION", "%.2f s" % pressure_abs if not _pressure_errors.is_empty() else "—",
			"erreur avec cibles · %d abattues" % _distraction_kills)
	add_kpi(report, "DERNIÈRE MANCHE", _signed_text(last_error) if not _errors.is_empty() else "—",
			"la plus longue : %d s" % roundi(rep_seconds[rep_seconds.size() - 1]))
	set_chart(report, "ERREUR PAR MANCHE (s) · négatif = trop tôt", _errors, "s", 0.75, true, true)
	set_panels(report, ["chart"])


# ---------------------------------------------------------------------------

func _signed_text(seconds: float) -> String:
	if absf(seconds) < 0.05:
		return "pile à l'heure"
	return "%.2f s trop %s" % [absf(seconds), "tard" if seconds > 0.0 else "tôt"]


func _counted_seconds() -> float:
	return float(Time.get_ticks_usec() - _count_start_usec) / 1000000.0


func _start_briefing(rep_index: int) -> void:
	_rep = rep_index
	_phase = Phase.BRIEFING
	_timer = briefing_seconds
	var under_pressure: bool = rep_distraction[_rep] if _rep < rep_distraction.size() else false
	var context := " · sous pression : abats les cibles en comptant" if under_pressure else ""
	hud.set_clock_text("MANCHE %d/%d" % [_rep + 1, rep_seconds.size()])
	hud.set_objective("Au bip, la charge est posée. Appuie sur ESPACE quand %d s se sont écoulées%s." % [
		roundi(rep_seconds[_rep]), context])


func _start_counting() -> void:
	_phase = Phase.COUNTING
	_count_start_usec = Time.get_ticks_usec()
	Sfx.play(&"go")
	hud.show_feedback("CHARGE POSÉE", Hud.COLOR_INFO)
	hud.set_objective("ESPACE à %d s." % roundi(rep_seconds[_rep]))
	Telemetry.log_event("count_start", {"rep": _rep, "target_s": rep_seconds[_rep]})
	var under_pressure: bool = rep_distraction[_rep] if _rep < rep_distraction.size() else false
	if under_pressure:
		for index in 3:
			_spawn_distraction()


func _commit() -> void:
	var target_seconds := rep_seconds[_rep]
	var counted := _counted_seconds()
	var error := counted - target_seconds
	var under_pressure := not _distraction_targets.is_empty()
	_errors.append(error)
	_ratios.append(counted / target_seconds)
	if under_pressure:
		_pressure_errors.append(error)
	else:
		_calm_errors.append(error)
	Telemetry.log_event("count_commit", {
		"rep": _rep, "target_s": target_seconds, "counted_s": counted, "error_s": error, "pressure": under_pressure,
	})

	# Tolérance proportionnelle à la durée : 250 points au mieux, 0 au-delà de trois tolérances.
	var tolerance := 0.5 + 0.05 * target_seconds
	score += roundi(250.0 * clampf(1.0 - absf(error) / (tolerance * 3.0), 0.0, 1.0))
	var good := absf(error) <= tolerance
	hud.show_feedback("%s  (%.2f s pour %d s)" % [_signed_text(error), counted, roundi(target_seconds)],
			Hud.COLOR_GOOD if good else Hud.COLOR_BAD, result_seconds)
	hud.set_side_stat("ERREUR MOYENNE", "%.2f s" % Stats.mean_abs(_errors))
	Sfx.play(&"success" if good else &"fail")

	_clear_distraction()
	_phase = Phase.RESULT
	_timer = result_seconds


func _spawn_distraction() -> void:
	var center := player.eye_position() + Vector3(0.0, 0.0, -distraction_distance)
	var offset := Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-1.6, 1.6), 0.0)
	_distraction_targets.append(spawn_target(center + offset, distraction_radius))


func _clear_distraction() -> void:
	for target in _distraction_targets:
		if is_instance_valid(target):
			target.destroy()
	_distraction_targets.clear()
