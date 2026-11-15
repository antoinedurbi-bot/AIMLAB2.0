extends RefCounted
## Catalogue des exercices : ce que le menu affiche et ce que le gestionnaire de
## partie instancie. Pour ajouter un exercice : écrire un script qui étend
## drill_base.gd, puis l'inscrire ici.
##
## Champs d'une entrée :
##   id, title, tag, description : affichage ;
##   focus    : la compétence travaillée, en une ligne ;
##   map      : scène de la carte à charger ;
##   script   : script de l'exercice ;
##   duration : durée maximale de la session (s) ;
##   params   : variables de l'exercice à surcharger (nom -> valeur).

const MAP_RANGE := "res://scenes/arena.tscn"
const MAP_STRAFE_LANE := "res://scenes/maps/strafe_lane.tscn"
const MAP_ANGLE_HALL := "res://scenes/maps/angle_hall.tscn"
const MAP_KILL_HOUSE := "res://scenes/maps/kill_house.tscn"

const DRILLS := [
	{
		"id": "gridshot",
		"title": "GRIDSHOT",
		"tag": "Visée",
		"focus": "Flicks larges, vitesse d'enchaînement",
		"description": "Trois sphères sur une grille face à toi. Détruis-en une : une autre surgit aussitôt ailleurs. Enchaîne les flicks le plus vite et le plus proprement possible.",
		"map": MAP_RANGE,
		"script": preload("res://scripts/drills/gridshot_drill.gd"),
		"duration": 60.0,
		"params": {},
	},
	{
		"id": "microflick",
		"title": "MICROFLICKS",
		"tag": "Visée",
		"focus": "Petits ajustements sur cibles de la taille d'une tête",
		"description": "Une seule petite cible à la fois, toujours proche de la précédente et à hauteur de tête. Travaille la précision des micro-corrections, celles qui font les tirs à la tête.",
		"map": MAP_RANGE,
		"script": preload("res://scripts/drills/gridshot_drill.gd"),
		"duration": 60.0,
		"params": {
			"grid_columns": 7,
			"grid_rows": 3,
			"cell_spacing": 0.5,
			"grid_distance": 13.0,
			"target_radius": 0.16,
			"simultaneous_targets": 1,
			"miss_penalty": 25,
		},
	},
	{
		"id": "angle_hold",
		"title": "TENUE D'ANGLE",
		"tag": "Réaction",
		"focus": "Temps de réaction, premier tir, placement du viseur",
		"description": "Tu surveilles un passage. Une cible surgit d'un côté à un moment imprévisible : elle s'arrête un instant ou traverse en courant. Abats-la au premier tir, sans jamais tirer dans le vide.",
		"map": MAP_ANGLE_HALL,
		"script": preload("res://scripts/drills/angle_hold_drill.gd"),
		"duration": 60.0,
		"params": {},
	},
	{
		"id": "counter_strafe",
		"title": "STRAFE / CONTRE-STRAFE",
		"tag": "Déplacement",
		"focus": "S'arrêter net avant de tirer",
		"description": "Déplace-toi latéralement à pleine vitesse, arrête-toi d'un appui sur la touche opposée, puis tire. Un tir déclenché en mouvement est dévié : chaque tir est mesuré (vitesse, temps d'arrêt, méthode).",
		"map": MAP_STRAFE_LANE,
		"script": preload("res://scripts/drills/counter_strafe_drill.gd"),
		"duration": 60.0,
		"params": {},
	},
	{
		"id": "jiggle_peek",
		"title": "JIGGLE PEEK",
		"tag": "Déplacement",
		"focus": "Prendre une information sans se faire toucher",
		"description": "À couvert derrière un coin, sors juste assez pour apercevoir l'adversaire puis reviens aussitôt. Reste exposé trop longtemps et il te touche. Aucun tir : seule compte la brièveté de la sortie.",
		"map": MAP_ANGLE_HALL,
		"script": preload("res://scripts/drills/jiggle_peek_drill.gd"),
		"duration": 60.0,
		"params": {},
	},
	{
		"id": "pre_aim",
		"title": "PRÉ-VISÉE",
		"tag": "Placement",
		"focus": "Placement du viseur en nettoyant des angles",
		"description": "Traverse le parcours et abats la cible cachée derrière chaque angle. Les positions changent à chaque session. On mesure l'écart entre ton viseur et la tête à l'instant où la cible devient visible.",
		"map": MAP_KILL_HOUSE,
		"script": preload("res://scripts/drills/pre_aim_drill.gd"),
		"duration": 90.0,
		"params": {},
	},
	{
		"id": "charge_timer",
		"title": "CHRONO DE LA CHARGE",
		"tag": "Sens du jeu",
		"focus": "Compter de tête le temps écoulé depuis la pose",
		"description": "Au bip, la charge est posée. Appuie sur ESPACE à l'instant demandé, sans chronomètre : 10 s, 20 s, puis 20 s et 38 s en abattant des cibles. 38 s est le dernier instant pour lancer un désamorçage de 7 s sur une charge de 45 s.",
		"map": MAP_RANGE,
		"script": preload("res://scripts/drills/charge_timer_drill.gd"),
		"duration": 200.0,
		"params": {},
	},
]


## Entrée du catalogue pour un identifiant, ou la première si l'identifiant est inconnu.
static func find(drill_id: String) -> Dictionary:
	for item: Variant in DRILLS:
		var entry: Dictionary = item
		if entry.get("id", "") == drill_id:
			return entry
	var first: Dictionary = DRILLS[0]
	return first
