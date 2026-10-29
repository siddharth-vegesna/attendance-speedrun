# Attendance Speedrun: title -> cutscene -> 60s run to class -> quiz -> PRESENT / ABSENT.
# The campus mesh comes from blender/build_campus.py (Blender coords, converted with B()).
extends Node3D

const D = preload("res://scripts/data.gd")
const Player = preload("res://scripts/player.gd")
const Door = preload("res://scripts/door.gd")

const FLOOR := 1.2
const UP := 6.2
const LOBBY_X := 14.0
const ROOM_W := 8.0
const CORR_Y0 := 25.0
const CORR_Y1 := 29.0
const DOOR_A := 1.0
const CUTSCENE_ROOM := 0
const SPAWN := Vector3(0, 0.2, 28)

enum State { TITLE, CUTSCENE, COUNTDOWN, RUN, QUIZ, RESULT }
var state := State.TITLE

var player: CharacterBody3D
var rooms := []
var npcs := []
var target_number := ""
var time_left := 0.0
var run_time := 0.0
var shuffle_timer := 0.0
var guide_timer := 0.0
var wrong_rooms := 0
var bonks := 0
var current_q := {}
var quiz_time := 0.0
var last_tick := 0
var rng := RandomNumberGenerator.new()

var font_bold: SystemFont
var font_serif: SystemFont
var sounds := {}

# UI
var title_panel: Control
var hud: Control
var timer_label: Label
var target_label: Label
var toast_label: Label
var big_label: Label
var flash: ColorRect
var fade: ColorRect
var quiz_panel: Control
var quiz_q: Label
var quiz_bar: ProgressBar
var quiz_buttons := []
var result_panel: Control
var result_stamp: Label
var result_text: Label
var dialog_panel: Control
var dialog_name: Label
var dialog_text: Label
var skip_button: Button
var toast_tween: Tween
var big_tween: Tween

# cutscene + guide
var cut_cam: Camera3D
var cut_student: Node3D
var cut_prof: Node3D
var cut_line := -1
var cut_chars := 0.0
var guide: Node3D
var guide_bubble: Label3D
var guide_line_timer := 0.0


static func B(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


func _ready() -> void:
	rng.randomize()
	font_bold = SystemFont.new()
	font_bold.font_names = PackedStringArray(["Arial Black", "Arial", "Helvetica"])
	font_serif = SystemFont.new()
	font_serif.font_names = PackedStringArray(["Times New Roman", "Georgia", "serif"])
	_build_environment()
	add_child(load("res://assets/campus.glb").instantiate())
	_build_lights()
	_build_rooms()
	_build_npcs()
	_build_guide()
	_build_cutscene()
	_build_ui()
	_load_sounds()
	player = Player.new()
	add_child(player)
	player.reset_to(SPAWN, 0)
	_show_title()
	if "--shots" in OS.get_cmdline_user_args():
		_debug_shots()


# ------------------------------------------------------------------ world
func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.55, 0.88)
	sky_mat.sky_horizon_color = Color(0.78, 0.86, 0.95)
	sky_mat.ground_horizon_color = Color(0.78, 0.82, 0.86)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.93, 0.9, 0.86)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_hdr_threshold = 1.2
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120
	add_child(sun)


