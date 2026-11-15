extends RefCounted
## Programme adaptatif : construit la routine du jour (environ 25 minutes) à
## partir du dernier diagnostic. La compétence la plus faible reçoit le plus de
## sessions, la suivante un peu moins ; un socle fixe couvre le déplacement et
## le placement, qui comptent autant que la visée dans un FPS tactique.

## Exercices qui travaillent chaque compétence du diagnostic, par ordre de priorité.
const SKILL_DRILLS := {
	"flick": ["gridshot", "microflick"],
	"tracking": ["duel", "multi_target"],
	"reaction": ["angle_hold", "peek_duel"],
	"spray": ["multi_target", "tap_burst"],
}
## Durée comptée par session, compte à rebours et lecture du rapport compris (minutes).
const MINUTES_PER_SESSION := 1.5


## Renvoie la routine : [{drill_id, sessions, reason}]. `ordered_skills` : compétences
## de la plus faible à la plus forte (PlayerProfile.skills_by_weakness()).
static func build(ordered_skills: Array[String], has_benchmark: bool) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	_add(plan, "gridshot", 2, "Échauffement")
	if has_benchmark and ordered_skills.size() >= 2:
		var weakest: Array = SKILL_DRILLS.get(ordered_skills[0], [])
		var second: Array = SKILL_DRILLS.get(ordered_skills[1], [])
		if weakest.size() >= 2:
			_add(plan, str(weakest[0]), 4, "Point faible n°1")
			_add(plan, str(weakest[1]), 2, "Point faible n°1")
		if not second.is_empty():
			_add(plan, str(second[0]), 2, "Point faible n°2")
	else:
		_add(plan, "microflick", 2, "Visée")
		_add(plan, "duel", 3, "Duels")
	_add(plan, "counter_strafe", 2, "Socle : arrêt avant le tir")
	_add(plan, "pre_aim", 2, "Socle : placement du viseur")
	_add(plan, "angle_hold", 2, "Socle : tenue d'angle")
	return plan


static func total_minutes(plan: Array[Dictionary]) -> float:
	var sessions := 0
	for item in plan:
		sessions += int(item.get("sessions", 0))
	return float(sessions) * MINUTES_PER_SESSION


## Ajoute des sessions à un exercice déjà présent, sinon crée la ligne.
static func _add(plan: Array[Dictionary], drill_id: String, sessions: int, reason: String) -> void:
	for item in plan:
		if item.get("drill_id", "") == drill_id:
			item["sessions"] = int(item.get("sessions", 0)) + sessions
			return
	plan.append({"drill_id": drill_id, "sessions": sessions, "reason": reason})
