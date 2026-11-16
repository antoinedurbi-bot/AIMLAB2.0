extends VBoxContainer
## Réglages du lobby, répartis en onglets : Souris, Réticule, Touches, Vidéo, Jeu.
## Chaque ligne est un libellé et un contrôle ; les changements sont appliqués
## et enregistrés aussitôt.

const Crosshair := preload("res://ui/crosshair.gd")
const Weapons := preload("res://scripts/weapons.gd")
const BotRanks := preload("res://scripts/ai/bot_ranks.gd")

const TABS := ["SOURIS", "RÉTICULE", "TOUCHES", "VIDÉO", "JEU"]
const CROSSHAIR_STYLES := ["Croix", "Croix + point", "Point", "Cercle + point"]
const QUALITY_LEVELS := ["Performance", "Qualité", "Ultra"]
## Boutons de souris acceptés comme touche (la molette est exclue).
const BINDABLE_MOUSE_BUTTONS := [1, 2, 3, 8, 9]

## Vrai pendant qu'on écrit dans les champs par code : les signaux sont ignorés.
var _updating: bool = false
var _tab_buttons: Array[Button] = []
var _tab_pages: Array[Control] = []
## Page en cours de construction : les lignes s'y ajoutent.
var _list: VBoxContainer

var _dpi_spin: SpinBox
var _cm_spin: SpinBox
var _game_sens_spin: SpinBox
var _sens_summary: Label

var _crosshair_spins: Dictionary = {}
var _crosshair_style_option: OptionButton
var _crosshair_color_button: ColorPickerButton
var _crosshair_outline_check: CheckBox
var _crosshair_code_edit: LineEdit
var _crosshair_status: Label

## action -> bouton affichant sa touche.
var _key_buttons: Dictionary = {}
## Action en attente d'une touche, "" sinon.
var _capturing: String = ""
var _key_status: Label


func _ready() -> void:
	add_theme_constant_override(&"separation", 18)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 8)
	add_child(tabs)
	var group := ButtonGroup.new()
	for index in TABS.size():
		var button := Button.new()
		button.text = str(TABS[index])
		button.theme_type_variation = &"DrillButton"
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(170.0, 40.0)
		button.add_theme_font_size_override(&"font_size", 16)
		button.pressed.connect(_show_tab.bind(index))
		tabs.add_child(button)
		_tab_buttons.append(button)

	_begin_page()
	_build_mouse()
	_begin_page()
	_build_crosshair()
	_begin_page()
	_build_keys()
	_begin_page()
	_build_video()
	_begin_page()
	_build_game()
	_refresh_sensitivity_fields()
	_show_tab(0)
	GameSettings.keys_changed.connect(_refresh_keys)
	visibility_changed.connect(_cancel_capture)


func _show_tab(index: int) -> void:
	_cancel_capture()
	for page_index in _tab_pages.size():
		_tab_pages[page_index].visible = page_index == index
		_tab_buttons[page_index].set_pressed_no_signal(page_index == index)


## Crée une page (panneau centré, liste défilante) et la rend courante.
func _begin_page() -> void:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size.x = 860.0
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 10)
	scroll.add_child(_list)
	_tab_pages.append(panel)


# ---------------------------------------------------------------------------
# Souris
# ---------------------------------------------------------------------------

func _build_mouse() -> void:
	_dpi_spin = _make_spin(50.0, 32000.0, 50.0, GameSettings.dpi, "")
	_dpi_spin.value_changed.connect(_on_dpi_changed)
	_add_row("DPI", _dpi_spin)

	_cm_spin = _make_spin(1.0, 300.0, 0.01, GameSettings.cm_per_360, " cm")
	_cm_spin.value_changed.connect(_on_cm_changed)
	_add_row("Distance pour 360°", _cm_spin)

	var game_option := OptionButton.new()
	for game: String in GameSettings.GAMES:
		game_option.add_item(game)
	game_option.select(GameSettings.reference_game)
	game_option.item_selected.connect(_on_game_selected)
	_add_row("Jeu de référence", game_option)

	_game_sens_spin = _make_spin(0.001, 100.0, 0.001, 1.0, "")
	_game_sens_spin.value_changed.connect(_on_game_sens_changed)
	_add_row("Sensibilité dans ce jeu", _game_sens_spin)

	_sens_summary = _caption("")
	_list.add_child(_sens_summary)


func _selected_game() -> String:
	var game: String = GameSettings.game_name(GameSettings.reference_game)
	return game


func _on_dpi_changed(value: float) -> void:
	if _updating:
		return
	# Le cm/360° est conservé : seule la sensibilité « en jeu » équivalente change.
	GameSettings.dpi = value
	_commit_sensitivity()