func _omni(pos: Vector3, rng_: float, energy: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.omni_range = rng_
	l.light_energy = energy
	l.light_color = Color(1, 0.96, 0.9)
	add_child(l)


func _build_lights() -> void:
	_omni(B(0, 8, 10), 20, 1.6)
	_omni(B(-8, 7, 4), 12, 0.8)
	_omni(B(8, 7, 4), 12, 0.8)
	_omni(B(-8, 24, 4.5), 12, 0.8)
	_omni(B(8, 24, 4.5), 12, 0.8)
	_omni(B(0, 24, 10), 16, 1.0)
	for k in 8:
		var x0 := LOBBY_X + k * ROOM_W
		_omni(B(x0 + 4, 27, 9.3), 8, 0.8)
		_omni(B(x0 + 4, 33, 9.2), 9, 0.9)
		_omni(B(x0 + 4, 21, 9.2), 9, 0.9)


func _mat(c: Color, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emit > 0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _mesh(mesh: Mesh, pos: Vector3, c: Color, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(c, emit)
	return mi


func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2
	return s


func _label3d(text: String, size: int, color := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font_bold
	l.font_size = size
	l.pixel_size = 0.005
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.85)
	return l


func make_person(shirt: Color, pants: Color, seated := false, backpack := false) -> Node3D:
	var skins := [Color(0.78, 0.58, 0.42), Color(0.62, 0.43, 0.3), Color(0.88, 0.7, 0.55), Color(0.5, 0.34, 0.24)]
	var skin: Color = skins[rng.randi_range(0, skins.size() - 1)]
	var p := Node3D.new()
	if not seated:
		p.add_child(_mesh(_boxm(Vector3(0.36, 0.85, 0.24)), Vector3(0, 0.425, 0), pants))
	var torso := CapsuleMesh.new()
	torso.radius = 0.24
	torso.height = 0.8
	p.add_child(_mesh(torso, Vector3(0, 1.22, 0), shirt))
	p.add_child(_mesh(_sphere(0.17), Vector3(0, 1.72, 0), skin))
	var hair := _mesh(_sphere(0.175), Vector3(0, 1.78, 0.02), Color(0.07, 0.05, 0.04))
	hair.scale = Vector3(1, 0.65, 1)
	p.add_child(hair)
	for ex in [-0.06, 0.06]:
		p.add_child(_mesh(_sphere(0.025), Vector3(ex, 1.73, -0.155), Color.BLACK))
	if backpack:
		p.add_child(_mesh(_boxm(Vector3(0.36, 0.45, 0.18)), Vector3(0, 1.25, 0.28), Color(0.12, 0.12, 0.14)))
	if seated:
		p.position.y = -0.42
	return p


func _attach_collider(body_parent: Node3D) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	sb.add_child(cs)
	body_parent.add_child(sb)


# ------------------------------------------------------------------ rooms
func _build_rooms() -> void:
	var shirts := [Color(0.85, 0.3, 0.3), Color(0.3, 0.6, 0.35), Color(0.95, 0.85, 0.3)]
	for k in 8:
		for north in [true, false]:
			var x0 := LOBBY_X + k * ROOM_W
			var wall_y := CORR_Y1 + 0.1 if north else CORR_Y0 - 0.1
			var into := 1.0 if north else -1.0
			var r := {"x0": x0, "north": north, "number": "", "wall_y": wall_y, "into": into}

			var sign_root := Node3D.new()
			sign_root.position = B(x0 + 3.2, wall_y - into * 0.16, 8.1)
			if not north:
				sign_root.rotation.y = PI
			sign_root.add_child(_mesh(_boxm(Vector3(1.2, 0.5, 0.04)), Vector3(0, 0, -0.03), Color(0.12, 0.16, 0.38)))
			var lbl := _label3d("", 72)
			lbl.position.z = 0.01
			lbl.outline_size = 0
			sign_root.add_child(lbl)
			add_child(sign_root)
			r.label = lbl

			var door := Door.new()
			door.position = B(x0 + DOOR_A, wall_y, UP)
			add_child(door)
			door.setup(into, Vector3(0, 0, into), Color(0.55, 0.36, 0.22))
			door.bonked.connect(_on_bonk)
			r.door = door

			var area := Area3D.new()
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(7.2, 3.0, 6.8)
			cs.shape = bs
			area.add_child(cs)
			area.position = B(x0 + 4, wall_y + into * 4.6, UP + 1.5)
			add_child(area)
			area.body_entered.connect(_on_room_entered.bind(rooms.size()))

			# the same three students in the same seats in every single room
			for s in 3:
				var dy := 1.6 + (s + 1) * 1.25 - 0.32
				var col: float = [-2.6, 0.0, 2.6][s]
				var p := make_person(shirts[s], Color(0.2, 0.2, 0.3), true)
				p.position += B(x0 + 4 + col - 0.45, wall_y + into * dy, UP)
				p.rotation.y = 0.0 if north else PI
				add_child(p)
			rooms.append(r)


func _assign_numbers() -> void:
	var nums := []
	for i in rooms.size():
		nums.append("%s%d" % [D.ROOM_PREFIX, D.FIRST_ROOM + i])
	nums.shuffle()
	for i in rooms.size():
		rooms[i].number = nums[i]
		rooms[i].label.text = nums[i]
		rooms[i].label.modulate = Color.WHITE


func _shuffle_signs() -> void:
	# Never reshuffle the room the player is standing next to; that would be too evil.
	var eligible := []
	for i in rooms.size():
		var r = rooms[i]
		var door_pos: Vector3 = B(r.x0 + 1.7, r.wall_y, UP)
		if player.global_position.distance_to(door_pos) > 5.0:
			eligible.append(i)
	var nums := []
	for i in eligible:
		nums.append(rooms[i].number)
	nums.shuffle()
	for j in eligible.size():
		var r = rooms[eligible[j]]
		r.number = nums[j]
		var lbl: Label3D = r.label
		var tw := create_tween()
		tw.tween_property(lbl, "modulate", Color(1, 0.3, 0.3), 0.15)
		tw.tween_callback(func(): lbl.text = r.number)
		tw.tween_property(lbl, "modulate", Color.WHITE, 0.3)
	_toast("FACILITIES AI: Room numbers re-optimized for efficiency.")


# ------------------------------------------------------------------ NPCs + guide
func _build_npcs() -> void:
	var spots := [
		[B(-4, 13, FLOOR), 0.3], [B(-3.2, 12.4, FLOOR), 2.4], [B(-4.4, 12.0, FLOOR), 4.0],
		[B(4.5, 11, FLOOR), 1.0], [B(5.2, 11.8, FLOOR), 3.5],
		[B(3, 5.5, FLOOR), 0.0], [B(-6, 4, FLOOR), 1.7], [B(9, 17.5, FLOOR), 2.2],
		[B(-3, -6.5, 0.9), 3.1], [B(-2.2, -6.6, 0.9), 2.9], [B(6, 20, UP), 1.2], [B(30, 27.5, UP), 1.5],
	]
	var shirts := [Color(0.2, 0.3, 0.75), Color(0.9, 0.9, 0.9), Color(0.15, 0.15, 0.15), Color(0.85, 0.5, 0.6),
		Color(0.4, 0.55, 0.35), Color(0.75, 0.2, 0.25)]
	for i in spots.size():
		var p := make_person(shirts[i % shirts.size()], Color(0.18, 0.2, 0.3), false, i % 2 == 0)
		p.position = spots[i][0]
		p.rotation.y = spots[i][1]
		_attach_collider(p)
		var bubble := _label3d(D.NPC_LINES[i % D.NPC_LINES.size()], 36, Color(1, 1, 0.85))
		bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bubble.position.y = 2.2
		bubble.visible = false
		p.add_child(bubble)
		add_child(p)
		npcs.append({"node": p, "bubble": bubble})


func _build_guide() -> void:
	guide = Node3D.new()
	guide.position = B(11.5, 5, FLOOR + 2.0)
	guide.add_child(_mesh(_sphere(0.35), Vector3.ZERO, Color(0.92, 0.95, 1.0)))
	guide.add_child(_mesh(_boxm(Vector3(0.4, 0.22, 0.05)), Vector3(0, 0.03, 0.33), Color(0.1, 0.12, 0.2)))
	for ex in [-0.08, 0.08]:
		guide.add_child(_mesh(_sphere(0.035), Vector3(ex, 0.05, 0.36), Color(0.3, 1, 0.9), 4.0))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.47
	guide.add_child(_mesh(ring, Vector3(0, -0.15, 0), Color(0.3, 1, 0.9), 3.0))
	var name_l := _label3d("CampusGPT", 40, Color(0.4, 1, 0.9))
	name_l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_l.position.y = 0.6
	guide.add_child(name_l)
	guide_bubble = _label3d(D.GUIDE_LINES[0], 34, Color.WHITE)
	guide_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	guide_bubble.position.y = 0.95
	guide_bubble.width = 900
	guide_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD
	guide.add_child(guide_bubble)
	add_child(guide)


# ------------------------------------------------------------------ cutscene
func _build_cutscene() -> void:
	cut_cam = Camera3D.new()
	cut_cam.fov = 70
	add_child(cut_cam)
	cut_cam.look_at_from_position(B(21.2, 30.0, UP + 2.2), B(16.8, 35.0, UP + 1.3))
	cut_student = make_person(Color(0.2, 0.3, 0.8), Color(0.85, 0.8, 0.7), false, true)
	add_child(cut_student)
	cut_prof = make_person(Color(0.95, 0.95, 0.95), Color(0.2, 0.2, 0.22))
	# glasses + moustache so he looks like he has seen things
	cut_prof.add_child(_mesh(_boxm(Vector3(0.24, 0.05, 0.02)), Vector3(0, 1.74, -0.17), Color.BLACK))
	cut_prof.add_child(_mesh(_boxm(Vector3(0.14, 0.03, 0.03)), Vector3(0, 1.64, -0.165), Color(0.15, 0.1, 0.08)))
	add_child(cut_prof)
	var board_text := _label3d("ATTENDANCE\n= EARNED", 64, Color(0.15, 0.2, 0.6))
	board_text.outline_size = 0
	board_text.position = B(18, 36.85, UP + 1.75)
	board_text.rotation.y = 0
	add_child(board_text)


func _start_cutscene() -> void:
	state = State.CUTSCENE
	title_panel.visible = false
	hud.visible = false
	cut_cam.look_at_from_position(B(21.2, 30.0, UP + 2.2), B(16.8, 35.0, UP + 1.3))
	cut_cam.current = true
	rooms[CUTSCENE_ROOM].door.open_instant()
	cut_student.position = B(15.7, 26.6, UP)
	cut_student.rotation.y = 0
	cut_prof.position = B(17.2, 35.6, UP)
	cut_prof.rotation.y = PI
	dialog_panel.visible = true
	skip_button.visible = true
	dialog_name.text = ""
	dialog_text.text = ""
	cut_line = -1
	_fade_in()
	_sfx("door")
	var tw := create_tween()
	tw.tween_property(cut_student, "position", B(15.7, 31.0, UP), 1.2)
	tw.tween_property(cut_student, "position", B(16.6, 33.4, UP), 0.8)
	tw.parallel().tween_property(cut_student, "rotation:y", -0.3, 0.8)
	tw.tween_callback(_next_line)


func _next_line() -> void:
	if state != State.CUTSCENE:
		return
	cut_line += 1
	if cut_line >= D.CUTSCENE.size():
		_end_cutscene()
		return
	var line: Array = D.CUTSCENE[cut_line]
	var speaker: String = line[0]
	dialog_name.text = "YOU (LATE)" if speaker == "STUDENT" else "THE PROFESSOR"
	dialog_name.modulate = Color(0.5, 0.75, 1) if speaker == "STUDENT" else Color(1, 0.85, 0.3)
	dialog_text.text = line[1]
	dialog_text.visible_characters = 0
	cut_chars = 0.0
	var who := cut_student if speaker == "STUDENT" else cut_prof
	var tw := create_tween()
	tw.tween_property(who, "scale", Vector3(1, 1.08, 1), 0.08)
	tw.tween_property(who, "scale", Vector3.ONE, 0.12)
	tw.tween_property(who, "scale", Vector3(1, 1.05, 1), 0.08)
	tw.tween_property(who, "scale", Vector3.ONE, 0.12)


func _advance_dialog() -> void:
	if cut_line < 0:
		return
	var typing := dialog_text.visible_characters != -1 \
		and dialog_text.visible_characters < dialog_text.text.length()
	if typing:
		dialog_text.visible_characters = -1
		cut_chars = 9999.0
	else:
		_next_line()


func _end_cutscene() -> void:
	state = State.COUNTDOWN
	dialog_panel.visible = false
	skip_button.visible = false
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.5)
	tw.tween_callback(_begin_run)


# ------------------------------------------------------------------ run
func _begin_run() -> void:
	state = State.COUNTDOWN
	title_panel.visible = false
	result_panel.visible = false
	quiz_panel.visible = false
	dialog_panel.visible = false
	skip_button.visible = false
	_assign_numbers()
	var pick := rng.randi_range(0, rooms.size() - 1)
	while pick == CUTSCENE_ROOM:
		pick = rng.randi_range(0, rooms.size() - 1)
	target_number = rooms[pick].number
	for i in rooms.size():
		rooms[i].door.reset(i != CUTSCENE_ROOM and rng.randf() < D.BONK_CHANCE)
		rooms[i].door.enabled = false
	rooms[CUTSCENE_ROOM].door.open_instant()
	time_left = D.TIME_LIMIT
	run_time = 0.0
	shuffle_timer = D.SHUFFLE_EVERY
	guide_timer = 4.0
	wrong_rooms = 0
	bonks = 0
	last_tick = 99
	player.reset_to(SPAWN, 0)
	player.frozen = true
	player.cam.current = true
	hud.visible = true
	target_label.text = "YOUR CLASS:  %s" % target_number
	timer_label.text = "%.1f" % time_left
	timer_label.modulate = Color.WHITE
	_fade_in()
	var tw := create_tween()
	for n in ["3", "2", "1"]:
		tw.tween_callback(func(): _big(n, Color.WHITE); _sfx("beep"))
		tw.tween_interval(0.7)
	tw.tween_callback(_go)


func _go() -> void:
	_big("GO!", Color(0.4, 1, 0.5))
	_sfx("go")
	state = State.RUN
	player.frozen = false
	for r in rooms:
		r.door.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_toast("CampusGPT: I have calculated the optimal route. Please turn around.")


func _on_room_entered(body: Node3D, idx: int) -> void:
	if body != player or state != State.RUN:
		return
	var r = rooms[idx]
	if r.number == target_number:
		_start_quiz()
		return
	time_left -= D.WRONG_ROOM_PENALTY
	wrong_rooms += 1
	_flash(Color(1, 0, 0, 0.4))
	_big("WRONG ROOM  -%ds" % int(D.WRONG_ROOM_PENALTY), Color(1, 0.35, 0.35))
	_toast(D.WRONG_ROOM_LINES[rng.randi_range(0, D.WRONG_ROOM_LINES.size() - 1)])
	_sfx("buzzer")
	var out: Vector3 = B(r.x0 + 1.7, r.wall_y - r.into * 1.5, UP + 1)
	player.knockback(out - player.global_position, 13.0, 4.0)


func _on_bonk() -> void:
	bonks += 1
	_sfx("bonk")
	_flash(Color(1, 1, 1, 0.5))
	_big("BONK!", Color(1, 0.85, 0.2))
	_toast("A door opened outward. Fire safety regulations, apparently.")


# ------------------------------------------------------------------ quiz + result
func _start_quiz() -> void:
	state = State.QUIZ
	player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sfx("ding")
	current_q = D.QUESTIONS[rng.randi_range(0, D.QUESTIONS.size() - 1)]
	quiz_q.text = current_q.q
	for i in 4:
		quiz_buttons[i].text = "%s)   %s" % ["ABCD"[i], current_q.a[i]]
		quiz_buttons[i].disabled = false
	quiz_time = D.QUIZ_TIME
	quiz_panel.visible = true


func _on_answer(i: int) -> void:
	if state != State.QUIZ:
		return
	if i == int(current_q.correct):
		_end(true, "You made it in %.1f seconds AND you know what happened last class.\nThe professor is visibly disappointed." % run_time)
	else:
		_end(false, D.WRONG_ANSWER_LINES[rng.randi_range(0, D.WRONG_ANSWER_LINES.size() - 1)]
			+ "\nCorrect answer: " + str(current_q.a[int(current_q.correct)]))


func _end(present: bool, reason: String) -> void:
	state = State.RESULT
	player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	quiz_panel.visible = false
	hud.visible = false
	result_panel.visible = true
	result_stamp.text = "PRESENT" if present else "ABSENT"
	result_stamp.modulate = Color(0.3, 0.95, 0.45) if present else Color(1, 0.25, 0.25)
	var att := "Attendance: 75.01%  (survived... for now)" if present else "Attendance: 74.99%  (DEBARRED FROM EXAMS)"
	result_text.text = "%s\n\nTime: %.1fs   |   Wrong rooms: %d   |   Doors to the face: %d\n%s" % [
		reason, run_time, wrong_rooms, bonks, att]
	result_stamp.pivot_offset = result_stamp.size / 2
	result_stamp.scale = Vector2(3, 3)
	result_stamp.rotation = -0.2
	var tw := create_tween()
	tw.tween_property(result_stamp, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _sfx("stamp" if present else "buzzer"))


# ------------------------------------------------------------------ loop + input
func _process(delta: float) -> void:
	guide.position.y = FLOOR + 2.0 + sin(Time.get_ticks_msec() * 0.003) * 0.12
	guide.rotate_y(delta * 0.8)
	guide_line_timer -= delta
	if guide_line_timer <= 0:
		guide_line_timer = 4.0
		guide_bubble.text = D.GUIDE_LINES[rng.randi_range(0, D.GUIDE_LINES.size() - 1)]
	for n in npcs:
		n.bubble.visible = n.node.global_position.distance_to(player.global_position) < 6.0 and state == State.RUN

	match state:
		State.CUTSCENE:
			if cut_line >= 0 and dialog_text.visible_characters != -1:
				var before := int(cut_chars)
				cut_chars += delta * 45.0
				if int(cut_chars) != before and int(cut_chars) % 3 == 0:
					_sfx("blip")
				dialog_text.visible_characters = int(cut_chars)
				if cut_chars >= dialog_text.text.length():
					dialog_text.visible_characters = -1
		State.RUN:
			time_left -= delta
			run_time += delta
			timer_label.text = "%.1f" % max(time_left, 0.0)
			if time_left < 10:
				timer_label.modulate = Color(1, 0.3, 0.3)
				if int(time_left) != last_tick:
					last_tick = int(time_left)
					_sfx("tick")
			shuffle_timer -= delta
			if shuffle_timer <= 0:
				shuffle_timer = D.SHUFFLE_EVERY
				_shuffle_signs()
			guide_timer -= delta
			if guide_timer <= 0:
				guide_timer = 9.0
				_toast("CampusGPT: " + D.GUIDE_LINES[rng.randi_range(0, D.GUIDE_LINES.size() - 1)])
			if player.global_position.y < -15:
				player.reset_to(SPAWN, 0)
			if time_left <= 0:
				_end(false, D.TIMEOUT_LINES[rng.randi_range(0, D.TIMEOUT_LINES.size() - 1)])
		State.QUIZ:
			quiz_time -= delta
			quiz_bar.value = quiz_time / D.QUIZ_TIME * 100.0
			if quiz_time <= 0:
				_end(false, "You took too long to remember what happened. Suspicious.")


func _input(e: InputEvent) -> void:
	var pressed_advance: bool = (e is InputEventKey and e.pressed and not e.echo
		and e.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]) \
		or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	match state:
		State.CUTSCENE:
			if pressed_advance:
				_advance_dialog()
				get_viewport().set_input_as_handled()
		State.RUN:
			if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			elif e is InputEventMouseButton and e.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif e is InputEventKey and e.pressed and e.keycode == KEY_R:
				_begin_run()


# ------------------------------------------------------------------ UI
func _lbl(text: String, size: int, color := Color.WHITE, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font if font else font_bold)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _btn(text: String, size: int, bg: Color, fg := Color.BLACK) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg.lightened(0.15) if st == "hover" else bg
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 28
		sb.content_margin_right = 28
		sb.content_margin_top = 14
		sb.content_margin_bottom = 14
		b.add_theme_stylebox_override(st, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, fg)
	return b


func _panel_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 30
	sb.content_margin_bottom = 30
	return sb


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# --- HUD
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	timer_label = _lbl("60.0", 72)
	timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_label.position = Vector2(-150, 20)
	timer_label.size = Vector2(300, 90)
	hud.add_child(timer_label)
	var tbox := PanelContainer.new()
	tbox.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.1, 0.25, 0.85)))
	tbox.position = Vector2(24, 24)
	var tv := VBoxContainer.new()
	tbox.add_child(tv)
	target_label = _lbl("YOUR CLASS: B-201", 34, Color(1, 0.85, 0.3))
	tv.add_child(target_label)
	tv.add_child(_lbl("Signs may change. Facilities is optimizing.", 16, Color(0.8, 0.85, 1)))
	hud.add_child(tbox)
	toast_label = _lbl("", 26, Color(0.85, 1, 0.95))
	toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.position = Vector2(-700, -110)
	toast_label.size = Vector2(1400, 60)
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	hud.add_child(toast_label)
	var cross := ColorRect.new()
	cross.color = Color(1, 1, 1, 0.8)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.size = Vector2(6, 6)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-3, -3)
	hud.add_child(cross)
	hud.add_child(_lbl_at("WASD move  -  Mouse look  -  Shift sprint  -  Space jump  -  R restart", 16,
		Control.PRESET_BOTTOM_RIGHT, Vector2(-760, -40), Vector2(740, 30), Color(1, 1, 1, 0.6)))
	hud.visible = false

	big_label = _lbl("", 110, Color.WHITE)
	big_label.set_anchors_preset(Control.PRESET_CENTER)
	big_label.position = Vector2(-700, -200)
	big_label.size = Vector2(1400, 160)
	big_label.modulate.a = 0
	big_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(big_label)

	flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 0, 0, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)

	# --- dialog
	dialog_panel = PanelContainer.new()
	dialog_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.06, 0.12, 0.92)))
	dialog_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dialog_panel.offset_top = -230
	dialog_panel.offset_bottom = -30
	dialog_panel.offset_left = 120
	dialog_panel.offset_right = -120
	var dv := VBoxContainer.new()
	dialog_panel.add_child(dv)
	dialog_name = _lbl("", 26, Color.WHITE)
	dialog_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	dv.add_child(dialog_name)
	dialog_text = _lbl("", 32, Color.WHITE, font_serif)
	dialog_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	dialog_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(dialog_text)
	var hint := _lbl("click / space  >>", 16, Color(1, 1, 1, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dv.add_child(hint)
	dialog_panel.visible = false
	root.add_child(dialog_panel)
	skip_button = _btn("SKIP  >>", 20, Color(1, 1, 1, 0.85))
	skip_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip_button.position = Vector2(-200, 24)
	skip_button.pressed.connect(_end_cutscene)
	skip_button.visible = false
	root.add_child(skip_button)

	# --- quiz
	quiz_panel = CenterContainer.new()
	quiz_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var qp := PanelContainer.new()
	qp.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.08, 0.2, 0.96)))
	qp.custom_minimum_size = Vector2(1000, 0)
	quiz_panel.add_child(qp)
	var qv := VBoxContainer.new()
	qv.add_theme_constant_override("separation", 14)
	qp.add_child(qv)
	qv.add_child(_lbl("ATTENDANCE VERIFICATION  -  STEP 2 OF 2", 22, Color(1, 0.85, 0.3)))
	qv.add_child(_lbl("Prove you were here last class.", 18, Color(0.8, 0.85, 1)))
	quiz_q = _lbl("", 36, Color.WHITE, font_serif)
	quiz_q.autowrap_mode = TextServer.AUTOWRAP_WORD
	quiz_q.custom_minimum_size = Vector2(920, 0)
	qv.add_child(quiz_q)
	for i in 4:
		var b := _btn("", 24, Color(0.92, 0.92, 0.96))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_answer.bind(i))
		qv.add_child(b)
		quiz_buttons.append(b)
	quiz_bar = ProgressBar.new()
	quiz_bar.show_percentage = false
	quiz_bar.custom_minimum_size = Vector2(0, 14)
	qv.add_child(quiz_bar)
	quiz_panel.visible = false
	root.add_child(quiz_panel)

	# --- result
	result_panel = ColorRect.new()
	result_panel.color = Color(0, 0, 0, 0.75)
	result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var rc := CenterContainer.new()
	rc.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(rc)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 22)
	rc.add_child(rv)
	result_stamp = _lbl("PRESENT", 150, Color.WHITE)
	rv.add_child(result_stamp)
	result_text = _lbl("", 26, Color.WHITE)
	result_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	result_text.custom_minimum_size = Vector2(1100, 0)
	rv.add_child(result_text)
	var rh := HBoxContainer.new()
	rh.alignment = BoxContainer.ALIGNMENT_CENTER
	rh.add_theme_constant_override("separation", 20)
	var again := _btn("TRY AGAIN", 28, Color(1, 0.84, 0.25))
	again.pressed.connect(_begin_run)
	var to_title := _btn("BACK TO TITLE", 28, Color(0.85, 0.88, 0.95))
	to_title.pressed.connect(_show_title)
	rh.add_child(again)
	rh.add_child(to_title)
	rv.add_child(rh)
	result_panel.visible = false
	root.add_child(result_panel)

	# --- title
	title_panel = ColorRect.new()
	title_panel.color = Color(0.05, 0.07, 0.17, 0.93)
	title_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var tc := CenterContainer.new()
	tc.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_panel.add_child(tc)
	var tvb := VBoxContainer.new()
	tvb.add_theme_constant_override("separation", 16)
	tc.add_child(tvb)
	tvb.add_child(_lbl("BITS PILANI, DUBAI CAMPUS", 22, Color(1, 0.8, 0.35)))
	tvb.add_child(_lbl("SMART ATTENDANCE SYSTEM v7.0", 64, Color.WHITE))
	var hist := RichTextLabel.new()
	hist.bbcode_enabled = true
	hist.fit_content = true
	hist.scroll_active = false
	hist.custom_minimum_size = Vector2(900, 0)
	hist.add_theme_font_override("normal_font", font_serif)
	hist.add_theme_font_size_override("normal_font_size", 28)
	hist.text = "[center][s]Roll call[/s]  -  too slow\n[s]Signing a sheet[/s]  -  too slow\n[s]Scanning a QR code[/s]  -  too slow\n[s]Facial recognition[/s]  -  [color=#ff6060]TOO EASY[/color]\n\n[color=#ffd84a]NEW: Speedrun-Based Attendance Verification[/color][/center]"
	tvb.add_child(hist)
	tvb.add_child(_lbl("Reach your classroom in 60 seconds. Then answer one question about last class.\nFail either and you are ABSENT.", 20, Color(0.82, 0.86, 1)))
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_theme_constant_override("separation", 20)
	var start := _btn("MARK MY ATTENDANCE", 34, Color(1, 0.84, 0.25))
	start.pressed.connect(_start_cutscene)
	var skip := _btn("skip story", 22, Color(0.3, 0.33, 0.5), Color.WHITE)
	skip.pressed.connect(_begin_run)
	bh.add_child(start)
	bh.add_child(skip)
	tvb.add_child(bh)
	tvb.add_child(_lbl("Facial recognition has been deprecated for being too convenient.", 15, Color(1, 1, 1, 0.45)))
	root.add_child(title_panel)

	fade = ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)


