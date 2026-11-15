extends Node
## Intelligence d'un bot : machine à états posée sur une cible humanoïde.
##
##   MOVING     — suit un chemin (A*) vers son objectif : une position fixe
##                (la charge, un point de patrouille) ou le joueur s'il le traque.
##   ENGAGING   — voit le joueur depuis assez longtemps (temps de réaction) :
##                s'arrête, tire une rafale, strafe, recommence.
##   DEFUSING   — arrivé sur son objectif, il y reste immobile (désamorçage).
##
## Perception : ligne de vue de la tête du bot vers les yeux du joueur, et ouïe
## (un joueur qui court à portée révèle sa position). Quand le bot perd le joueur
## de vue, il se rend à sa dernière position connue.
##
## Le niveau `skill` (0 = recrue, 1 = élite) règle temps de réaction, précision,
## vitesse et durée des pauses. Le bot ne « triche » pas : il ne connaît la
## position du joueur que s'il l'a vu ou entendu.

signal shot_fired(hit: bool, origin: Vector3)

enum State { MOVING, ENGAGING, DEFUSING }

const Humanoid := preload("res://scripts/humanoid_target.gd")
const PlayerController := preload("res://scripts/player.gd")
const NavGrid := preload("res://scripts/ai/nav_grid.gd")

const WORLD_MASK := 1
const HEARING_RANGE := 18.0
const WAYPOINT_REACHED := 0.6
const ARRIVAL_DISTANCE := 1.2
## Délai sans voir le joueur avant d'abandonner le combat (s).
const LOSE_SIGHT_SECONDS := 1.2

var state: int = State.MOVING
## Vrai : le bot cherche le joueur. Faux : il se rend à `objective`.
var hunting: bool = false
var objective: Vector3 = Vector3.ZERO
## Vrai : arrivé sur l'objectif, le bot y reste (désamorçage).
var hold_at_objective: bool = false

var reaction_seconds: float = 0.45
var accuracy: float = 0.5
var move_speed: float = 4.4
var burst_size: int = 4
var fire_interval: float = 0.12
var pause_seconds: float = 0.5

var _body: Humanoid
var _player: PlayerController
var _nav: NavGrid
var _rng := RandomNumberGenerator.new()
var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _repath_timer: float = 0.0
var _seen_seconds: float = 0.0
var _unseen_seconds: float = 0.0
var _last_known: Vector3 = Vector3.ZERO
var _knows_player: bool = false
var _burst_left: int = 0
var _shot_timer: float = 0.0
var _strafe_timer: float = 0.0
var _strafe_side: float = 1.0
var _moved_this_frame: bool = false


## `skill` : 0 (recrue) à 1 (élite).
func setup(body: Humanoid, player: PlayerController, nav: NavGrid, skill: float) -> void:
	_body = body
	_player = player
	_nav = nav
	_rng.randomize()
	var level := clampf(skill, 0.0, 1.0)
	reaction_seconds = lerpf(0.7, 0.22, level)
	accuracy = lerpf(0.3, 0.8, level)
	move_speed = lerpf(3.8, 5.4, level)
	burst_size = roundi(lerpf(3.0, 6.0, level))
	pause_seconds = lerpf(0.75, 0.3, level)
	_body.moving_enabled = false


## Envoie le bot vers une position ; `hold` : il y reste à l'arrivée.
func go_to(world_position: Vector3, hold: bool) -> void:
	hunting = false
	hold_at_objective = hold
	objective = world_position
	_request_path(objective)


## Le bot traque le joueur : il va vers sa dernière position connue, ou patrouille.
func hunt(patrol_point: Vector3) -> void:
	hunting = true
	hold_at_objective = false
	objective = patrol_point
	_request_path(objective)


func is_defusing() -> bool:
	return state == State.DEFUSING


func is_engaging() -> bool:
	return state == State.ENGAGING


func _process(delta: float) -> void:
	if _body == null or not _body.alive or _player == null:
		return
	_moved_this_frame = false
	_perceive(delta)
	match state:
		State.MOVING:
			_update_moving(delta)
		State.ENGAGING:
			_update_engaging(delta)
		State.DEFUSING:
			# Un bot qui désamorce se défend s'il voit le joueur assez longtemps.
			if _seen_seconds >= reaction_seconds * 1.5:
				state = State.ENGAGING
				_burst_left = burst_size


