extends "res://scripts/drills/drill_base.gd"
## Diagnostic de départ (2 minutes) : quatre mini-épreuves de 27 s, chacune
## précédée de 3 s de consigne. Chaque épreuve donne une note sur 100 ; la plus
## basse désigne la compétence à travailler en priorité. Les notes sont
## enregistrées dans le profil (PlayerProfile) et pilotent la routine du jour.
##
##   1. FLICK     — une sphère à la fois, à détruire le plus vite possible.
##   2. TRACKING  — garder le viseur sur une sphère qui change de direction.
##   3. RÉACTION  — tirer dès qu'une sphère apparaît, sans tirer avant.
##   4. SPRAY     — rafales longues sur une cible fixe, en compensant le recul.
##
## Barèmes (note 100) : flick = 1,6 cible/s corrigé de la précision ; tracking =
## 75 % du temps sur la cible ; réaction = 180 ms de médiane (0 à 450 ms) ;
## spray = 70 % des balles au but à partir de la troisième de chaque rafale.

enum Phase { FLICK, TRACKING, REACTION, SPRAY }

const PHASE_NAMES := ["FLICK", "TRACKING", "RÉACTION", "SPRAY"]
const PHASE_HINTS := [
	"Détruis chaque sphère le plus vite possible.",
	"Garde le viseur sur la sphère : pas besoin de tirer.",
	"Tire dès que la sphère apparaît. Ne tire pas avant.",
	"Maintiens le clic : rafales de 8 à 10 balles sur la sphère, en tirant le viseur vers le bas.",
]
const PHASE_SECONDS := 27.0
const INTRO_SECONDS := 3.0
const TARGET_DISTANCE := 10.0

var _phase: int = Phase.FLICK
var _intro: bool = true
var _timer: float = INTRO_SECONDS
var _target: AimTarget
var _origin: Vector3 = Vector3.ZERO

# Flick
var _flick_shots: int = 0
var _flick_hits: int = 0
# Tracking
var _track_time: float = 0.0
var _track_on: float = 0.0
var _track_direction: float = 1.0
var _track_speed: float = 0.0
var _track_timer: float = 0.0
# Réaction
var _reaction_wait: float = 0.0
var _reaction_shown_usec: int = 0
var _reaction_times: PackedFloat32Array = PackedFloat32Array()
var _reaction_premature: int = 0
# Spray
var _spray_bullets: int = 0
var _spray_hits: int = 0


func setup() -> void:
	_origin = player.eye_position() + Vector3(0.0, 0.0, -TARGET_DISTANCE)
	hud.set_side_stat("ÉPREUVE", "1 / 4")
	_show_intro()


func update(delta: float) -> void:
	_timer -= delta
	if _intro:
		if _timer <= 0.0:
			_start_phase()
		return
	match _phase:
		Phase.TRACKING:
			_update_tracking(delta)
		Phase.REACTION:
			_update_reaction(delta)
	if _timer <= 0.0:
		_end_phase()


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	if _intro:
		return
	shots += 1
	var struck := collider as AimTarget
	var on_target := struck != null and struck == _target and struck.alive
	if on_target:
		hits += 1
	match _phase:
		Phase.FLICK:
			_flick_shots += 1
			record_shot(on_target, _target, shot)
			if on_target:
				_flick_hits += 1
				fx.explosion(_target.global_position)
				_target.destroy()
				_spawn_flick_target()
		Phase.REACTION:
			if _target == null:
				_reaction_premature += 1
				record_shot(false, null, shot, {"premature": true})
				hud.show_feedback("TROP TÔT", Hud.COLOR_BAD)
			else:
				record_shot(on_target, _target, shot)
				if on_target:
					var shot_usec: int = shot.get("time_usec", Time.get_ticks_usec())
					var reaction_ms := float(shot_usec - _reaction_shown_usec) / 1000.0
					_reaction_times.append(reaction_ms)
					hud.show_feedback("%d ms" % roundi(reaction_ms), Hud.COLOR_GOOD)
					fx.explosion(_target.global_position)
					_clear_target()
					_reaction_wait = rng.randf_range(0.8, 2.0)
		Phase.SPRAY:
			record_shot(on_target, _target, shot, {"spray_index": shot.get("spray_index", 0)})
			# Les deux premières balles d'une rafale sont précises : on note la suite.
			var spray_index: int = shot.get("spray_index", 0)
			if spray_index >= 2:
				_spray_bullets += 1
				if on_target:
					_spray_hits += 1
		Phase.TRACKING:
			record_shot(on_target, _target, shot)
	if on_target:
		hud.flash_hit()
		Sfx.play(&"hit")
		score += 10
	else:
		if collider != null:
			fx.impact(hit_position, hit_normal)
		hud.flash_miss()


