extends Control
## Mini-carte tactique plein écran : plan de la carte vu de dessus (issu de la
## grille de navigation), position et regard du joueur, fumigènes actifs.
## Un clic sur une zone praticable choisit une position dans le monde.

signal position_chosen(world_position: Vector3)
signal cancelled

const NavGrid := preload("res://scripts/ai/nav_grid.gd")

const FLOOR_COLOR := Color(0.16, 0.2, 0.28)
const WALL_COLOR := Color(0.04, 0.05, 0.08)
const PLAYER_COLOR := Color(0.0, 0.9, 1.0)
const SMOKE_COLOR := Color(0.8, 0.85, 0.9, 0.55)

var _nav: NavGrid
var _texture: ImageTexture
var _player_position: Vector3 = Vector3.ZERO
var _player_yaw: float = 0.0
var _smokes: PackedVector3Array = PackedVector3Array()
var _smoke_radius: float = 4.0
var _caption: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)


## Fournit la grille de la carte (à appeler une fois).
func set_nav(nav: NavGrid) -> void:
	_nav = nav
	var cells := nav.grid_size()
	if cells.x <= 0 or cells.y <= 0:
		return
	var pixels := PackedByteArray()
	pixels.resize(cells.x * cells.y * 4)
	for y in cells.y:
		for x in cells.x:
			var color := WALL_COLOR if nav.is_cell_solid(Vector2i(x, y)) else FLOOR_COLOR
			var index := (y * cells.x + x) * 4
			pixels[index] = color.r8
			pixels[index + 1] = color.g8
			pixels[index + 2] = color.b8
			pixels[index + 3] = 255
	_texture = ImageTexture.create_from_image(Image.create_from_data(cells.x, cells.y, false, Image.FORMAT_RGBA8, pixels))


func update_state(player_position: Vector3, player_yaw_deg: float, smokes: PackedVector3Array, smoke_radius: float, caption: String) -> void:
	_player_position = player_position
	_player_yaw = player_yaw_deg
	_smokes = smokes
	_smoke_radius = smoke_radius
	_caption = caption
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT:
		cancelled.emit()
	elif button.button_index == MOUSE_BUTTON_LEFT and _nav != null:
		var world := _to_world(button.position)
		if _nav.is_walkable(world):
			position_chosen.emit(world)
	accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.01, 0.03, 0.78))
	if _nav == null or _texture == null:
		return
	var plot := _plot_rect()
	draw_texture_rect(_texture, plot, false)
	draw_rect(plot, Color(0.0, 0.85, 1.0, 0.5), false, 2.0)
	var scale_px := plot.size.x / _nav.world_size().x
	for smoke in _smokes:
		draw_circle(_to_screen(smoke), _smoke_radius * scale_px, SMOKE_COLOR)
	var player := _to_screen(_player_position)
	var yaw := deg_to_rad(_player_yaw)
	var forward := Vector2(-sin(yaw), -cos(yaw))
	draw_line(player, player + forward * 22.0, PLAYER_COLOR, 2.0, true)
	draw_circle(player, 6.0, PLAYER_COLOR)
	var font := get_theme_default_font()
	draw_string(font, Vector2(plot.position.x, plot.position.y - 14.0), _caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color.WHITE)


func _plot_rect() -> Rect2:
	var world := _nav.world_size()
	var scale_px := minf((size.x - 80.0) / world.x, (size.y - 120.0) / world.y)
	var plot_size := world * scale_px
	return Rect2((size - plot_size) * 0.5 + Vector2(0.0, 20.0), plot_size)


func _to_screen(world_position: Vector3) -> Vector2:
	var plot := _plot_rect()
	var origin := _nav.world_origin()
	var world := _nav.world_size()
	return plot.position + Vector2((world_position.x - origin.x) / world.x, (world_position.z - origin.y) / world.y) * plot.size


func _to_world(screen_position: Vector2) -> Vector3:
	var plot := _plot_rect()
	var origin := _nav.world_origin()
	var world := _nav.world_size()
	var ratio := (screen_position - plot.position) / plot.size
	return Vector3(origin.x + ratio.x * world.x, 0.0, origin.y + ratio.y * world.y)
