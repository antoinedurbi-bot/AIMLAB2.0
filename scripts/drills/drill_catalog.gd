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

## Grandes cartes originales (deux ou trois sites), au choix dans le menu.
const TACTICAL_MAPS := [
	{"name": "Citadelle", "path": "res://scenes/maps/tactical_citadelle.tscn"},
	{"name": "Triade (3 sites)", "path": "res://scenes/maps/tactical_triade.tscn"},
	{"name": "Faubourg", "path": "res://scenes/maps/tactical_faubourg.tscn"},
	{"name": "Entrepôt", "path": "res://scenes/maps/tactical_entrepot.tscn"},
	{"name": "Canal", "path": "res://scenes/maps/tactical_canal.tscn"},
	{"name": "Rotonde", "path": "res://scenes/maps/tactical_rotonde.tscn"},
	{"name": "Dédale", "path": "res://scenes/maps/tactical_dedale.tscn"},
]

const DRILLS := [
	{
		"id": "benchmark",
		"title": "DIAGNOSTIC",
		"tag": "2 min",
		"focus": "Évaluer flick, tracking, réaction et contrôle du spray",
		"description": "Quatre mini-épreuves de 27 secondes notées sur 100. La note la plus basse désigne ta priorité, et la routine du jour s'y adapte. À refaire chaque semaine pour mesurer tes progrès.",
		"map": MAP_RANGE,
		"script": preload("res://scripts/drills/benchmark_drill.gd"),
		"duration": 122.0,
		"params": {},
	},
	{
		"id": "duel",
		"title": "DUEL",
		"tag": "Combat",
		"focus": "Éliminer une cible humanoïde qui strafe",
		"description": "Une silhouette strafe de façon erratique et marque de brefs arrêts. Élimine-la avant la fin du temps imparti : tête en un tir, corps en trois. Tir automatique avec recul, imprécision en mouvement. La difficulté s'ajuste à tes résultats.",
		"map": MAP_STRAFE_LANE,
		"script": preload("res://scripts/drills/duel_drill.gd"),
		"duration": 60.0,
		"params": {},
	},
	{
		"id": "tap_burst",
		"title": "TAP ET RAFALES",
		"tag": "Combat",
		"focus": "Tirs isolés et rafales courtes à longue distance",
		"description": "La cible est plus loin et strafe moins vite. À cette distance une longue rafale part hors de la cible : tire une à trois balles, replace le viseur, recommence. La longueur moyenne de tes rafales est mesurée.",
		"map": MAP_STRAFE_LANE,
		"script": preload("res://scripts/drills/duel_drill.gd"),
		"duration": 60.0,
		"params": {"enemy_depth": -4.5, "strafe_scale": 0.6, "base_time_limit": 3.6},
	},
	{
		"id": "peek_duel",
		"title": "DUEL D'ANGLE",
		"tag": "Combat",
		"focus": "Sortir d'un coin et gagner contre un adversaire qui riposte",
		"description": "Un adversaire tient l'angle derrière le coin et tire quelques dixièmes de seconde après t'avoir vu. Sors serré ou large, élimine-le avant, ou reviens à couvert et ressors. Exposition, largeur de sortie et re-sorties sont mesurées.",
		"map": MAP_ANGLE_HALL,
		"script": preload("res://scripts/drills/peek_duel_drill.gd"),
		"duration": 75.0,
		"params": {},
	},
	{
		"id": "multi_target",
		"title": "CIBLES MULTIPLES",
		"tag": "Combat",
		"focus": "Transfert de rafale et ordre des cibles",
		"description": "Des vagues de trois silhouettes. Élimine-les en enchaînant, sans relâcher le clic si tu le peux, et choisis l'ordre qui raccourcit tes trajets de viseur. Temps par vague et temps de transfert sont mesurés.",
		"map": MAP_STRAFE_LANE,
		"script": preload("res://scripts/drills/multi_target_drill.gd"),
		"duration": 60.0,
		"params": {},
	},
	{
		"id": "sound_locate",
		"title": "LOCALISATION AU SON",
		"tag": "Sens du jeu",
		"focus": "Situer une source sonore à l'oreille",
		"description": "Un signal est émis quelque part autour de toi. Tourne-toi vers sa source et clique ; elle est ensuite révélée. Dix essais. Casque stéréo indispensable.",
		"map": MAP_RANGE,
		"script": preload("res://scripts/drills/sound_locate_drill.gd"),
		"duration": 150.0,
		"params": {},
	},
	{
		"id": "defuse",
		"title": "DÉSAMORÇAGE",
		"tag": "Carte",
		"focus": "Reprendre un site et désamorcer avant l'explosion",
		"description": "La charge explose dans 45 secondes. Pars du spawn défenseur, nettoie le site, puis appuie sur ESPACE au centre du site et reste immobile 7 secondes. Bouger ou s'éloigner interrompt le désamorçage.",
		"map": MAP_RANGE,
		"maps": TACTICAL_MAPS,
		"script": preload("res://scripts/drills/site_clear_drill.gd"),
		"duration": 45.0,
		"params": {"angle_count": 5, "retake": true, "charge_seconds": 45.0},
	},
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
	{
		"id": "site_attack",
		"title": "ATTAQUE DE SITE",
		"tag": "Carte",
		"focus": "Entrer sur un site et nettoyer chaque angle",
		"description": "Sur une grande carte au choix, un site est tiré au sort. Tu pars du lobby, tu entres et tu abats les huit cibles cachées derrière les caisses et les coins. Les positions changent à chaque session.",
		"map": MAP_RANGE,
		"maps": TACTICAL_MAPS,
		"script": preload("res://scripts/drills/site_clear_drill.gd"),
		"duration": 120.0,
		"params": {"angle_count": 8},
	},
	{
		"id": "site_retake",
		"title": "REPRISE DE SITE",
		"tag": "Carte",
		"focus": "Revenir du spawn défenseur et reprendre un site",
		"description": "Même principe côté défense : tu pars du spawn des défenseurs, tu rejoins le site tiré au sort et tu le reprends angle par angle. Le chronomètre récompense une reprise rapide et propre.",
		"map": MAP_RANGE,
		"maps": TACTICAL_MAPS,
		"script": preload("res://scripts/drills/site_clear_drill.gd"),
		"duration": 120.0,
		"params": {"angle_count": 8, "retake": true},
	},
	{
		"id": "free_roam",
		"title": "EXPLORATION LIBRE",
		"tag": "Carte",
		"focus": "Apprendre une carte : trajets, angles, rotations",
		"description": "Parcours librement une grande carte, sans cible ni score. Utile avant les exercices d'attaque et de reprise pour repérer les entrées de chaque site.",
		"map": MAP_RANGE,
		"maps": TACTICAL_MAPS,
		"script": preload("res://scripts/drills/free_roam_drill.gd"),
		"duration": 300.0,
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
