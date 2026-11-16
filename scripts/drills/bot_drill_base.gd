extends "res://scripts/drills/drill_base.gd"
## Base des exercices contre des bots dotés d'une IA : construit la grille de
## navigation de la carte, fait apparaître les bots, gère leurs tirs, la vie du
## joueur et les statistiques de combat communes.

const Humanoid := preload("res://scripts/humanoid_target.gd")
const BotBrain := preload("res://scripts/ai/bot_brain.gd")
const NavGrid := preload("res://scripts/ai/nav_grid.gd")
const BotRanks := preload("res://scripts/ai/bot_ranks.gd")
const UtilityKit := preload("res://scripts/utility/utility_kit.gd")
const BotSquad := preload("res://scripts/ai/bot_squad.gd")
const HUMANOID_SCENE: PackedScene = preload("res://scenes/humanoid_target.tscn")

## Étendue couverte par la grille de navigation (x, z en mètres).
const NAV_BOUNDS := Rect2(-76.0, -74.0, 152.0, 148.0)
const PLAYER_MAX_HEALTH := 100.0
## Dégâts d'une balle de bot : une balle dans la tête élimine, le corps en demande trois.
const BOT_HEAD_DAMAGE := 150.0
const BOT_BODY_DAMAGE := 40.0

var nav := NavGrid.new()
var bots: Array[Humanoid] = []
## target_id -> BotBrain.
var brains: Dictionary = {}
var player_health: float = PLAYER_MAX_HEALTH
var utilities: UtilityKit
var squad: BotSquad
## Balles reçues pendant qu'au moins deux bots te combattaient en même temps.
var crossfire_hits: int = 0
## Charges de chaque utilitaire par session.
var utility_charges: int = 2
var bots_blinded: int = 0
var burn_kills: int = 0

var deaths: int = 0
var bot_kills: int = 0
var damage_taken: float = 0.0
var bot_shots: int = 0
var bot_hits: int = 0
var bot_head_hits: int = 0
var head_hits: int = 0
var body_hits: int = 0
var kill_times: PackedFloat32Array = PackedFloat32Array()
var _bot_spawn_usec: Dictionary = {}


func uses_movement() -> bool:
	return true


## Niveau des bots (0 à 1) déduit de la difficulté adaptative.
func bot_skill() -> float:
	return clampf(inverse_lerp(0.6, 1.8, difficulty), 0.0, 1.0)


## Rang des bots : celui choisi dans le menu, ou celui de la difficulté adaptative.
func bot_rank() -> int:
	var chosen: int = GameSettings.bot_rank
	if chosen >= 0:
		return clampi(chosen, 0, BotRanks.count() - 1)
	return BotRanks.rank_from_skill(bot_skill())


## À appeler dans setup() : arme automatique et grille de navigation.
func prepare_bots() -> void:
	player.automatic = true
	player.recoil_enabled = true
	player_health = PLAYER_MAX_HEALTH
	nav.build(map_root, NAV_BOUNDS)
	squad = BotSquad.new()
	add_child(squad)
	squad.start(nav)
	utilities = UtilityKit.new()
	add_child(utilities)
	utilities.start(player, hud, map_root, utility_charges)
	utilities.detonated.connect(_on_utility_detonated)


## À appeler à chaque image : brûlures des zones incendiaires.
func tick_utilities(delta: float) -> void:
	if utilities == null:
		return
	var burn := UtilityKit.FIRE_DAMAGE_PER_SECOND * delta
	for index in range(bots.size() - 1, -1, -1):
		var bot := bots[index]
		if utilities.is_burning(bot.global_position) and bot.apply_damage(burn):
			bot_kills += 1
			burn_kills += 1
			fx.explosion(bot.head_position())
			var burned_brain := brain_of(bot)
			if burned_brain != null:
				squad.remove_member(burned_brain, bot.global_position)
			bots.remove_at(index)
			brains.erase(bot.target_id)
			bot.destroy()
	if utilities.is_burning(player.global_position):
		player_health -= burn
		damage_taken += burn
		if player_health <= 0.0:
			deaths += 1
			player_health = PLAYER_MAX_HEALTH
			on_player_died()


func _on_utility_detonated(kind: int, at: Vector3) -> void:
	if kind != UtilityKit.Kind.FLASH:
		return
	for bot in bots:
		var brain := brain_of(bot)
		if brain != null and bot.head_position().distance_to(at) <= UtilityKit.FLASH_RANGE and brain.try_blind(at, UtilityKit.FLASH_SECONDS):
			bots_blinded += 1


func spawn_bot(at: Vector3) -> BotBrain:
	var bot := HUMANOID_SCENE.instantiate() as Humanoid
	bot.target_id = _next_target_id
	_next_target_id += 1
	bot.position = Vector3(at.x, 0.0, at.z)
	add_child(bot)
	var brain := BotBrain.new()
	bot.add_child(brain)
	brain.setup(bot, player, nav, BotRanks.profile(bot_rank()))
	brain.shot_fired.connect(_on_bot_shot)
	bots.append(bot)
	brains[bot.target_id] = brain
	squad.add_member(brain)
	_bot_spawn_usec[bot.target_id] = Time.get_ticks_usec()
	return brain


