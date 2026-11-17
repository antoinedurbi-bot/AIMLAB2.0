extends CharacterBody3D
## Contrôleur FPS : visée 1:1 sur les counts bruts de la souris, déplacement de
## FPS tactique et tir hitscan. Les touches viennent de GameSettings.keys.
##
## Déplacement — la vitesse au sol rejoint la vitesse voulue à taux constant :
##   * départ : pleine vitesse en ~160 ms ;
##   * touche relâchée : tir précis après ~85 ms, arrêt complet en ~120 ms ;
##   * contre-strafe (touche opposée) : tir précis après ~50 ms.
## L'arrêt est donc franc même sans contre-strafe, qui reste un peu plus rapide.
## Pas de gain de vitesse en l'air : le saut conserve l'élan, avec très peu de
## contrôle. L'atterrissage et une balle reçue ralentissent brièvement.
## La vitesse de course dépend de l'arme ; marcher et s'accroupir sont silencieux.
##
## Recul — chaque balle fait monter le viseur lui-même (le joueur le voit et le
## contre en tirant la souris vers le bas) ; la balle part là où il pointe.
## Les trois premières balles d'une rafale sont parfaitement précises, puis une
## petite erreur aléatoire s'installe. Quand on cesse de tirer, le recul se
## résorbe progressivement : le viseur redescend et la rafale repart de zéro,
## en un peu moins d'une demi-seconde après une courte rafale.
##
## Précision — immobile, la première balle a une faible dispersion propre à
## l'arme (réduite accroupi). Au-dessus de ACCURATE_SPEED le tir est dévié, de
## plus en plus avec la vitesse ; en l'air il part n'importe où.
##
## Ces valeurs visent le ressenti d'un FPS tactique moderne ; ce sont des
## estimations réglables ci-dessous, pas des mesures d'un jeu.

## Émis à chaque tir. `collider` est nul si le rayon n'a rien touché. `shot`
## décrit l'état du joueur au moment du tir (vitesse, déviation, touches...).
signal fired(collider: Object, hit_position: Vector3, hit_normal: Vector3, muzzle_position: Vector3, shot: Dictionary)

## Touche 1, 2 ou 3 (index 0 à 2) : choix d'un utilitaire.
signal utility_key_pressed(index: int)
## Clic droit : lancer l'utilitaire sélectionné depuis `origin` dans `direction`.
signal utility_throw_requested(origin: Vector3, direction: Vector3)

const MAX_PITCH_DEG := 89.0

## Vitesse de course de référence (fusil) ; l'arme en main fixe la valeur réelle.
const RUN_SPEED := 5.4
## Marche et accroupi : fraction de la vitesse de course.
const WALK_RATIO := 0.54
const CROUCH_RATIO := 0.45
## Taux d'accélération et de freinage au sol (m/s²).
const GROUND_ACCELERATION := 34.0
const GROUND_DECELERATION := 45.0
## Contrôle en l'air (m/s²) : volontairement faible.
const AIR_ACCELERATION := 7.0
const GRAVITY := 20.0
## Après un saut : vitesse multipliée par LANDING_SLOW, rétablie en LANDING_RECOVERY s.
const LANDING_SLOW := 0.55
const LANDING_RECOVERY := 0.35
const MIN_AIR_TIME := 0.15
## Balle reçue : vitesse multipliée par TAG_SLOW, rétablie en TAG_RECOVERY s.
const TAG_SLOW := 0.3
const TAG_RECOVERY := 0.5

## Vitesse (m/s) sous laquelle le tir est parfaitement précis.
const ACCURATE_SPEED := 1.5
## Fraction de RUN_SPEED à partir de laquelle on considère le joueur « à pleine vitesse ».
const FULL_SPEED_RATIO := 0.85
const MIN_MOVING_SPREAD_DEG := 1.2
const MAX_MOVING_SPREAD_DEG := 5.0
const AIR_SPREAD_DEG := 8.0
const CROUCH_SPREAD_FACTOR := 0.8

