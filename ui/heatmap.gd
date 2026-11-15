extends Control
## Heatmap 2D des tirs ratés, générée dynamiquement.
##
## Chaque tir est placé par rapport au centre de la cible visée, en « rayons de
## cible » (1.0 = bord de la sphère) : la carte reste donc comparable quelle
## que soit la distance ou la taille des cibles. La densité est accumulée par
## noyaux gaussiens dans une grille, puis convertie en texture.

const GRID := 96
## Demi-étendue de la carte, en rayons de cible.
const RANGE_RADII := 3.5
## Écart-type du noyau gaussien, en rayons de cible.
const KERNEL_SIGMA := 0.28

const AXIS_COLOR := Color(1.0, 1.0, 1.0, 0.1)
const RING_COLOR := Color(1.0, 1.0, 1.0, 0.14)
const TARGET_COLOR := Color(0.0, 0.85, 1.0)
const MISS_COLOR := Color(1.0, 0.25, 0.8, 0.9)
const HIT_COLOR := Color(0.2, 0.95, 1.0, 0.28)
const LABEL_COLOR := Color(0.6, 0.68, 0.78)

var _misses: PackedVector2Array = PackedVector2Array()
var _hits: PackedVector2Array = PackedVector2Array()
var _texture: ImageTexture


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(queue_redraw)


## `misses` et `hits` : positions des tirs relatives au centre de la cible,
## en rayons de cible (x vers la droite, y vers le haut).
func set_data(misses: PackedVector2Array, hits: PackedVector2Array) -> void:
	_misses = misses
	_hits = hits
	_rebuild_texture()
	queue_redraw()


func _rebuild_texture() -> void:
	_texture = null
	if _misses.is_empty():
		return

	var density := PackedFloat32Array()
	density.resize(GRID * GRID)
	density.fill(0.0)
	var cells_per_radius := float(GRID) / (RANGE_RADII * 2.0)
	var sigma := KERNEL_SIGMA * cells_per_radius
	var reach := ceili(sigma * 3.0)
	var falloff := 1.0 / (2.0 * sigma * sigma)

	for miss in _misses:
		# Les tirs hors cadre sont ramenés sur le bord pour rester visibles.
		var gx := clampf((miss.x / RANGE_RADII * 0.5 + 0.5) * float(GRID), 0.5, float(GRID) - 0.5)
		var gy := clampf((-miss.y / RANGE_RADII * 0.5 + 0.5) * float(GRID), 0.5, float(GRID) - 0.5)
		var x_min := maxi(int(gx) - reach, 0)
		var x_max := mini(int(gx) + reach, GRID - 1)
		var y_min := maxi(int(gy) - reach, 0)
		var y_max := mini(int(gy) + reach, GRID - 1)
		for y in range(y_min, y_max + 1):
			var dy := float(y) + 0.5 - gy
			for x in range(x_min, x_max + 1):
				var dx := float(x) + 0.5 - gx
				density[y * GRID + x] += exp(-(dx * dx + dy * dy) * falloff)

	var peak := 0.0
	for value in density:
		peak = maxf(peak, value)
	if peak <= 0.0:
		return

	var pixels := PackedByteArray()
	pixels.resize(GRID * GRID * 4)
	for index in GRID * GRID:
		var color := _heat_color(density[index] / peak)
		pixels[index * 4] = color.r8
		pixels[index * 4 + 1] = color.g8
		pixels[index * 4 + 2] = color.b8
		pixels[index * 4 + 3] = color.a8
	var image := Image.create_from_data(GRID, GRID, false, Image.FORMAT_RGBA8, pixels)
	_texture = ImageTexture.create_from_image(image)


