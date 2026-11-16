extends "res://scripts/drills/drill_base.gd"
## Tenue d'angle : le joueur, immobile, surveille un passage. Une cible surgit
## d'un côté à un moment imprévisible — soit elle s'arrête un instant dans
## l'ouverture (peek), soit elle la traverse en courant.
##
## Mesures : temps de réaction (première visibilité → tir qui touche), réussite
## du premier tir, tirs prématurés, placement initial du viseur par rapport à la
## cible, et sens des tirs ratés (derrière ou devant la cible en mouvement).

enum Phase { WAITING, MOVING_OUT, HOLDING, RETURNING, CROSSING }

var target_radius: float = 0.26
## Vitesse de déplacement de la cible (m/s) : celle d'un joueur qui court.
var target_speed: float = 5.4
var min_delay: float = 0.8
var max_delay: float = 2.4
## Proportion de peeks (le reste : traversées complètes).
var peek_ratio: float = 0.7
var min_hold: float = 0.5
var max_hold: float = 0.9

var _target: AimTarget
var _phase: int = Phase.WAITING
var _timer: float = 0.0
## Côté de départ de la cible : -1 = ouest (gauche), +1 = est (droite).
var _side: int = 1
var _goal_x: float = 0.0
var _west: Vector3 = Vector3.ZERO
var _east: Vector3 = Vector3.ZERO
var _crossing: bool = false
var _seen: bool = false
var _seen_usec: int = 0
var _rep_shots: int = 0

var _reps: int = 0
var _kills: int = 0
var _escapes: int = 0
var _premature: int = 0
var _first_shots: int = 0
var _first_shot_hits: int = 0
var _misses_behind: int = 0
var _misses_ahead: int = 0
var _reaction_times: PackedFloat32Array = PackedFloat32Array()
var _initial_offsets: PackedFloat32Array = PackedFloat32Array()
## Avance du viseur sur la cible à son apparition (° ; négatif = viseur derrière elle).
var _initial_leads: PackedFloat32Array = PackedFloat32Array()


func spawn_marker() -> String:
	return "HoldSpawn"


func setup() -> void:
	_west = marker("HoldWest")
	_east = marker("HoldEast")
	hud.set_objective("Un tir dès que la cible apparaît")


func begin() -> void:
	_phase = Phase.WAITING
	_timer = rng.randf_range(min_delay, max_delay)


func update(delta: float) -> void:
	match _phase:
		Phase.WAITING:
			_timer -= delta
			if _timer <= 0.0:
				_start_rep()
		Phase.MOVING_OUT:
			if _move_target(delta):
				_phase = Phase.HOLDING
				_timer = rng.randf_range(min_hold, max_hold)
		Phase.HOLDING:
			_timer -= delta
			if _timer <= 0.0:
				_phase = Phase.RETURNING
				_goal_x = _hidden_position(_side).x
		Phase.RETURNING, Phase.CROSSING:
			if _move_target(delta):
				_end_rep(false)

	if _target != null and not _seen and visible_to_player(_target.global_position):
		_seen = true
		_seen_usec = Time.get_ticks_usec()
		var offset: Vector2 = Telemetry.angular_offset_to(_target.global_position)
		_initial_offsets.append(offset.length())
		_initial_leads.append(-float(_movement_direction()) * offset.x)
		Telemetry.log_event("target_visible", {"crossing": _crossing, "side": _side, "offset_deg": offset})


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	shots += 1
	var struck := collider as AimTarget
	if _target != null and struck == _target and _target.alive:
		_register_kill(shot)
		return

	if _target != null and _seen:
		# Cible visible mais manquée : de quel côté est parti le tir ?
		_rep_shots += 1
		if _rep_shots == 1:
			_first_shots += 1
		var direction := _movement_direction()
		if direction != 0:
			var shot_offset: Vector2 = -Telemetry.angular_offset_to(_target.global_position)
			if shot_offset.x * float(direction) < 0.0:
				_misses_behind += 1
			else:
				_misses_ahead += 1
		score = maxi(score - 20, 0)
		record_shot(false, _target, shot, {"crossing": _crossing})
	else:
		_premature += 1
		score = maxi(score - 50, 0)
		record_shot(false, null, shot, {"premature": true})
		hud.show_feedback("TIR PRÉMATURÉ", Hud.COLOR_BAD)
	if collider != null:
		fx.impact(hit_position, hit_normal)
	hud.flash_miss()
	Sfx.play(&"miss")


