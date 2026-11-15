extends Control
## Jauge de vitesse de déplacement : montre en direct si le joueur est sous le
## seuil de précision (cyan) ou encore trop rapide pour tirer juste (magenta).

const ACCURATE_COLOR := Color(0.0, 0.9, 1.0)
const MOVING_COLOR := Color(1.0, 0.25, 0.7)
const BACKGROUND_COLOR := Color(0.02, 0.03, 0.05, 0.55)

var _speed: float = 0.0
var _threshold: float = 1.5
var _maximum: float = 5.4


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## `threshold` : vitesse sous laquelle le tir est précis ; `maximum` : pleine vitesse.
func set_values(speed: float, threshold: float, maximum: float) -> void:
	if is_equal_approx(speed, _speed) and is_equal_approx(threshold, _threshold) and is_equal_approx(maximum, _maximum):
		return
	_speed = speed
	_threshold = threshold
	_maximum = maxf(maximum, 0.1)
	queue_redraw()


func _draw() -> void:
	var bar := Rect2(0.0, size.y - 10.0, size.x, 10.0)
	draw_rect(bar, BACKGROUND_COLOR)
	var accurate := _speed <= _threshold
	var color := ACCURATE_COLOR if accurate else MOVING_COLOR
	var fill := clampf(_speed / _maximum, 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), color)
	# Repère du seuil de précision.
	var threshold_x := bar.size.x * clampf(_threshold / _maximum, 0.0, 1.0)
	draw_line(Vector2(threshold_x, bar.position.y - 5.0), Vector2(threshold_x, bar.end.y + 1.0), Color.WHITE, 2.0)

	var font := get_theme_default_font()
	var font_size := 15
	var label := "%.1f m/s · %s" % [_speed, "PRÉCIS" if accurate else "EN MOUVEMENT"]
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var label_position := Vector2((size.x - label_width) * 0.5, bar.position.y - 10.0)
	draw_string_outline(font, label_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 4, Color(0.0, 0.0, 0.0, 0.7))
	draw_string(font, label_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