## Dégradé : transparent → bleu nuit → cyan → magenta → blanc chaud.
func _heat_color(intensity: float) -> Color:
	var t := clampf(intensity, 0.0, 1.0)
	if t < 0.08:
		return Color(0.0, 0.2, 0.5, 0.0).lerp(Color(0.0, 0.3, 0.7, 0.35), t / 0.08)
	if t < 0.4:
		return Color(0.0, 0.3, 0.7, 0.35).lerp(Color(0.0, 0.85, 1.0, 0.7), (t - 0.08) / 0.32)
	if t < 0.75:
		return Color(0.0, 0.85, 1.0, 0.7).lerp(Color(1.0, 0.2, 0.75, 0.88), (t - 0.4) / 0.35)
	return Color(1.0, 0.2, 0.75, 0.88).lerp(Color(1.0, 0.92, 0.85, 0.97), (t - 0.75) / 0.25)


func _draw() -> void:
	var side := minf(size.x, size.y)
	if side <= 8.0:
		return
	var plot := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	var center := plot.get_center()
	var unit := side * 0.5 / RANGE_RADII

	draw_rect(plot, Color(0.015, 0.025, 0.045, 0.95))
	if _texture != null:
		draw_texture_rect(_texture, plot, false)

	# Repères : axes et anneaux à 1, 2 et 3 rayons de cible.
	draw_line(Vector2(plot.position.x, center.y), Vector2(plot.end.x, center.y), AXIS_COLOR, 1.0)
	draw_line(Vector2(center.x, plot.position.y), Vector2(center.x, plot.end.y), AXIS_COLOR, 1.0)
	for index in range(2, 4):
		draw_arc(center, unit * float(index), 0.0, TAU, 96, RING_COLOR, 1.0, true)

	# Silhouette de la cible.
	draw_circle(center, unit, Color(TARGET_COLOR.r, TARGET_COLOR.g, TARGET_COLOR.b, 0.1))
	draw_arc(center, unit, 0.0, TAU, 96, TARGET_COLOR, 2.0, true)

	for hit in _hits:
		draw_circle(_plot_point(hit, center, unit, plot), 2.0, HIT_COLOR)
	for miss in _misses:
		var point := _plot_point(miss, center, unit, plot)
		draw_circle(point, 3.5, Color(0.0, 0.0, 0.0, 0.55))
		draw_circle(point, 2.5, MISS_COLOR)

	draw_rect(plot, Color(0.0, 0.85, 1.0, 0.3), false, 1.0)

	var font := get_theme_default_font()
	var font_size := 13
	draw_string(font, plot.position + Vector2(8.0, 18.0), "HAUT", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, LABEL_COLOR)
	draw_string(font, Vector2(plot.position.x + 8.0, plot.end.y - 8.0), "BAS", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, LABEL_COLOR)
	draw_string(font, Vector2(plot.position.x + 8.0, center.y - 6.0), "GAUCHE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, LABEL_COLOR)
	draw_string(font, Vector2(plot.end.x - 64.0, center.y - 6.0), "DROITE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, LABEL_COLOR)
	draw_string(font, center + Vector2(unit * 0.72 + 4.0, -unit * 0.72 - 4.0), "cible", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, TARGET_COLOR)
	draw_string(font, center + Vector2(4.0, -unit * 2.0 - 4.0), "2 R", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, LABEL_COLOR)
	draw_string(font, center + Vector2(4.0, -unit * 3.0 - 4.0), "3 R", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, LABEL_COLOR)

	if _misses.is_empty():
		draw_string(font, Vector2(plot.position.x, plot.end.y - 34.0), "Aucun tir raté : rien à afficher", HORIZONTAL_ALIGNMENT_CENTER, side, 16, LABEL_COLOR)


## Position à l'écran d'un tir exprimé en rayons de cible (bornée au cadre).
func _plot_point(offset: Vector2, center: Vector2, unit: float, plot: Rect2) -> Vector2:
	var point: Vector2 = center + Vector2(offset.x, -offset.y) * unit
	point.x = clampf(point.x, plot.position.x + 3.0, plot.end.x - 3.0)
	point.y = clampf(point.y, plot.position.y + 3.0, plot.end.y - 3.0)
	return point