func brain_of(bot: Humanoid) -> BotBrain:
	return brains.get(bot.target_id) as BotBrain


## Traite un tir du joueur contre les bots. Renvoie le bot éliminé, ou null.
func resolve_player_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> Humanoid:
	shots += 1
	var speed: float = shot.get("speed", 0.0)
	var struck := collider as Humanoid
	if struck == null or not bots.has(struck):
		var nearest := nearest_bot()
		if nearest != null:
			Telemetry.record_shot(false, nearest.head_position(), Humanoid.HEAD_RADIUS, nearest.target_id, speed, {})
		else:
			Telemetry.record_shot(false, Vector3.ZERO, 0.0, -1, speed, {})
		if collider != null:
			fx.impact(hit_position, hit_normal)
		hud.flash_miss()
		return null
	hits += 1
	var head := struck.is_head_hit(hit_position)
	Telemetry.record_shot(true, struck.head_position(), Humanoid.HEAD_RADIUS, struck.target_id, speed, {"head": head})
	if head:
		head_hits += 1
	else:
		body_hits += 1
	hud.flash_hit()
	Sfx.play(&"hit")
	var struck_brain := brain_of(struck)
	if struck_brain != null:
		struck_brain.notify_damage(player.global_position)
	if not struck.apply_damage(player.weapon_damage(head)):
		return null
	var now: int = shot.get("time_usec", Time.get_ticks_usec())
	var born: int = _bot_spawn_usec.get(struck.target_id, now)
	bot_kills += 1
	kill_times.append(float(now - born) / 1000.0)
	fx.explosion(struck.head_position())
	Sfx.play(&"kill")
	if struck_brain != null:
		squad.remove_member(struck_brain, player.global_position)
	bots.erase(struck)
	brains.erase(struck.target_id)
	return struck


func nearest_bot() -> Humanoid:
	var best: Humanoid = null
	var best_angle := INF
	for bot in bots:
		var offset: Vector2 = Telemetry.angular_offset_to(bot.head_position())
		if offset.length() < best_angle:
			best_angle = offset.length()
			best = bot
	return best


## Appelé quand la vie du joueur tombe à zéro (à surcharger : réapparition, pénalité).
func on_player_died() -> void:
	pass


func add_combat_stats(report: Dictionary) -> void:
	report["bot_kills"] = bot_kills
	report["deaths"] = deaths
	report["damage_taken"] = damage_taken
	report["bot_accuracy"] = Stats.percent(bot_hits, bot_shots)
	report["headshot_rate"] = Stats.percent(head_hits, head_hits + body_hits)
	report["avg_bot_kill_ms"] = Stats.mean(kill_times)
	report["bot_rank"] = bot_rank()
	report["bots_blinded"] = bots_blinded
	report["crossfire_hits"] = crossfire_hits
	report["squad_flanks"] = squad.flanks_ordered
	report["squad_assists"] = squad.assists_ordered
	report["squad_trades"] = squad.trades_informed
	report["squad_defuser_swaps"] = squad.defuser_swaps
	report["burn_kills"] = burn_kills
	if utilities != null:
		report["smokes_used"] = utilities.throws[UtilityKit.Kind.SMOKE]
		report["incendiaries_used"] = utilities.throws[UtilityKit.Kind.INCENDIARY]
		report["flashes_used"] = utilities.throws[UtilityKit.Kind.FLASH]
	report["bot_rank_name"] = BotRanks.rank_name(bot_rank())
	report["bot_rank_adaptive"] = GameSettings.bot_rank < 0
	report["bot_headshot_rate"] = Stats.percent(bot_head_hits, bot_hits)
	report["difficulty_level"] = difficulty


func _on_bot_shot(hit: bool, head: bool, origin: Vector3, end_point: Vector3) -> void:
	if finished:
		return
	bot_shots += 1
	fx.tracer(origin, end_point)
	if not hit:
		return
	var damage := BOT_HEAD_DAMAGE if head else BOT_BODY_DAMAGE
	bot_hits += 1
	if squad.engaging_count() >= 2:
		crossfire_hits += 1
	if head:
		bot_head_hits += 1
	damage_taken += damage
	player_health -= damage
	hud.show_feedback("%s · %d PV" % ["TÊTE" if head else "TOUCHÉ", roundi(maxf(player_health, 0.0))], Hud.COLOR_BAD, 0.6)
	hud.flash_miss()
	Sfx.play(&"miss")
	Telemetry.log_event("player_hit", {"health": player_health, "head": head})
	if player_health <= 0.0:
		deaths += 1
		player_health = PLAYER_MAX_HEALTH
		Sfx.play(&"fail")
		Telemetry.log_event("player_died", {"head": head})
		on_player_died()
