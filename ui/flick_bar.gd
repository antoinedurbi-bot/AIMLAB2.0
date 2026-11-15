extends Control
## Barre empilée : répartition des flicks en underflick / précis / overflick.

const UNDER_COLOR := Color(1.0, 0.62, 0.1)
const PRECISE_COLOR := Color(0.0, 0.85, 1.0)
const OVER_COLOR := Color(1.0, 0.2, 0.75)
const TEXT_COLOR := Color(0.01, 0.03, 0.05)

var _under: float = 0.0
var _precise: float = 0.0
var _over: float = 0.0


## Définit la répartition (nombres de flicks ou pourcentages, peu importe l'unité).
func set_distribution(under: float, precise: float, over: float) -> void:
	_under = maxf(under, 0.0)
	_precise = maxf(precise, 0.0)
	_over = maxf(over, 0.0)
	queue_redraw()


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 1.0, 0.06))
	var total := _under + _precise + _over
	if total <= 0.0:
		var font := get_theme_default_font()
		var font_size := 15
		var baseline := (size.y + float(font_size)) * 0.5 - 2.0
		draw_string(font, Vector2(12.0, baseline), "Pas assez de flicks analysables", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.6, 0.68, 0.78))
		return
	var cursor := 0.0
	cursor = _draw_segment(cursor, _under / total, UNDER_COLOR, "UNDER")
	cursor = _draw_segment(cursor, _precise / total, PRECISE_COLOR, "PRÉCIS")
	_draw_segment(cursor, _over / total, OVER_COLOR, "OVER")


## Dessine un segment et renvoie l'abscisse de fin.
func _draw_segment(start_x: float, share: float, color: Color, caption: String) -> float:
	var width := size.x * share
	if width <= 0.0:
		return start_x
	draw_rect(Rect2(start_x, 0.0, width, size.y), color)
	var font := get_theme_default_font()
	var font_size := 15
	var text := "%s %d %%" % [caption, roundi(share * 100.0)]
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	if text_width + 16.0 <= width:
		var baseline := (size.y + float(font_size)) * 0.5 - 2.0
		draw_string(font, Vector2(start_x + (width - text_width) * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, TEXT_COLOR)
	return start_x + width
