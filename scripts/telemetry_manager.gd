extends Node
## Autoload « Telemetry » : capture haute fréquence et analyse biomécanique.
##
## Capture — à chaque tick physique (1000 Hz, cf. project.godot) on échantillonne
## le yaw/pitch de la caméra et sa vitesse angulaire. Chaque tir est horodaté
## avec l'écart angulaire entre le viseur et la cible visée.
##
## Analyse — à la fin de la session, le signal est dérivé (vitesse puis
## accélération angulaire) et découpé en « flicks » (trajet entre deux tirs) :
##   * Overflick / Underflick : position du viseur à la fin du mouvement
##     balistique primaire (premier sous-mouvement rapide du trajet), projetée
##     sur l'axe départ → cible et comparée au rayon apparent de la cible.
##   * Fluidité : variance de l'accélération angulaire de chaque flick,
##     rapportée à la variance minimale théorique pour la même amplitude et la
##     même durée (indice sans dimension, 100 = profil « minimum-jerk »).
##
## Remarque : Godot distribue les événements souris une fois par image rendue.
## L'échantillonnage est bien à 1000 Hz, mais l'angle ne change qu'à la cadence
## du rendu ; la fenêtre de dérivation s'adapte donc au FPS mesuré, et le projet
## désactive la V-Sync par défaut pour maximiser cette résolution temporelle.

signal session_started(mode_name: String)
signal session_finished(report: Dictionary)

## Amplitude minimale (°) pour qu'un trajet entre deux tirs compte comme un flick.
const MIN_FLICK_ANGLE := 3.0
## Vitesse de pointe minimale (°/s) d'un mouvement rapide.
const MIN_FLICK_PEAK_SPEED := 40.0
## Le mouvement balistique primaire est le premier sous-mouvement qui atteint
## cette fraction de la vitesse de pointe du trajet...
const PRIMARY_START_RATIO := 0.25
## ... et il se termine quand la vitesse retombe sous cette fraction de son propre pic.
const PRIMARY_END_RATIO := 0.15
## Vitesse (°/s) sous laquelle le viseur est considéré comme immobile.
const MOVING_SPEED := 8.0
## sqrt(12 / 17,14) : score brut d'un profil minimum-jerk parfait, utilisé pour
## ramener l'indice de fluidité sur une échelle 0–100.
const MIN_JERK_REFERENCE := 0.8367


class ShotRecord:
	## Index de l'échantillon de télémétrie au moment du clic.
	var tick: int = 0
	## Secondes écoulées depuis le début de la session.
	var time: float = 0.0
	var hit: bool = false
	## Faux si aucune cible n'était présente (tir non analysable).
	var has_target: bool = false
	## Position du tir relative au centre de la cible, en degrés (droite +, haut +).
	var offset: Vector2 = Vector2.ZERO
	## Rayon apparent de la cible, en degrés.
	var angular_radius: float = 0.0
	var target_id: int = -1


var recording: bool = false

var _camera: Camera3D
var _mode_name: String = ""
var _duration: float = 60.0
var _tick_rate: float = 1000.0
var _dt: float = 0.001
var _start_usec: int = 0

var _count: int = 0
var _frames: int = 0
## Yaw déroulé (sans saut à ±180°) et pitch, en degrés, un échantillon par tick.
var _yaw: PackedFloat64Array = PackedFloat64Array()
var _pitch: PackedFloat64Array = PackedFloat64Array()
## Vitesse angulaire instantanée (°/s) mesurée d'un tick au suivant.
var _raw_speed: PackedFloat32Array = PackedFloat32Array()
var _yaw_unwrapped: float = 0.0
var _last_yaw_wrapped: float = 0.0
var _last_pitch: float = 0.0
var _shots: Array[ShotRecord] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(false)
	set_process(false)


# ---------------------------------------------------------------------------
# API de capture
# ---------------------------------------------------------------------------

