extends Control
## Profil du joueur en pentagone : un axe par domaine, noté de 0 (centre) à 100
## (sommet). Chaque triangle du polygone s'étire vers son sommet à mesure que le
## joueur progresse dans ce domaine. Un domaine jamais évalué est affiché en gris.

const RING_COLOR := Color(1.0, 1.0, 1.0, 0.12)
const AXIS_COLOR := Color(1.0, 1.0, 1.0, 0.2)
const FILL_COLOR := Color(0.0, 0.85, 1.0, 0.28)
const EDGE_COLOR := Color(0.0, 0.9, 1.0)
const WEAK_COLOR := Color(1.0, 0.3, 0.75)
const LABEL_COLOR := Color(0.82, 0.88, 0.95)
const MISSING_COLOR := Color(0.5, 0.55, 0.62)

var _labels: PackedStringArray = PackedStringArray()
## Notes de 0 à 100 ; une valeur négative signifie « pas encore évalué ».
var _values: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## `labels` et `values` ont la même taille (cinq pour un pentagone).
func set_profile(labels: PackedStringArray, values: PackedFloat32Array) -> void:
	_labels = labels
	_values = values
	queue_redraw()


func _draw() -> void:
	var count := _values.size()
	if count < 3 or _labels.size() != count:
		return
	var center := size * 0.5 + Vector2(0.0, 6.0)
	var radius := minf(size.x * 0.5 - 110.0, size.y * 0.5 - 34.0)
	if radius < 20.0:
		return

	# Anneaux de repère à 25, 50, 75 et 100.
	for ring in range(1, 5):
		var ring_points := PackedVector2Array()
		for index in count + 1:
			ring_points.append(center + _direction(index % count, count) * radius * float(ring) * 0.25)
		draw_polyline(ring_points, RING_COLOR, 1.0, true)
	for index in count:
		draw_line(center, center + _direction(index, count) * radius, AXIS_COLOR, 1.0, true)

	# Polygone du joueur : chaque sommet est à (note / 100) du rayon.
	var weakest := -1
	var points := PackedVector2Array()
	for index in count:
		var value := clampf(_values[index], 0.0, 100.0)
		# Un minimum visible évite un polygone dégénéré quand une note vaut zéro.
		points.append(center + _direction(index, count) * radius * maxf(value, 4.0) / 100.0)
		if _values[index] >= 0.0 and (weakest < 0 or _values[index] < _values[weakest]):
			weakest = index
	draw_colored_polygon(points, FILL_COLOR)
	for index in count:
		draw_line(center, points[index], Color(0.0, 0.9, 1.0, 0.25), 1.0, true)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, EDGE_COLOR, 2.0, true)

	var font := get_theme_default_font()
	for index in count:
		var evaluated := _values[index] >= 0.0
		var color := LABEL_COLOR
		if not evaluated:
			color = MISSING_COLOR
		elif index == weakest:
			color = WEAK_COLOR
		draw_circle(points[index], 4.0, color)
		var text := "%s  %s" % [_labels[index], "%d" % roundi(_values[index]) if evaluated else "—"]
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14)
		var direction := _direction(index, count)
		var anchor := center + direction * (radius + 14.0)
		# Le texte est décalé du côté extérieur de son sommet.
		var offset_x := -text_size.x * 0.5 + direction.x * text_size.x * 0.5
		draw_string(font, anchor + Vector2(offset_x, 5.0 + direction.y * 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, color)


## Direction unitaire du sommet `index` (le premier est en haut, sens horaire).
func _direction(index: int, count: int) -> Vector2:
	return Vector2.from_angle(-PI * 0.5 + TAU * float(index) / float(count))
