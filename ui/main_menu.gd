extends Control
## Lobby : quatre pages (Accueil, Jouer, Profil, Réglages) derrière une barre de
## navigation. Chaque page montre peu de texte : un titre, une valeur, un bouton.
## Les pages sont construites par code ; la scène ne contient que le cadre.

## `map_path` / `map_name` sont vides pour les exercices à carte fixe.
signal play_requested(drill_id: String, map_path: String, map_name: String)
signal quit_requested

enum Page { HOME, PLAY, PROFILE, SETTINGS }

const DrillCatalog := preload("res://scripts/drills/drill_catalog.gd")
const TrainingPlan := preload("res://scripts/training_plan.gd")
const RadarChart := preload("res://ui/radar_chart.gd")
const SettingsPanel := preload("res://ui/settings_panel.gd")

const PAGE_TITLES := ["ACCUEIL", "JOUER", "PROFIL", "RÉGLAGES"]
const ACCENT := Color(0.0, 0.9, 1.0)

var _pages_list: Array[Control] = []
var _nav_buttons: Array[Button] = []
var _category: String = "aim"
var _selected_drill: String = "gridshot"
var _next_routine_drill: String = "benchmark"

# Accueil
var _routine_value: Label
var _routine_bar: ProgressBar
var _routine_hint: Label
var _routine_button: Button
var _diagnostic_value: Label
var _diagnostic_hint: Label
var _last_value: Label
var _last_hint: Label

# Jouer
var _category_buttons: Dictionary = {}
var _card_buttons: Dictionary = {}
var _card_grid: GridContainer
var _detail_title: Label
var _detail_focus: Label
var _detail_record: Label
var _detail_description: Label
var _variant_row: HBoxContainer
var _map_row: HBoxContainer
var _map_option: OptionButton
var _play_button: Button

# Profil
var _radar: RadarChart
var _skill_bars: Dictionary = {}
var _skill_values: Dictionary = {}
var _profile_summary: Label
var _routine_list: VBoxContainer

@onready var _top_bar: HBoxContainer = %TopBar
@onready var _pages: MarginContainer = %Pages


func _ready() -> void:
	var known: Dictionary = DrillCatalog.find(GameSettings.last_drill)
	_selected_drill = known.get("id", "gridshot")
	var known_category: String = known.get("category", "")
	if known_category == "":
		_selected_drill = "gridshot"
	else:
		_category = known_category
	_build_top_bar()
	_add_page(_build_home())
	_add_page(_build_play())
	_add_page(_build_profile())
	_add_page(SettingsPanel.new())
	visibility_changed.connect(_on_visibility_changed)
	_show_page(Page.HOME)
	_show_category(_category)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh_home()
		_refresh_profile()
		_refresh_detail()


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _build_top_bar() -> void:
	var logo := _label("KINETIC // AIM", &"HeadingLabel", 30)
	logo.add_theme_color_override(&"font_color", Color.WHITE)
	_top_bar.add_child(logo)
	_top_bar.add_child(_spacer(40.0))
	var group := ButtonGroup.new()
	for index in PAGE_TITLES.size():
		var button := _tab_button(str(PAGE_TITLES[index]), group, 18)
		button.custom_minimum_size = Vector2(170.0, 46.0)
		button.pressed.connect(_show_page.bind(index))
		_top_bar.add_child(button)
		_nav_buttons.append(button)
	var filler := Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_bar.add_child(filler)
	var quit_button := Button.new()
	quit_button.text = "QUITTER"
	quit_button.pressed.connect(_on_quit_pressed)
	_top_bar.add_child(quit_button)


func _on_quit_pressed() -> void:
	quit_requested.emit()


func _add_page(page: Control) -> void:
	page.visible = false
	_pages.add_child(page)
	_pages_list.append(page)


func _show_page(index: int) -> void:
	for page_index in _pages_list.size():
		_pages_list[page_index].visible = page_index == index
		_nav_buttons[page_index].set_pressed_no_signal(page_index == index)


func _start(drill_id: String, map_path: String, map_name: String) -> void:
	GameSettings.last_drill = drill_id
	GameSettings.save_settings()
	play_requested.emit(drill_id, map_path, map_name)