const Weapons := preload("res://scripts/weapons.gd")

## Balles d'une rafale sans aucune erreur aléatoire ; l'erreur atteint son maximum 4 balles plus tard.
const ACCURATE_SHOTS := 3
## Part de la montée normale appliquée aux trois premières balles.
const EARLY_CLIMB_RATIO := 0.35
## Le recul ne se résorbe qu'après ce nombre d'intervalles de tir sans tirer.
const RECOIL_HOLD_INTERVALS := 1.5
## Vitesse de résorption : balles de rafale « oubliées » par seconde.
const RECOIL_RECOVERY_RATE := 16.0
## Vitesse maximale du viseur sous l'effet du recul (°/s).
const RECOIL_VIEW_SPEED := 140.0
const MAX_SPRAY_HEAT := 60.0
## Accroupi : hauteur des yeux, vitesse, et recul multiplié par ce facteur.
const STAND_EYE_HEIGHT := 1.7
const CROUCH_EYE_HEIGHT := 1.15
const CROUCH_RECOIL_FACTOR := 0.8
const JUMP_VELOCITY := 5.6
## Au-dessus de cette vitesse les pas s'entendent ; distance entre deux pas (m).
const LOUD_SPEED := 3.3
const STEP_DISTANCE := 2.3
const KEY_BIT_CROUCH := 32

## Bits du masque de touches transmis à la télémétrie.
const KEY_BIT_FORWARD := 1
const KEY_BIT_BACK := 2
const KEY_BIT_LEFT := 4
const KEY_BIT_RIGHT := 8
const KEY_BIT_WALK := 16

## Autorise la rotation de la caméra.
var look_enabled: bool = false
## Autorise le tir.
var fire_enabled: bool = false
## Autorise le déplacement (ZQSD / WASD selon la disposition du clavier).
var move_enabled: bool = false
## Dévie les tirs déclenchés en mouvement.
var movement_inaccuracy: bool = false
## Active les touches d'utilitaires (1, 2, 3 et clic droit).
var utility_enabled: bool = false
## Tir automatique tant que le clic est maintenu.
var automatic: bool = false
## Applique le recul (les balles montent puis se balancent pendant une rafale).
var recoil_enabled: bool = false

var yaw_deg: float = 0.0
var pitch_deg: float = 0.0

# --- Suivi du déplacement, lu par les exercices ---
## Dernier instant (µs) où le joueur était à pleine vitesse, 0 si jamais.
var last_full_speed_usec: int = 0
## Sens latéral à cet instant : -1 gauche, +1 droite, 0 si déplacement avant/arrière.
var full_speed_direction: int = 0
var left_press_usec: int = 0
var left_release_usec: int = 0
var right_press_usec: int = 0
var right_release_usec: int = 0

var _degrees_per_count: float = 0.04
var _key_forward: bool = false
var _key_back: bool = false
var _key_left: bool = false
var _key_right: bool = false
var _key_walk: bool = false
var _trigger_held: bool = false
var _key_crouch: bool = false
var _step_distance: float = 0.0
var _landing_slow: float = 1.0
var _tag_slow: float = 1.0
var _air_time: float = 0.0
## Profil de l'arme en main (voir scripts/weapons.gd).
var weapon: Dictionary = {}
## Distance parcourue en faisant du bruit depuis le début de la session (m).
var loud_distance: float = 0.0
var _next_shot_usec: int = 0
var _last_shot_usec: int = 0
## Nombre de balles de la rafale en cours (fractionnaire pendant la résorption).
var _spray_heat: float = 0.0
## Décalage du viseur dû au recul (°) : x vers la droite, y vers le haut.
var _punch: Vector2 = Vector2.ZERO

@onready var pivot: Node3D = $Pivot
@onready var camera: Camera3D = $Pivot/Camera3D
@onready var aim_ray: RayCast3D = $Pivot/Camera3D/AimRay
@onready var muzzle: Marker3D = $Pivot/Camera3D/Muzzle