func begin_session(mode_name: String, duration: float, camera: Camera3D) -> void:
	_camera = camera
	_mode_name = mode_name
	_duration = duration
	_tick_rate = float(Engine.physics_ticks_per_second)
	_dt = 1.0 / _tick_rate

	var capacity := ceili(duration * _tick_rate) + 4096
	_yaw.resize(capacity)
	_pitch.resize(capacity)
	_raw_speed.resize(capacity)
	_count = 0
	_frames = 0
	_shots.clear()

	var angles := _camera_angles()
	_yaw_unwrapped = angles.x
	_last_yaw_wrapped = angles.x
	_last_pitch = angles.y

	_start_usec = Time.get_ticks_usec()
	recording = true
	set_physics_process(true)
	set_process(true)
	session_started.emit(mode_name)


## Termine la session, calcule le rapport et le renvoie.
func end_session(score: int) -> Dictionary:
	if not recording:
		return {}
	_stop()
	var report := _build_report(score)
	session_finished.emit(report)
	return report


## Abandonne la session sans produire de rapport.
func cancel_session() -> void:
	if recording:
		_stop()


## Enregistre un tir. `target_position` / `target_radius` décrivent la cible
## touchée, ou la cible la plus proche du viseur en cas de tir raté
## (`target_radius` <= 0 s'il n'y avait aucune cible).
func record_shot(hit: bool, target_position: Vector3, target_radius: float, target_id: int = -1) -> void:
	if not recording or not is_instance_valid(_camera):
		return
	var shot := ShotRecord.new()
	shot.tick = _count
	shot.time = float(Time.get_ticks_usec() - _start_usec) / 1000000.0
	shot.hit = hit
	shot.target_id = target_id
	if target_radius > 0.0:
		shot.has_target = true
		shot.offset = -angular_offset_to(target_position)
		var distance := _camera.global_position.distance_to(target_position)
		shot.angular_radius = rad_to_deg(asin(clampf(target_radius / maxf(distance, 0.001), 0.0, 1.0)))
	_shots.append(shot)


## Écart angulaire (°) d'un point du monde par rapport au viseur :
## x > 0 = à droite, y > 0 = au-dessus.
func angular_offset_to(world_position: Vector3) -> Vector2:
	if not is_instance_valid(_camera):
		return Vector2.ZERO
	var local: Vector3 = _camera.global_transform.affine_inverse() * world_position
	var azimuth := atan2(local.x, -local.z)
	var elevation := atan2(local.y, sqrt(local.x * local.x + local.z * local.z))
	return Vector2(rad_to_deg(azimuth), rad_to_deg(elevation))


func sample_count() -> int:
	return _count


# ---------------------------------------------------------------------------
# Échantillonnage
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not recording or not is_instance_valid(_camera):
		return
	var angles := _camera_angles()
	var d_yaw := wrapf(angles.x - _last_yaw_wrapped, -180.0, 180.0)
	var d_pitch := angles.y - _last_pitch
	_yaw_unwrapped += d_yaw
	_last_yaw_wrapped = angles.x
	_last_pitch = angles.y

	if _count >= _yaw.size():
		var grown := _yaw.size() + 8192
		_yaw.resize(grown)
		_pitch.resize(grown)
		_raw_speed.resize(grown)

	var horizontal := d_yaw * cos(deg_to_rad(angles.y))
	_yaw[_count] = _yaw_unwrapped
	_pitch[_count] = angles.y
	_raw_speed[_count] = sqrt(horizontal * horizontal + d_pitch * d_pitch) * _tick_rate
	_count += 1


func _process(_delta: float) -> void:
	if recording:
		_frames += 1


## (yaw, pitch) de la caméra en degrés ; le yaw est dans [-180, 180].
func _camera_angles() -> Vector2:
	var euler := _camera.global_transform.basis.get_euler()
	return Vector2(rad_to_deg(euler.y), rad_to_deg(euler.x))


func _stop() -> void:
	recording = false
	set_physics_process(false)
	set_process(false)


# ---------------------------------------------------------------------------
# Analyse
# ---------------------------------------------------------------------------