func _on_cm_changed(value: float) -> void:
	if _updating:
		return
	GameSettings.cm_per_360 = value
	_commit_sensitivity()


func _on_game_selected(index: int) -> void:
	GameSettings.reference_game = index
	_commit_sensitivity()


func _on_game_sens_changed(value: float) -> void:
	if _updating:
		return
	var converted: float = GameSettings.game_sens_to_cm(_selected_game(), value)
	GameSettings.cm_per_360 = clampf(converted, 1.0, 300.0)
	_commit_sensitivity()


func _commit_sensitivity() -> void:
	GameSettings.commit_sensitivity()
	_refresh_sensitivity_fields()


func _refresh_sensitivity_fields() -> void:
	_updating = true
	var cm: float = GameSettings.cm_per_360
	_dpi_spin.value = GameSettings.dpi
	_cm_spin.value = cm
	var game_sens: float = GameSettings.cm_to_game_sens(_selected_game(), cm)
	_game_sens_spin.value = game_sens
	var parts := PackedStringArray()
	for game: String in GameSettings.GAMES:
		var equivalent: float = GameSettings.cm_to_game_sens(game, cm)
		parts.append("%s %.3f" % [game, equivalent])
	_sens_summary.text = "  ·  ".join(parts)
	_updating = false


# ---------------------------------------------------------------------------
# Réticule : aperçu, préréglages, code d'import / export, éditeur
# ---------------------------------------------------------------------------

func _build_crosshair() -> void:
	var preview_panel := Panel.new()
	preview_panel.custom_minimum_size.y = 120.0
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color(0.16, 0.19, 0.24)
	preview_style.set_corner_radius_all(6)
	preview_panel.add_theme_stylebox_override(&"panel", preview_style)
	_list.add_child(preview_panel)
	var preview: Control = Crosshair.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_panel.add_child(preview)

	var preset_option := OptionButton.new()
	preset_option.add_item("Choisir…")
	for preset_name: String in GameSettings.CROSSHAIR_PRESETS:
		preset_option.add_item(preset_name)
	preset_option.item_selected.connect(_on_crosshair_preset_selected.bind(preset_option))
	_add_row("Préréglage", preset_option)

	_crosshair_code_edit = LineEdit.new()
	_crosshair_code_edit.placeholder_text = "KA1;…"
	_crosshair_code_edit.text_submitted.connect(_on_crosshair_code_submitted)
	_add_row("Code", _crosshair_code_edit)
	var code_buttons := HBoxContainer.new()
	code_buttons.alignment = BoxContainer.ALIGNMENT_END
	code_buttons.add_theme_constant_override(&"separation", 8)
	var import_button := Button.new()
	import_button.text = "IMPORTER"
	import_button.pressed.connect(_on_crosshair_import_pressed)
	code_buttons.add_child(import_button)
	var export_button := Button.new()
	export_button.text = "COPIER"
	export_button.pressed.connect(_on_crosshair_export_pressed)
	code_buttons.add_child(export_button)
	_crosshair_status = _caption("")
	_crosshair_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_buttons.add_child(_crosshair_status)
	code_buttons.move_child(_crosshair_status, 0)
	_list.add_child(code_buttons)

	_crosshair_style_option = OptionButton.new()
	for style_name: String in CROSSHAIR_STYLES:
		_crosshair_style_option.add_item(style_name)
	_crosshair_style_option.select(GameSettings.crosshair_style)
	_crosshair_style_option.item_selected.connect(_on_crosshair_style_selected)
	_add_row("Forme", _crosshair_style_option)

	_crosshair_color_button = ColorPickerButton.new()
	_crosshair_color_button.color = GameSettings.crosshair_color
	_crosshair_color_button.edit_alpha = false
	_crosshair_color_button.custom_minimum_size.y = 34.0
	_crosshair_color_button.color_changed.connect(_on_crosshair_color_changed)
	_add_row("Couleur", _crosshair_color_button)

	_add_crosshair_spin("Longueur", &"crosshair_length", 0.0, 40.0, 1.0, " px")
	_add_crosshair_spin("Épaisseur", &"crosshair_thickness", 1.0, 10.0, 1.0, " px")
	_add_crosshair_spin("Écart", &"crosshair_gap", 0.0, 30.0, 1.0, " px")
	_add_crosshair_spin("Point", &"crosshair_dot_size", 1.0, 12.0, 1.0, " px")
	_add_crosshair_spin("Opacité", &"crosshair_opacity", 0.1, 1.0, 0.05, "")

	_crosshair_outline_check = CheckBox.new()
	_crosshair_outline_check.button_pressed = GameSettings.crosshair_outline
	_crosshair_outline_check.toggled.connect(_on_crosshair_outline_toggled)
	_add_row("Contour noir", _crosshair_outline_check)