func _ready() -> void:
	GameSettings.sensitivity_changed.connect(_refresh_settings)
	_refresh_settings()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if look_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_look(event as InputEventMouseMotion)
		return
	if event.is_echo():
		return
	var action: String = GameSettings.action_for(GameSettings.event_code(event))
	if action == "":
		return
	var pressed := event.is_pressed()
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Mini-carte ouverte : sa touche la referme ; les relâchements restent pris en compte.
		if action == "util1" and pressed and utility_enabled:
			utility_key_pressed.emit(0)
		elif not pressed and move_enabled:
			_handle_action(action, false)
		return
	_handle_action(action, pressed)


func _process(delta: float) -> void:
	_update_recoil(delta)
	# Accroupissement : la caméra descend ou remonte progressivement.
	var eye_height := CROUCH_EYE_HEIGHT if _key_crouch and move_enabled else STAND_EYE_HEIGHT
	pivot.position.y = move_toward(pivot.position.y, eye_height, 5.0 * delta)
	# Tir automatique : une balle par intervalle tant que le clic est maintenu.
	var weapon_automatic: bool = weapon.get("automatic", true)
	if not automatic or not weapon_automatic or not _trigger_held or not fire_enabled:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_trigger_held = false
		return
	var now := Time.get_ticks_usec()
	if now >= _next_shot_usec:
		_fire()
		_next_shot_usec = maxi(_next_shot_usec + int(_fire_interval() * 1000000.0), now)


func _physics_process(delta: float) -> void:
	if not move_enabled:
		return

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var grounded := is_on_floor()
	_landing_slow = move_toward(_landing_slow, 1.0, delta * (1.0 - LANDING_SLOW) / LANDING_RECOVERY)
	_tag_slow = move_toward(_tag_slow, 1.0, delta * (1.0 - TAG_SLOW) / TAG_RECOVERY)

	# Vitesse voulue : direction des touches, plafond selon la posture et les ralentissements.
	var strafe := float(_key_right) - float(_key_left)
	var advance := float(_key_back) - float(_key_forward)
	var wish := Vector3.ZERO
	if strafe != 0.0 or advance != 0.0:
		var top := run_speed()
		if _key_crouch:
			top *= CROUCH_RATIO
		elif _key_walk:
			top *= WALK_RATIO
		top *= minf(_landing_slow, _tag_slow)
		wish = (global_transform.basis * Vector3(strafe, 0.0, advance)).normalized() * top

	if grounded:
		var rate := GROUND_DECELERATION
		if wish != Vector3.ZERO:
			rate = GROUND_ACCELERATION
			# Touche opposée à l'élan : le freinage s'ajoute à l'accélération (contre-strafe).
			if horizontal.dot(wish) < 0.0:
				rate += GROUND_DECELERATION
		horizontal = horizontal.move_toward(wish, rate * delta)
	elif wish != Vector3.ZERO:
		# En l'air : on infléchit la trajectoire sans jamais gagner de vitesse.
		var cap := maxf(horizontal.length(), wish.length() * 0.3)
		horizontal = (horizontal + wish.normalized() * AIR_ACCELERATION * delta).limit_length(cap)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if grounded:
		velocity.y = maxf(velocity.y, 0.0)
	else:
		velocity.y -= GRAVITY * delta
		_air_time += delta
	move_and_slide()
	if is_on_floor():
		if _air_time >= MIN_AIR_TIME:
			_landing_slow = LANDING_SLOW
		_air_time = 0.0

	var current_speed := horizontal_speed()
	# Bruits de pas : courir s'entend, marcher ou s'accroupir non.
	if current_speed > LOUD_SPEED and is_on_floor():
		loud_distance += current_speed * delta
		_step_distance += current_speed * delta
		if _step_distance >= STEP_DISTANCE:
			_step_distance = 0.0
			Sfx.play(&"step")
	if current_speed >= run_speed() * FULL_SPEED_RATIO:
		last_full_speed_usec = Time.get_ticks_usec()
		var lateral := lateral_velocity()
		if absf(lateral) >= current_speed * 0.7:
			full_speed_direction = 1 if lateral > 0.0 else -1
		else:
			full_speed_direction = 0


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

