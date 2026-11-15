extends CharacterBody3D
## Contrôleur FPS : visée 1:1 sur les counts bruts de la souris, déplacement au
## sol de type FPS tactique (accélération vive, friction forte) et tir hitscan.
##
## Visée — aucune interpolation, aucun lissage : chaque count est converti en
## degrés via la sensibilité cm/360° de GameSettings.
##
## Déplacement — modèle friction + accélération vers la direction voulue. Deux
## façons de s'arrêter coexistent et sont mesurables :
##   * relâcher la touche : la friction seule amène sous ACCURATE_SPEED en ~120 ms ;
##   * contre-strafe (appui bref sur la touche opposée) : ~40 ms.
## Les valeurs sont une approximation d'un FPS tactique, pas une copie d'un jeu.
##
## Imprécision — quand `movement_inaccuracy` est actif, un tir déclenché au-dessus
## de ACCURATE_SPEED est dévié aléatoirement, d'autant plus que la vitesse est grande.

## Émis à chaque tir. `collider` est nul si le rayon n'a rien touché. `shot`
## décrit l'état du joueur au moment du tir (vitesse, déviation, touches...).
signal fired(collider: Object, hit_position: Vector3, hit_normal: Vector3, muzzle_position: Vector3, shot: Dictionary)

const MAX_PITCH_DEG := 89.0

## Vitesse de course et de marche (m/s).
const RUN_SPEED := 5.4
const WALK_SPEED := 2.9
const GROUND_ACCELERATION := 12.0
const FRICTION := 10.0
## Sous cette vitesse la friction devient constante : l'arrêt est franc.
const STOP_SPEED := 2.2
const GRAVITY := 22.0

## Vitesse (m/s) sous laquelle le tir est parfaitement précis.
const ACCURATE_SPEED := 1.5
## Fraction de RUN_SPEED à partir de laquelle on considère le joueur « à pleine vitesse ».
const FULL_SPEED_RATIO := 0.85
const MIN_MOVING_SPREAD_DEG := 1.2
const MAX_MOVING_SPREAD_DEG := 5.0

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

@onready var pivot: Node3D = $Pivot
@onready var camera: Camera3D = $Pivot/Camera3D
@onready var aim_ray: RayCast3D = $Pivot/Camera3D/AimRay
@onready var muzzle: Marker3D = $Pivot/Camera3D/Muzzle


func _ready() -> void:
	GameSettings.sensitivity_changed.connect(_refresh_settings)
	_refresh_settings()


func _input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		if look_enabled:
			_look(event as InputEventMouseMotion)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if fire_enabled and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			_fire()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.echo:
			_handle_key(key.physical_keycode, key.pressed)


func _physics_process(delta: float) -> void:
	if not move_enabled:
		return

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()

	# Friction : proportionnelle à la vitesse, puis constante sous STOP_SPEED.
	if speed > 0.0001:
		var drop := maxf(speed, STOP_SPEED) * FRICTION * delta
		horizontal *= maxf(speed - drop, 0.0) / speed

	# Accélération vers la direction voulue, plafonnée à la vitesse cible.
	var strafe := float(_key_right) - float(_key_left)
	var advance := float(_key_back) - float(_key_forward)
	if strafe != 0.0 or advance != 0.0:
		var wish_direction: Vector3 = (global_transform.basis * Vector3(strafe, 0.0, advance)).normalized()
		var wish_speed := WALK_SPEED if _key_walk else RUN_SPEED
		var missing := wish_speed - horizontal.dot(wish_direction)
		if missing > 0.0:
			horizontal += wish_direction * minf(GROUND_ACCELERATION * wish_speed * delta, missing)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	var current_speed := horizontal_speed()
	if current_speed >= RUN_SPEED * FULL_SPEED_RATIO:
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
	Telemetry.input_mask = 0


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Vitesse le long de l'axe latéral du joueur (m/s) : positive vers sa droite.
func lateral_velocity() -> float:
	return velocity.dot(global_transform.basis.x)


## Position des yeux dans le monde.
func eye_position() -> Vector3:
	return camera.global_position


# ---------------------------------------------------------------------------
# Visée
# ---------------------------------------------------------------------------

func _refresh_settings() -> void:
	_degrees_per_count = GameSettings.degrees_per_count()
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
	rotation.y = deg_to_rad(wrapf(yaw_deg, -180.0, 180.0))
	pivot.rotation.x = deg_to_rad(pitch_deg)


# ---------------------------------------------------------------------------
# Touches de déplacement (codes physiques : ZQSD sur AZERTY, WASD sur QWERTY)
# ---------------------------------------------------------------------------

func _handle_key(physical_keycode: Key, pressed: bool) -> void:
	var now := Time.get_ticks_usec()
	var label := ""
	match physical_keycode:
		KEY_W:
			_key_forward = pressed
			label = "forward"
		KEY_S:
			_key_back = pressed
			label = "back"
		KEY_A:
			_key_left = pressed
			label = "left"
			if pressed:
				left_press_usec = now
			else:
				left_release_usec = now
		KEY_D:
			_key_right = pressed
			label = "right"
			if pressed:
				right_press_usec = now
			else:
				right_release_usec = now
		KEY_SHIFT:
			_key_walk = pressed
			label = "walk"
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
	Telemetry.input_mask = mask
	Telemetry.log_event("key", {"key": label, "pressed": pressed, "speed": horizontal_speed()})


# ---------------------------------------------------------------------------
# Tir
# ---------------------------------------------------------------------------

func _fire() -> void:
	var speed := horizontal_speed()
	var deviation := Vector2.ZERO
	if movement_inaccuracy and speed > ACCURATE_SPEED:
		var excess := clampf((speed - ACCURATE_SPEED) / (RUN_SPEED - ACCURATE_SPEED), 0.0, 1.0)
		var spread := lerpf(MIN_MOVING_SPREAD_DEG, MAX_MOVING_SPREAD_DEG, excess)
		deviation = Vector2.from_angle(randf() * TAU) * (spread * sqrt(randf()))

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
		"accurate": speed <= ACCURATE_SPEED,
		"deviation": deviation,
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