func finalize(report: Dictionary) -> void:
	var seconds := PHASE_SECONDS
	var flick_accuracy := float(_flick_hits) / float(maxi(_flick_shots, 1))
	var flick_score := clampf(float(_flick_hits) / seconds * flick_accuracy / 1.6, 0.0, 1.0) * 100.0
	var track_ratio := _track_on / maxf(_track_time, 0.001)
	var track_score := clampf(track_ratio / 0.75, 0.0, 1.0) * 100.0
	var reaction_median := Stats.median(_reaction_times)
	var reaction_score := 0.0
	if _reaction_times.size() >= 3:
		reaction_score = clampf((450.0 - reaction_median) / 270.0, 0.0, 1.0) * 100.0
		# Chaque tir prématuré coûte 5 points : anticiper n'est pas réagir.
		reaction_score = maxf(reaction_score - 5.0 * float(_reaction_premature), 0.0)
	var spray_ratio := float(_spray_hits) / float(maxi(_spray_bullets, 1))
	var spray_score := 0.0
	if _spray_bullets >= 12:
		spray_score = clampf(spray_ratio / 0.7, 0.0, 1.0) * 100.0

	var scores := {"flick": flick_score, "tracking": track_score, "reaction": reaction_score, "spray": spray_score}
	var weakest := "flick"
	for skill: String in scores:
		var value: float = scores[skill]
		var lowest: float = scores[weakest]
		if value < lowest:
			weakest = skill
	var overall := (flick_score + track_score + reaction_score + spray_score) / 4.0
	PlayerProfile.add_benchmark(scores)

	report["score"] = roundi(overall * 10.0)
	report["bench_flick"] = flick_score
	report["bench_tracking"] = track_score
	report["bench_reaction"] = reaction_score
	report["bench_spray"] = spray_score
	report["bench_overall"] = overall
	report["bench_weakest"] = weakest
	report["bench_flick_hits"] = _flick_hits
	report["bench_flick_accuracy"] = flick_accuracy * 100.0
	report["bench_tracking_ratio"] = track_ratio * 100.0
	report["bench_reaction_median_ms"] = reaction_median
	report["bench_reaction_premature"] = _reaction_premature
	report["bench_spray_ratio"] = spray_ratio * 100.0
	report["bench_spray_bullets"] = _spray_bullets

	add_kpi(report, "FLICK", "%d / 100" % roundi(flick_score), "%d cibles · %d %% de précision" % [_flick_hits, roundi(flick_accuracy * 100.0)])
	add_kpi(report, "TRACKING", "%d / 100" % roundi(track_score), "%d %% du temps sur la cible" % roundi(track_ratio * 100.0))
	add_kpi(report, "RÉACTION", "%d / 100" % roundi(reaction_score), "médiane %d ms · %d tirs prématurés" % [roundi(reaction_median), _reaction_premature])
	add_kpi(report, "SPRAY", "%d / 100" % roundi(spray_score), "%d %% des balles au but après la 2e" % roundi(spray_ratio * 100.0))
	set_chart(report, "NOTE PAR COMPÉTENCE · FLICK, TRACKING, RÉACTION, SPRAY", PackedFloat32Array([flick_score, track_score, reaction_score, spray_score]), "pts", 60.0, false)
	set_panels(report, ["chart", "heatmap"])


# ---------------------------------------------------------------------------
# Enchaînement des épreuves
# ---------------------------------------------------------------------------

func _show_intro() -> void:
	_intro = true
	_timer = INTRO_SECONDS
	_clear_target()
	player.automatic = false
	player.recoil_enabled = false
	hud.set_side_stat("ÉPREUVE", "%d / 4 · %s" % [_phase + 1, PHASE_NAMES[_phase]])
	hud.set_objective("%s — %s" % [PHASE_NAMES[_phase], PHASE_HINTS[_phase]])
	hud.show_countdown(str(PHASE_NAMES[_phase]), INTRO_SECONDS - 0.6)
	Sfx.play(&"tick")


func _start_phase() -> void:
	_intro = false
	_timer = PHASE_SECONDS
	Sfx.play(&"go")
	Telemetry.log_event("bench_phase", {"phase": PHASE_NAMES[_phase]})
	match _phase:
		Phase.FLICK:
			_spawn_flick_target()
		Phase.TRACKING:
			_target = spawn_target(_origin, 0.32)
			_track_timer = 0.0
		Phase.REACTION:
			_reaction_wait = rng.randf_range(0.8, 2.0)
		Phase.SPRAY:
			player.automatic = true
			player.recoil_enabled = true
			_target = spawn_target(_origin + Vector3(0.0, 0.0, -1.0), 0.34)


func _end_phase() -> void:
	if _phase >= Phase.SPRAY:
		_clear_target()
		player.automatic = false
		player.recoil_enabled = false
		finished = true
		return
	_phase += 1
	_show_intro()


func _clear_target() -> void:
	if _target != null and is_instance_valid(_target):
		_target.destroy()
	_target = null


# ---------------------------------------------------------------------------
# Épreuves
# ---------------------------------------------------------------------------

func _spawn_flick_target() -> void:
	var offset := Vector3(rng.randf_range(-4.0, 4.0), rng.randf_range(-1.8, 1.8), 0.0)
	_target = spawn_target(_origin + offset, 0.3)


func _update_tracking(delta: float) -> void:
	if _target == null:
		return
	_track_timer -= delta
	if _track_timer <= 0.0:
		_track_timer = rng.randf_range(0.5, 1.3)
		_track_direction = -_track_direction if rng.randf() < 0.7 else _track_direction
		_track_speed = rng.randf_range(2.5, 4.5)
	var next_x := _target.position.x + _track_direction * _track_speed * delta
	if absf(next_x - _origin.x) > 5.0:
		_track_direction = -_track_direction
		next_x = clampf(next_x, _origin.x - 5.0, _origin.x + 5.0)
	_target.position.x = next_x
	_target.position.y = _origin.y + sin(elapsed * 1.7) * 0.6
	_track_time += delta
	if player.aim_collider() == _target:
		_track_on += delta
	hud.set_side_stat("TRACKING", "%d %% sur la cible" % roundi(100.0 * _track_on / maxf(_track_time, 0.001)))


func _update_reaction(delta: float) -> void:
	if _target != null:
		return
	_reaction_wait -= delta
	if _reaction_wait <= 0.0:
		var offset := Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(-0.8, 0.8), 0.0)
		_target = spawn_target(_origin + offset, 0.35)
		_reaction_shown_usec = Time.get_ticks_usec()
