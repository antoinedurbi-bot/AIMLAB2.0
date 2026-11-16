extends Node
## Intelligence d'un bot : machine à états posée sur une cible humanoïde, avec
## un modèle de joueur dont chaque facette dépend du rang (voir bot_ranks.gd).
##
## États
##   MOVING    — suit un chemin (A*) vers son objectif, ou vers le joueur s'il le traque.
##   ENGAGING  — a le joueur en vue depuis plus que son temps de réaction : rafale,
##               puis strafe ou mise à couvert, puis nouvelle sortie.
##   COVERING  — rejoint une position hors de vue, attend, puis ressort.
##   DEFUSING  — immobile sur son objectif (désamorçage) ; se défend s'il est attaqué.
##
## Perception
##   Vue    : ligne de vue ET champ de vision (le bot a une direction de regard,
##            qu'il tourne à vitesse finie). De dos, il ne te voit pas.
##   Ouïe   : te repère si tu cours à portée.
##   Dégâts : se retourne vers l'origine du tir.
##   Équipe : l'escouade (bot_squad.gd) transmet ta position entre bots coordonnés
##            et leur donne des rôles : entrée, contournement, soutien, couverture.
##
## Visée
##   Le bot vise un point (tête ou torse) avec un écart angulaire qui part de
##   `aim_error` à ta découverte et retombe vers `steady_error` (son « flick »),
##   augmenté de son retard sur ta vitesse latérale et du recul non compensé.
##   Chaque balle est un vrai rayon : un mur, une caisse ou un pas de côté
##   t'en protègent réellement.

signal shot_fired(hit: bool, head: bool, origin: Vector3, end_point: Vector3)

enum State { MOVING, ENGAGING, COVERING, DEFUSING, GUARDING }

const Humanoid := preload("res://scripts/humanoid_target.gd")
const PlayerController := preload("res://scripts/player.gd")
const NavGrid := preload("res://scripts/ai/nav_grid.gd")

## Décor + fumigènes : ce qui bloque la vue d'un bot.
const VISION_MASK := 9
## Décor + joueur : ce que les balles d'un bot peuvent toucher.
const SHOT_MASK := 5
const WAYPOINT_REACHED := 0.6
const ARRIVAL_DISTANCE := 1.2
const LOSE_SIGHT_SECONDS := 1.4
const FIRE_INTERVAL := 0.1
const RECOIL_PER_SHOT_DEG := 0.55
const RUN_AND_GUN_ERROR_DEG := 4.0
## Hauteur de la tête et du torse du joueur par rapport à ses yeux (m).
const HEAD_OFFSET := -0.05
const CHEST_OFFSET := -0.45
## Un impact au-dessus de (yeux - cette marge) compte comme tête.
const HEAD_ZONE := 0.18
const MEMORY_SECONDS := 6.0

var state: int = State.MOVING
var hunting: bool = false
var objective: Vector3 = Vector3.ZERO
var hold_at_objective: bool = false
var rank_profile: Dictionary = {}
## Vrai si ce bot suit les ordres de l'escouade (tiré selon la coordination de son rang).
var coordinated: bool = false

var _body: Humanoid
var _player: PlayerController
var _nav: NavGrid
var _rng := RandomNumberGenerator.new()

var _reaction: float = 0.45
var _aim_error: float = 3.6
var _settle: float = 0.56
var _steady_error: float = 0.85
var _tracking_lag: float = 0.18
var _recoil_control: float = 0.45
var _head_aim: float = 0.32
var _fov: float = 65.0
var _turn_speed: float = 290.0
var _hearing: float = 15.0
var _speed: float = 4.7
var _burst: int = 5
var _run_and_gun: float = 0.18
var _cover: float = 0.3
var _teamwork: bool = true

