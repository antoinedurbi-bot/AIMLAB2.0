extends "res://scripts/drills/drill_base.gd"
## Duel en sortie d'angle : un adversaire immobile tient l'angle derrière le
## coin et RIPOSTE. Dès qu'il voit ta tête ou une épaule, il lui faut
## `enemy_reaction_ms` pour te toucher : à toi de sortir et de l'éliminer avant.
##
## Mesures : duels gagnés / perdus, durée d'exposition avant l'élimination,
## largeur de la sortie (serrée ou large), part de tirs à la tête, re-sorties.

const Humanoid := preload("res://scripts/humanoid_target.gd")
const HUMANOID_SCENE: PackedScene = preload("res://scenes/humanoid_target.tscn")

## Temps de réaction de l'adversaire au niveau de difficulté 1 (ms).
var enemy_reaction_ms: float = 520.0
var shoulder_offset: float = 0.3
var chest_height: float = 1.3
## Au-delà de cette distance parcourue à découvert (m), la sortie est dite « large ».
var wide_peek_distance: float = 1.0

var _markers: PackedStringArray = PackedStringArray(["JiggleEnemy1", "JiggleEnemy2", "JiggleEnemy3"])
var _enemy: Humanoid
var _enemy_index: int = -1
var _cooldown: float = 0.0
var _reaction_ms: float = 520.0
var _exposed: bool = false
var _exposure_usec: int = 0
var _exposure_x: float = 0.0
var _peeks_this_duel: int = 0

var _wins: int = 0
var _losses: int = 0
var _head_hits: int = 0
var _body_hits: int = 0
var _wide_wins: int = 0
var _tight_wins: int = 0
var _repeeks: int = 0
var _exposures: PackedFloat32Array = PackedFloat32Array()
var _widths: PackedFloat32Array = PackedFloat32Array()


func uses_movement() -> bool:
	return true


func spawn_marker() -> String:
	return "JiggleSpawn"


func setup() -> void:
	_reaction_ms = enemy_reaction_ms / difficulty
	player.automatic = true
	player.recoil_enabled = true
	hud.set_objective("Sors, élimine, ou reviens à couvert · riposte en %d ms" % roundi(_reaction_ms))
	hud.set_speed_gauge_visible(true)
	hud.set_side_stat("DUELS", "0 gagnés · 0 perdus")
	_place_enemy()


func update(delta: float) -> void:
	hud.set_speed(player.horizontal_speed(), PlayerController.ACCURATE_SPEED, PlayerController.RUN_SPEED)
	if _enemy == null:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_place_enemy()
		return
	var exposed := _enemy_sees_player()
	var now := Time.get_ticks_usec()
	if exposed and not _exposed:
		_exposed = true
		_exposure_usec = now
		_exposure_x = player.global_position.x
		_peeks_this_duel += 1
		Telemetry.log_event("peek_start", {"enemy": _enemy_index})
	elif not exposed and _exposed:
		_exposed = false
		Telemetry.log_event("peek_end", {"enemy": _enemy_index, "ms": float(now - _exposure_usec) / 1000.0})
	if _exposed and float(now - _exposure_usec) / 1000.0 >= _reaction_ms:
		_losses += 1
		score = maxi(score - 50, 0)
		hud.show_feedback("TOUCHÉ · l'adversaire a tiré le premier", Hud.COLOR_BAD)
		hud.flash_miss()
		Sfx.play(&"fail")
		Telemetry.log_event("duel_lost", {"enemy": _enemy_index})
		_remove_enemy()


