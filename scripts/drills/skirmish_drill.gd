extends "res://scripts/drills/bot_drill_base.gd"
## Escarmouche : des bots traquent le joueur sur une grande carte. Ils
## patrouillent entre les sites, se dirigent vers lui quand ils le voient ou
## l'entendent courir, et tirent par rafales après leur temps de réaction.
## Éliminer un bot en fait apparaître un autre ailleurs. Mourir coûte des
## points et renvoie au point de départ.
##
## Mesures : éliminations, morts, dégâts subis, précision des bots contre toi,
## tirs à la tête, temps pour éliminer.

var bot_count: int = 2
var min_spawn_distance: float = 28.0

var _patrol_points: Array[Vector3] = []
var _respawn_timer: float = 0.0
var _patrol_timer: float = 8.0


func spawn_marker() -> String:
	return "AttackerSpawn"


func setup() -> void:
	prepare_bots()
	for letter in ["A", "B", "C"]:
		if has_marker("Site%s" % letter):
			_patrol_points.append(marker("Site%s" % letter))
			_patrol_points.append(marker("Lobby%s" % letter))
	_patrol_points.append(marker("DefenderSpawn"))
	hud.set_objective("Des bots te traquent. Ils t'entendent courir (Maj pour marcher) et tirent par rafales : punis-les pendant qu'ils sont à l'arrêt.")
	hud.set_speed_gauge_visible(true)
	_refresh_side_stat()


func begin() -> void:
	for index in bot_count:
		_spawn_hunter()


func update(delta: float) -> void:
	hud.set_speed(player.horizontal_speed(), PlayerController.ACCURATE_SPEED, PlayerController.RUN_SPEED)
	tick_utilities(delta)
	if bots.size() < bot_count:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_spawn_hunter()
			_respawn_timer = 2.5
	# Les bots qui ne combattent pas changent régulièrement de point de patrouille.
	_patrol_timer -= delta
	if _patrol_timer <= 0.0:
		_patrol_timer = 8.0
		for bot in bots:
			var brain := brain_of(bot)
			if brain != null and not brain.is_engaging():
				brain.hunt(_patrol_points[rng.randi_range(0, _patrol_points.size() - 1)])


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	var killed := resolve_player_shot(collider, hit_position, hit_normal, shot)
	if killed != null:
		score += 200
		hud.show_feedback("BOT ÉLIMINÉ", Hud.COLOR_GOOD)
		killed.destroy()
		_respawn_timer = 2.5
		_refresh_side_stat()


func on_player_died() -> void:
	score = maxi(score - 150, 0)
	hud.show_feedback("ÉLIMINÉ · retour au départ", Hud.COLOR_BAD, 1.5)
	player.teleport(marker("AttackerSpawn"), 0.0)
	player.automatic = true
	player.recoil_enabled = true
	player.utility_enabled = true
	_refresh_side_stat()


func finalize(report: Dictionary) -> void:
	add_combat_stats(report)
	var ratio := float(bot_kills) / float(maxi(deaths, 1))
	report["kill_death_ratio"] = ratio
	report["success_ratio"] = clampf(ratio / 3.0, 0.0, 1.0)
	add_kpi(report, "ÉLIMINATIONS", str(bot_kills), "%d morts · ratio %.1f" % [deaths, ratio])
	add_kpi(report, "DÉGÂTS SUBIS", str(roundi(damage_taken)), "les bots touchent %d %% de leurs balles, dont %d à la tête" % [roundi(Stats.percent(bot_hits, bot_shots)), bot_head_hits])
	add_kpi(report, "TIRS À LA TÊTE", "%d %%" % roundi(Stats.percent(head_hits, head_hits + body_hits)) if hits > 0 else "—", "")
	add_kpi(report, "TEMPS POUR ÉLIMINER", "%.1f s" % (Stats.mean(kill_times) / 1000.0) if bot_kills > 0 else "—", "de l'apparition du bot à son élimination")
	add_shooting_kpis(report)
	add_kpi(report, "BRUIT", "%d m" % roundi(player.loud_distance), "parcourus en courant, audibles par les bots")
	add_kpi(report, "RANG DES BOTS", BotRanks.rank_name(bot_rank()), "adaptatif" if GameSettings.bot_rank < 0 else "fixé dans le menu")
	set_chart(report, "TEMPS POUR ÉLIMINER CHAQUE BOT (ms)", kill_times, "ms", 12000.0, true)
	set_panels(report, ["chart", "heatmap"])


func _spawn_hunter() -> void:
	# Loin du joueur et hors de sa vue.
	var options: Array[Vector3] = []
	for point in _patrol_points:
		var far := point.distance_to(player.global_position) >= min_spawn_distance
		if far and not line_of_sight(point + Vector3(0.0, 1.6, 0.0), player.eye_position()):
			options.append(point)
	if options.is_empty():
		options = _patrol_points
	if options.is_empty():
		return
	var brain := spawn_bot(options[rng.randi_range(0, options.size() - 1)])
	brain.hunt(_patrol_points[rng.randi_range(0, _patrol_points.size() - 1)])


func _refresh_side_stat() -> void:
	hud.set_side_stat("ÉLIMINATIONS · MORTS", "%d · %d" % [bot_kills, deaths])