# ---------------------------------------------------------------------------
# Accueil : trois cartes, trois boutons
# ---------------------------------------------------------------------------

func _build_home() -> Control:
	var page := VBoxContainer.new()
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_theme_constant_override(&"separation", 36)
	var title := _label("PRÊT ?", &"TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 24)
	page.add_child(row)

	var routine := _home_card(row, "ROUTINE DU JOUR")
	_routine_value = _label("0 / 0", &"ValueLabel", 44)
	routine.add_child(_routine_value)
	_routine_bar = ProgressBar.new()
	_routine_bar.show_percentage = false
	_routine_bar.custom_minimum_size.y = 10.0
	routine.add_child(_routine_bar)
	_routine_hint = _label("", &"CaptionLabel")
	routine.add_child(_routine_hint)
	_routine_button = _home_button(routine, "CONTINUER", true)
	_routine_button.pressed.connect(_on_routine_pressed)

	var diagnostic := _home_card(row, "DIAGNOSTIC")
	_diagnostic_value = _label("—", &"ValueLabel", 44)
	diagnostic.add_child(_diagnostic_value)
	_diagnostic_hint = _label("", &"CaptionLabel")
	diagnostic.add_child(_diagnostic_hint)
	var diagnostic_button := _home_button(diagnostic, "PASSER · 2 MIN", false)
	diagnostic_button.pressed.connect(_start.bind("benchmark", "", ""))

	var last := _home_card(row, "LIBRE")
	_last_value = _label("", &"ValueLabel", 30)
	_last_value.clip_text = true
	last.add_child(_last_value)
	_last_hint = _label("", &"CaptionLabel")
	last.add_child(_last_hint)
	var browse_button := _home_button(last, "CHOISIR UN EXERCICE", false)
	browse_button.pressed.connect(_show_page.bind(Page.PLAY))
	return page


func _home_card(row: HBoxContainer, caption: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400.0, 270.0)
	row.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)
	box.add_child(_label(caption, &"SectionLabel"))
	return box


## Bouton placé en bas d'une carte d'accueil.
func _home_button(box: VBoxContainer, text: String, accent: bool) -> Button:
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)
	var button := Button.new()
	button.text = text
	if accent:
		button.theme_type_variation = &"AccentButton"
	box.add_child(button)
	return button


func _refresh_home() -> void:
	if _routine_value == null:
		return
	var has_benchmark: bool = PlayerProfile.has_benchmark()
	var ordered: Array[String] = PlayerProfile.skills_by_weakness()
	var plan: Array[Dictionary] = TrainingPlan.build(ordered, has_benchmark)
	var wanted_total := 0
	var done_total := 0
	_next_routine_drill = ""
	for item in plan:
		var drill_id: String = item.get("drill_id", "")
		var wanted: int = item.get("sessions", 0)
		var done: int = mini(PlayerProfile.sessions_today(drill_id), wanted)
		wanted_total += wanted
		done_total += done
		if done < wanted and _next_routine_drill == "":
			_next_routine_drill = drill_id
	_routine_value.text = "%d / %d" % [done_total, wanted_total]
	_routine_bar.max_value = maxf(float(wanted_total), 1.0)
	_routine_bar.value = float(done_total)
	if not has_benchmark:
		_next_routine_drill = "benchmark"
		_routine_hint.text = "Commence par le diagnostic"
		_routine_button.text = "DIAGNOSTIC"
	elif _next_routine_drill == "":
		_next_routine_drill = "benchmark"
		_routine_hint.text = "Terminée pour aujourd'hui"
		_routine_button.text = "REFAIRE LE DIAGNOSTIC"
	else:
		var next_entry: Dictionary = DrillCatalog.find(_next_routine_drill)
		_routine_hint.text = "Suivant : %s" % next_entry.get("title", "")
		_routine_button.text = "CONTINUER"

	if has_benchmark:
		var latest: Dictionary = PlayerProfile.latest_benchmark()
		var overall: float = latest.get("overall", 0.0)
		_diagnostic_value.text = "%d / 100" % roundi(overall)
		_diagnostic_hint.text = "Priorité : %s" % PlayerProfile.skill_name(ordered[0])
	else:
		_diagnostic_value.text = "—"
		_diagnostic_hint.text = "Jamais passé"

	var last_entry: Dictionary = DrillCatalog.find(GameSettings.last_drill)
	_last_value.text = str(last_entry.get("title", ""))
	_last_hint.text = "Dernier exercice joué"