## Recentre la vue (sans déplacer le joueur).
func reset_view() -> void:
	yaw_deg = 0.0
	pitch_deg = 0.0
	_apply_rotation()


## Place le joueur à `world_position` (pieds), orienté selon `facing_yaw_deg`
## (0 = vers -Z, positif = vers la gauche), à l'arrêt.
func teleport(world_position: Vector3, facing_yaw_deg: float) -> void:
	global_position = world_position
	loud_distance = 0.0
	velocity = Vector3.ZERO
	yaw_deg = facing_yaw_deg
	pitch_deg = 0.0
	_apply_rotation()
	reset_input()


## Oublie l'état des touches et l'historique de déplacement (début / fin de session).
func reset_input() -> void:
	_key_forward = false
	_key_back = false
	_key_left = false
	_key_right = false
	_key_walk = false
	velocity = Vector3.ZERO
	last_full_speed_usec = 0
	full_speed_direction = 0
	left_press_usec = 0
	left_release_usec = 0
	right_press_usec = 0
	right_release_usec = 0
	_trigger_held = false
	_key_crouch = false
	_landing_slow = 1.0
	_tag_slow = 1.0
	_air_time = 0.0
	_spray_heat = 0.0
	_punch = Vector2.ZERO
	automatic = false
	recoil_enabled = false
	utility_enabled = false
	Telemetry.input_mask = 0
	_apply_rotation()


## Vitesse de course avec l'arme en main (m/s).
func run_speed() -> float:
	var speed: float = weapon.get("speed", RUN_SPEED)
	return speed


## Ralentit brièvement le joueur : à appeler quand il reçoit une balle.
func apply_tag() -> void:
	_tag_slow = TAG_SLOW


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Vitesse le long de l'axe latéral du joueur (m/s) : positive vers sa droite.
func lateral_velocity() -> float:
	return velocity.dot(global_transform.basis.x)


## Position des yeux dans le monde.
func eye_position() -> Vector3:
	return camera.global_position


## Objet actuellement sous le viseur (sans tirer), ou null.
func aim_collider() -> Object:
	aim_ray.rotation = Vector3.ZERO
	aim_ray.force_raycast_update()
	if aim_ray.is_colliding():
		return aim_ray.get_collider()
	return null


## Décalage du recul (°) pour la balle numéro `index` d'une rafale : montée
## régulière, puis balancement horizontal autour du plafond. Réduit accroupi.
func recoil_offset(index: int) -> Vector2:
	var climb_step: float = weapon.get("climb", 0.6)
	var climb_shots: int = weapon.get("climb_shots", 8)
	var sway_amplitude: float = weapon.get("sway", 1.5)
	# Les trois premières balles montent à peine ; la montée se concentre ensuite,
	# pour retrouver le même total à `climb_shots` balles.
	var units := float(mini(index, climb_shots))
	if climb_shots > ACCURATE_SHOTS:
		units = EARLY_CLIMB_RATIO * float(mini(index, ACCURATE_SHOTS))
		if index > ACCURATE_SHOTS:
			var later := float(climb_shots) - EARLY_CLIMB_RATIO * float(ACCURATE_SHOTS)
			units += later / float(climb_shots - ACCURATE_SHOTS) * float(mini(index, climb_shots) - ACCURATE_SHOTS)
	var climb := climb_step * units
	var sway := 0.0
	if index > climb_shots - 3:
		sway = sin(float(index - climb_shots + 3) * 0.7) * sway_amplitude
	var factor := CROUCH_RECOIL_FACTOR if _key_crouch else 1.0
	return Vector2(sway, climb) * factor


