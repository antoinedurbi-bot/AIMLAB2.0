extends RefCounted
## Catalogue des exercices : ce que le lobby affiche et ce que le gestionnaire de
## partie instancie. Pour ajouter un exercice : écrire un script qui étend
## drill_base.gd, puis l'inscrire ici.
##
## Champs d'une entrée :
##   id       : identifiant (historique, difficulté, conseils) ;
##   category : onglet du lobby ("" = hors grille, lancé depuis l'accueil) ;
##   card     : titre de la carte du lobby ; les entrées qui partagent une carte
##              en sont les variantes, nommées par `variant` ;
##   title    : nom affiché en jeu et dans le rapport ;
##   focus    : la compétence travaillée, en quelques mots ;
##   description : deux phrases au plus, affichées sur demande ;
##   map / maps  : carte fixe, ou liste de cartes au choix ;
##   script, duration, params : exercice, durée maximale (s), variables surchargées.

const MAP_RANGE := "res://scenes/arena.tscn"
const MAP_STRAFE_LANE := "res://scenes/maps/strafe_lane.tscn"
const MAP_ANGLE_HALL := "res://scenes/maps/angle_hall.tscn"
const MAP_KILL_HOUSE := "res://scenes/maps/kill_house.tscn"

## Grandes cartes originales (deux ou trois sites), au choix dans le lobby.
const TACTICAL_MAPS := [
	{"name": "Citadelle", "path": "res://scenes/maps/tactical_citadelle.tscn"},
	{"name": "Triade (3 sites)", "path": "res://scenes/maps/tactical_triade.tscn"},
	{"name": "Faubourg", "path": "res://scenes/maps/tactical_faubourg.tscn"},
	{"name": "Entrepôt", "path": "res://scenes/maps/tactical_entrepot.tscn"},
	{"name": "Canal", "path": "res://scenes/maps/tactical_canal.tscn"},
	{"name": "Rotonde", "path": "res://scenes/maps/tactical_rotonde.tscn"},
	{"name": "Dédale", "path": "res://scenes/maps/tactical_dedale.tscn"},
]

## Onglets du lobby, dans l'ordre.
const CATEGORIES := [
	{"id": "aim", "title": "VISÉE"},
	{"id": "move", "title": "DÉPLACEMENT"},
	{"id": "duel", "title": "DUELS"},
	{"id": "bomb", "title": "CHARGE ET SITES"},
]

