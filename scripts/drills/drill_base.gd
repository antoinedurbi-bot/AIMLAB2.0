extends Node3D
## Classe de base d'un exercice.
##
## Le gestionnaire de partie instancie l'exercice choisi, lui fournit le joueur,
## le HUD, la fabrique d'effets et la carte chargée, puis appelle dans l'ordre :
##   setup()    au début du compte à rebours (cibles et décor de l'exercice) ;
##   begin()    au « GO » (le chronomètre et la télémétrie démarrent) ;
##   update()   à chaque image pendant la session ;
##   on_shot()  à chaque tir, on_action() à chaque appui sur Espace ;
##   finalize() à la fin, pour compléter le rapport de la télémétrie avec les
##              statistiques propres à l'exercice, ses cartes KPI et son graphique.
## Les nœuds créés par l'exercice sont ses enfants : ils disparaissent avec lui.

const PlayerController := preload("res://scripts/player.gd")
const Hud := preload("res://ui/hud.gd")
const FxSpawner := preload("res://scripts/fx_spawner.gd")
const AimTarget := preload("res://scripts/target.gd")
const Stats := preload("res://scripts/stats.gd")
const TARGET_SCENE: PackedScene = preload("res://scenes/target.tscn")

## Couche de collision du décor (murs, sol, caisses).
const WORLD_MASK := 1
## Demi-champ de vision utilisé pour décider si un point est « à l'écran » (degrés).
const VIEW_HALF_WIDTH := 48.0
const VIEW_HALF_HEIGHT := 31.0

var drill_id: String = ""
var title: String = ""
## Durée maximale de la session en secondes.
var duration: float = 60.0
## Niveau de difficulté adaptative fourni par le profil (1.0 = référence).
var difficulty: float = 1.0

var player: PlayerController
var hud: Hud
var fx: FxSpawner
var map_root: Node3D

var score: int = 0
var shots: int = 0
var hits: int = 0
## Passe à vrai quand l'exercice se termine avant la fin du chronomètre.
var finished: bool = false
## Secondes écoulées depuis begin(), tenu à jour par le gestionnaire de partie.
var elapsed: float = 0.0
var rng := RandomNumberGenerator.new()

var _next_target_id: int = 0


func _init() -> void:
	rng.randomize()


# ---------------------------------------------------------------------------
# À surcharger
# ---------------------------------------------------------------------------

## Vrai si le joueur peut se déplacer (les tirs en mouvement sont alors imprécis).
func uses_movement() -> bool:
	return false


## Vrai si le clic gauche tire.
func uses_fire() -> bool:
	return true


## Faux pour masquer le chronomètre (exercices où il faut compter de tête).
func shows_clock() -> bool:
	return true


## Nom du repère de la carte où placer le joueur ; vide = position par défaut de la carte.
func spawn_marker() -> String:
	return ""


func setup() -> void:
	pass


func begin() -> void:
	pass


func update(_delta: float) -> void:
	pass


func on_shot(_collider: Object, _hit_position: Vector3, _hit_normal: Vector3, _shot: Dictionary) -> void:
	pass


func on_action() -> void:
	pass


func finalize(_report: Dictionary) -> void:
	pass


# ---------------------------------------------------------------------------
# Utilitaires communs
# ---------------------------------------------------------------------------

## Position d'un repère (Marker3D) de la carte, dans « Markers ».
func marker(marker_name: String) -> Vector3:
	var node := _marker_node(marker_name)
	if node == null:
		return Vector3.ZERO
	return node.global_position


## Orientation d'un repère en degrés (0 = vers -Z, positif = vers la gauche).
func marker_yaw(marker_name: String) -> float:
	var node := _marker_node(marker_name)
	if node == null:
		return 0.0
	return rad_to_deg(node.global_rotation.y)


## Vrai si la carte possède ce repère (sans avertissement s'il manque).
func has_marker(marker_name: String) -> bool:
	return map_root != null and map_root.has_node("Markers/" + marker_name)


