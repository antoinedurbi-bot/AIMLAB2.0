extends "res://scripts/drills/bot_drill_base.gd"
## Défense de la charge (après la pose) : la charge est posée sur un site tiré
## au sort. Des bots partent du spawn des défenseurs, trouvent leur chemin
## jusqu'à elle et la désamorcent s'ils l'atteignent. Ils ripostent s'ils te
## voient. Il faut tenir jusqu'à l'explosion.
##
## Victoire : la charge explose. Défaite : un bot la désamorce.
## Mesures : bots éliminés, combien ont atteint la charge, progression maximale
## du désamorçage adverse, morts, dégâts subis, temps pour éliminer.

const Bomb := preload("res://scripts/bomb.gd")
const BOMB_SCENE: PackedScene = preload("res://scenes/bomb.tscn")

var fuse_seconds: float = 45.0
var defuse_seconds: float = 7.0
## Délai avant le premier bot, puis entre deux arrivées au niveau 1 (s).
var first_wave_delay: float = 2.0
var wave_interval: float = 9.0

var _site: String = ""
var _bomb: Bomb
var _bomb_position: Vector3 = Vector3.ZERO
var _wave_timer: float = 0.0
var _result: String = ""
var _reached: int = 0
var _max_defuse: float = 0.0
var _counted_arrivals: Dictionary = {}


func spawn_marker() -> String:
	if _site == "":
		_choose_site()
	return "Lobby" + _site


func setup() -> void:
	if _site == "":
		_choose_site()
	prepare_bots()
	duration = fuse_seconds + 1.0
	_bomb_position = marker("Site" + _site)
	_bomb = BOMB_SCENE.instantiate() as Bomb
	_bomb.fuse_seconds = fuse_seconds
	_bomb.defuse_seconds = defuse_seconds
	_bomb.position = _bomb_position
	add_child(_bomb)
	_bomb.exploded.connect(_on_bomb_exploded)
	_bomb.defused.connect(_on_bomb_defused)
	_wave_timer = first_wave_delay
	squad.set_objective(_bomb_position)
	hud.set_objective("Site %s : empêche le désamorçage pendant %d s" % [_site, roundi(fuse_seconds)])
	hud.set_speed_gauge_visible(true)
	hud.set_side_stat("BOTS ÉLIMINÉS", "0 · 100 PV")


func begin() -> void:
	_bomb.arm()


func shows_clock() -> bool:
	return not (_bomb != null and _bomb.is_being_defused())


func update(delta: float) -> void:
	hud.set_speed(player.horizontal_speed(), PlayerController.ACCURATE_SPEED, PlayerController.RUN_SPEED)
	tick_utilities(delta)
	if _result != "":
		return
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = wave_interval / difficulty
		# L'escouade décide : le premier désamorce, les suivants le couvrent.
		spawn_bot(marker("DefenderSpawn"))

	# Un bot arrivé sur la charge la désamorce tant qu'il est en vie et ne combat pas.
	var someone_defusing := false
	for bot in bots:
		var brain := brain_of(bot)
		if brain != null and brain.is_defusing():
			someone_defusing = true
			if not _counted_arrivals.has(bot.target_id):
				_counted_arrivals[bot.target_id] = true
				_reached += 1
				hud.show_feedback("UN BOT DÉSAMORCE", Hud.COLOR_BAD)
				Sfx.play(&"fail")
	_bomb.set_defusing(someone_defusing, false)
	if someone_defusing:
		_max_defuse = maxf(_max_defuse, _bomb.defuse_progress)
		hud.set_clock_text("DÉSAMORÇAGE %.1f / %.0f s" % [_bomb.defuse_progress, defuse_seconds])


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	var killed := resolve_player_shot(collider, hit_position, hit_normal, shot)
	if killed != null:
		var was_defusing := _counted_arrivals.has(killed.target_id)
		score += 200 + (100 if was_defusing else 0)
		hud.show_feedback("DÉSAMORÇAGE STOPPÉ" if was_defusing else "BOT ÉLIMINÉ", Hud.COLOR_GOOD)
		killed.destroy()
		hud.set_side_stat("BOTS ÉLIMINÉS", "%d · %d PV" % [bot_kills, roundi(player_health)])


func on_player_died() -> void:
	score = maxi(score - 150, 0)
	hud.show_feedback("ÉLIMINÉ · retour au lobby", Hud.COLOR_BAD, 1.5)
	player.teleport(marker("Lobby" + _site), 0.0)
	player.automatic = true
	player.recoil_enabled = true
	player.utility_enabled = true


func finalize(report: Dictionary) -> void:
	if _bomb != null:
		_bomb.stop()
	var won := _result == "exploded"
	add_combat_stats(report)
	report["bomb_site"] = _site
	report["bomb_defended"] = won
	report["bomb_enemies_killed"] = bot_kills
	report["bomb_enemies_reached"] = _reached
	report["bomb_max_enemy_defuse_s"] = _max_defuse
	report["bomb_avg_kill_ms"] = Stats.mean(kill_times)
	report["success_ratio"] = 1.0 if won and _reached <= 1 and deaths == 0 else (0.6 if won else 0.2)

	add_kpi(report, "CHARGE", "DÉFENDUE" if won else "DÉSAMORCÉE", "site %s" % _site)
	add_kpi(report, "BOTS ÉLIMINÉS", str(bot_kills), "%d ont atteint la charge" % _reached)
	add_kpi(report, "DÉSAMORÇAGE ADVERSE MAX", "%.1f s" % _max_defuse, "sur %d s nécessaires" % roundi(defuse_seconds))
	add_kpi(report, "RELÈVES DU DÉSAMORCEUR", str(squad.defuser_swaps), "%d balles reçues en tir croisé" % crossfire_hits)
	add_kpi(report, "MORTS", str(deaths), "%d points de dégâts subis" % roundi(damage_taken))
	add_kpi(report, "TIRS À LA TÊTE", "%d %%" % roundi(Stats.percent(head_hits, head_hits + body_hits)) if hits > 0 else "—", "")
	add_shooting_kpis(report)
	add_kpi(report, "RANG DES BOTS", BotRanks.rank_name(bot_rank()), "adaptatif" if GameSettings.bot_rank < 0 else "fixé dans le menu")
	set_chart(report, "TEMPS POUR ÉLIMINER CHAQUE BOT (ms)", kill_times, "ms", 9000.0, true)
	set_panels(report, ["chart", "heatmap"])


func _on_bomb_exploded() -> void:
	_result = "exploded"
	score += 400
	hud.show_feedback("LA CHARGE A EXPLOSÉ · site défendu", Hud.COLOR_GOOD, 2.0)
	Sfx.play(&"success")
	finished = true


func _on_bomb_defused(_by_player: bool) -> void:
	_result = "defused"
	hud.show_feedback("CHARGE DÉSAMORCÉE PAR UN BOT", Hud.COLOR_BAD, 2.0)
	Sfx.play(&"fail")
	finished = true


func _choose_site() -> void:
	var available := PackedStringArray()
	for letter in ["A", "B", "C"]:
		if has_marker("Site%s_01" % letter):
			available.append(letter)
	_site = "A" if available.is_empty() else available[rng.randi_range(0, available.size() - 1)]