const DRILLS := [
	{
		"id": "benchmark", "category": "", "card": "DIAGNOSTIC", "variant": "",
		"title": "DIAGNOSTIC",
		"focus": "Flick, tracking, réaction, spray",
		"description": "Quatre épreuves de 27 s notées sur 100. La note la plus basse fixe ta routine.",
		"map": MAP_RANGE,
		"script": preload("res://scripts/drills/benchmark_drill.gd"),
		"duration": 122.0,
		"params": {},
	},
	{
		"id": "gridshot", "category": "aim", "card": "FLICKS", "variant": "Larges",
		"title": "GRIDSHOT",
		"focus": "Vitesse d'enchaînement",
		"description": "Trois sphères sur une grille : détruis-en une, une autre apparaît.",
		"map": MAP_RANGE,
		"script": preload("res://scripts/drills/gridshot_drill.gd"),
		"duration": 60.0,
		"params": {},
	},
	{
		"id": "microflick", "category": "aim", "card": "FLICKS", "variant": "Micro",
		"title": "MICROFLICKS",
		"focus": "Précision à hauteur de tête",
		"description": "Une petite cible à la fois, toujours proche de la précédente.",
		"map": MAP_RANGE,
		"script": preload("res://scripts/drills/gridshot_drill.gd"),
		"duration": 60.0,
		"params": {"grid_columns": 7, "grid_rows": 3, "cell_spacing": 0.5, "grid_distance": 13.0, "target_radius": 0.16, "simultaneous_targets": 1, "miss_penalty": 25},
	},
	{
		"id": "multi_target", "category": "aim", "card": "TRANSFERTS", "variant": "",
		"title": "CIBLES MULTIPLES",
		"focus": "Passer d'une cible à l'autre",
		"description": "Vagues de trois silhouettes à éliminer d'une traite. Choisis l'ordre le plus court.",
		"map": MAP_STRAFE_LANE,
		"script": preload("res://scripts/drills/multi_target_drill.gd"),
		"duration": 60.0,
		"params": {},
	},
	{
		"id": "angle_hold", "category": "aim", "card": "TENUE D'ANGLE", "variant": "",
		"title": "TENUE D'ANGLE",
		"focus": "Réaction et premier tir",
		"description": "Une cible surgit du coin à un moment imprévisible. Un tir, pas de tir dans le vide.",
		"map": MAP_ANGLE_HALL,
		"script": preload("res://scripts/drills/angle_hold_drill.gd"),
		"duration": 60.0,
		"params": {},
	},
	{
		"id": "counter_strafe", "category": "move", "card": "ARRÊT ET TIR", "variant": "",
		"title": "STRAFE / CONTRE-STRAFE",
		"focus": "S'arrêter net avant de tirer",
		"description": "Strafe à pleine vitesse, arrête-toi, tire. Chaque tir en mouvement est dévié.",
		"map": MAP_STRAFE_LANE,
		"script": preload("res://scripts/drills/counter_strafe_drill.gd"),
		"duration": 60.0,
		"params": {},
	},
	{
		"id": "jiggle_peek", "category": "move", "card": "JIGGLE PEEK", "variant": "",
		"title": "JIGGLE PEEK",
		"focus": "Prendre l'info sans être touché",
		"description": "Sors du coin juste assez pour voir, puis reviens. Aucun tir.",
		"map": MAP_ANGLE_HALL,
		"script": preload("res://scripts/drills/jiggle_peek_drill.gd"),
		"duration": 60.0,
		"params": {},
	},
	{
		"id": "pre_aim", "category": "move", "card": "PARCOURS", "variant": "",
		"title": "PRÉ-VISÉE",
		"focus": "Viseur placé avant chaque angle",
		"description": "Traverse le parcours et abats la cible cachée derrière chaque angle.",
		"map": MAP_KILL_HOUSE,
		"script": preload("res://scripts/drills/pre_aim_drill.gd"),
		"duration": 90.0,
		"params": {},
	},
	{
		"id": "duel", "category": "duel", "card": "DUEL", "variant": "Proche",
		"title": "DUEL",
		"focus": "Cible qui strafe, recul actif",
		"description": "Une silhouette strafe de façon erratique. Tête : un tir. Corps : trois.",
		"map": MAP_STRAFE_LANE,
		"script": preload("res://scripts/drills/duel_drill.gd"),
		"duration": 60.0,
		"params": {},
	},
	{
		"id": "tap_burst", "category": "duel", "card": "DUEL", "variant": "Longue distance",
		"title": "TAP ET RAFALES",
		"focus": "Une à trois balles, pas plus",
		"description": "Cible lointaine : les longues rafales partent hors cible.",
		"map": MAP_STRAFE_LANE,
		"script": preload("res://scripts/drills/duel_drill.gd"),
		"duration": 60.0,
		"params": {"enemy_depth": -4.5, "strafe_scale": 0.6, "base_time_limit": 3.6},
	},
	{
		"id": "peek_duel", "category": "duel", "card": "DUEL D'ANGLE", "variant": "",
		"title": "DUEL D'ANGLE",
		"focus": "Sortir d'un coin face à un tireur",
		"description": "L'adversaire tient l'angle et riposte. Sors, tue, ou reviens à couvert.",
		"map": MAP_ANGLE_HALL,
		"script": preload("res://scripts/drills/peek_duel_drill.gd"),
		"duration": 75.0,
		"params": {},
	},
	{
		"id": "skirmish", "category": "duel", "card": "ESCARMOUCHE", "variant": "",
		"title": "ESCARMOUCHE",
		"focus": "Trois bots coordonnés te traquent",
		"description": "Ils te voient, t'entendent courir et se couvrent. Tu as 100 PV.",
		"map": MAP_RANGE,
		"maps": TACTICAL_MAPS,
		"script": preload("res://scripts/drills/skirmish_drill.gd"),
		"duration": 120.0,
		"params": {},
	},
	{
		"id": "site_attack", "category": "bomb", "card": "SITE", "variant": "Attaque",
		"title": "ATTAQUE DE SITE",
		"focus": "Entrer et nettoyer chaque angle",
		"description": "Pars du lobby et abats les huit cibles cachées sur le site.",
		"map": MAP_RANGE,
		"maps": TACTICAL_MAPS,
		"script": preload("res://scripts/drills/site_clear_drill.gd"),
		"duration": 120.0,
		"params": {"angle_count": 8},
	},
	{
		"id": "site_retake", "category": "bomb", "card": "SITE", "variant": "Reprise",
		"title": "REPRISE DE SITE",
		"focus": "Revenir et reprendre le site",
		"description": "Pars du spawn défenseur et reprends le site angle par angle.",
		"map": MAP_RANGE,
		"maps": TACTICAL_MAPS,
		"script": preload("res://scripts/drills/site_clear_drill.gd"),
		"duration": 120.0,
		"params": {"angle_count": 8, "retake": true},
	},
	{
		"id": "defuse", "category": "bomb", "card": "SITE", "variant": "Désamorçage",
		"title": "DÉSAMORÇAGE",
		"focus": "Nettoyer puis désamorcer en 45 s",
		"description": "Nettoie le site, puis désamorce au centre : 7 s sans bouger.",
		"map": MAP_RANGE,
		"maps": TACTICAL_MAPS,
		"script": preload("res://scripts/drills/site_clear_drill.gd"),
		"duration": 45.0,
		"params": {"angle_count": 5, "retake": true, "charge_seconds": 45.0},
	},
	{
		"id": "bomb_defense", "category": "bomb", "card": "DÉFENSE", "variant": "",
		"title": "DÉFENSE DE LA CHARGE",
		"focus": "Tenir le site après la pose",
		"description": "Des bots viennent désamorcer. Tiens 45 s.",
		"map": MAP_RANGE,
		"maps": TACTICAL_MAPS,
		"script": preload("res://scripts/drills/bomb_defense_drill.gd"),
		"duration": 46.0,
		"params": {},
	},
	{
		"id": "charge_timer", "category": "bomb", "card": "DERNIÈRE SECONDE", "variant": "",
		"title": "DERNIÈRE SECONDE",
		"focus": "Lire le rythme des bips",
		"description": "Une charge bipe devant toi, sans chrono. Lance le désamorçage le plus tard possible.",
		"map": MAP_RANGE,
		"script": preload("res://scripts/drills/charge_timer_drill.gd"),
		"duration": 120.0,
		"params": {},
	},
	{
		"id": "lineups", "category": "bomb", "card": "UTILITAIRES", "variant": "Lineups",
		"title": "LINEUPS",
		"focus": "Trouver et mémoriser des lancers",
		"description": "Fais atterrir l'incendiaire dans la zone marquée. Les lancers réussis sont mémorisés.",
		"map": MAP_RANGE,
		"maps": TACTICAL_MAPS,
		"script": preload("res://scripts/drills/lineup_drill.gd"),
		"duration": 240.0,
		"params": {},
	},
	{
		"id": "free_roam", "category": "bomb", "card": "UTILITAIRES", "variant": "Exploration",
		"title": "EXPLORATION LIBRE",
		"focus": "Apprendre une carte",
		"description": "Parcours la carte librement. Échap pour terminer.",
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


## Entrées d'une catégorie regroupées par carte : [{card, entries: [entrée, ...]}].
static func cards(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Variant in DRILLS:
		var entry: Dictionary = item
		if entry.get("category", "") != category:
			continue
		var card_title: String = entry.get("card", "")
		var found := false
		for card in result:
			if card.get("card", "") == card_title:
				var entries: Array = card["entries"]
				entries.append(entry)
				found = true
		if not found:
			result.append({"card": card_title, "entries": [entry]})
	return result
