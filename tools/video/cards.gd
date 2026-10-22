extends RefCounted
## Evidence cards for the video: full-screen panels that lay out real project
## files (layer names, collision masks, physics materials, the event bus,
## data resources, README and credits) like the editor shows them. Every
## value is read from the project at record time, never typed in by hand.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Take the narration transcript and record gameplay video to sync
#    alongside it." (cards stand in for the editor views the script asks for)

const BG := Color("1d2129")
const PANEL := Color("262b35")
const ROW := Color("2c323e")
const LIT := Color("4a3f12")
const TEXT := Color("e6e9ef")
const DIM := Color("9aa3b2")
const ACCENT := Color("ffd23f")
const KEYWORD := Color("ff7b72")
const NAME := Color("79c0ff")
const COMMENT := Color("6e7781")

static var _mono: Font


static func mono() -> Font:
	if _mono == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Menlo", "SF Mono", "Monaco", "monospace"])
		_mono = f
	return _mono


static func label(text: String, size := 24, colour := TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if font:
		l.add_theme_font_override("font", font)
	return l


static func _box(colour: Color, radius := 10, margin := 16) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = colour
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(margin)
	return b


## {root, body}: a full-screen card with a breadcrumb title and file path.
static func frame(title: String, path: String) -> Dictionary:
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_stylebox_override("panel", _box(BG, 0, 64))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 28)
	root.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	v.add_child(head)
	head.add_child(label(title, 40, TEXT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _box(PANEL, 8, 10))
	chip.add_child(label(path, 22, ACCENT, mono()))
	head.add_child(chip)
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	v.add_child(body)
	return {"root": root, "body": body}


## One table row of cells with fixed widths (0 = fill).
static func row(parent: Control, cells: Array, widths: Array, size := 26, header := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(PANEL if header else ROW, 8, 14))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	p.add_child(h)
	for i in cells.size():
		var c = cells[i]
		var node: Control = c if c is Control else label(str(c), size, DIM if header else TEXT, mono() if i == 0 and not header else null)
		var w: float = widths[i] if i < widths.size() else 0.0
		if w > 0.0:
			node.custom_minimum_size.x = w
		else:
			node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(node)
	parent.add_child(p)
	return p


static func lit(p: PanelContainer, on: bool) -> void:
	var b := _box(LIT if on else ROW, 8, 14)
	if on:
		b.border_color = ACCENT
		b.set_border_width_all(3)
	p.add_theme_stylebox_override("panel", b)


## The editor's 5-cell layer grid: numbered squares, filled where the bit is set.
static func bits(value: int, names: Array) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for i in 5:
		var on := value & (1 << i) != 0
		var cell := PanelContainer.new()
		var b := _box(Color("3d8bfd") if on else Color("3a404c"), 6, 0)
		cell.add_theme_stylebox_override("panel", b)
		cell.custom_minimum_size = Vector2(44, 44)
		var l := label(str(i + 1), 20, Color.WHITE if on else DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(l)
		h.add_child(cell)
	var named: Array[String] = []
	for i in 5:
		if value & (1 << i):
			named.append(names[i])
	var v := VBoxContainer.new()
	v.add_child(h)
	v.add_child(label(", ".join(named) if not named.is_empty() else "(none)", 18, DIM))
	return v


static func layer_names() -> Array:
	var out := []
	for i in 5:
		out.append(str(ProjectSettings.get_setting("layer_names/2d_physics/layer_%d" % (i + 1), "")))
	return out


# --- Physics -----------------------------------------------------------------------

## Project Settings > Layer Names > 2D Physics. rows[i] = layer i+1.
static func layers_card() -> Dictionary:
	var f := frame("Project Settings  ›  Layer Names  ›  2D Physics", "project.godot  [layer_names]")
	var rows := []
	var names := layer_names()
	for i in 5:
		rows.append(row(f["body"], ["Layer %d" % (i + 1), names[i]], [260, 0], 34))
	f["body"].add_child(label("Named once here, then picked by name in every scene's Collision Layer and Mask grids.", 24, DIM))
	f["rows"] = rows
	return f


## Collision layer / mask of each physics scene, read from the scenes.
static func collision_card() -> Dictionary:
	var f := frame("Collision layers and masks", "Scenes/*.tscn")
	var names := layer_names()
	var spec := [
		["debris", "res://Scenes/debris_piece.tscn", "", "DebrisPiece  (RigidBody2D)"],
		["barrier", "res://Scenes/barrier.tscn", "", "Barrier  (StaticBody2D)"],
		["bumper", "res://Scenes/crew_physics.tscn", "Bumper", "Crew bumper  (AnimatableBody2D)"],
		["sensor", "res://Scenes/crew_physics.tscn", "Sensor", "Crew sensor  (Area2D)"],
		["zone", "res://Scenes/incident_zone.tscn", "", "Incident zone  (Area2D)"],
	]
	row(f["body"], ["Node", "Collision layer", "Collision mask"], [520, 520, 0], 22, true)
	var rows := {}
	for s in spec:
		var inst: Node = load(s[1]).instantiate()
		var n: CollisionObject2D = inst if s[2] == "" else inst.get_node(s[2])
		rows[s[0]] = row(f["body"], [label(s[3], 26, TEXT), bits(n.collision_layer, names), bits(n.collision_mask, names)], [520, 520, 0])
		inst.free()
	f["rows"] = rows
	return f


## The seven PhysicsMaterials and the debris that uses each.
static func materials_card() -> Dictionary:
	var f := frame("Physics materials", "Data/physics_materials/*.tres")
	var users := {}
	for file in ResourceLoader.list_directory("res://Data/debris_types"):
		if file.ends_with(".tres"):
			var d: Resource = load("res://Data/debris_types/" + file)
			if d.physics_material:
				var key: String = d.physics_material.resource_name
				users[key] = users.get(key, []) + [d.display_name.to_lower()]
	users["concrete"] = ["road barriers"]
	row(f["body"], ["Material", "Friction", "Bounce", "Rough", "Absorbent", "Used by"], [230, 150, 150, 130, 160, 0], 22, true)
	var rows := {}
	for name in ["rubber", "glass", "metal", "wood", "plastic", "sandbag", "concrete"]:
		var m: PhysicsMaterial = load("res://Data/physics_materials/%s.tres" % name)
		rows[name] = row(f["body"], [name, "%.2f" % m.friction, "%.2f" % m.bounce, "yes" if m.rough else "-",
			"yes" if m.absorbent else "-", ", ".join(users.get(name, []))], [230, 150, 150, 130, 160, 0], 28)
	f["rows"] = rows
	return f


# --- Modular systems ------------------------------------------------------------------

## events.gd's signals on the left, who connects to them on the right.
static func events_card() -> Dictionary:
	var f := frame("Event bus", "Script/Autoload/events.gd")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	f["body"].add_child(cols)

	var code := RichTextLabel.new()
	code.bbcode_enabled = true
	code.fit_content = false
	code.scroll_active = false
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.size_flags_stretch_ratio = 1.5
	code.add_theme_font_override("normal_font", mono())
	code.add_theme_font_size_override("normal_font_size", 19)
	code.add_theme_stylebox_override("normal", _box(PANEL, 10, 22))
	var lines: Array[String] = []
	for line in FileAccess.get_file_as_string("res://Script/Autoload/events.gd").split("\n"):
		var t := line.strip_edges()
		if t.begins_with("# ---"):
			lines.append("[color=#%s]%s[/color]" % [COMMENT.to_html(false), t.replace("[", "[lb]")])
		elif t.begins_with("signal "):
			var rest := t.substr(7)
			var cut := rest.find("(")
			lines.append("[color=#%s]signal[/color] [color=#%s]%s[/color]%s" % [KEYWORD.to_html(false), NAME.to_html(false),
				rest.substr(0, cut), rest.substr(cut).replace("[", "[lb]")])
	code.text = "\n".join(lines)
	cols.add_child(code)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	right.add_child(label("Listeners  (Events.*.connect calls per script)", 24, DIM))
	var counts := {}
	for dir in ["res://Script/", "res://Script/Autoload/"]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".gd") and file != "events.gd":
				var text := FileAccess.get_file_as_string(dir + file)
				var re := RegEx.create_from_string("Events\\.\\w+\\.connect")
				var n := re.search_all(text).size()
				if n > 0:
					counts[file] = n
	var files := counts.keys()
	files.sort_custom(func(a, b) -> bool: return counts[a] > counts[b])
	var rows := {}
	for file in files:
		rows[file] = row(right, [file, str(counts[file])], [380, 0], 22)
	f["rows"] = rows
	return f


## Data/ folder tree on the left, car_crash.tres in an inspector on the right.
static func data_card() -> Dictionary:
	var f := frame("Data-driven types", "Data/")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	f["body"].add_child(cols)
	var tree := VBoxContainer.new()
	tree.custom_minimum_size.x = 640
	tree.add_theme_constant_override("separation", 6)
	cols.add_child(tree)
	var rows := {}
	for folder in ["crew_types", "debris_types", "incident_types", "physics_materials"]:
		var files := Array(ResourceLoader.list_directory("res://Data/" + folder)).filter(func(x: String) -> bool: return x.ends_with(".tres"))
		rows[folder] = row(tree, ["▾ %s/" % folder, "%d files" % files.size()], [420, 0], 24)
		if folder == "incident_types":
			for file in files:
				var r := row(tree, ["    " + file, ""], [420, 0], 18)
				rows[file] = r

	var insp := VBoxContainer.new()
	insp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	insp.add_theme_constant_override("separation", 6)
	insp.visible = false
	cols.add_child(insp)
	insp.add_child(label("Inspector  ›  car_crash.tres  (IncidentType)", 24, DIM))
	var t: Resource = load("res://Data/incident_types/car_crash.tres")
	var fields := [
		["display_name", t.display_name],
		["crew_types", str(Array(t.crew_types)).replace("&", "")],
		["time_limit_seconds", str(t.time_limit_seconds)],
		["resolve_seconds", str(t.resolve_seconds)],
		["min_stage", str(t.min_stage)],
		["where", "ROAD" if t.where == 0 else "FOI"],
		["blocks_road", str(t.blocks_road)],
		["road_classes", str(Array(t.road_classes))],
		["debris", str(Array(t.debris)).replace("&", "")],
		["debris_count", str(t.debris_count)],
	]
	for fld in fields:
		rows["field_" + fld[0]] = row(insp, [fld[0], fld[1]], [330, 0], 22)
	f["inspector"] = insp
	f["rows"] = rows
	return f


# --- Technical delivery ---------------------------------------------------------------------

static func _image(path: String, height: float) -> TextureRect:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(height * img.get_width() / img.get_height(), height)
	return tr


static func itch_card() -> Dictionary:
	var f := frame("itch.io page  ·  HTML5, plays in the browser", "docs/itch/ITCH_PAGE.md")
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 28)
	f["body"].add_child(top)
	top.add_child(_image("res://docs/itch/cover.png", 420))
	var txt := VBoxContainer.new()
	txt.add_theme_constant_override("separation", 14)
	top.add_child(txt)
	txt.add_child(label("The Race Against Time", 44, TEXT))
	txt.add_child(label("Dispatch emergency crews across a map that goes stale.", 28, ACCENT))
	txt.add_child(label("Kind: HTML (playable in browser)  ·  Genre: Strategy / Simulation", 22, DIM))
	txt.add_child(label("Web export: Godot 4.7, single-threaded (no SharedArrayBuffer needed)", 22, DIM))
	var shots := HBoxContainer.new()
	shots.add_theme_constant_override("separation", 20)
	f["body"].add_child(shots)
	for s in ["screenshot_1_dispatch", "screenshot_2_scene", "screenshot_3_report"]:
		shots.add_child(_image("res://docs/itch/%s.png" % s, 240))
	return f


