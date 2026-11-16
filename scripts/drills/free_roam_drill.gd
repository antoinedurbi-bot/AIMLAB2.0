extends "res://scripts/drills/drill_base.gd"
## Exploration libre : aucune cible, aucun score. Sert à apprendre une carte
## (trajets, angles, temps de rotation) ; la télémétrie enregistre le parcours.

func uses_movement() -> bool:
	return true


func ends_on_cancel() -> bool:
	return true


func spawn_marker() -> String:
	return "AttackerSpawn"


func setup() -> void:
	hud.set_objective("Exploration libre · Échap pour terminer")
	hud.set_speed_gauge_visible(true)
	hud.set_side_stat("DISTANCE", "0 m")


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	shots += 1
	record_shot(false, null, shot)
	if collider != null:
		fx.impact(hit_position, hit_normal)


func update(_delta: float) -> void:
	hud.set_speed(player.horizontal_speed(), PlayerController.ACCURATE_SPEED, PlayerController.RUN_SPEED)


func finalize(report: Dictionary) -> void:
	var distance: float = report.get("distance_moved_m", 0.0)
	var moving: float = report.get("moving_time_ratio", 0.0)
	var average_speed: float = report.get("avg_move_speed", 0.0)
	add_kpi(report, "DISTANCE PARCOURUE", "%d m" % roundi(distance), "pendant l'exploration")
	add_kpi(report, "TEMPS EN MOUVEMENT", "%d %%" % roundi(moving), "du temps de session")
	add_kpi(report, "VITESSE MOYENNE", "%.1f m/s" % average_speed, "en déplacement")
	set_panels(report, [])