func _build_report(score: int) -> Dictionary:
	var elapsed := float(_count) * _dt
	var shot_count := _shots.size()
	var hit_count := 0
	var hit_times := PackedFloat64Array()
	var miss_offsets := PackedVector2Array()
	var hit_offsets := PackedVector2Array()
	var miss_sum := Vector2.ZERO
	var miss_distance_sum := 0.0

	for shot in _shots:
		var normalized := Vector2.ZERO
		if shot.angular_radius > 0.0:
			normalized = shot.offset / shot.angular_radius
		if shot.hit:
			hit_count += 1
			hit_times.append(shot.time)
			hit_offsets.append(normalized)
		elif shot.has_target:
			miss_offsets.append(normalized)
			miss_sum += shot.offset
			miss_distance_sum += shot.offset.length()

	# Temps entre deux cibles détruites (ms).
	var intervals := PackedFloat64Array()
	for i in range(1, hit_times.size()):
		intervals.append((hit_times[i] - hit_times[i - 1]) * 1000.0)
	var avg_ttk := 0.0
	var median_ttk := 0.0
	var best_ttk := 0.0
	if not intervals.is_empty():
		var total := 0.0
		for value in intervals:
			total += value
		avg_ttk = total / float(intervals.size())
		var sorted_intervals := intervals.duplicate()
		sorted_intervals.sort()
		median_ttk = sorted_intervals[sorted_intervals.size() >> 1]
		best_ttk = sorted_intervals[0]

	var analysed_misses := miss_offsets.size()
	var report := {
		"mode": _mode_name,
		"duration": _duration,
		"elapsed": elapsed,
		"score": score,
		"shots": shot_count,
		"hits": hit_count,
		"misses": shot_count - hit_count,
		"accuracy": 100.0 * float(hit_count) / float(shot_count) if shot_count > 0 else 0.0,
		"kills_per_second": float(hit_count) / elapsed if elapsed > 0.0 else 0.0,
		"avg_ttk_ms": avg_ttk,
		"median_ttk_ms": median_ttk,
		"best_ttk_ms": best_ttk,
		"miss_offsets": miss_offsets,
		"hit_offsets": hit_offsets,
		"miss_bias_deg": miss_sum / float(analysed_misses) if analysed_misses > 0 else Vector2.ZERO,
		"avg_miss_distance_deg": miss_distance_sum / float(analysed_misses) if analysed_misses > 0 else 0.0,
		"flick_count": 0,
		"overflick_count": 0,
		"underflick_count": 0,
		"precise_count": 0,
		"overflick_rate": 0.0,
		"underflick_rate": 0.0,
		"precise_rate": 0.0,
		"avg_overshoot_deg": 0.0,
		"avg_undershoot_deg": 0.0,
		"flick_bias_deg": 0.0,
		"avg_flick_distance_deg": 0.0,
		"avg_peak_speed": 0.0,
		"smoothness": 0.0,
		"smoothness_samples": 0,
		"accel_std": 0.0,
		"sample_count": _count,
		"sample_rate_hz": _tick_rate,
		"input_rate_hz": float(_frames) / elapsed if elapsed > 0.0 else 0.0,
	}
	_analyse_kinematics(report)
	return report


