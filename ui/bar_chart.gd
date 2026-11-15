extends Control
## Graphique « une barre par répétition » : temps de réaction par cible, vitesse
## à chaque tir, erreur de chaque manche... Chaque barre est verte ou rouge selon
## qu'elle respecte ou non le seuil ; la moyenne est tracée en pointillés.

const GOOD_COLOR := Color(0.2, 0.95, 0.7)
const BAD_COLOR := Color(1.0, 0.3, 0.45)
const NEUTRAL_COLOR := Color(0.0, 0.85, 1.0)
const AXIS_COLOR := Color(1.0, 1.0, 1.0, 0.16)
const TEXT_COLOR := Color(0.62, 0.7, 0.8)
const TITLE_COLOR := Color(1.0, 0.25, 0.78)
const THRESHOLD_COLOR := Color(1.0, 1.0, 1.0, 0.75)

var _title: String = ""
var _values: PackedFloat32Array = PackedFloat32Array()
var _unit: String = ""
var _threshold: float = NAN
var _lower_is_better: bool = true
var _signed: bool = false


func _ready() -> void:
	resized.connect(queue_redraw)


## `chart` : dictionnaire produit par DrillBase.set_chart().
func set_chart(chart: Dictionary) -> void:
	_title = chart.get("title", "")
	_unit = chart.get("unit", "")
	_threshold = chart.get("threshold", NAN)
	_lower_is_better = chart.get("lower_is_better", true)
	_signed = chart.get("signed", false)
	var values: Variant = chart.get("values", PackedFloat32Array())
	if values is PackedFloat32Array:
		_values = values
	else:
		_values = PackedFloat32Array()
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_string(font, Vector2(0.0, 16.0), _title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, TITLE_COLOR)

	var plot := Rect2(6.0, 34.0, size.x - 12.0, size.y - 60.0)
	if plot.size.x <= 20.0 or plot.size.y <= 20.0:
		return
	draw_rect(plot, Color(0.015, 0.025, 0.045, 0.9))
	if _values.is_empty():
		draw_string(font, Vector2(plot.position.x, plot.get_center().y), "Aucune donnée pour cette session",
				HORIZONTAL_ALIGNMENT_CENTER, plot.size.x, 15, TEXT_COLOR)
		return

	var has_threshold := not is_nan(_threshold)
	var total := 0.0
	var lowest := _values[0]
	var highest := _values[0]
	var extent := 0.0
	for value in _values:
		total += value
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
		extent = maxf(extent, absf(value))
	var average := total / float(_values.size())
	if has_threshold:
		extent = maxf(extent, absf(_threshold))
	extent = maxf(extent * 1.12, 0.0001)

	# En mode signé le zéro est au milieu ; sinon les barres partent du bas.
	var baseline := plot.get_center().y if _signed else plot.end.y
	var scale_y := (plot.size.y * 0.5 if _signed else plot.size.y) / extent
	draw_line(Vector2(plot.position.x, baseline), Vector2(plot.end.x, baseline), AXIS_COLOR, 1.0)

	var slot := minf(plot.size.x / float(_values.size()), 46.0)
	var bar_width := maxf(slot - 3.0, 1.0)
	for index in _values.size():
		var value := _values[index]
		var bar_height := absf(value) * scale_y
		var x := plot.position.x + float(index) * slot + (slot - bar_width) * 0.5
		var top := baseline - bar_height if value >= 0.0 else baseline
		draw_rect(Rect2(x, top, bar_width, maxf(bar_height, 1.0)), _bar_color(value, has_threshold))

	if has_threshold:
		_draw_level(plot, baseline - _threshold * scale_y, THRESHOLD_COLOR, "seuil %s %s" % [_format(_threshold), _unit], font, false)
		if _signed:
			_draw_level(plot, baseline + _threshold * scale_y, THRESHOLD_COLOR, "", font, false)
	_draw_level(plot, baseline - average * scale_y, NEUTRAL_COLOR, "", font, true)

	var summary := "moyenne %s %s · min %s · max %s · %d valeurs" % [
		_format(average), _unit, _format(lowest), _format(highest), _values.size()]
	draw_string(font, Vector2(plot.position.x, size.y - 6.0), summary, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, TEXT_COLOR)


func _bar_color(value: float, has_threshold: bool) -> Color:
	if not has_threshold:
		return NEUTRAL_COLOR
	var good := false
	if _signed:
		good = absf(value) <= _threshold
	elif _lower_is_better:
		good = value <= _threshold
	else:
		good = value >= _threshold
	return GOOD_COLOR if good else BAD_COLOR


## Trace une ligne horizontale de repère (pointillée pour la moyenne).
func _draw_level(plot: Rect2, y: float, color: Color, caption: String, font: Font, dashed: bool) -> void:
	if y < plot.position.y - 1.0 or y > plot.end.y + 1.0:
		return
	var from := Vector2(plot.position.x, y)
	var to := Vector2(plot.end.x, y)
	if dashed:
		draw_dashed_line(from, to, color, 1.0, 6.0)
	else:
		draw_line(from, to, color, 1.0)
	if caption != "":
		draw_string(font, Vector2(plot.position.x + 6.0, y - 4.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, color)


func _format(value: float) -> String:
	if absf(value) >= 100.0:
		return "%d" % roundi(value)
	if absf(value) >= 10.0:
		return "%.1f" % value
	return "%.2f" % value
