extends Node
## Autoload « SessionHistory » : historique persistant des sessions.
##
## Chaque session terminée y dépose toutes ses statistiques scalaires (nombres,
## booléens, textes). Le coach et le menu s'en servent pour comparer une session
## aux précédentes (record, moyenne récente, progression).

const SAVE_PATH := "user://history.json"
const MAX_ENTRIES := 2000

var _entries: Array[Dictionary] = []


func _ready() -> void:
	_load()


## Enregistre une session. Seules les valeurs scalaires du rapport sont conservées.
func add_session(drill_id: String, report: Dictionary) -> void:
	var entry := {
		"drill": drill_id,
		"date": Time.get_datetime_string_from_system(),
		"unix": Time.get_unix_time_from_system(),
	}
	for key: Variant in report:
		var value: Variant = report[key]
		if value is int or value is bool or value is String:
			entry[str(key)] = value
		elif value is float:
			var number: float = value
			if is_finite(number):
				entry[str(key)] = number
	_entries.append(entry)
	while _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	_save()


## Sessions les plus récentes d'un exercice, la plus récente en premier.
func recent(drill_id: String, count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var index := _entries.size() - 1
	while index >= 0 and result.size() < count:
		var entry := _entries[index]
		if entry.get("drill", "") == drill_id:
			result.append(entry)
		index -= 1
	return result


func session_count(drill_id: String) -> int:
	var total := 0
	for entry in _entries:
		if entry.get("drill", "") == drill_id:
			total += 1
	return total


## Meilleur score enregistré pour un exercice (0 si aucune session).
func best_score(drill_id: String) -> int:
	var best := 0
	for entry in _entries:
		if entry.get("drill", "") == drill_id:
			var score: int = int(entry.get("score", 0))
			best = maxi(best, score)
	return best


## Moyenne d'une statistique sur des sessions (clé absente = session ignorée).
## Renvoie NAN si aucune session ne contient la clé.
static func average(sessions: Array[Dictionary], key: String) -> float:
	var total := 0.0
	var samples := 0
	for entry in sessions:
		var value: Variant = entry.get(key)
		if value is float or value is int:
			var number: float = value
			total += number
			samples += 1
	if samples == 0:
		return NAN
	return total / float(samples)


func _load() -> void:
	_entries.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (parsed is Array):
		return
	var items: Array = parsed
	for item: Variant in items:
		if item is Dictionary:
			var entry: Dictionary = item
			_entries.append(entry)


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("KINETIC // AIM : impossible d'enregistrer %s." % SAVE_PATH)
		return
	file.store_string(JSON.stringify(_entries))
	file.close()
