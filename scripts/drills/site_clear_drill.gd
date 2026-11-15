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

var _site: String = ""


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

	var action := "Reprends" if retake else "Attaque"
	hud.set_objective("%s le site %s (lettre magenta au-dessus du site) : %d cibles à hauteur de tête y sont cachées." % [action, _site, angle_count])
	hud.set_speed_gauge_visible(true)
	hud.set_side_stat("SITE %s" % _site, "0 / %d" % angle_count)


func finalize(report: Dictionary) -> void:
	super.finalize(report)
	report["site"] = _site


func _choose_site() -> void:
	var available := PackedStringArray()
	for letter in ["A", "B", "C"]:
		if has_marker("Site%s_01" % letter):
			available.append(letter)
	if available.is_empty():
		_site = "A"
	else:
		_site = available[rng.randi_range(0, available.size() - 1)]
