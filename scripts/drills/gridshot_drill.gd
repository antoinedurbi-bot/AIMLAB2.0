extends "res://scripts/drills/drill_base.gd"
## Gridshot : une grille invisible fait face au joueur. `simultaneous_targets`
## sphères y sont présentes en permanence ; dès qu'une cible est détruite, une
## autre apparaît instantanément dans une cellule libre différente.
##
## Les paramètres sont surchargés par le catalogue (variante « microflicks » :
## petites cibles rapprochées à hauteur de tête).

var grid_columns: int = 5
var grid_rows: int = 5
## Distance entre deux cellules voisines (m).
var cell_spacing: float = 1.0
## Distance entre les yeux du joueur et le plan de la grille (m).
var grid_distance: float = 9.0
var target_radius: float = 0.38
var simultaneous_targets: int = 3
var hit_points: int = 100
## Bonus maximal accordé quand deux cibles sont détruites coup sur coup.
var speed_bonus_points: int = 100
var miss_penalty: int = 35

## Vector2i (cellule) -> cible présente dans cette cellule.
var _occupied: Dictionary = {}
var _last_hit_usec: int = 0
## Temps entre deux cibles détruites (ms), dans l'ordre.
var _kill_intervals: PackedFloat32Array = PackedFloat32Array()


func setup() -> void:
	hud.set_objective("Détruis les sphères le plus vite possible.")
	_fill_grid()


func begin() -> void:
	_last_hit_usec = Time.get_ticks_usec()


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	shots += 1
	var target := collider as AimTarget
	if target != null and target.alive:
		_register_hit(target, shot)
	else:
		score = maxi(score - miss_penalty, 0)
		record_shot(false, nearest_target(_alive_targets()), shot)
		if collider != null:
			fx.impact(hit_position, hit_normal)
		hud.flash_miss()
		Sfx.play(&"miss")


func finalize(report: Dictionary) -> void:
	var hit_count: int = report.get("hits", 0)
	var avg_ttk: float = report.get("avg_ttk_ms", 0.0)
	var median_ttk: float = report.get("median_ttk_ms", 0.0)
	var best_ttk: float = report.get("best_ttk_ms", 0.0)
	var kills_per_second: float = report.get("kills_per_second", 0.0)
	var peak_speed: float = report.get("avg_peak_speed", 0.0)
	var flick_distance: float = report.get("avg_flick_distance_deg", 0.0)
	var misses: int = report.get("misses", 0)

	report["ttk_consistency_ms"] = Stats.deviation(_kill_intervals)
	add_shooting_kpis(report)
	add_kpi(report, "TEMPS MOYEN ENTRE CIBLES", "%d ms" % roundi(avg_ttk) if hit_count > 1 else "—",
			"médiane %d ms · record %d ms" % [roundi(median_ttk), roundi(best_ttk)])
	add_kpi(report, "CIBLES DÉTRUITES", str(hit_count), "%.2f cibles / seconde" % kills_per_second)
	add_kpi(report, "TIRS RATÉS", str(misses), "-%d points par tir raté" % miss_penalty)
	add_kpi(report, "VITESSE DE POINTE MOY.", "%d °/s" % roundi(peak_speed) if peak_speed > 0.0 else "—", "pendant les flicks")
	add_kpi(report, "AMPLITUDE MOY. DES FLICKS", "%.1f°" % flick_distance if flick_distance > 0.0 else "—",
			"distance angulaire à parcourir")
	set_chart(report, "TEMPS ENTRE DEUX CIBLES (ms)", _kill_intervals, "ms", avg_ttk, true)
	set_panels(report, ["flicks", "heatmap", "chart"])


func _register_hit(target: AimTarget, shot: Dictionary) -> void:
	var now := Time.get_ticks_usec()
	var since_last_hit := float(now - _last_hit_usec) / 1000000.0
	_last_hit_usec = now
	hits += 1
	if hits > 1:
		_kill_intervals.append(since_last_hit * 1000.0)
	# Bonus de vitesse : complet sous 150 ms entre deux cibles, nul au-delà de 800 ms.
	var speed_factor := clampf(1.0 - (since_last_hit - 0.15) / 0.65, 0.0, 1.0)
	score += hit_points + roundi(float(speed_bonus_points) * speed_factor)

	record_shot(true, target, shot)
	var target_position := target.global_position
	var freed_cell := target.grid_cell
	_occupied.erase(freed_cell)
	target.destroy()
	fx.explosion(target_position)
	_spawn_in_grid(freed_cell)
	hud.flash_hit()
	Sfx.play(&"kill")


func _cell_position(cell: Vector2i) -> Vector3:
	var center := player.eye_position() + Vector3(0.0, 0.0, -grid_distance)
	var offset_x := (float(cell.x) - float(grid_columns - 1) * 0.5) * cell_spacing
	var offset_y := (float(cell.y) - float(grid_rows - 1) * 0.5) * cell_spacing
	return center + Vector3(offset_x, offset_y, 0.0)


func _fill_grid() -> void:
	while _occupied.size() < simultaneous_targets:
		if not _spawn_in_grid(Vector2i(-1, -1)):
			break


## Fait apparaître une cible dans une cellule libre tirée au hasard, différente
## de `excluded` (la cellule qui vient d'être libérée).
func _spawn_in_grid(excluded: Vector2i) -> bool:
	var free_cells: Array[Vector2i] = []
	for column in grid_columns:
		for row in grid_rows:
			var candidate := Vector2i(column, row)
			if candidate != excluded and not _occupied.has(candidate):
				free_cells.append(candidate)
	if free_cells.is_empty():
		return false
	var chosen: Vector2i = free_cells[rng.randi_range(0, free_cells.size() - 1)]
	var target := spawn_target(_cell_position(chosen), target_radius)
	target.grid_cell = chosen
	_occupied[chosen] = target
	return true


func _alive_targets() -> Array[AimTarget]:
	var result: Array[AimTarget] = []
	for value: Variant in _occupied.values():
		var target := value as AimTarget
		if is_instance_valid(target) and target.alive:
			result.append(target)
	return result