func _analyse_kinematics(report: Dictionary) -> void:
	var n := _count
	if n < 32:
		return

	# 1) Fenêtre de dérivation : au moins 1,5 image rendue, pour lisser les
	#    paliers créés par la distribution des événements souris une fois par image.
	var frame_ms := 1000.0 * float(n) * _dt / float(maxi(_frames, 1))
	var half_ms := clampf(frame_ms * 1.5, 4.0, 25.0)
	var half := maxi(1, roundi(half_ms * _tick_rate / 1000.0))

	# 2) Vitesse angulaire (°/s) dans le repère écran : X vers la droite, Y vers le haut.
	var vel_x := PackedFloat32Array()
	var vel_y := PackedFloat32Array()
	vel_x.resize(n)
	vel_y.resize(n)
	for i in n:
		var a := maxi(i - half, 0)
		var b := mini(i + half, n - 1)
		var span := float(b - a) * _dt
		var cos_pitch := cos(deg_to_rad(_pitch[i]))
		vel_x[i] = -(_yaw[b] - _yaw[a]) * cos_pitch / span
		vel_y[i] = (_pitch[b] - _pitch[a]) / span
	vel_x = _box_smooth(vel_x, half)
	vel_y = _box_smooth(vel_y, half)

	var speed := PackedFloat32Array()
	speed.resize(n)
	for i in n:
		speed[i] = sqrt(vel_x[i] * vel_x[i] + vel_y[i] * vel_y[i])

	# 3) Accélération angulaire (°/s²).
	var acc_x := PackedFloat32Array()
	var acc_y := PackedFloat32Array()
	acc_x.resize(n)
	acc_y.resize(n)
	for i in n:
		var a := maxi(i - half, 0)
		var b := mini(i + half, n - 1)
		var span := float(b - a) * _dt
		acc_x[i] = (vel_x[b] - vel_x[a]) / span
		acc_y[i] = (vel_y[b] - vel_y[a]) / span

	# 4) Découpage en flicks : un segment = trajet du viseur entre deux tirs.
	var flicks := 0
	var over := 0
	var under := 0
	var precise := 0
	var overshoot_sum := 0.0
	var undershoot_sum := 0.0
	var signed_error_sum := 0.0
	var distance_sum := 0.0
	var peak_sum := 0.0
	var smooth_sum := 0.0
	var smooth_count := 0
	var acc_square_sum := 0.0
	var acc_samples := 0
	var previous_tick := 0

	for shot in _shots:
		var start := clampi(previous_tick, 0, n - 1)
		var stop := clampi(shot.tick, 0, n - 1)
		previous_tick = shot.tick
		if stop - start < 4:
			continue

		# Le viseur est souvent encore en mouvement au moment du tir précédent : cette
		# décélération appartient au geste d'avant. L'analyse démarre au creux de vitesse
		# qui la suit (pente mesurée sur une demi-fenêtre pour ignorer le bruit).
		var begin := start
		while begin + half <= stop and speed[begin + half] < speed[begin]:
			begin += 1
		var trough_limit := mini(begin + half, stop)
		for i in range(begin, trough_limit + 1):
			if speed[i] < speed[begin]:
				begin = i

		var peak_speed := 0.0
		for i in range(begin, stop + 1):
			peak_speed = maxf(peak_speed, speed[i])
		if peak_speed < MIN_FLICK_PEAK_SPEED:
			continue

		var cos_ref := cos(deg_to_rad(_pitch[stop]))

		# --- Fluidité : variance de l'accélération pendant la phase de mouvement ---
		var threshold := maxf(MOVING_SPEED, peak_speed * 0.05)
		var onset := begin
		while onset < stop and speed[onset] <= threshold:
			onset += 1
		var settle := stop
		while settle > onset and speed[settle] <= threshold:
			settle -= 1
		var move_samples := settle - onset
		if move_samples >= maxi(8, half * 2):
			var move_time := float(move_samples) * _dt
			var move_x := -(_yaw[settle] - _yaw[onset]) * cos_ref
			var move_y := _pitch[settle] - _pitch[onset]
			var move_distance := sqrt(move_x * move_x + move_y * move_y)
			if move_distance >= 1.0:
				var mean_x := 0.0
				var mean_y := 0.0
				var mean_square := 0.0
				for i in range(onset, settle + 1):
					mean_x += acc_x[i]
					mean_y += acc_y[i]
					mean_square += acc_x[i] * acc_x[i] + acc_y[i] * acc_y[i]
				var samples := float(move_samples + 1)
				acc_square_sum += mean_square
				acc_samples += move_samples + 1
				mean_x /= samples
				mean_y /= samples
				mean_square /= samples
				var variance := maxf(mean_square - (mean_x * mean_x + mean_y * mean_y), 0.000001)
				# Variance minimale possible pour parcourir cette distance dans ce temps
				# (profil d'accélération linéaire, départ et arrivée à l'arrêt).
				var ideal_variance := 12.0 * move_distance * move_distance / pow(move_time, 4.0)
				var ratio := sqrt(ideal_variance / variance) / MIN_JERK_REFERENCE
				smooth_sum += clampf(ratio, 0.0, 1.0)
				smooth_count += 1

		# --- Overflick / Underflick ---
		if not shot.has_target:
			continue
		var start_yaw := _yaw[begin]
		var start_pitch := _pitch[begin]
		var aim := Vector2(-(_yaw[stop] - start_yaw) * cos_ref, _pitch[stop] - start_pitch)
		var to_target: Vector2 = aim - shot.offset
		var distance := to_target.length()
		if distance < MIN_FLICK_ANGLE:
			continue
		var direction: Vector2 = to_target / distance

		# Mouvement balistique primaire : premier sous-mouvement significatif du trajet.
		# Il se termine à la première retombée de vitesse sous une fraction de son pic ;
		# s'il n'y en a pas avant le tir, on retient la position au moment du tir.
		var primary_threshold := maxf(MIN_FLICK_PEAK_SPEED, peak_speed * PRIMARY_START_RATIO)
		var cursor := begin
		while cursor < stop and speed[cursor] < primary_threshold:
			cursor += 1
		var primary_peak := speed[cursor]
		var end_index := stop
		for i in range(cursor + 1, stop + 1):
			if speed[i] > primary_peak:
				primary_peak = speed[i]
			elif speed[i] < primary_peak * PRIMARY_END_RATIO:
				end_index = i
				break
		var end_point := Vector2(-(_yaw[end_index] - start_yaw) * cos_ref, _pitch[end_index] - start_pitch)
		var error := end_point.dot(direction) - distance

		flicks += 1
		distance_sum += distance
		peak_sum += primary_peak
		signed_error_sum += error
		if error > shot.angular_radius:
			over += 1
			overshoot_sum += error
		elif error < -shot.angular_radius:
			under += 1
			undershoot_sum += -error
		else:
			precise += 1

	if flicks > 0:
		var flick_total := float(flicks)
		report["flick_count"] = flicks
		report["overflick_count"] = over
		report["underflick_count"] = under
		report["precise_count"] = precise
		report["overflick_rate"] = 100.0 * float(over) / flick_total
		report["underflick_rate"] = 100.0 * float(under) / flick_total
		report["precise_rate"] = 100.0 * float(precise) / flick_total
		report["avg_overshoot_deg"] = overshoot_sum / float(over) if over > 0 else 0.0
		report["avg_undershoot_deg"] = undershoot_sum / float(under) if under > 0 else 0.0
		report["flick_bias_deg"] = signed_error_sum / flick_total
		report["avg_flick_distance_deg"] = distance_sum / flick_total
		report["avg_peak_speed"] = peak_sum / flick_total
	if smooth_count > 0:
		report["smoothness"] = 100.0 * smooth_sum / float(smooth_count)
		report["smoothness_samples"] = smooth_count
	if acc_samples > 0:
		report["accel_std"] = sqrt(acc_square_sum / float(acc_samples))


## Moyenne glissante centrée de demi-largeur `half` (somme préfixe, O(n)).
static func _box_smooth(source: PackedFloat32Array, half: int) -> PackedFloat32Array:
	var n := source.size()
	var result := PackedFloat32Array()
	result.resize(n)
	if n == 0:
		return result
	var prefix := PackedFloat64Array()
	prefix.resize(n + 1)
	prefix[0] = 0.0
	for i in n:
		prefix[i + 1] = prefix[i] + source[i]
	for i in n:
		var a := maxi(i - half, 0)
		var b := mini(i + half, n - 1)
		result[i] = (prefix[b + 1] - prefix[a]) / float(b - a + 1)
	return result