# ---------------------------------------------------------------------------
# Perception
# ---------------------------------------------------------------------------

func _perceive(delta: float) -> void:
	var eye := _player.eye_position()
	if _line_of_sight(_body.head_position(), eye):
		_seen_seconds += delta
		_unseen_seconds = 0.0
		_last_known = _player.global_position
		_knows_player = true
	else:
		_unseen_seconds += delta
		_seen_seconds = maxf(_seen_seconds - delta * 2.0, 0.0)
		# Ouïe : un joueur qui court à portée trahit sa position.
		var distance := _body.global_position.distance_to(_player.global_position)
		if distance <= HEARING_RANGE and _player.horizontal_speed() > PlayerController.LOUD_SPEED:
			_last_known = _player.global_position
			_knows_player = true

	if state != State.ENGAGING and _seen_seconds >= reaction_seconds:
		state = State.ENGAGING
		_burst_left = burst_size
		_shot_timer = 0.0
	elif state == State.ENGAGING and _unseen_seconds >= LOSE_SIGHT_SECONDS:
		state = State.MOVING
		_request_path(_last_known if hunting else objective)


func _line_of_sight(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	return _body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# ---------------------------------------------------------------------------
# Déplacement
# ---------------------------------------------------------------------------

func _update_moving(delta: float) -> void:
	_repath_timer -= delta
	if hunting and _knows_player and _repath_timer <= 0.0:
		_request_path(_last_known)
	if _path_index >= _path.size():
		if hold_at_objective and _flat_distance(_body.global_position, objective) <= ARRIVAL_DISTANCE + 0.6:
			state = State.DEFUSING
		elif hunting and _repath_timer <= 0.0:
			# Rien trouvé à la dernière position connue : retour en patrouille.
			_knows_player = false
			_request_path(objective)
		return
	var target := _path[_path_index]
	var limit := ARRIVAL_DISTANCE if hold_at_objective and _path_index == _path.size() - 1 else WAYPOINT_REACHED
	if _flat_distance(_body.global_position, target) <= limit:
		_path_index += 1
		return
	_step_towards(target, move_speed * delta)


func _request_path(destination: Vector3) -> void:
	_repath_timer = 1.5
	_path = _nav.find_path(_body.global_position, destination)
	_path_index = 1 if _path.size() > 1 else 0


func _step_towards(target: Vector3, distance: float) -> void:
	var offset := Vector3(target.x - _body.global_position.x, 0.0, target.z - _body.global_position.z)
	var length := offset.length()
	if length < 0.001:
		return
	_body.global_position += offset / length * minf(distance, length)
	_moved_this_frame = true


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------

func _update_engaging(delta: float) -> void:
	if _burst_left > 0:
		# Rafale : le bot est à l'arrêt, c'est la fenêtre pour le punir.
		_shot_timer -= delta
		if _shot_timer <= 0.0 and _unseen_seconds <= 0.0:
			_shot_timer = fire_interval
			_burst_left -= 1
			_fire()
			if _burst_left == 0:
				_strafe_timer = pause_seconds
				_strafe_side = 1.0 if _rng.randf() < 0.5 else -1.0
		return
	# Entre deux rafales : strafe perpendiculaire à la ligne de tir.
	_strafe_timer -= delta
	var to_player: Vector3 = _player.global_position - _body.global_position
	var side := Vector3(-to_player.z, 0.0, to_player.x).normalized() * _strafe_side
	var next := _body.global_position + side * move_speed * 0.8 * delta
	if _nav.is_walkable(next):
		_body.global_position = next
		_moved_this_frame = true
	else:
		_strafe_side = -_strafe_side
	if _strafe_timer <= 0.0:
		_burst_left = burst_size
		_shot_timer = 0.08


## Tire une balle : la probabilité de toucher baisse avec la distance et quand
## le joueur se déplace vite.
func _fire() -> void:
	var distance := _body.global_position.distance_to(_player.global_position)
	var chance := accuracy * clampf(1.15 - distance / 60.0, 0.35, 1.0)
	if _player.horizontal_speed() > PlayerController.LOUD_SPEED:
		chance *= 0.6
	if _player.is_crouching():
		chance *= 0.85
	shot_fired.emit(_rng.randf() < clampf(chance, 0.05, 0.95), _body.head_position())