func _on_crosshair_preset_selected(index: int, option: OptionButton) -> void:
	if index <= 0:
		return
	var code: String = GameSettings.CROSSHAIR_PRESETS.get(option.get_item_text(index), "")
	_apply_crosshair_code(code, "Préréglage appliqué")
	option.select(0)


func _on_crosshair_code_submitted(_text: String) -> void:
	_on_crosshair_import_pressed()


func _on_crosshair_import_pressed() -> void:
	_apply_crosshair_code(_crosshair_code_edit.text, "Importé")


func _on_crosshair_export_pressed() -> void:
	var code: String = GameSettings.crosshair_to_code()
	DisplayServer.clipboard_set(code)
	_crosshair_code_edit.text = code
	_crosshair_status.text = "Copié"


## Applique un code de réticule et met à jour tous les champs de l'éditeur.
func _apply_crosshair_code(code: String, success_message: String) -> void:
	var valid: bool = GameSettings.crosshair_from_code(code)
	if not valid:
		_crosshair_status.text = "Code invalide"
		return
	_updating = true
	for property: Variant in _crosshair_spins:
		var spin := _crosshair_spins[property] as SpinBox
		var current: float = GameSettings.get(str(property))
		spin.value = current
	_crosshair_style_option.select(GameSettings.crosshair_style)
	_crosshair_color_button.color = GameSettings.crosshair_color
	_crosshair_outline_check.set_pressed_no_signal(GameSettings.crosshair_outline)
	_updating = false
	_crosshair_status.text = success_message
	GameSettings.commit_crosshair()


func _add_crosshair_spin(caption: String, property: StringName, minimum: float, maximum: float, step: float, suffix: String) -> void:
	var current: float = GameSettings.get(property)
	var spin := _make_spin(minimum, maximum, step, current, suffix)
	spin.value_changed.connect(_on_crosshair_value_changed.bind(property))
	_add_row(caption, spin)
	_crosshair_spins[property] = spin


func _on_crosshair_value_changed(value: float, property: StringName) -> void:
	if _updating:
		return
	GameSettings.set(property, value)
	GameSettings.commit_crosshair()


func _on_crosshair_style_selected(index: int) -> void:
	GameSettings.crosshair_style = index
	GameSettings.commit_crosshair()


func _on_crosshair_color_changed(color: Color) -> void:
	GameSettings.crosshair_color = color
	GameSettings.commit_crosshair()


func _on_crosshair_outline_toggled(enabled: bool) -> void:
	GameSettings.crosshair_outline = enabled
	GameSettings.commit_crosshair()


# ---------------------------------------------------------------------------
# Touches : cliquer une ligne puis appuyer sur la nouvelle touche
# ---------------------------------------------------------------------------

func _build_keys() -> void:
	_key_status = _caption("Clique une action, puis appuie sur la touche ou le bouton de souris.")
	_list.add_child(_key_status)
	for item: Variant in GameSettings.ACTIONS:
		var pair: Array = item
		var action: String = pair[0]
		var button := Button.new()
		button.pressed.connect(_on_key_button_pressed.bind(action))
		_add_row(str(pair[1]), button)
		_key_buttons[action] = button
	var reset_button := Button.new()
	reset_button.text = "TOUCHES PAR DÉFAUT"
	reset_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	reset_button.pressed.connect(_on_reset_keys_pressed)
	_list.add_child(reset_button)
	_refresh_keys()


func _refresh_keys() -> void:
	for action: Variant in _key_buttons:
		var button := _key_buttons[action] as Button
		button.text = "…" if str(action) == _capturing else GameSettings.key_label(str(action))


func _on_key_button_pressed(action: String) -> void:
	_capturing = action
	_key_status.text = "Appuie sur une touche · Échap pour annuler"
	_refresh_keys()


func _on_reset_keys_pressed() -> void:
	_cancel_capture()
	GameSettings.reset_keys()


func _cancel_capture() -> void:
	if _capturing == "":
		return
	_capturing = ""
	_key_status.text = "Clique une action, puis appuie sur la touche ou le bouton de souris."
	_refresh_keys()


## Pendant une capture, la prochaine touche (ou bouton de souris) devient la touche de l'action.
func _input(event: InputEvent) -> void:
	if _capturing == "" or not event.is_pressed() or event.is_echo():
		return
	var code := 0
	var key := event as InputEventKey
	var button := event as InputEventMouseButton
	if key != null:
		if key.keycode != KEY_ESCAPE:
			code = int(key.physical_keycode)
	elif button != null:
		if not BINDABLE_MOUSE_BUTTONS.has(int(button.button_index)):
			return
		code = -int(button.button_index)
	else:
		return
	get_viewport().set_input_as_handled()
	var action := _capturing
	_cancel_capture()
	if code != 0:
		GameSettings.bind_key(action, code)


