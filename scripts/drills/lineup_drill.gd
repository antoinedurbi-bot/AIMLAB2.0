extends "res://scripts/drills/drill_base.gd"
## Lineups : une zone cible est marquée sur un site (anneau au sol et repère en
## hauteur). Il faut y faire atterrir un incendiaire lancé à la main, depuis
## l'endroit de ton choix. Chaque lancer réussi est enregistré comme lineup
## (position, orientation et inclinaison du viseur) et rappelé aux sessions
## suivantes. Utilitaires illimités ; le fumigène se pose depuis la mini-carte (1).
##
## Mesures : lancers, réussites, écart moyen à la cible, meilleur lancer.

const UtilityKit := preload("res://scripts/utility/utility_kit.gd")

## Rayon (m) dans lequel un lancer compte comme réussi.
var success_radius: float = 2.0
var targets_per_session: int = 4

var _kit: UtilityKit
var _site: String = ""
var _target: Vector3 = Vector3.ZERO
var _target_index: int = 0
var _target_name: String = ""
var _ring: MeshInstance3D
var _label: Label3D
var _stand_marker: MeshInstance3D

var _throws: int = 0
var _successes: int = 0
var _errors: PackedFloat32Array = PackedFloat32Array()
## Position et visée du joueur au moment du dernier lancer d'incendiaire.
var _last_throw: Dictionary = {}


func uses_movement() -> bool:
	return true


func uses_fire() -> bool:
	return false


func spawn_marker() -> String:
	if _site == "":
		_choose_site()
	return "Lobby" + _site


func setup() -> void:
	if _site == "":
		_choose_site()
	_kit = UtilityKit.new()
	add_child(_kit)
	_kit.start(player, hud, map_root, -1)
	_kit.detonated.connect(_on_utility_detonated)
	player.utility_throw_requested.connect(_on_throw_requested)
	hud.set_speed_gauge_visible(false)
	hud.set_side_stat("LINEUPS", "0 / %d" % targets_per_session)
	_next_target()


func finalize(report: Dictionary) -> void:
	report["lineup_throws"] = _throws
	report["lineup_successes"] = _successes
	report["lineup_success_rate"] = Stats.percent(_successes, _throws)
	report["lineup_mean_error_m"] = Stats.mean(_errors)
	report["lineup_best_error_m"] = Stats.minimum(_errors)
	report["smokes_placed"] = _kit.throws[UtilityKit.Kind.SMOKE]
	add_kpi(report, "LINEUPS TROUVÉS", "%d / %d" % [_successes, targets_per_session], "enregistrés pour les prochaines sessions")
	add_kpi(report, "LANCERS", str(_throws), "%d %% de réussite" % roundi(Stats.percent(_successes, _throws)))
	add_kpi(report, "ÉCART MOYEN", "%.1f m" % Stats.mean(_errors) if _throws > 0 else "—", "à la cible, tous lancers confondus")
	add_kpi(report, "MEILLEUR LANCER", "%.1f m" % Stats.minimum(_errors) if _throws > 0 else "—", "réussi sous %.1f m" % success_radius)
	set_chart(report, "ÉCART À LA CIBLE PAR LANCER (m)", _errors, "m", success_radius, true)
	set_panels(report, ["chart"])


# ---------------------------------------------------------------------------

func _choose_site() -> void:
	var available := PackedStringArray()
	for letter in ["A", "B", "C"]:
		if has_marker("Site%s_01" % letter):
			available.append(letter)
	_site = "A" if available.is_empty() else available[rng.randi_range(0, available.size() - 1)]


func _next_target() -> void:
	if _target_index >= targets_per_session:
		finished = true
		return
	# Cibles : positions candidates du site, espacées (1, 5, 9, 13).
	var marker_index := 1 + _target_index * 4
	_target_name = "Site%s_%02d" % [_site, marker_index]
	if not has_marker(_target_name):
		_target_name = "Site%s_01" % _site
	var spot := marker(_target_name)
	_target = Vector3(spot.x, 0.0, spot.z)
	_target_index += 1
	_show_target()

	var saved: Dictionary = PlayerProfile.lineup(str(map_root.name), _target_name)
	if saved.is_empty():
		hud.set_objective("Cible %d / %d · incendiaire dans la zone (%s puis %s)" % [
			_target_index, targets_per_session, GameSettings.key_label("util2"), GameSettings.key_label("throw")])
		_stand_marker.visible = false
	else:
		var stand := Vector3(float(saved.get("x", 0.0)), 0.0, float(saved.get("z", 0.0)))
		_stand_marker.position = stand + Vector3(0.0, 0.03, 0.0)
		_stand_marker.visible = true
		hud.set_objective("Cible %d / %d · lineup connu : disque cyan, %.0f° / %.0f°" % [
			_target_index, targets_per_session, float(saved.get("yaw", 0.0)), float(saved.get("pitch", 0.0))])


func _show_target() -> void:
	if _ring == null:
		var torus := TorusMesh.new()
		torus.inner_radius = success_radius - 0.12
		torus.outer_radius = success_radius
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.BLACK
		material.emission_enabled = true
		material.emission = Color(1.0, 0.5, 0.1)
		material.emission_energy_multiplier = 3.0
		torus.material = material
		_ring = MeshInstance3D.new()
		_ring.mesh = torus
		add_child(_ring)
		_label = Label3D.new()
		_label.text = "CIBLE"
		_label.font_size = 96
		_label.pixel_size = 0.03
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.modulate = Color(1.0, 0.6, 0.15)
		add_child(_label)
		var disc := CylinderMesh.new()
		disc.top_radius = 0.5
		disc.bottom_radius = 0.5
		disc.height = 0.05
		var disc_material := StandardMaterial3D.new()
		disc_material.albedo_color = Color.BLACK
		disc_material.emission_enabled = true
		disc_material.emission = Color(0.0, 0.9, 1.0)
		disc_material.emission_energy_multiplier = 2.5
		disc.material = disc_material
		_stand_marker = MeshInstance3D.new()
		_stand_marker.mesh = disc
		_stand_marker.visible = false
		add_child(_stand_marker)
	_ring.position = _target + Vector3(0.0, 0.08, 0.0)
	_label.position = _target + Vector3(0.0, 8.5, 0.0)


func _on_throw_requested(_origin: Vector3, _direction: Vector3) -> void:
	_last_throw = {
		"x": player.global_position.x, "z": player.global_position.z,
		"yaw": wrapf(player.yaw_deg, -180.0, 180.0), "pitch": player.pitch_deg,
	}


func _on_utility_detonated(kind: int, at: Vector3) -> void:
	if kind != UtilityKit.Kind.INCENDIARY or finished:
		return
	var error := Vector2(at.x - _target.x, at.z - _target.z).length()
	_throws += 1
	_errors.append(error)
	Telemetry.log_event("lineup_throw", {"target": _target_name, "error_m": error})
	if error > success_radius:
		hud.show_feedback("À %.1f m de la cible" % error, Hud.COLOR_BAD)
		return
	_successes += 1
	score += 200 + roundi(100.0 * (1.0 - error / success_radius))
	PlayerProfile.save_lineup(str(map_root.name), _target_name, _last_throw)
	hud.show_feedback("LINEUP ENREGISTRÉ · %.1f m" % error, Hud.COLOR_GOOD, 2.0)
	hud.set_side_stat("LINEUPS", "%d / %d" % [_successes, targets_per_session])
	Sfx.play(&"success")
	_next_target()
