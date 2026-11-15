extends "res://scripts/drills/drill_base.gd"
## Base des exercices contre des bots dotés d'une IA : construit la grille de
## navigation de la carte, fait apparaître les bots, gère leurs tirs, la vie du
## joueur et les statistiques de combat communes.

const Humanoid := preload("res://scripts/humanoid_target.gd")
const BotBrain := preload("res://scripts/ai/bot_brain.gd")
const NavGrid := preload("res://scripts/ai/nav_grid.gd")
const HUMANOID_SCENE: PackedScene = preload("res://scenes/humanoid_target.tscn")

## Étendue couverte par la grille de navigation (x, z en mètres).
const NAV_BOUNDS := Rect2(-76.0, -74.0, 152.0, 148.0)
const PLAYER_MAX_HEALTH := 100.0
## Dégâts d'une balle de bot.
const BOT_DAMAGE := 24.0

var nav := NavGrid.new()
var bots: Array[Humanoid] = []
## target_id -> BotBrain.
var brains: Dictionary = {}
var player_health: float = PLAYER_MAX_HEALTH

var deaths: int = 0
var bot_kills: int = 0
var damage_taken: float = 0.0
var bot_shots: int = 0
var bot_hits: int = 0
var head_hits: int = 0
var body_hits: int = 0
var kill_times: PackedFloat32Array = PackedFloat32Array()
var _bot_spawn_usec: Dictionary = {}


func uses_movement() -> bool:
	return true


## Niveau des bots (0 à 1) déduit de la difficulté adaptative.
func bot_skill() -> float:
	return clampf(inverse_lerp(0.6, 1.8, difficulty), 0.0, 1.0)


## À appeler dans setup() : arme automatique et grille de navigation.
func prepare_bots() -> void:
	player.automatic = true
	player.recoil_enabled = true
	player_health = PLAYER_MAX_HEALTH
	nav.build(map_root, NAV_BOUNDS)


func spawn_bot(at: Vector3) -> BotBrain:
	var bot := HUMANOID_SCENE.instantiate() as Humanoid
	bot.target_id = _next_target_id
	_next_target_id += 1
	bot.position = Vector3(at.x, 0.0, at.z)
	add_child(bot)
	var brain := BotBrain.new()
	bot.add_child(brain)
	brain.setup(bot, player, nav, bot_skill())
	brain.shot_fired.connect(_on_bot_shot)
	bots.append(bot)
	brains[bot.target_id] = brain
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
	if not struck.apply_damage(player.weapon_damage(head)):
		return null
	var now: int = shot.get("time_usec", Time.get_ticks_usec())
	var born: int = _bot_spawn_usec.get(struck.target_id, now)
	bot_kills += 1
	kill_times.append(float(now - born) / 1000.0)
	fx.explosion(struck.head_position())
	Sfx.play(&"kill")
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
	report["bot_skill"] = bot_skill()
	report["difficulty_level"] = difficulty


func _on_bot_shot(hit: bool, origin: Vector3) -> void:
	if finished:
		return
	bot_shots += 1
	var eye := player.eye_position()
	if hit:
		bot_hits += 1
		damage_taken += BOT_DAMAGE
		player_health -= BOT_DAMAGE
		fx.tracer(origin, eye + Vector3(0.0, -0.3, 0.0))
		hud.show_feedback("TOUCHÉ · %d PV" % roundi(maxf(player_health, 0.0)), Hud.COLOR_BAD, 0.6)
		hud.flash_miss()
		Sfx.play(&"miss")
		Telemetry.log_event("player_hit", {"health": player_health})
		if player_health <= 0.0:
			deaths += 1
			player_health = PLAYER_MAX_HEALTH
			Sfx.play(&"fail")
			Telemetry.log_event("player_died", {})
			on_player_died()
	else:
		# Balle perdue : le traceur passe à côté.
		var miss := Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.2, 0.6), rng.randf_range(-0.8, 0.8))
		fx.tracer(origin, eye + miss)