func _lbl_at(text: String, size: int, preset: int, pos: Vector2, sz: Vector2, color: Color) -> Label:
	var l := _lbl(text, size, color)
	l.set_anchors_preset(preset)
	l.position = pos
	l.size = sz
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _show_title() -> void:
	state = State.TITLE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	result_panel.visible = false
	quiz_panel.visible = false
	hud.visible = false
	title_panel.visible = true
	player.frozen = true
	# slow pan over the entrance behind the title card
	cut_cam.look_at_from_position(B(-14, -32, 5), B(0, 0, 8))
	cut_cam.current = true


func _toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1
	if toast_tween:
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(3.5)
	toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)


func _big(text: String, color: Color) -> void:
	big_label.text = text
	big_label.add_theme_color_override("font_color", color)
	big_label.modulate.a = 1
	big_label.pivot_offset = big_label.size / 2
	big_label.scale = Vector2(1.4, 1.4)
	if big_tween:
		big_tween.kill()
	big_tween = create_tween()
	big_tween.tween_property(big_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	big_tween.tween_interval(0.5)
	big_tween.tween_property(big_label, "modulate:a", 0.0, 0.3)


func _flash(c: Color) -> void:
	flash.color = c
	create_tween().tween_property(flash, "color:a", 0.0, 0.5)


func _fade_in() -> void:
	fade.color.a = 1
	create_tween().tween_property(fade, "color:a", 0.0, 0.6)


func _load_sounds() -> void:
	for n in ["bonk", "buzzer", "tick", "ding", "stamp", "door", "beep", "go", "blip"]:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/sfx/%s.wav" % n)
		add_child(p)
		sounds[n] = p


func _sfx(n: String) -> void:
	if sounds.has(n):
		sounds[n].play()


# ------------------------------------------------------------------ debug screenshots
# godot --path game -- --shots   saves screenshots of key moments to shots/ and quits.
func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://../shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir + "/" + name + ".png")


func _debug_shots() -> void:
	await get_tree().create_timer(1.0).timeout
	await _snap("01_title")
	_start_cutscene()
	await get_tree().create_timer(3.0).timeout
	await _snap("02_cutscene")
	for i in 6:
		var ev := InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().create_timer(0.3).timeout
	print("TEST cutscene line after 6 presses: ", cut_line)
	_begin_run()
	await get_tree().create_timer(3.0).timeout
	await _snap("03_plaza")
	var yaw_before := player.rotation.y
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(200, 0)
	Input.parse_input_event(mm)
	await get_tree().create_timer(0.2).timeout
	print("TEST mouse turn: yaw changed by ", player.rotation.y - yaw_before, " mouse_mode=", Input.mouse_mode)
	player.reset_to(B(0, 4, FLOOR + 0.1), 0)
	await get_tree().create_timer(0.5).timeout
	await _snap("04_lobby")
	player.reset_to(B(-11, 9, FLOOR + 0.1), -PI / 2)
	await get_tree().create_timer(0.5).timeout
	await _snap("05_lobby_side")
	player.reset_to(B(16, 27, UP + 0.1), -PI / 2)
	await get_tree().create_timer(0.5).timeout
	await _snap("06_corridor")
	var test_room = rooms[5]
	test_room.door.reset(true)
	test_room.door.enabled = true
	player.reset_to(B(test_room.x0 + 1.7, test_room.wall_y - test_room.into * 1.0, UP + 0.1), 0)
	await get_tree().create_timer(0.6).timeout
	print("TEST bonks=", bonks, " door_open=", test_room.door.is_open)
	var wrong_idx := 3 if rooms[3].number != target_number else 4
	var t_before := time_left
	player.reset_to(B(rooms[wrong_idx].x0 + 4, rooms[wrong_idx].wall_y + rooms[wrong_idx].into * 4, UP + 0.1), 0)
	await get_tree().create_timer(0.5).timeout
	print("TEST wrong_rooms=", wrong_rooms, " penalty=", t_before - time_left)
	await _snap("06b_wrong_room")
	_start_quiz()
	await get_tree().create_timer(0.3).timeout
	await _snap("07_quiz")
	_on_answer(int(current_q.correct))
	await get_tree().create_timer(0.6).timeout
	await _snap("08_result")
	get_tree().quit()