## Décalage du viseur (°) après `heat` balles, interpolé entre deux balles pour
## que la résorption soit continue.
func recoil_target(heat: float) -> Vector2:
	var whole := floori(heat)
	return recoil_offset(whole).lerp(recoil_offset(whole + 1), heat - float(whole))


## Fait monter le viseur avec la rafale, puis le ramène quand on cesse de tirer.
func _update_recoil(delta: float) -> void:
	var idle := float(Time.get_ticks_usec() - _last_shot_usec) / 1000000.0
	if idle > _fire_interval() * RECOIL_HOLD_INTERVALS:
		_spray_heat = move_toward(_spray_heat, 0.0, RECOIL_RECOVERY_RATE * delta)
	var wanted := recoil_target(_spray_heat) if recoil_enabled else Vector2.ZERO
	if _punch.is_equal_approx(wanted):
		return
	_punch = _punch.move_toward(wanted, RECOIL_VIEW_SPEED * delta)
	_apply_rotation()


## Dégâts de l'arme en main sur une cible à 100 points de vie.
func weapon_damage(head: bool) -> float:
	var amount: float = weapon.get("head" if head else "body", 150.0 if head else 40.0)
	return amount


func is_crouching() -> bool:
	return _key_crouch


func _fire_interval() -> float:
	var interval: float = weapon.get("interval", 0.1)
	return interval


# ---------------------------------------------------------------------------
# Visée
# ---------------------------------------------------------------------------

func _refresh_settings() -> void:
	_degrees_per_count = GameSettings.degrees_per_count()
	weapon = Weapons.get_profile(GameSettings.weapon)
	camera.fov = GameSettings.vertical_fov()


func _look(motion: InputEventMouseMotion) -> void:
	var counts := _raw_counts(motion)
	yaw_deg -= counts.x * _degrees_per_count
	pitch_deg = clampf(pitch_deg - counts.y * _degrees_per_count, -MAX_PITCH_DEG, MAX_PITCH_DEG)
	_apply_rotation()


## Déplacement brut de la souris en counts.
## `screen_relative` (Godot 4.3+) est la variante de `relative` qui n'est pas
## mise à l'échelle par le stretch de la fenêtre : c'est la seule valeur 1:1
## quelle que soit la résolution. Sur une version antérieure, on retombe sur
## `relative` en annulant le facteur de stretch.
func _raw_counts(motion: InputEventMouseMotion) -> Vector2:
	var raw: Variant = motion.get(&"screen_relative")
	if raw is Vector2:
		var counts: Vector2 = raw
		return counts
	var visible_width := get_viewport().get_visible_rect().size.x
	var stretch := float(get_window().size.x) / maxf(visible_width, 1.0)
	return motion.relative * stretch


func _apply_rotation() -> void:
	rotation.y = deg_to_rad(wrapf(yaw_deg - _punch.x, -180.0, 180.0))
	pivot.rotation.x = deg_to_rad(clampf(pitch_deg + _punch.y, -MAX_PITCH_DEG, MAX_PITCH_DEG))


# ---------------------------------------------------------------------------
# Actions (touches et boutons définis dans GameSettings.keys)
# ---------------------------------------------------------------------------

func _handle_action(action: String, pressed: bool) -> void:
	var now := Time.get_ticks_usec()
	match action:
		"forward":
			_key_forward = pressed
		"back":
			_key_back = pressed
		"left":
			_key_left = pressed
			if pressed:
				left_press_usec = now
			else:
				left_release_usec = now
		"right":
			_key_right = pressed
			if pressed:
				right_press_usec = now
			else:
				right_release_usec = now
		"walk":
			_key_walk = pressed
		"crouch":
			_key_crouch = pressed
		"jump":
			if pressed and move_enabled and is_on_floor():
				velocity.y = JUMP_VELOCITY
		"fire":
			_trigger_held = pressed
			if fire_enabled and pressed and now >= _next_shot_usec:
				_fire()
				_next_shot_usec = now + int(_fire_interval() * 1000000.0)
			return
		"throw":
			if pressed and utility_enabled:
				utility_throw_requested.emit(camera.global_position, -camera.global_transform.basis.z)
			return
		"util1", "util2", "util3":
			if pressed and utility_enabled:
				utility_key_pressed.emit(action.to_int() - 1)
			return
		_:
			return

	var mask := 0
	if _key_forward:
		mask |= KEY_BIT_FORWARD
	if _key_back:
		mask |= KEY_BIT_BACK
	if _key_left:
		mask |= KEY_BIT_LEFT
	if _key_right:
		mask |= KEY_BIT_RIGHT
	if _key_walk:
		mask |= KEY_BIT_WALK
	if _key_crouch:
		mask |= KEY_BIT_CROUCH
	Telemetry.input_mask = mask
	Telemetry.log_event("key", {"key": action, "pressed": pressed, "speed": horizontal_speed()})