func _on_routine_pressed() -> void:
	var entry: Dictionary = DrillCatalog.find(_next_routine_drill)
	var maps: Array = entry.get("maps", [])
	if maps.is_empty():
		_start(_next_routine_drill, "", "")
	else:
		var first_map: Dictionary = maps[0]
		_start(_next_routine_drill, str(first_map.get("path", "")), str(first_map.get("name", "")))


# ---------------------------------------------------------------------------
# Jouer : catégories, cartes d'exercices, panneau de lancement
# ---------------------------------------------------------------------------

func _build_play() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", 18)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 8)
	page.add_child(tabs)
	var group := ButtonGroup.new()
	for item: Variant in DrillCatalog.CATEGORIES:
		var category: Dictionary = item
		var category_id: String = category.get("id", "")
		var button := _tab_button(str(category.get("title", "")), group, 16)
		button.custom_minimum_size = Vector2(200.0, 40.0)
		button.pressed.connect(_show_category.bind(category_id))
		tabs.add_child(button)
		_category_buttons[category_id] = button

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override(&"separation", 32)
	page.add_child(columns)

	_card_grid = GridContainer.new()
	_card_grid.columns = 2
	_card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_grid.add_theme_constant_override(&"h_separation", 16)
	_card_grid.add_theme_constant_override(&"v_separation", 16)
	columns.add_child(_card_grid)

	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 520.0
	columns.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 14)
	panel.add_child(box)
	_detail_title = _label("", &"ValueLabel", 36)
	box.add_child(_detail_title)
	_detail_focus = _label("", &"", 20)
	_detail_focus.add_theme_color_override(&"font_color", ACCENT)
	box.add_child(_detail_focus)
	_detail_description = _label("", &"CaptionLabel", 16)
	_detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail_description)

	_variant_row = HBoxContainer.new()
	_variant_row.add_theme_constant_override(&"separation", 8)
	box.add_child(_variant_row)

	_map_row = HBoxContainer.new()
	_map_row.add_theme_constant_override(&"separation", 12)
	_map_row.add_child(_label("Carte", &"CaptionLabel"))
	_map_option = OptionButton.new()
	_map_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_option.item_selected.connect(_on_map_selected)
	_map_row.add_child(_map_option)
	box.add_child(_map_row)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)
	_detail_record = _label("", &"CaptionLabel")
	box.add_child(_detail_record)
	_play_button = Button.new()
	_play_button.text = "JOUER"
	_play_button.theme_type_variation = &"AccentButton"
	_play_button.custom_minimum_size.y = 64.0
	_play_button.pressed.connect(_on_play_pressed)
	box.add_child(_play_button)
	return page


func _show_category(category_id: String) -> void:
	_category = category_id
	for key: Variant in _category_buttons:
		var tab := _category_buttons[key] as Button
		tab.set_pressed_no_signal(str(key) == category_id)
	for child in _card_grid.get_children():
		_card_grid.remove_child(child)
		child.queue_free()
	_card_buttons.clear()

	var group := ButtonGroup.new()
	var cards: Array[Dictionary] = DrillCatalog.cards(category_id)
	var selected_here := false
	for card in cards:
		var entries: Array = card.get("entries", [])
		for item: Variant in entries:
			var entry: Dictionary = item
			if entry.get("id", "") == _selected_drill:
				selected_here = true
	if not selected_here and not cards.is_empty():
		var first_entries: Array = cards[0].get("entries", [])
		var first_entry: Dictionary = first_entries[0]
		_selected_drill = first_entry.get("id", "")
	for card in cards:
		_card_grid.add_child(_make_card(card, group))
	_refresh_detail()


