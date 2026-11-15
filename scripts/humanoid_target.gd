extends StaticBody3D
## Cible humanoïde mobile : un corps (capsule) et une tête (sphère cyan, le
## point à viser), qui strafe de façon erratique comme un joueur en duel.
##
## Comportement : la cible court latéralement, change de direction à des
## intervalles aléatoires et marque parfois un arrêt bref (le moment où un
## vrai joueur tire). L'accélération est finie : les demi-tours ne sont pas
## instantanés, on peut donc les lire et les anticiper.

const HEAD_HEIGHT := 1.62
const HEAD_RADIUS := 0.14
## Hauteur (m) au-dessus des pieds à partir de laquelle un impact compte comme tête.
const HEAD_LIMIT := 1.46
const HEAD_DAMAGE := 150.0
const BODY_DAMAGE := 40.0

var target_id: int = -1
var alive: bool = true
var health: float = 100.0

## Faux : la cible reste immobile.
var moving_enabled: bool = true
var strafe_speed: float = 5.4
var acceleration: float = 40.0
## Bornes du déplacement sur l'axe X (coordonnées locales au parent).
var min_x: float = -6.0
var max_x: float = 6.0
## Durée d'un strafe avant un changement de comportement (s).
var change_min: float = 0.25
var change_max: float = 0.9
## Probabilité de marquer un arrêt plutôt que de repartir en sens inverse.
var stop_chance: float = 0.3
var stop_min: float = 0.12
var stop_max: float = 0.35

var _direction: int = 1
var _velocity: float = 0.0
var _timer: float = 0.0
var _stopped: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_direction = 1 if _rng.randf() < 0.5 else -1
	_timer = _rng.randf_range(change_min, change_max)


func _process(delta: float) -> void:
	if not alive or not moving_enabled:
		return
	_timer -= delta
	if _timer <= 0.0:
		if _stopped:
			_stopped = false
			_direction = 1 if _rng.randf() < 0.5 else -1
			_timer = _rng.randf_range(change_min, change_max)
		elif _rng.randf() < stop_chance:
			_stopped = true
			_timer = _rng.randf_range(stop_min, stop_max)
		else:
			_direction = -_direction
			_timer = _rng.randf_range(change_min, change_max)

	var wanted := 0.0 if _stopped else float(_direction) * strafe_speed
	_velocity = move_toward(_velocity, wanted, acceleration * delta)
	var next_x := position.x + _velocity * delta
	if next_x < min_x or next_x > max_x:
		next_x = clampf(next_x, min_x, max_x)
		_direction = -_direction
		_velocity = 0.0
	position.x = next_x


## Position du centre de la tête dans le monde.
func head_position() -> Vector3:
	return global_position + Vector3(0.0, HEAD_HEIGHT, 0.0)


## Vrai si un impact à `hit_position` touche la tête.
func is_head_hit(hit_position: Vector3) -> bool:
	return hit_position.y - global_position.y >= HEAD_LIMIT


## Vitesse latérale actuelle (m/s, valeur absolue).
func current_speed() -> float:
	return absf(_velocity)


## Applique les dégâts d'un impact ; renvoie vrai si la cible est éliminée.
func apply_hit(head: bool) -> bool:
	health -= HEAD_DAMAGE if head else BODY_DAMAGE
	return health <= 0.0


func destroy() -> void:
	if not alive:
		return
	alive = false
	collision_layer = 0
	queue_free()