func on_shot(collider: Object, hit_position: Vector3, hit_normal: Vector3, shot: Dictionary) -> void:
	shots += 1
	var speed: float = shot.get("speed", 0.0)
	var details := {"spray_index": shot.get("spray_index", 0)}
	if _enemy == null:
		Telemetry.record_shot(false, Vector3.ZERO, 0.0, -1, speed, details)
		return
	if collider as Humanoid != _enemy:
		Telemetry.record_shot(false, _enemy.head_position(), Humanoid.HEAD_RADIUS, _enemy.target_id, speed, details)
		if collider != null:
			fx.impact(hit_position, hit_normal)
		hud.flash_miss()
		return
	hits += 1
	var head := _enemy.is_head_hit(hit_position)
	details["head"] = head
	Telemetry.record_shot(true, _enemy.head_position(), Humanoid.HEAD_RADIUS, _enemy.target_id, speed, details)
	if head:
		_head_hits += 1
	else:
		_body_hits += 1
	hud.flash_hit()
	Sfx.play(&"hit")
	if _enemy.apply_damage(player.weapon_damage(head)):
		var exposure_ms := float(Time.get_ticks_usec() - _exposure_usec) / 1000.0 if _exposed else 0.0
		var width := absf(player.global_position.x - _exposure_x) if _exposed else 0.0
		_wins += 1
		_exposures.append(exposure_ms)
		_widths.append(width)
		if width >= wide_peek_distance:
			_wide_wins += 1
		else:
			_tight_wins += 1
		if _peeks_this_duel > 1:
			_repeeks += 1
		score += 150 + (50 if head else 0) + roundi(100.0 * clampf(1.0 - exposure_ms / _reaction_ms, 0.0, 1.0))
		fx.explosion(_enemy.head_position())
		hud.show_feedback("ÉLIMINÉ · exposé %d ms · sortie %s" % [roundi(exposure_ms), "large" if width >= wide_peek_distance else "serrée"], Hud.COLOR_GOOD)
		Sfx.play(&"kill")
		Telemetry.log_event("duel_won", {"exposure_ms": exposure_ms, "width_m": width, "head": head})
		_remove_enemy()


func finalize(report: Dictionary) -> void:
	var duels := _wins + _losses
	var win_rate := Stats.percent(_wins, duels)
	report["duels"] = duels
	report["duel_wins"] = _wins
	report["duel_losses"] = _losses
	report["duel_win_rate"] = win_rate
	report["headshot_rate"] = Stats.percent(_head_hits, _head_hits + _body_hits)
	report["avg_exposure_ms"] = Stats.mean(_exposures)
	report["avg_peek_width_m"] = Stats.mean(_widths)
	report["wide_peek_wins"] = _wide_wins
	report["tight_peek_wins"] = _tight_wins
	report["repeek_wins"] = _repeeks
	report["enemy_reaction_ms"] = _reaction_ms
	report["difficulty_level"] = difficulty
	report["success_ratio"] = win_rate / 100.0

	add_kpi(report, "DUELS GAGNÉS", "%d / %d" % [_wins, duels], "%d %% de victoires" % roundi(win_rate))
	add_kpi(report, "EXPOSITION AVANT ÉLIMINATION", "%d ms" % roundi(Stats.mean(_exposures)) if _wins > 0 else "—",
			"l'adversaire tire à %d ms" % roundi(_reaction_ms))
	add_kpi(report, "SORTIES", "%d serrées · %d larges" % [_tight_wins, _wide_wins], "largeur moyenne %.1f m" % Stats.mean(_widths))
	add_kpi(report, "TIRS À LA TÊTE", "%d %%" % roundi(Stats.percent(_head_hits, _head_hits + _body_hits)) if hits > 0 else "—", "sur les balles au but")
	add_kpi(report, "RE-SORTIES GAGNANTES", str(_repeeks), "duels gagnés après un retour à couvert")
	add_shooting_kpis(report)
	set_chart(report, "EXPOSITION AVANT ÉLIMINATION (ms)", _exposures, "ms", _reaction_ms, true)
	set_panels(report, ["chart", "heatmap"])


func _enemy_sees_player() -> bool:
	var from := _enemy.head_position()
	if line_of_sight(from, player.eye_position()):
		return true
	var chest := player.global_position + Vector3(0.0, chest_height, 0.0)
	var side: Vector3 = player.global_transform.basis.x * shoulder_offset
	return line_of_sight(from, chest + side) or line_of_sight(from, chest - side)


func _place_enemy() -> void:
	var index := rng.randi_range(0, _markers.size() - 1)
	if index == _enemy_index:
		index = (index + 1) % _markers.size()
	_enemy_index = index
	var spot := marker(_markers[index])
	var enemy := HUMANOID_SCENE.instantiate() as Humanoid
	enemy.target_id = _next_target_id
	_next_target_id += 1
	enemy.moving_enabled = false
	enemy.position = Vector3(spot.x, 0.0, spot.z)
	add_child(enemy)
	_enemy = enemy
	_exposed = false
	_peeks_this_duel = 0


func _remove_enemy() -> void:
	if _enemy != null:
		_enemy.destroy()
		_enemy = null
	_exposed = false
	_cooldown = 0.8
	hud.set_side_stat("DUELS", "%d gagnés · %d perdus" % [_wins, _losses])
