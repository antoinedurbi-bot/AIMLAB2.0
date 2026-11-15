extends Control
## Réticule 2D personnalisable, dessiné au pixel près.
##
## Les dimensions de GameSettings sont en pixels physiques : on compense le
## facteur de stretch de la fenêtre et on aligne le centre sur la grille de
## pixels pour que les traits restent nets à toutes les résolutions.
## Sert aussi d'aperçu dans le menu (il se dessine au centre de son rectangle).

const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.85)

var _hit_flash: float = 0.0
var _miss_flash: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameSettings.crosshair_changed.connect(queue_redraw)
	resized.connect(queue_redraw)
	set_process(false)


func _process(delta: float) -> void:
	_hit_flash = maxf(_hit_flash - delta * 7.0, 0.0)
	_miss_flash = maxf(_miss_flash - delta * 6.0, 0.0)
	queue_redraw()
	if _hit_flash <= 0.0 and _miss_flash <= 0.0:
		set_process(false)


## Affiche brièvement le marqueur de touche (croix diagonale).
func flash_hit() -> void:
	_hit_flash = 1.0
	set_process(true)
	queue_redraw()


## Teinte brièvement le réticule pour signaler un tir raté.
func flash_miss() -> void:
	_miss_flash = 1.0
	set_process(true)
	queue_redraw()


func _draw() -> void:
	var pixel_scale := _pixel_scale()
	var to_canvas := 1.0 / pixel_scale
	var origin := global_position
	# Centre du réticule en pixels physiques, aligné sur la grille de pixels.
	var center := ((origin + size * 0.5) * pixel_scale).floor()

	var color: Color = GameSettings.crosshair_color
	color = color.lerp(Color(1.0, 0.25, 0.3), _miss_flash * 0.8)
	color.a = GameSettings.crosshair_opacity

	var style: int = GameSettings.crosshair_style
	var thickness := maxf(roundf(GameSettings.crosshair_thickness), 1.0)
	var arm_length := maxf(roundf(GameSettings.crosshair_length), 0.0)
	var gap := maxf(roundf(GameSettings.crosshair_gap), 0.0)
	var dot_size := maxf(roundf(GameSettings.crosshair_dot_size), 1.0)
	var outline: bool = GameSettings.crosshair_outline

	var rects: Array[Rect2] = []
	var has_cross := style == GameSettings.CrosshairStyle.CROSS or style == GameSettings.CrosshairStyle.CROSS_DOT
	var has_dot := style == GameSettings.CrosshairStyle.CROSS_DOT or style == GameSettings.CrosshairStyle.DOT \
			or style == GameSettings.CrosshairStyle.CIRCLE
	if has_cross and arm_length > 0.0:
		var half := floorf(thickness * 0.5)
		# Avec une épaisseur impaire, le trait central occupe le pixel [0, 1[ :
		# les branches droite et basse sont décalées d'un pixel pour rester symétriques.
		var odd := thickness - half * 2.0
		rects.append(Rect2(gap + odd, -half, arm_length, thickness))
		rects.append(Rect2(-gap - arm_length, -half, arm_length, thickness))
		rects.append(Rect2(-half, gap + odd, thickness, arm_length))
		rects.append(Rect2(-half, -gap - arm_length, thickness, arm_length))
	if has_dot:
		var dot_half := floorf(dot_size * 0.5)
		rects.append(Rect2(-dot_half, -dot_half, dot_size, dot_size))

	if outline:
		var outline_color := OUTLINE_COLOR
		outline_color.a *= color.a
		for rect in rects:
			draw_rect(_to_local_rect(rect.grow(1.0), center, origin, to_canvas), outline_color)
	for rect in rects:
		draw_rect(_to_local_rect(rect, center, origin, to_canvas), color)

	var local_center := center * to_canvas - origin
	if style == GameSettings.CrosshairStyle.CIRCLE:
		var radius := (gap + arm_length) * to_canvas
		if outline:
			draw_arc(local_center, radius, 0.0, TAU, 64, Color(0.0, 0.0, 0.0, 0.6 * color.a), (thickness + 2.0) * to_canvas, true)
		draw_arc(local_center, radius, 0.0, TAU, 64, color, thickness * to_canvas, true)

	if _hit_flash > 0.0:
		_draw_hit_marker(local_center, to_canvas)


func _draw_hit_marker(local_center: Vector2, to_canvas: float) -> void:
	var marker_color := Color(1.0, 1.0, 1.0, _hit_flash)
	var inner := (10.0 + (1.0 - _hit_flash) * 6.0) * to_canvas
	var outer := inner + 9.0 * to_canvas
	for index in 4:
		var direction := Vector2.from_angle(PI * 0.25 + float(index) * PI * 0.5)
		draw_line(local_center + direction * inner, local_center + direction * outer, marker_color, 2.0 * to_canvas, true)


## Convertit un rectangle exprimé en pixels physiques autour du centre vers
## l'espace local du Control.
func _to_local_rect(rect: Rect2, center: Vector2, origin: Vector2, to_canvas: float) -> Rect2:
	return Rect2((center + rect.position) * to_canvas - origin, rect.size * to_canvas)


## Nombre de pixels physiques par unité de canvas (stretch « canvas_items »).
func _pixel_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var visible_width := get_viewport_rect().size.x
	var window_width := float(get_window().size.x)
	if visible_width <= 0.0 or window_width <= 0.0:
		return 1.0
	return window_width / visible_width