func finalize(report: Dictionary) -> void:
	var median_reaction := Stats.median(_reaction_times)
	report["reps"] = _reps
	report["kills"] = _kills
	report["escapes"] = _escapes
	report["kill_rate"] = Stats.percent(_kills, _reps)
	report["premature_shots"] = _premature
	report["reaction_median_ms"] = median_reaction
	report["reaction_best_ms"] = Stats.minimum(_reaction_times)
	report["reaction_std_ms"] = Stats.deviation(_reaction_times)
	report["first_shot_accuracy"] = Stats.percent(_first_shot_hits, _first_shots)
	report["initial_offset_deg"] = Stats.mean(_initial_offsets)
	report["initial_lead_deg"] = Stats.mean(_initial_leads)
	report["misses_behind"] = _misses_behind
	report["misses_ahead"] = _misses_ahead

	add_kpi(report, "RÉACTION MÉDIANE", "%d ms" % roundi(median_reaction) if _kills > 0 else "—",
			"meilleure %d ms · écart-type %d ms" % [roundi(Stats.minimum(_reaction_times)), roundi(Stats.deviation(_reaction_times))])
	add_kpi(report, "CIBLES ABATTUES", "%d / %d" % [_kills, _reps], "%d se sont échappées" % _escapes)
	add_kpi(report, "PREMIER TIR", "%d %%" % roundi(Stats.percent(_first_shot_hits, _first_shots)) if _first_shots > 0 else "—",
			"réussite du premier tir sur cible visible")
	add_kpi(report, "TIRS PRÉMATURÉS", str(_premature), "tirs sans cible visible (-50 points)")
	add_kpi(report, "ÉCART INITIAL", "%.1f°" % Stats.mean(_initial_offsets) if not _initial_offsets.is_empty() else "—",
			"distance viseur → cible à son apparition")
	add_kpi(report, "TIRS RATÉS", "%d derrière · %d devant" % [_misses_behind, _misses_ahead],
			"par rapport au sens de déplacement de la cible")
	set_chart(report, "TEMPS DE RÉACTION PAR CIBLE ABATTUE (ms)", _reaction_times, "ms", 300.0, true)
	set_panels(report, ["chart", "heatmap"])


# ---------------------------------------------------------------------------

func _hidden_position(side: int) -> Vector3:
	return _east if side > 0 else _west


## Sens de déplacement actuel de la cible sur l'axe X : -1, +1, ou 0 à l'arrêt.
func _movement_direction() -> int:
	if _target == null or _phase == Phase.HOLDING or _phase == Phase.WAITING:
		return 0
	return 1 if _goal_x > _target.position.x else -1


func _start_rep() -> void:
	_reps += 1
	_side = 1 if rng.randf() < 0.5 else -1
	_crossing = rng.randf() >= peek_ratio
	_seen = false
	_rep_shots = 0
	_target = spawn_target(_hidden_position(_side), target_radius)
	if _crossing:
		_phase = Phase.CROSSING
		_goal_x = _hidden_position(-_side).x
	else:
		_phase = Phase.MOVING_OUT
		# Point d'arrêt à l'intérieur de l'ouverture, du côté d'où vient la cible.
		_goal_x = float(_side) * rng.randf_range(0.3, 1.1)
	Telemetry.log_event("rep_start", {"crossing": _crossing, "side": _side})


## Avance la cible vers `_goal_x` ; renvoie vrai quand elle y est arrivée.
func _move_target(delta: float) -> bool:
	if _target == null:
		return true
	var position_x := move_toward(_target.position.x, _goal_x, target_speed * delta)
	_target.position.x = position_x
	return is_equal_approx(position_x, _goal_x)


func _register_kill(shot: Dictionary) -> void:
	hits += 1
	_kills += 1
	_rep_shots += 1
	if _rep_shots == 1:
		_first_shots += 1
		_first_shot_hits += 1
	var shot_usec: int = shot.get("time_usec", Time.get_ticks_usec())
	var reaction_ms := 0.0
	if _seen:
		reaction_ms = float(shot_usec - _seen_usec) / 1000.0
		_reaction_times.append(reaction_ms)
	# 100 points + jusqu'à 150 selon la réaction (complet sous 180 ms, nul au-delà de 500 ms).
	score += 100 + roundi(150.0 * clampf(1.0 - (reaction_ms - 180.0) / 320.0, 0.0, 1.0))
	record_shot(true, _target, shot, {"reaction_ms": reaction_ms, "crossing": _crossing})
	fx.explosion(_target.global_position)
	hud.flash_hit()
	hud.show_feedback("%d ms" % roundi(reaction_ms), Hud.COLOR_GOOD if reaction_ms <= 300.0 else Hud.COLOR_INFO)
	Sfx.play(&"kill")
	_end_rep(true)


func _end_rep(killed: bool) -> void:
	if not killed:
		_escapes += 1
		Telemetry.log_event("target_escaped", {"crossing": _crossing, "seen": _seen})
	if _target != null:
		_target.destroy()
		_target = null
	_phase = Phase.WAITING
	_timer = rng.randf_range(min_delay, max_delay)