var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _repath_timer: float = 0.0
var _facing_yaw: float = 0.0
var _desired_yaw: float = 0.0
var _seen_seconds: float = 0.0
var _unseen_seconds: float = 99.0
var _visible: bool = false
var _last_known: Vector3 = Vector3.ZERO
var _known_usec: int = 0
var _burst_left: int = 0
var _burst_shot: int = 0
var _shot_timer: float = 0.0
var _pause_timer: float = 0.0
var _strafe_side: float = 1.0
var _aim_head: bool = false
var _moving_fire: bool = false
var _cover_wait: float = 0.0
var _fight_position: Vector3 = Vector3.ZERO
var _moved: bool = false
var _blind_seconds: float = 0.0
## Point de passage imposé par l'escouade (contournement) ; Vector3.INF = aucun.
var _via: Vector3 = Vector3.INF
var _guard_post: Vector3 = Vector3.INF


func setup(body: Humanoid, player: PlayerController, nav: NavGrid, profile: Dictionary) -> void:
	_body = body
	_player = player
	_nav = nav
	rank_profile = profile
	_rng.randomize()
	_reaction = profile.get("reaction", 0.45)
	_aim_error = profile.get("aim_error", 3.6)
	_settle = profile.get("settle", 0.56)
	_steady_error = profile.get("steady_error", 0.85)
	_tracking_lag = profile.get("tracking_lag", 0.18)
	_recoil_control = profile.get("recoil_control", 0.45)
	_head_aim = profile.get("head_aim", 0.32)
	_fov = profile.get("fov", 65.0)
	_turn_speed = profile.get("turn_speed", 290.0)
	_hearing = profile.get("hearing", 15.0)
	_speed = profile.get("speed", 4.7)
	_burst = profile.get("burst", 5)
	_run_and_gun = profile.get("run_and_gun", 0.18)
	_cover = profile.get("cover", 0.3)
	_teamwork = profile.get("teamwork", true)
	var coordination: float = profile.get("coordination", 0.5)
	coordinated = _rng.randf() < coordination
	# Chaque bot a son propre temps de réaction, à ±12 % de celui du rang.
	_reaction *= _rng.randf_range(0.88, 1.12)
	_body.moving_enabled = false


## Envoie le bot vers une position ; `hold` : il y reste à l'arrivée.
func go_to(world_position: Vector3, hold: bool) -> void:
	hunting = false
	hold_at_objective = hold
	objective = world_position
	_guard_post = Vector3.INF
	if state == State.GUARDING or state == State.DEFUSING:
		state = State.MOVING
	_request_path(objective)


## Se poste à `post` et surveille la dernière position connue du joueur.
func guard(post: Vector3) -> void:
	hunting = false
	hold_at_objective = false
	objective = post
	_guard_post = post
	state = State.MOVING
	_request_path(post)


# --- Interface de l'escouade ---

func body_position() -> Vector3:
	return _body.global_position if _body != null else Vector3.ZERO


func knowledge_usec() -> int:
	return _known_usec


func last_known_position() -> Vector3:
	return _last_known


func remembers_player() -> bool:
	return _remembers_player()


## Vrai si le bot combat (rafale, strafe ou mise à couvert).
func is_fighting() -> bool:
	return state == State.ENGAGING or state == State.COVERING


## Reçoit une information d'un coéquipier (ignorée si elle est plus ancienne que la sienne).
func inform(world_position: Vector3, usec: int) -> void:
	if usec > _known_usec:
		_last_known = world_position
		_known_usec = usec


## Impose un point de passage pour arriver par un autre côté. Renvoie vrai si l'ordre change.
func set_via(point: Vector3) -> bool:
	if point == Vector3.INF or point.distance_to(_via) < 1.0:
		return false
	_via = point
	if state == State.MOVING:
		_request_path(_last_known if _remembers_player() else objective)
	return true


func clear_via() -> void:
	_via = Vector3.INF


## Le bot traque le joueur ; sans information, il patrouille vers `patrol_point`.
func hunt(patrol_point: Vector3) -> void:
	hunting = true
	hold_at_objective = false
	objective = patrol_point
	if state == State.MOVING:
		_request_path(_last_known if _remembers_player() else objective)