func _marker_node(marker_name: String) -> Node3D:
	var node: Node3D = null
	if map_root != null:
		node = map_root.get_node_or_null("Markers/" + marker_name) as Node3D
	if node == null:
		push_warning("KINETIC // AIM : repère « %s » introuvable sur la carte." % marker_name)
	return node


## Crée une cible sphérique enfant de l'exercice.
func spawn_target(at: Vector3, radius: float, enemy_style: bool = false) -> AimTarget:
	var target := TARGET_SCENE.instantiate() as AimTarget
	target.configure(_next_target_id, Vector2i.ZERO, radius)
	target.enemy_style = enemy_style
	_next_target_id += 1
	target.position = at
	add_child(target)
	return target


## Vrai si aucun élément du décor ne coupe le segment `from` → `to`.
func line_of_sight(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return result.is_empty()


## Vrai si le point est dans le champ de vision du joueur et non masqué par le décor.
func visible_to_player(world_position: Vector3) -> bool:
	var offset: Vector2 = Telemetry.angular_offset_to(world_position)
	if absf(offset.x) > VIEW_HALF_WIDTH or absf(offset.y) > VIEW_HALF_HEIGHT:
		return false
	return line_of_sight(player.eye_position(), world_position)


## Cible vivante la plus proche du viseur (en angle) parmi `candidates`, ou null.
func nearest_target(candidates: Array[AimTarget]) -> AimTarget:
	var best: AimTarget = null
	var best_angle := INF
	for candidate in candidates:
		if not is_instance_valid(candidate) or not candidate.alive:
			continue
		var offset: Vector2 = Telemetry.angular_offset_to(candidate.global_position)
		if offset.length() < best_angle:
			best_angle = offset.length()
			best = candidate
	return best


## Enregistre un tir dans la télémétrie par rapport à `target` (null = aucune cible).
func record_shot(hit: bool, target: AimTarget, shot: Dictionary, extra: Dictionary = {}) -> void:
	var speed: float = shot.get("speed", 0.0)
	var details := extra.duplicate()
	details["deviation"] = shot.get("deviation", Vector2.ZERO)
	if target != null and is_instance_valid(target):
		Telemetry.record_shot(hit, target.global_position, target.radius, target.target_id, speed, details)
	else:
		Telemetry.record_shot(hit, Vector3.ZERO, 0.0, -1, speed, details)


## Ajoute une carte KPI au rapport (affichée dans le tableau de fin de session).
static func add_kpi(report: Dictionary, label: String, value: String, hint: String = "") -> void:
	var kpis: Array = report.get("kpis", [])
	kpis.append({"label": label, "value": value, "hint": hint})
	report["kpis"] = kpis


## Définit le graphique « une barre par répétition » du rapport.
## `threshold` : NAN pour aucun seuil. `signed` : valeurs centrées sur zéro
## (le seuil devient alors une bande ±threshold).
static func set_chart(report: Dictionary, chart_title: String, values: PackedFloat32Array, unit: String, threshold: float = NAN, lower_is_better: bool = true, signed: bool = false) -> void:
	report["chart"] = {
		"title": chart_title,
		"values": values,
		"unit": unit,
		"threshold": threshold,
		"lower_is_better": lower_is_better,
		"signed": signed,
	}


## Indique quels panneaux d'analyse afficher : "flicks", "heatmap", "chart".
static func set_panels(report: Dictionary, panels: Array) -> void:
	report["panels"] = panels


## Cartes KPI communes aux exercices de tir : précision et tirs en mouvement.
func add_shooting_kpis(report: Dictionary) -> void:
	var shot_count: int = report.get("shots", 0)
	var hit_count: int = report.get("hits", 0)
	var accuracy: float = report.get("accuracy", 0.0)
	add_kpi(report, "PRÉCISION", "%.1f %%" % accuracy if shot_count > 0 else "—",
			"%d touchés / %d tirs" % [hit_count, shot_count])