# ---------------------------------------------------------------------------
# Vidéo
# ---------------------------------------------------------------------------

func _build_video() -> void:
	var quality_option := OptionButton.new()
	for level: String in QUALITY_LEVELS:
		quality_option.add_item(level)
	quality_option.select(GameSettings.quality)
	quality_option.item_selected.connect(_on_quality_selected)
	_add_row("Qualité", quality_option)

	var fov_spin := _make_spin(60.0, 130.0, 1.0, GameSettings.fov_horizontal, "°")
	fov_spin.value_changed.connect(_on_fov_changed)
	_add_row("Champ de vision horizontal", fov_spin)

	var fps_spin := _make_spin(0.0, 1000.0, 10.0, float(GameSettings.max_fps), " FPS")
	fps_spin.value_changed.connect(_on_max_fps_changed)
	_add_row("Limite d'images (0 = aucune)", fps_spin)

	var vsync_check := CheckBox.new()
	vsync_check.button_pressed = GameSettings.vsync
	vsync_check.toggled.connect(_on_vsync_toggled)
	_add_row("V-Sync", vsync_check)

	var fullscreen_check := CheckBox.new()
	fullscreen_check.button_pressed = GameSettings.fullscreen
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_add_row("Plein écran (F11)", fullscreen_check)


func _on_quality_selected(index: int) -> void:
	GameSettings.quality = index
	GameSettings.commit_graphics()


func _on_fov_changed(value: float) -> void:
	GameSettings.fov_horizontal = value
	GameSettings.commit_sensitivity()


func _on_max_fps_changed(value: float) -> void:
	GameSettings.max_fps = roundi(value)
	GameSettings.commit_graphics()


func _on_vsync_toggled(enabled: bool) -> void:
	GameSettings.vsync = enabled
	GameSettings.commit_graphics()


func _on_fullscreen_toggled(enabled: bool) -> void:
	GameSettings.fullscreen = enabled
	GameSettings.commit_graphics()


# ---------------------------------------------------------------------------
# Jeu : arme, bots, son, données
# ---------------------------------------------------------------------------

func _build_game() -> void:
	var weapon_option := OptionButton.new()
	var weapon_index := 0
	for weapon_id: String in Weapons.ORDER:
		var profile: Dictionary = Weapons.get_profile(weapon_id)
		weapon_option.add_item(str(profile.get("name", weapon_id)))
		if weapon_id == GameSettings.weapon:
			weapon_index = weapon_option.item_count - 1
	weapon_option.select(weapon_index)
	weapon_option.item_selected.connect(_on_weapon_selected)
	_add_row("Arme", weapon_option)

	var rank_option := OptionButton.new()
	rank_option.add_item("Adaptatif")
	for rank in BotRanks.count():
		rank_option.add_item(BotRanks.rank_name(rank))
	rank_option.select(GameSettings.bot_rank + 1)
	rank_option.item_selected.connect(_on_bot_rank_selected)
	_add_row("Rang des bots", rank_option)

	var volume_spin := _make_spin(0.0, 100.0, 5.0, GameSettings.sfx_volume * 100.0, " %")
	volume_spin.value_changed.connect(_on_volume_changed)
	_add_row("Volume", volume_spin)

	var export_check := CheckBox.new()
	export_check.button_pressed = GameSettings.export_raw_telemetry
	export_check.toggled.connect(_on_export_toggled)
	_add_row("Exporter la télémétrie brute", export_check)


func _on_weapon_selected(index: int) -> void:
	GameSettings.weapon = str(Weapons.ORDER[clampi(index, 0, Weapons.ORDER.size() - 1)])
	GameSettings.commit_sensitivity()


func _on_bot_rank_selected(index: int) -> void:
	GameSettings.bot_rank = index - 1
	GameSettings.save_settings()


func _on_volume_changed(value: float) -> void:
	GameSettings.sfx_volume = value / 100.0
	GameSettings.commit_audio()
	Sfx.play(&"hit")


func _on_export_toggled(enabled: bool) -> void:
	GameSettings.export_raw_telemetry = enabled
	GameSettings.save_settings()


# ---------------------------------------------------------------------------
# Construction des lignes
# ---------------------------------------------------------------------------

func _add_row(caption: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	control.custom_minimum_size.x = 300.0
	row.add_child(control)
	_list.add_child(row)


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"CaptionLabel"
	return label


func _make_spin(minimum: float, maximum: float, step: float, current: float, suffix: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = current
	spin.suffix = suffix
	spin.select_all_on_focus = true
	return spin