## À appeler quand le bot est touché : il se tourne vers l'origine du tir.
func notify_damage(from_position: Vector3) -> void:
	_learn_position(from_position)
	_desired_yaw = _yaw_to(from_position)
	if state == State.MOVING or state == State.COVERING:
		_seen_seconds = maxf(_seen_seconds, _reaction * 0.5)


## Aveugle le bot si l'explosion d'un flash est dans son champ de vision et non masquée.
func try_blind(flash_position: Vector3, seconds: float) -> bool:
	var angle := absf(wrapf(_yaw_to(flash_position) - _facing_yaw, -180.0, 180.0))
	if angle > _fov or not _line_of_sight(_body.head_position(), flash_position):
		return false
	_blind_seconds = seconds
	_seen_seconds = 0.0
	return true


func is_defusing() -> bool:
	return state == State.DEFUSING


func is_engaging() -> bool:
	return state == State.ENGAGING or state == State.COVERING


func _process(delta: float) -> void:
	if _body == null or not _body.alive or _player == null:
		return
	_moved = false
	_perceive(delta)
	match state:
		State.MOVING:
			_update_moving(delta)
		State.ENGAGING:
			_update_engaging(delta)
		State.COVERING:
			_update_covering(delta)
		State.DEFUSING:
			# Il lâche le désamorçage s'il a le joueur en vue assez longtemps.
			if _seen_seconds >= _reaction * 1.3:
				_start_engaging()
		State.GUARDING:
			# En couverture : immobile, regard vers la menace, prêt à tirer.
			if _remembers_player():
				_desired_yaw = _yaw_to(_last_known)
			if _seen_seconds >= _reaction:
				_start_engaging()
	_facing_yaw = _rotate_towards(_facing_yaw, _desired_yaw, _turn_speed * delta)


# ---------------------------------------------------------------------------
# Perception
# ---------------------------------------------------------------------------

func _perceive(delta: float) -> void:
	var eye := _player.eye_position()
	var head := _body.head_position()
	var distance := head.distance_to(eye)
	var angle := absf(wrapf(_yaw_to(eye) - _facing_yaw, -180.0, 180.0))
	_blind_seconds = maxf(_blind_seconds - delta, 0.0)
	_visible = _blind_seconds <= 0.0 and (angle <= _fov or distance < 3.0) and _line_of_sight(head, eye)
	if _visible:
		_seen_seconds += delta
		_unseen_seconds = 0.0
		_learn_position(_player.global_position)
		_desired_yaw = _yaw_to(eye)
	else:
		_unseen_seconds += delta
		_seen_seconds = maxf(_seen_seconds - delta * 2.0, 0.0)
		# Ouïe : un joueur qui court à portée trahit sa position.
		var feet_distance := _body.global_position.distance_to(_player.global_position)
		if feet_distance <= _hearing and _player.horizontal_speed() > PlayerController.LOUD_SPEED:
			_learn_position(_player.global_position)
			_desired_yaw = _yaw_to(_player.global_position)

	if state == State.MOVING and _seen_seconds >= _reaction:
		_start_engaging()
	elif state == State.ENGAGING and _unseen_seconds >= LOSE_SIGHT_SECONDS:
		state = State.MOVING
		_request_path(_last_known if hunting else objective)


func _learn_position(world_position: Vector3) -> void:
	_last_known = world_position
	_known_usec = Time.get_ticks_usec()


func _remembers_player() -> bool:
	return _known_usec > 0 and float(Time.get_ticks_usec() - _known_usec) / 1000000.0 <= MEMORY_SECONDS


func _line_of_sight(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, VISION_MASK)
	return _body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Yaw (°) de la direction allant du bot vers `world_position`.
func _yaw_to(world_position: Vector3) -> float:
	var offset := Vector3(world_position.x - _body.global_position.x, 0.0, world_position.z - _body.global_position.z)
	return rad_to_deg(atan2(-offset.x, -offset.z))


func _rotate_towards(current: float, target: float, step: float) -> float:
	var difference := wrapf(target - current, -180.0, 180.0)
	return current + clampf(difference, -step, step)


