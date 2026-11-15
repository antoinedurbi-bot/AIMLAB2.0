extends "res://scripts/drills/drill_base.gd"
## Localisation au son : un signal est émis quelque part autour du joueur (son
## spatialisé, casque recommandé). Il faut se tourner vers la source et cliquer.
## La source est révélée après chaque réponse.
##
## Mesures : erreur angulaire, confusions gauche / droite et avant / arrière,
## temps de réponse.

var repetitions: int = 10
var source_distance: float = 12.0
var reveal_seconds: float = 1.3
var answer_timeout: float = 7.0

var _player3d: AudioStreamPlayer3D
var _rep: int = 0
var _waiting: float = 1.2
var _active: bool = false
var _source: Vector3 = Vector3.ZERO
var _start_yaw: float = 0.0
var _emit_usec: int = 0
var _pulse: float = 0.0
var _reveal: float = 0.0
var _marker_target: AimTarget

var _errors: PackedFloat32Array = PackedFloat32Array()
var _times: PackedFloat32Array = PackedFloat32Array()
var _side_confusions: int = 0
var _front_back_confusions: int = 0


func setup() -> void:
	_player3d = AudioStreamPlayer3D.new()
	_player3d.stream = Sfx.get_stream(&"beep")
	_player3d.unit_size = 14.0
	_player3d.max_distance = 80.0
	add_child(_player3d)
	hud.set_objective("Écoute le signal, tourne-toi vers sa source et clique. Casque recommandé.")
	hud.set_side_stat("ERREUR MOYENNE", "—")


func shows_clock() -> bool:
	return false


func update(delta: float) -> void:
	if _reveal > 0.0:
		_reveal -= delta
		if _reveal <= 0.0:
			if _marker_target != null:
				_marker_target.destroy()
				_marker_target = null
			if _rep >= repetitions:
				finished = true
			else:
				_waiting = rng.randf_range(1.0, 2.0)
		return
	if not _active:
		_waiting -= delta
		if _waiting <= 0.0:
			_emit()
		return
	_pulse -= delta
	if _pulse <= 0.0:
		_pulse = 0.55
		_player3d.play()
	if float(Time.get_ticks_usec() - _emit_usec) / 1000000.0 > answer_timeout:
		_answer()


func on_shot(_collider: Object, _hit_position: Vector3, _hit_normal: Vector3, _shot: Dictionary) -> void:
	if _active:
		_answer()


func finalize(report: Dictionary) -> void:
	var mean_error := Stats.mean(_errors)
	report["sound_reps"] = _errors.size()
	report["sound_mean_error_deg"] = mean_error
	report["sound_median_error_deg"] = Stats.median(_errors)
	report["sound_side_confusions"] = _side_confusions
	report["sound_front_back_confusions"] = _front_back_confusions
	report["sound_mean_time_s"] = Stats.mean(_times)
	add_kpi(report, "ERREUR MOYENNE", "%d°" % roundi(mean_error) if not _errors.is_empty() else "—", "médiane %d°" % roundi(Stats.median(_errors)))
	add_kpi(report, "GAUCHE / DROITE", str(_side_confusions), "réponses du mauvais côté")
	add_kpi(report, "AVANT / ARRIÈRE", str(_front_back_confusions), "source derrière prise pour devant, ou l'inverse")
	add_kpi(report, "TEMPS DE RÉPONSE", "%.1f s" % Stats.mean(_times) if not _times.is_empty() else "—", "du signal au clic")
	set_chart(report, "ERREUR ANGULAIRE PAR ESSAI (°)", _errors, "°", 20.0, true)
	set_panels(report, ["chart"])


func _emit() -> void:
	# Azimut par rapport au regard actuel : jamais pile devant.
	var azimuth := rng.randf_range(20.0, 170.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	_start_yaw = player.yaw_deg
	var angle := deg_to_rad(_start_yaw + azimuth)
	var eye := player.eye_position()
	_source = eye + Vector3(-sin(angle), 0.0, -cos(angle)) * source_distance
	_player3d.global_position = _source
	_active = true
	_emit_usec = Time.get_ticks_usec()
	_pulse = 0.0
	Telemetry.log_event("sound_emit", {"rep": _rep, "azimuth_deg": azimuth})


func _answer() -> void:
	_active = false
	_rep += 1
	var offset: Vector2 = Telemetry.angular_offset_to(_source)
	var error := absf(offset.x)
	var seconds := float(Time.get_ticks_usec() - _emit_usec) / 1000000.0
	_errors.append(error)
	_times.append(seconds)
	# Position de la source au départ, comparée à la rotation effectuée.
	var asked := wrapf(rad_to_deg(atan2(-(_source.x - player.eye_position().x), -(_source.z - player.eye_position().z))) - _start_yaw, -180.0, 180.0)
	var turned := wrapf(player.yaw_deg - _start_yaw, -180.0, 180.0)
	if error > 30.0 and signf(asked) != signf(turned) and absf(turned) > 10.0:
		_side_confusions += 1
	elif error > 90.0:
		_front_back_confusions += 1
	score += roundi(200.0 * clampf(1.0 - error / 60.0, 0.0, 1.0))
	hud.show_feedback("Erreur %d° · %.1f s" % [roundi(error), seconds], Hud.COLOR_GOOD if error <= 20.0 else Hud.COLOR_BAD, reveal_seconds)
	hud.set_side_stat("ERREUR MOYENNE", "%d°" % roundi(Stats.mean(_errors)))
	_marker_target = spawn_target(_source, 0.5, true)
	_marker_target.set_hittable(false)
	_reveal = reveal_seconds
	Telemetry.log_event("sound_answer", {"rep": _rep, "error_deg": error, "seconds": seconds})