# ---------------------------------------------------------------------------
# Tir
# ---------------------------------------------------------------------------

func _fire() -> void:
	var speed := horizontal_speed()
	var deviation := Vector2.ZERO
	var airborne := move_enabled and not is_on_floor()
	if movement_inaccuracy and (speed > ACCURATE_SPEED or airborne):
		var excess := clampf((speed - ACCURATE_SPEED) / (run_speed() - ACCURATE_SPEED), 0.0, 1.0)
		var spread := AIR_SPREAD_DEG if airborne else lerpf(MIN_MOVING_SPREAD_DEG, MAX_MOVING_SPREAD_DEG, excess)
		deviation = Vector2.from_angle(randf() * TAU) * (spread * sqrt(randf()))

	# Numéro de la balle dans la rafale ; le recul ne se résorbe qu'après une vraie pause.
	var spray_index := roundi(_spray_heat)
	_spray_heat = minf(_spray_heat + 1.0, MAX_SPRAY_HEAT)
	_last_shot_usec = Time.get_ticks_usec()
	if recoil_enabled:
		# Le recul est déjà dans l'orientation du viseur. Les premières balles sont
		# exactes ; ensuite une petite erreur aléatoire propre à l'arme s'installe.
		var ramp := clampf(float(spray_index - (ACCURATE_SHOTS - 1)) / 4.0, 0.0, 1.0)
		var error: float = weapon.get("spread", 0.25) * ramp
		if _key_crouch:
			error *= CROUCH_SPREAD_FACTOR
		deviation += Vector2.from_angle(randf() * TAU) * (error * sqrt(randf()))

	# Le rayon est dévié le temps du tir (x > 0 : vers la droite, y > 0 : vers le haut).
	aim_ray.rotation = Vector3(deg_to_rad(deviation.y), deg_to_rad(-deviation.x), 0.0)
	aim_ray.force_raycast_update()
	var origin := camera.global_position
	var direction: Vector3 = -aim_ray.global_transform.basis.z
	var hit_position: Vector3 = origin + direction * absf(aim_ray.target_position.z)
	var hit_normal: Vector3 = -direction
	var collider: Object = null
	if aim_ray.is_colliding():
		collider = aim_ray.get_collider()
		hit_position = aim_ray.get_collision_point()
		hit_normal = aim_ray.get_collision_normal()
	aim_ray.rotation = Vector3.ZERO

	var shot := {
		"time_usec": Time.get_ticks_usec(),
		"speed": speed,
		"accurate": speed <= ACCURATE_SPEED and not airborne,
		"deviation": deviation,
		"spray_index": spray_index,
		"crouched": _key_crouch,
		"airborne": airborne,
		"lateral_velocity": lateral_velocity(),
		"walking": _key_walk,
		"last_full_speed_usec": last_full_speed_usec,
		"full_speed_direction": full_speed_direction,
		"left_press_usec": left_press_usec,
		"left_release_usec": left_release_usec,
		"right_press_usec": right_press_usec,
		"right_release_usec": right_release_usec,
	}
	fired.emit(collider, hit_position, hit_normal, muzzle.global_position, shot)
