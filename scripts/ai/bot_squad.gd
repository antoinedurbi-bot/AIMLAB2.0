extends Node
## Coordinateur d'escouade : fait agir les bots ensemble au lieu de côte à côte.
## Deux fois par seconde, il lit ce que chaque bot sait et distribue des ordres ;
## un bot n'obéit que s'il est « coordonné » (tirage selon son rang).
##
##   Information — la position du joueur perçue par un bot est transmise aux autres.
##   Rôles en traque — ENTRÉE va droit sur le joueur ; CONTOURNEMENT passe par le
##     point de passage qui l'amène par un autre côté ; SOUTIEN suit l'entrée.
##   Soutien — quand un bot engage, ses coéquipiers libres convergent pour un
##     tir croisé au lieu de continuer leur patrouille.
##   Échange — quand un bot meurt, les autres apprennent où était le joueur.
##   Objectif — un seul bot désamorce ; les autres se postent autour et
##     surveillent l'endroit d'où vient le joueur. Si le désamorceur tombe, le
##     plus proche prend sa place.

enum Role { ENTRY, FLANK, SUPPORT }
enum Mode { HUNT, OBJECTIVE }

const BotBrain := preload("res://scripts/ai/bot_brain.gd")
const NavGrid := preload("res://scripts/ai/nav_grid.gd")

const ORDER_INTERVAL := 0.5
## Distance à laquelle les bots de couverture se postent autour de l'objectif (m).
const COVER_DISTANCE := 6.0

var mode: int = Mode.HUNT
var objective: Vector3 = Vector3.ZERO
## Points de passage de la carte, utilisés pour les contournements et les patrouilles.
var waypoints: Array[Vector3] = []

## Statistiques de coordination, lues par l'exercice.
var flanks_ordered: int = 0
var assists_ordered: int = 0
var trades_informed: int = 0
var defuser_swaps: int = 0

var _nav: NavGrid
var _members: Array[BotBrain] = []
var _roles: Dictionary = {}
var _defuser: BotBrain
var _timer: float = 0.0
var _next_role: int = 0
var _rng := RandomNumberGenerator.new()


func start(nav: NavGrid) -> void:
	_nav = nav
	_rng.randomize()


## Passe en mode objectif : un désamorceur, les autres en couverture.
func set_objective(world_position: Vector3) -> void:
	mode = Mode.OBJECTIVE
	objective = world_position


func add_member(brain: BotBrain) -> void:
	_members.append(brain)
	_roles[brain] = _next_role % 3
	_next_role += 1
	if mode == Mode.OBJECTIVE:
		_assign_objective_role(brain)


## À appeler quand un bot est éliminé : `killer_position` est transmis aux survivants.
func remove_member(brain: BotBrain, killer_position: Vector3) -> void:
	_members.erase(brain)
	_roles.erase(brain)
	for member in _members:
		if member.coordinated:
			member.inform(killer_position, Time.get_ticks_usec())
			trades_informed += 1
	if brain == _defuser:
		_defuser = null
		_promote_defuser()


## Nombre de bots en train de combattre le joueur.
func engaging_count() -> int:
	var total := 0
	for member in _members:
		if member.is_fighting():
			total += 1
	return total


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or _members.is_empty():
		return
	_timer = ORDER_INTERVAL
	_share_knowledge()
	if mode == Mode.HUNT:
		_order_hunt()
	else:
		if _defuser == null:
			_promote_defuser()


# ---------------------------------------------------------------------------

## Diffuse l'information la plus récente à tous les bots coordonnés.
func _share_knowledge() -> void:
	var freshest: BotBrain = null
	for member in _members:
		if member.coordinated and (freshest == null or member.knowledge_usec() > freshest.knowledge_usec()):
			freshest = member
	if freshest == null or freshest.knowledge_usec() <= 0:
		return
	for member in _members:
		if member != freshest and member.coordinated:
			member.inform(freshest.last_known_position(), freshest.knowledge_usec())


func _order_hunt() -> void:
	var fighter: BotBrain = null
	var entry: BotBrain = null
	for member in _members:
		if member.is_fighting() and fighter == null:
			fighter = member
		if int(_roles.get(member, Role.ENTRY)) == Role.ENTRY and entry == null:
			entry = member
	for member in _members:
		if not member.coordinated or member.is_fighting():
			continue
		var role: int = _roles.get(member, Role.ENTRY)
		if fighter != null and member.remembers_player():
			# Un coéquipier combat : venir croiser le tir par un autre angle.
			if member.set_via(_flank_point(member.last_known_position(), fighter.body_position())):
				assists_ordered += 1
		elif role == Role.FLANK and member.remembers_player() and entry != null:
			if member.set_via(_flank_point(member.last_known_position(), entry.body_position())):
				flanks_ordered += 1
		elif role != Role.FLANK:
			member.clear_via()


## Point de passage qui amène sur `target` par le côté opposé à `ally_position`.
func _flank_point(target: Vector3, ally_position: Vector3) -> Vector3:
	var ally_direction := Vector2(ally_position.x - target.x, ally_position.z - target.z).normalized()
	var best := Vector3.INF
	var best_score := -INF
	for point in waypoints:
		var offset := Vector2(point.x - target.x, point.z - target.z)
		var distance := offset.length()
		if distance < 8.0 or distance > 70.0:
			continue
		# Plus l'angle avec la direction de l'allié est grand, meilleur est le contournement.
		var side_score := -offset.normalized().dot(ally_direction) - distance / 140.0
		if side_score > best_score:
			best_score = side_score
			best = point
	return best


func _assign_objective_role(brain: BotBrain) -> void:
	if _defuser == null:
		_defuser = brain
		brain.go_to(objective, true)
		return
	if not brain.coordinated:
		# Sans coordination, chacun fonce sur l'objectif.
		brain.go_to(objective, true)
		return
	# Couverture : un poste à quelques mètres de l'objectif, regard vers la menace.
	var angle := _rng.randf() * TAU
	var post := objective
	for attempt in 12:
		var candidate := objective + Vector3(cos(angle), 0.0, sin(angle)) * COVER_DISTANCE
		if _nav.is_walkable(candidate):
			post = candidate
			break
		angle += TAU / 12.0
	brain.guard(post)


## Le bot coordonné le plus proche de l'objectif devient désamorceur.
func _promote_defuser() -> void:
	var best: BotBrain = null
	var best_distance := INF
	for member in _members:
		var distance := member.body_position().distance_to(objective)
		if distance < best_distance:
			best_distance = distance
			best = member
	if best != null:
		_defuser = best
		best.go_to(objective, true)
		defuser_swaps += 1