## Carte cliquable d'un exercice : titre, compétence, nombre de variantes.
func _make_card(card: Dictionary, group: ButtonGroup) -> Button:
	var entries: Array = card.get("entries", [])
	var first: Dictionary = entries[0]
	var card_title: String = card.get("card", "")
	var button := Button.new()
	button.theme_type_variation = &"DrillButton"
	button.toggle_mode = true
	button.button_group = group
	button.custom_minimum_size = Vector2(0.0, 132.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_card_pressed.bind(card_title))
	_card_buttons[card_title] = button

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	button.add_child(margin)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 4)
	margin.add_child(box)
	var title := _label(card_title, &"ValueLabel", 26)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	var focus := _label(str(first.get("focus", "")), &"CaptionLabel", 16)
	focus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus.clip_text = true
	box.add_child(focus)
	if entries.size() > 1:
		var names := PackedStringArray()
		for item: Variant in entries:
			var entry: Dictionary = item
			names.append(str(entry.get("variant", "")))
		var variants := _label(" · ".join(names), &"", 14)
		variants.add_theme_color_override(&"font_color", ACCENT)
		variants.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(variants)
	return button


func _on_card_pressed(card_title: String) -> void:
	for card in DrillCatalog.cards(_category):
		if card.get("card", "") == card_title:
			var entries: Array = card.get("entries", [])
			var first: Dictionary = entries[0]
			_selected_drill = first.get("id", "")
	_refresh_detail()


func _on_variant_pressed(drill_id: String) -> void:
	_selected_drill = drill_id
	_refresh_detail()


func _on_map_selected(_index: int) -> void:
	_refresh_record()


func _on_play_pressed() -> void:
	_start(_selected_drill, _selected_map("path"), _selected_map("name"))


## Met à jour le panneau de droite pour l'exercice sélectionné.
func _refresh_detail() -> void:
	if _detail_title == null:
		return
	var entry: Dictionary = DrillCatalog.find(_selected_drill)
	var card_title: String = entry.get("card", "")
	_detail_title.text = card_title
	_detail_focus.text = str(entry.get("focus", ""))
	_detail_description.text = str(entry.get("description", ""))
	var card_button := _card_buttons.get(card_title) as Button
	if card_button != null:
		card_button.set_pressed_no_signal(true)

	for child in _variant_row.get_children():
		_variant_row.remove_child(child)
		child.queue_free()
	var siblings: Array = []
	for card in DrillCatalog.cards(_category):
		if card.get("card", "") == card_title:
			siblings = card.get("entries", [])
	_variant_row.visible = siblings.size() > 1
	if siblings.size() > 1:
		var group := ButtonGroup.new()
		for item: Variant in siblings:
			var sibling: Dictionary = item
			var sibling_id: String = sibling.get("id", "")
			var button := _tab_button(str(sibling.get("variant", "")).to_upper(), group, 15)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.set_pressed_no_signal(sibling_id == _selected_drill)
			button.pressed.connect(_on_variant_pressed.bind(sibling_id))
			_variant_row.add_child(button)

	var maps: Array = entry.get("maps", [])
	var previous_choice := maxi(_map_option.selected, 0)
	_map_option.clear()
	for item: Variant in maps:
		var map_entry: Dictionary = item
		_map_option.add_item(str(map_entry.get("name", "")))
	_map_row.visible = not maps.is_empty()
	if not maps.is_empty():
		_map_option.select(clampi(previous_choice, 0, maps.size() - 1))
	_refresh_record()


func _refresh_record() -> void:
	var entry: Dictionary = DrillCatalog.find(_selected_drill)
	var duration: float = entry.get("duration", 60.0)
	var map_name := _selected_map("name")
	var history_key := _selected_drill if map_name == "" else "%s@%s" % [_selected_drill, map_name]
	var sessions: int = SessionHistory.session_count(history_key)
	if sessions <= 0:
		_detail_record.text = "%d s · jamais joué" % roundi(duration)
	else:
		_detail_record.text = "%d s · record %d · %d sessions" % [roundi(duration), SessionHistory.best_score(history_key), sessions]


## Champ (« path » ou « name ») de la carte choisie, vide si l'exercice a une carte fixe.
func _selected_map(field: String) -> String:
	var entry: Dictionary = DrillCatalog.find(_selected_drill)
	var maps: Array = entry.get("maps", [])
	if maps.is_empty():
		return ""
	var map_entry: Dictionary = maps[clampi(_map_option.selected, 0, maps.size() - 1)]
	return str(map_entry.get(field, ""))


