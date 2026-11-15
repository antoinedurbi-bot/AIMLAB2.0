extends RefCounted
## Petites fonctions statistiques partagées par les exercices et le coach.
## S'utilise via `const Stats := preload("res://scripts/stats.gd")`.


static func mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


static func median(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var middle := sorted_values.size() >> 1
	if sorted_values.size() % 2 == 1:
		return sorted_values[middle]
	return (sorted_values[middle - 1] + sorted_values[middle]) * 0.5


## Écart-type (population).
static func deviation(values: PackedFloat32Array) -> float:
	if values.size() < 2:
		return 0.0
	var average := mean(values)
	var total := 0.0
	for value in values:
		total += (value - average) * (value - average)
	return sqrt(total / float(values.size()))


static func minimum(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var best := values[0]
	for value in values:
		best = minf(best, value)
	return best


static func maximum(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var best := values[0]
	for value in values:
		best = maxf(best, value)
	return best


## Moyenne des valeurs absolues.
static func mean_abs(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += absf(value)
	return total / float(values.size())


## Pourcentage (0–100) de `part` dans `total`, 0 si `total` est nul.
static func percent(part: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return 100.0 * float(part) / float(total)
