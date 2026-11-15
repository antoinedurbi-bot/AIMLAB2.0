extends Node
## Autoload « PlayerProfile » : profil d'entraînement persistant (user://profile.json).
##
## Contient les diagnostics passés (un score sur 100 par compétence), le niveau
## de difficulté atteint dans chaque exercice et l'avancement de la routine du jour.

signal changed

const SAVE_PATH := "user://profile.json"
const SKILLS := ["flick", "tracking", "reaction", "spray"]
const SKILL_NAMES := {
	"flick": "Flick",
	"tracking": "Tracking",
	"reaction": "Réaction",
	"spray": "Contrôle du spray",
}
const MIN_DIFFICULTY := 0.6
const MAX_DIFFICULTY := 1.8

var _data: Dictionary = {"benchmarks": [], "difficulty": {}, "routine_date": "", "routine_done": {}}


func _ready() -> void:
	_load()


# --- Diagnostics ---

## Enregistre un diagnostic : `scores` associe chaque compétence de SKILLS à une note sur 100.
func add_benchmark(scores: Dictionary) -> void:
	var entry := {"date": Time.get_datetime_string_from_system()}
	var total := 0.0
	for skill: String in SKILLS:
		var value: float = scores.get(skill, 0.0)
		entry[skill] = value
		total += value
	entry["overall"] = total / float(SKILLS.size())
	var list: Array = _data.get("benchmarks", [])
	list.append(entry)
	_data["benchmarks"] = list
	_save()
	changed.emit()


func has_benchmark() -> bool:
	var list: Array = _data.get("benchmarks", [])
	return not list.is_empty()


## Dernier diagnostic, ou un dictionnaire vide.
func latest_benchmark() -> Dictionary:
	var list: Array = _data.get("benchmarks", [])
	if list.is_empty():
		return {}
	var entry: Dictionary = list[list.size() - 1]
	return entry


## Compétences du dernier diagnostic, de la plus faible à la plus forte.
func skills_by_weakness() -> Array[String]:
	var latest := latest_benchmark()
	var ordered: Array[String] = []
	for skill: String in SKILLS:
		ordered.append(skill)
	if latest.is_empty():
		return ordered
	for i in ordered.size():
		for j in range(i + 1, ordered.size()):
			var first: float = latest.get(ordered[i], 0.0)
			var second: float = latest.get(ordered[j], 0.0)
			if second < first:
				var swap := ordered[i]
				ordered[i] = ordered[j]
				ordered[j] = swap
	return ordered


## Profil en cinq domaines pour le graphique en pentagone : les quatre notes du
## dernier diagnostic, plus le déplacement (part de tirs propres sur les trois
## dernières sessions de strafe / contre-strafe). -1 = domaine pas encore évalué.
func radar_values() -> PackedFloat32Array:
	var latest := latest_benchmark()
	var values := PackedFloat32Array()
	for skill: String in SKILLS:
		var note: float = latest.get(skill, -1.0)
		values.append(note)
	var sessions: Array[Dictionary] = SessionHistory.recent("counter_strafe", 3)
	var movement: float = SessionHistory.average(sessions, "clean_rate")
	values.append(-1.0 if is_nan(movement) else movement)
	return values


func radar_labels() -> PackedStringArray:
	return PackedStringArray(["Flick", "Tracking", "Réaction", "Spray", "Déplacement"])


func skill_name(skill: String) -> String:
	return str(SKILL_NAMES.get(skill, skill))


# --- Difficulté adaptative ---

## Niveau de difficulté d'un exercice (1.0 = référence).
func difficulty(drill_id: String) -> float:
	var levels: Dictionary = _data.get("difficulty", {})
	var level: float = levels.get(drill_id, 1.0)
	return clampf(level, MIN_DIFFICULTY, MAX_DIFFICULTY)


## Ajuste la difficulté après une session. `success` (0 à 1) : au-dessus de 0,75
## l'exercice durcit de 8 %, en dessous de 0,45 il s'adoucit de 7 %.
func adjust_difficulty(drill_id: String, success: float) -> float:
	var level := difficulty(drill_id)
	if success >= 0.75:
		level *= 1.08
	elif success < 0.45:
		level *= 0.93
	level = clampf(level, MIN_DIFFICULTY, MAX_DIFFICULTY)
	var levels: Dictionary = _data.get("difficulty", {})
	levels[drill_id] = level
	_data["difficulty"] = levels
	_save()
	return level


# --- Lineups ---

## Enregistre un lineup réussi : position du joueur, orientation et inclinaison du viseur.
func save_lineup(map_key: String, target: String, data: Dictionary) -> void:
	var lineups: Dictionary = _data.get("lineups", {})
	lineups["%s/%s" % [map_key, target]] = data.duplicate()
	_data["lineups"] = lineups
	_save()


## Lineup enregistré pour cette cible, ou un dictionnaire vide.
func lineup(map_key: String, target: String) -> Dictionary:
	var lineups: Dictionary = _data.get("lineups", {})
	var entry: Variant = lineups.get("%s/%s" % [map_key, target], {})
	if entry is Dictionary:
		var saved: Dictionary = entry
		return saved
	return {}


# --- Routine du jour ---

## Nombre de sessions de cet exercice déjà faites aujourd'hui.
func sessions_today(drill_id: String) -> int:
	_roll_day()
	var done: Dictionary = _data.get("routine_done", {})
	return int(done.get(drill_id, 0))


func mark_session(drill_id: String) -> void:
	_roll_day()
	var done: Dictionary = _data.get("routine_done", {})
	done[drill_id] = int(done.get(drill_id, 0)) + 1
	_data["routine_done"] = done
	_save()
	changed.emit()


func _roll_day() -> void:
	var today := Time.get_date_string_from_system()
	if str(_data.get("routine_date", "")) != today:
		_data["routine_date"] = today
		_data["routine_done"] = {}


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary:
		var loaded: Dictionary = parsed
		for key: Variant in loaded:
			_data[key] = loaded[key]


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("KINETIC // AIM : impossible d'enregistrer %s." % SAVE_PATH)
		return
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()