## Markdown headings of a file as an outline.
static func outline_card(title: String, path: String) -> Dictionary:
	var f := frame(title, path.trim_prefix("res://"))
	var rows := {}
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("## ") or line.begins_with("### "):
			var deep := line.begins_with("### ")
			var text := line.trim_prefix("### ").trim_prefix("## ")
			rows[text] = row(f["body"], [("      " if deep else "") + text], [0], 22 if deep else 28)
	f["rows"] = rows
	return f


static func gitlog_card(lines: PackedStringArray) -> Dictionary:
	var f := frame("Version control  ·  GitHub", "git log --oneline")
	for line in lines:
		if line.strip_edges() != "":
			row(f["body"], [line.substr(0, 7), line.substr(8).left(100)], [150, 0], 21)
	return f


## Third-party rows of ATTRIBUTIONS.md: asset, author, licence.
static func attributions_card() -> Dictionary:
	var f := frame("Attributions", "ATTRIBUTIONS.md")
	row(f["body"], ["Asset", "Author / creator", "Licence"], [760, 520, 0], 20, true)
	var md := FileAccess.get_file_as_string("res://ATTRIBUTIONS.md")
	var section := md.substr(md.find("## Third-party assets"), md.find("## Team-created") - md.find("## Third-party assets"))
	var link := RegEx.create_from_string("\\[([^\\]]*)\\]\\([^)]*\\)")
	var rows := {}
	for line in section.split("\n"):
		if not line.begins_with("| ") or line.begins_with("| Asset") or line.begins_with("| ---"):
			continue
		var cells := line.split("|")
		var asset := link.sub(cells[1].strip_edges(), "$1", true).replace("**", "")
		var author := link.sub(cells[4].strip_edges(), "$1", true)
		var licence := link.sub(cells[5].strip_edges(), "$1", true).replace("**", "")
		licence = licence.get_slice(",", 0).get_slice(".", 0)
		rows[asset] = row(f["body"], [label(asset.left(60), 18, TEXT), label(author.left(44), 18, DIM), label(licence.left(30), 18, TEXT)], [760, 520, 0], 18)
	f["rows"] = rows
	return f