# ---------------------------------------------------------------------------
# Déplacement
# ---------------------------------------------------------------------------

func _update_moving(delta: float) -> void:
	_repath_timer -= delta
	if hunting and _remembers_player() and _repath_timer <= 0.0:
		_request_path(_last_known)
	if _path_index >= _path.size():
		if hold_at_objective and _flat_distance(_body.global_position, objective) <= ARRIVAL_DISTANCE + 0.6:
			state = State.DEFUSING
		elif _guard_post != Vector3.INF and _flat_distance(_body.global_position, _guard_post) <= 2.0:
			state = State.GUARDING
		elif _repath_timer <= 0.0:
			_request_path(objective)
		return
	var target := _path[_path_index]
	var limit := ARRIVAL_DISTANCE if hold_at_objective and _path_index == _path.size() - 1 else WAYPOINT_REACHED
	if _flat_distance(_body.global_position, target) <= limit:
		_path_index += 1
		return
	# En approche d'une position connue du joueur, le bot regarde vers elle (pré-visée) ;
	# sinon il regarde où il va.
	if _remembers_player() and _flat_distance(_body.global_position, _last_known) < 20.0:
		_desired_yaw = _yaw_to(_last_known)
	else:
		_desired_yaw = _yaw_to(target)
	_step_towards(target, _speed * delta)


func _request_path(destination: Vector3) -> void:
	_repath_timer = 1.2
	# Contournement : passer par le point imposé s'il n'est pas déjà atteint.
	if _via != Vector3.INF and _flat_distance(_body.global_position, _via) > 4.0 and _guard_post == Vector3.INF and not hold_at_objective:
		_path = _nav.find_path(_body.global_position, _via)
		_path.append_array(_nav.find_path(_via, destination))
	else:
		if _via != Vector3.INF:
			_via = Vector3.INF
		_path = _nav.find_path(_body.global_position, destination)
	_path_index = 1 if _path.size() > 1 else 0


func _step_towards(target: Vector3, distance: float) -> void:
	var offset := Vector3(target.x - _body.global_position.x, 0.0, target.z - _body.global_position.z)
	var length := offset.length()
	if length < 0.001:
		return
	_body.global_position += offset / length * minf(distance, length)
	_moved = true


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------

func _start_engaging() -> void:
	state = State.ENGAGING
	_fight_position = _body.global_position
	_begin_burst()


func _begin_burst() -> void:
	_burst_left = _burst + _rng.randi_range(-1, 1)
	_burst_shot = 0
	_shot_timer = 0.0
	_aim_head = _rng.randf() < _head_aim
	_moving_fire = _rng.randf() < _run_and_gun


func _update_engaging(delta: float) -> void:
	if _burst_left > 0:
		# Les joueurs peu expérimentés tirent en marchant ; les autres s'arrêtent.
		if _moving_fire:
			_strafe(delta, 0.7)
		_shot_timer -= delta
		if _shot_timer <= 0.0 and _visible:
			_shot_timer = FIRE_INTERVAL
			_fire()
			_burst_left -= 1
			_burst_shot += 1
			if _burst_left <= 0:
				_after_burst()
		elif not _visible and _unseen_seconds > 0.35:
			_after_burst()
		return
	# Entre deux rafales : strafe pour ne pas rester une cible fixe.
	_pause_timer -= delta
	_strafe(delta, 0.85)
	if _pause_timer <= 0.0:
		_begin_burst()


func _after_burst() -> void:
	_burst_left = 0
	_strafe_side = 1.0 if _rng.randf() < 0.5 else -1.0
	_pause_timer = _rng.randf_range(0.25, 0.55)
	# Les bons joueurs ne restent pas à découvert : ils se cachent puis ressortent.
	var hurt := _body.health < 60.0
	if _rng.randf() < _cover or (hurt and _cover > 0.1):
		var spot := _find_cover()
		if spot != Vector3.INF:
			state = State.COVERING
			_cover_wait = _rng.randf_range(0.5, 1.4) + (0.8 if hurt else 0.0)
			_path = _nav.find_path(_body.global_position, spot)
			_path_index = 1 if _path.size() > 1 else 0