# ---------------------------------------------------------------------------
# Profil : radar, notes du diagnostic, routine
# ---------------------------------------------------------------------------

func _build_profile() -> Control:
	var page := HBoxContainer.new()
	page.add_theme_constant_override(&"separation", 32)

	var radar_panel := PanelContainer.new()
	radar_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(radar_panel)
	_radar = RadarChart.new()
	_radar.custom_minimum_size = Vector2(480.0, 480.0)
	radar_panel.add_child(_radar)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 560.0
	side.add_theme_constant_override(&"separation", 16)
	page.add_child(side)

	var notes_panel := PanelContainer.new()
	side.add_child(notes_panel)
	var notes := VBoxContainer.new()
	notes.add_theme_constant_override(&"separation", 10)
	notes_panel.add_child(notes)
	notes.add_child(_label("DIAGNOSTIC", &"SectionLabel"))
	_profile_summary = _label("", &"ValueLabel", 28)
	notes.add_child(_profile_summary)
	for skill: String in PlayerProfile.SKILLS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 12)
		var skill_label := _label(PlayerProfile.skill_name(skill))
		skill_label.custom_minimum_size.x = 130.0
		row.add_child(skill_label)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size.y = 12.0
		row.add_child(bar)
		var value := _label("—")
		value.custom_minimum_size.x = 40.0
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		notes.add_child(row)
		_skill_bars[skill] = bar
		_skill_values[skill] = value

	var routine_panel := PanelContainer.new()
	routine_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(routine_panel)
	_routine_list = VBoxContainer.new()
	_routine_list.add_theme_constant_override(&"separation", 6)
	routine_panel.add_child(_routine_list)
	return page


func _refresh_profile() -> void:
	if _radar == null:
		return
	_radar.set_profile(PlayerProfile.radar_labels(), PlayerProfile.radar_values())
	var has_benchmark: bool = PlayerProfile.has_benchmark()
	var ordered: Array[String] = PlayerProfile.skills_by_weakness()
	var latest: Dictionary = PlayerProfile.latest_benchmark() if has_benchmark else {}
	if has_benchmark:
		var overall: float = latest.get("overall", 0.0)
		_profile_summary.text = "%d / 100 · priorité : %s" % [roundi(overall), PlayerProfile.skill_name(ordered[0])]
	else:
		_profile_summary.text = "Aucun diagnostic"
	for skill: String in PlayerProfile.SKILLS:
		var note: float = latest.get(skill, 0.0)
		var bar := _skill_bars[skill] as ProgressBar
		bar.value = note
		var value := _skill_values[skill] as Label
		value.text = str(roundi(note)) if has_benchmark else "—"

	for child in _routine_list.get_children():
		_routine_list.remove_child(child)
		child.queue_free()
	_routine_list.add_child(_label("ROUTINE DU JOUR", &"SectionLabel"))
	for item in TrainingPlan.build(ordered, has_benchmark):
		var drill_id: String = item.get("drill_id", "")
		var wanted: int = item.get("sessions", 0)
		var done: int = mini(PlayerProfile.sessions_today(drill_id), wanted)
		var entry: Dictionary = DrillCatalog.find(drill_id)
		var row := HBoxContainer.new()
		var name_label := _label("%s  %s" % ["✓" if done >= wanted else "○", entry.get("title", drill_id)])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if done >= wanted:
			name_label.add_theme_color_override(&"font_color", Color(0.3, 1.0, 0.72))
		row.add_child(name_label)
		row.add_child(_label("%d / %d" % [done, wanted], &"CaptionLabel"))
		_routine_list.add_child(row)


# ---------------------------------------------------------------------------
# Petits constructeurs
# ---------------------------------------------------------------------------

func _label(text: String, variation: StringName = &"", font_size: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	if variation != &"":
		label.theme_type_variation = variation
	if font_size > 0:
		label.add_theme_font_size_override(&"font_size", font_size)
	return label


func _spacer(width: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.x = width
	return spacer


## Bouton d'onglet : reste enfoncé, un seul actif par groupe.
func _tab_button(text: String, group: ButtonGroup, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = &"DrillButton"
	button.toggle_mode = true
	button.button_group = group
	button.add_theme_font_size_override(&"font_size", font_size)
	return button
