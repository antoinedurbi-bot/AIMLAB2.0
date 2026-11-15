extends RefCounted
## Grille de navigation d'une carte graybox, pour la recherche de chemin des bots.
##
## La grille (cellules de 1 m) est construite à partir des boîtes de collision
## de la carte (nœud « Collision ») : toute boîte plus haute qu'une marche rend
## ses cellules infranchissables, élargies du rayon d'un bot. Les chemins sont
## calculés par A* (AStarGrid2D) puis renvoyés en coordonnées du monde.

const CELL := 1.0
## Hauteur (m) au-dessus de laquelle un obstacle bloque le passage.
const STEP_HEIGHT := 0.3
## Marge ajoutée autour des obstacles (rayon d'un bot).
const AGENT_RADIUS := 0.4

var _grid := AStarGrid2D.new()
var _origin: Vector2 = Vector2.ZERO
var _size: Vector2i = Vector2i.ZERO
var ready: bool = false


## Construit la grille sur `bounds` (x, z en mètres) à partir des collisions de `map_root`.
func build(map_root: Node3D, bounds: Rect2) -> void:
	_origin = bounds.position
	_size = Vector2i(ceili(bounds.size.x / CELL), ceili(bounds.size.y / CELL))
	_grid.region = Rect2i(Vector2i.ZERO, _size)
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()

	var collision := map_root.get_node_or_null(^"Collision")
	if collision == null:
		return
	for child in collision.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null:
			continue
		var half := Vector3.ZERO
		var box := shape_node.shape as BoxShape3D
		var cylinder := shape_node.shape as CylinderShape3D
		if box != null:
			half = box.size * 0.5
		elif cylinder != null:
			half = Vector3(cylinder.radius, cylinder.height * 0.5, cylinder.radius)
		else:
			continue
		var center := shape_node.global_position
		if center.y + half.y <= STEP_HEIGHT:
			continue
		var low := _cell(Vector3(center.x - half.x - AGENT_RADIUS, 0.0, center.z - half.z - AGENT_RADIUS))
		var high := _cell(Vector3(center.x + half.x + AGENT_RADIUS, 0.0, center.z + half.z + AGENT_RADIUS))
		for y in range(maxi(low.y, 0), mini(high.y, _size.y - 1) + 1):
			for x in range(maxi(low.x, 0), mini(high.x, _size.x - 1) + 1):
				_grid.set_point_solid(Vector2i(x, y), true)
	ready = true


## Dimensions de la grille en cellules, et emprise dans le monde (x, z en mètres).
func grid_size() -> Vector2i:
	return _size


func world_origin() -> Vector2:
	return _origin


func world_size() -> Vector2:
	return Vector2(_size) * CELL


func is_cell_solid(cell: Vector2i) -> bool:
	return not _inside(cell) or _grid.is_point_solid(cell)


## Vrai si un bot peut se tenir à cette position.
func is_walkable(world_position: Vector3) -> bool:
	var cell := _cell(world_position)
	return _inside(cell) and not _grid.is_point_solid(cell)


## Chemin au sol de `from` à `to` (points du monde, y = 0). Vide si aucun chemin.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var path := PackedVector3Array()
	if not ready:
		return path
	var start := _nearest_free(_cell(from))
	var goal := _nearest_free(_cell(to))
	if start.x < 0 or goal.x < 0:
		return path
	for cell in _grid.get_id_path(start, goal):
		path.append(Vector3(_origin.x + (float(cell.x) + 0.5) * CELL, 0.0, _origin.y + (float(cell.y) + 0.5) * CELL))
	return path


func _cell(world_position: Vector3) -> Vector2i:
	return Vector2i(floori((world_position.x - _origin.x) / CELL), floori((world_position.z - _origin.y) / CELL))


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _size.x and cell.y < _size.y


## Cellule libre la plus proche de `cell` (elle-même si elle est libre), ou (-1, -1).
func _nearest_free(cell: Vector2i) -> Vector2i:
	for radius in 6:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var candidate := cell + Vector2i(dx, dy)
				if _inside(candidate) and not _grid.is_point_solid(candidate):
					return candidate
	return Vector2i(-1, -1)