func _strafe(delta: float, speed_factor: float) -> void:
	var to_player: Vector3 = _player.global_position - _body.global_position
	var side: Vector3 = Vector3(-to_player.z, 0.0, to_player.x).normalized() * _strafe_side
	var next: Vector3 = _body.global_position + side * _speed * speed_factor * delta
	if _nav.is_walkable(next):
		_body.global_position = next
		_moved = true
	else:
		_strafe_side = -_strafe_side


## Cherche à proximité une position d'où le joueur ne voit pas la tête du bot.
## Renvoie Vector3.INF s'il n'y en a pas.
func _find_cover() -> Vector3:
	var eye := _player.eye_position()
	var best := Vector3.INF
	var best_distance := INF
	for ring in range(1, 4):
		for step in 8:
			var angle := TAU * float(step) / 8.0 + float(ring) * 0.4
			var candidate: Vector3 = _body.global_position + Vector3(cos(angle), 0.0, sin(angle)) * float(ring) * 1.8
			if not _nav.is_walkable(candidate):
				continue
			var head: Vector3 = candidate + Vector3(0.0, Humanoid.HEAD_HEIGHT, 0.0)
			if _line_of_sight(eye, head):
				continue
			var distance: float = candidate.distance_to(_body.global_position)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best


func _update_covering(delta: float) -> void:
	if _path_index < _path.size():
		var target := _path[_path_index]
		if _flat_distance(_body.global_position, target) <= WAYPOINT_REACHED:
			_path_index += 1
		else:
			_step_towards(target, _speed * delta)
		return
	_cover_wait -= delta
	_desired_yaw = _yaw_to(_last_known)
	if _cover_wait > 0.0:
		return
	# Ressortie : retour vers la position de tir, visée déjà posée sur l'angle.
	state = State.MOVING
	_seen_seconds = _reaction * 0.6
	_request_path(_fight_position if not hunting else _last_known)


## Tire une balle : un rayon partant de la tête du bot vers son point de visée,
## dévié de son écart de visée du moment.
func _fire() -> void:
	var origin := _body.head_position()
	var eye := _player.eye_position()
	var aim_point: Vector3 = eye + Vector3(0.0, HEAD_OFFSET if _aim_head else CHEST_OFFSET, 0.0)
	var direction: Vector3 = (aim_point - origin).normalized()
	var distance: float = origin.distance_to(aim_point)

	# Écart de visée (écart-type, en degrés).
	var sigma := _steady_error + _aim_error * exp(-_seen_seconds / maxf(_settle, 0.05))
	var lateral_speed := absf(_player.lateral_velocity())
	sigma += rad_to_deg(lateral_speed / maxf(distance, 1.0)) * _tracking_lag
	sigma += RECOIL_PER_SHOT_DEG * float(_burst_shot) * (1.0 - _recoil_control)
	if _moved:
		sigma += RUN_AND_GUN_ERROR_DEG
	var error := Vector2(_rng.randfn(0.0, sigma), _rng.randfn(0.0, sigma))
	# Le recul non compensé fait monter les balles.
	error.y += RECOIL_PER_SHOT_DEG * float(_burst_shot) * (1.0 - _recoil_control) * 0.5

	var right: Vector3 = direction.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(direction)
	var shot_direction: Vector3 = (direction + right * tan(deg_to_rad(error.x)) + up * tan(deg_to_rad(error.y))).normalized()
	var end_point: Vector3 = origin + shot_direction * 200.0
	var query := PhysicsRayQueryParameters3D.create(origin, end_point, SHOT_MASK)
	var result := _body.get_world_3d().direct_space_state.intersect_ray(query)
	var hit := false
	var head := false
	if not result.is_empty():
		end_point = result["position"]
		hit = result["collider"] == _player
		head = hit and end_point.y >= eye.y - HEAD_ZONE
	shot_fired.emit(hit, head, origin, end_point)
