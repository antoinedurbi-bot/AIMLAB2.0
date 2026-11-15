extends "res://scripts/drills/pre_aim_drill.gd"
## Attaque / reprise de site sur une grande carte : un site est tiré au sort,
## `angle_count` cibles y sont cachées parmi les positions candidates de la
## carte (repères « SiteX_01 », « SiteX_02 »...). Le joueur part du lobby qui
## mène au site (attaque) ou du spawn des défenseurs (reprise) et doit nettoyer
## le site. Mêmes mesures que la pré-visée : écart viseur → tête à la découverte
## de chaque cible, temps pour abattre, tirs en mouvement.

## Vrai : départ du spawn des défenseurs (reprise). Faux : départ du lobby (attaque).
var retake: bool = false
## Distance minimale entre deux cibles (m).
var min_spacing: float = 4.0

## Si > 0 : une charge explose après ce délai (s). Il faut nettoyer le site puis
## la désamorcer (ESPACE, immobile au centre du site pendant `defuse_seconds`).
var charge_seconds: float = 0.0
var defuse_seconds: float = 7.0
var defuse_radius: float = 4.0

const Bomb := preload("res://scripts/bomb.gd")
const BOMB_SCENE: PackedScene = preload("res://scenes/bomb.tscn")

var _site: String = ""
var _bomb: Bomb
var _defusing: bool = false
var _defuse_progress: float = 0.0
var _defused: bool = false


func spawn_marker() -> String:
	if _site == "":
		_choose_site()
	return "DefenderSpawn" if retake else "Lobby" + _site


func setup() -> void:
	if _site == "":
		_choose_site()
	var pool: Array[Vector3] = []
	var index := 1
	while has_marker("Site%s_%02d" % [_site, index]):
		pool.append(marker("Site%s_%02d" % [_site, index]))
		index += 1
	# Tirage sans remise, en écartant les positions trop proches d'une cible déjà placée.
	var placed: Array[Vector3] = []
	while placed.size() < angle_count and not pool.is_empty():
		var pick := rng.randi_range(0, pool.size() - 1)
		var candidate := pool[pick]
		pool.remove_at(pick)
		var too_close := false
		for other in placed:
			if other.distance_to(candidate) < min_spacing:
				too_close = true
		if not too_close:
			placed.append(candidate)
			_targets.append(spawn_target(candidate, target_radius))
	angle_count = placed.size()

	if charge_seconds > 0.0:
		duration = charge_seconds
		# La charge est posée au centre du site : on la voit clignoter et on l'entend biper.
		_bomb = BOMB_SCENE.instantiate() as Bomb
		_bomb.fuse_seconds = charge_seconds
		_bomb.defuse_seconds = defuse_seconds
		_bomb.position = marker("Site" + _site)
		add_child(_bomb)
	var action := "Reprends" if retake else "Attaque"
	hud.set_objective("%s le site %s (lettre magenta au-dessus du site) : %d cibles à hauteur de tête y sont cachées." % [action, _site, angle_count])
	hud.set_speed_gauge_visible(true)
	hud.set_side_stat("SITE %s" % _site, "0 / %d" % angle_count)
	if charge_seconds > 0.0:
		hud.set_objective("Charge posée sur le site %s : nettoie-le (%d cibles), puis ESPACE au centre du site, immobile %d s. Explosion à %d s." % [
			_site, angle_count, roundi(defuse_seconds), roundi(charge_seconds)])


func begin() -> void:
	if _bomb != null:
		_bomb.arm()


func update(delta: float) -> void:
	super.update(delta)
	if _bomb != null:
		_bomb.set_defusing(_defusing, true)
	if charge_seconds <= 0.0 or not _defusing:
		return
	var away := player.global_position.distance_to(marker("Site" + _site)) > defuse_radius
	if away or player.horizontal_speed() > 0.6:
		_defusing = false
		_defuse_progress = 0.0
		hud.show_feedback("DÉSAMORÇAGE INTERROMPU", Hud.COLOR_BAD)
		return
	_defuse_progress += delta
	hud.set_side_stat("DÉSAMORÇAGE", "%.1f / %.0f s" % [_defuse_progress, defuse_seconds])
	if _defuse_progress >= defuse_seconds:
		_defused = true
		if _bomb != null:
			_bomb.stop()
		_finish_time = elapsed
		score += 300 + roundi(maxf(charge_seconds - elapsed, 0.0) * 10.0)
		hud.show_feedback("CHARGE DÉSAMORCÉE", Hud.COLOR_GOOD)
		Sfx.play(&"success")
		finished = true


func on_action() -> void:
	if charge_seconds <= 0.0 or _defusing or _defused:
		return
	if _cleared < angle_count:
		hud.show_feedback("SITE NON NETTOYÉ · %d cibles restantes" % (angle_count - _cleared), Hud.COLOR_BAD)
	elif player.global_position.distance_to(marker("Site" + _site)) > defuse_radius:
		hud.show_feedback("TROP LOIN · rejoins le centre du site", Hud.COLOR_INFO)
	else:
		_defusing = true
		_defuse_progress = 0.0
		Sfx.play(&"beep")
		Telemetry.log_event("defuse_start", {"elapsed": elapsed})


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	super.on_shot(collider, hit_position, hit_normal, shot)
	# Avec une charge, nettoyer le site ne termine pas la session : il reste à désamorcer.
	if charge_seconds > 0.0 and not _defused:
		finished = false


func finalize(report: Dictionary) -> void:
	super.finalize(report)
	report["site"] = _site
	if charge_seconds > 0.0:
		report["charge_seconds"] = charge_seconds
		report["defused"] = _defused
		report["defuse_margin_s"] = charge_seconds - elapsed if _defused else 0.0
		report["course_completed"] = _defused
		add_kpi(report, "CHARGE", "DÉSAMORCÉE" if _defused else "EXPLOSÉE",
				"%.1f s de marge" % (charge_seconds - elapsed) if _defused else "site nettoyé à %d / %d" % [_cleared, angle_count])


func _choose_site() -> void:
	var available := PackedStringArray()
	for letter in ["A", "B", "C"]:
		if has_marker("Site%s_01" % letter):
			available.append(letter)
	if available.is_empty():
		_site = "A"
	else:
		_site = available[rng.randi_range(0, available.size() - 1)]
