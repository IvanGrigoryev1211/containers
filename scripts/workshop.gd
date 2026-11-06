extends Node3D

## Compact, intentionally plain first-person workshop greybox.
## All dimensions are metres in Godot units.

const PLAYER_SPEED := 4.5
const PLAYER_HEIGHT := 1.7
const INTERACTION_DISTANCE := 4.0

@export_category("Player settings")
@export_range(50.0, 110.0, 1.0) var camera_fov := 75.0
@export_range(0.01, 1.0, 0.01) var mouse_sensitivity := 0.12

var player: CharacterBody3D
var camera_pivot: Node3D
var camera: Camera3D
var prompt_label: Label
var debug_label: Label
var target_station: StaticBody3D
var debug_timer := 0.0
var debug_panel: CanvasLayer
var game_state: Variant


func _ready() -> void:

	game_state = get_node("/root/GameState")
	_setup_input_actions()
	_build_lighting_and_environment()
	_build_room()
	_build_stations()
	_build_player()
	_build_ui()
	_build_debug_panel()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	if debug_timer > 0.0:
		debug_timer -= delta
		if debug_timer <= 0.0:
			debug_label.text = ""

	_update_interaction_target()


func _physics_process(_delta: float) -> void:
	if player == null:
		return

	var move_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var local_direction := Vector3(move_input.x, 0.0, move_input.y)
	var world_direction := (player.global_transform.basis * local_direction).normalized()
	player.velocity.x = world_direction.x * PLAYER_SPEED
	player.velocity.z = world_direction.z * PLAYER_SPEED
	player.velocity.y = 0.0
	player.move_and_slide()


func _input(event: InputEvent) -> void:
	# Use the physical E key directly as well as the InputMap action. This keeps
	# interaction available even when a UI control has already handled the event.
	if event is InputEventKey and event.pressed and not event.echo:
		# DEBUG-ONLY: remove these shortcuts once a real economy interface exists.
		if event.physical_keycode == KEY_F2 or event.keycode == KEY_F2:
			game_state.earn(100, "DEBUG F2")
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_F3 or event.keycode == KEY_F3:
			game_state.spend(100, "DEBUG F3")
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_F4 or event.keycode == KEY_F4:
			game_state.reset_for_debug()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_E or event.keycode == KEY_E:
			_update_interaction_target()
			_interact_with_target()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("release_cursor"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		camera_pivot.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivity))
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))


func _setup_input_actions() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("interact", KEY_E)
	_add_key_action("release_cursor", KEY_ESCAPE)


func _add_key_action(action_name: StringName, key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var input_event := InputEventKey.new()
	input_event.physical_keycode = key
	InputMap.action_add_event(action_name, input_event)


func _build_lighting_and_environment() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("1d2228")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c9d1d9")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.light_energy = 1.25
	light.shadow_enabled = true
	add_child(light)

	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(0.0, 3.5, 0.0)
	fill_light.light_color = Color("dce7f2")
	fill_light.light_energy = 2.0
	fill_light.omni_range = 12.0
	add_child(fill_light)


func _build_room() -> void:
	var room_material := _material(Color("6d7279"))
	var floor_material := _material(Color("484d53"))
	var dark_material := _material(Color("3c4147"))

	_add_solid_box("Floor", Vector3(0.0, -0.15, 0.0), Vector3(12.0, 0.3, 10.0), floor_material)
	_add_solid_box("BackWall", Vector3(0.0, 2.0, -5.0), Vector3(12.0, 4.0, 0.25), room_material)
	_add_solid_box("LeftWall", Vector3(-6.0, 2.0, 0.0), Vector3(0.25, 4.0, 10.0), room_material)
	_add_solid_box("RightWall", Vector3(6.0, 2.0, 0.0), Vector3(0.25, 4.0, 10.0), room_material)
	_add_solid_box("Counter", Vector3(0.0, 0.8, 2.25), Vector3(4.2, 1.6, 0.8), dark_material)

	# Ceiling rails give a restrained sense of room scale without decorative art.
	for x in [-3.0, 0.0, 3.0]:
		_add_visual_box("CeilingRail", Vector3(x, 3.85, 0.0), Vector3(0.12, 0.12, 9.4), dark_material)


func _build_stations() -> void:
	var station_data := [
		["Терминал аукциона", Vector3(-4.15, 0.0, -3.95), Color("4b7f9e")],
		["Стол вскрытия", Vector3(-1.4, 0.0, -3.95), Color("8a6f50")],
		["Рабочий стол", Vector3(1.4, 0.0, -3.95), Color("647a58")],
		["Терминал продажи", Vector3(4.15, 0.0, -3.95), Color("916568")],
		["Стойка улучшения", Vector3(4.65, 0.0, 1.3), Color("7564a0")],
	]

	for station_info in station_data:
		_create_station(station_info[0], station_info[1], station_info[2])


func _create_station(station_name: String, position_3d: Vector3, accent: Color) -> void:
	var station := StaticBody3D.new()
	station.name = station_name.replace(" ", "_")
	station.position = position_3d
	station.set_meta("station_name", station_name)
	add_child(station)

	var base_material := _material(Color("555a60"))
	var accent_material := _material(accent)
	var top_material := _material(Color("858b91"))
	_add_box_to(station, Vector3(0.0, 0.5, 0.0), Vector3(2.05, 1.0, 0.85), base_material, true)
	_add_box_to(station, Vector3(0.0, 1.05, 0.0), Vector3(2.25, 0.12, 1.0), top_material, true)
	_add_box_to(station, Vector3(-0.78, 0.78, 0.46), Vector3(0.22, 0.3, 0.06), accent_material, false)

	if "Терминал" in station_name:
		_add_box_to(station, Vector3(0.0, 1.52, -0.1), Vector3(0.92, 0.62, 0.12), accent_material, true)
		_add_box_to(station, Vector3(0.0, 1.18, 0.0), Vector3(0.12, 0.28, 0.12), base_material, true)
	elif station_name == "Стол вскрытия":
		_add_box_to(station, Vector3(0.0, 1.19, 0.0), Vector3(1.18, 0.18, 0.58), accent_material, true)
		_add_box_to(station, Vector3(0.58, 1.26, 0.0), Vector3(0.18, 0.25, 0.25), top_material, true)
	elif station_name == "Рабочий стол":
		_add_box_to(station, Vector3(-0.5, 1.32, 0.0), Vector3(0.18, 0.5, 0.18), accent_material, true)
		_add_box_to(station, Vector3(0.0, 1.22, 0.0), Vector3(0.95, 0.12, 0.4), accent_material, true)
	else:
		_add_box_to(station, Vector3(0.0, 1.55, 0.0), Vector3(1.3, 0.75, 0.35), accent_material, true)

	_add_station_label(station, station_name)


func _add_station_label(parent: Node3D, station_name: String) -> void:
	var label := Label3D.new()
	label.text = station_name
	label.position = Vector3(0.0, 2.12, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 44
	label.outline_size = 6
	label.modulate = Color("f0f3f6")
	parent.add_child(label)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0.0, PLAYER_HEIGHT, 3.8)
	add_child(player)

	var player_collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = PLAYER_HEIGHT
	player_collision.shape = capsule
	player_collision.position.y = -PLAYER_HEIGHT / 2.0
	player.add_child(player_collision)

	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	player.add_child(camera_pivot)
	camera = Camera3D.new()
	camera.name = "FirstPersonCamera"
	camera.fov = camera_fov
	camera.current = true
	camera_pivot.add_child(camera)


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.position = Vector2(632.0, 345.0)
	crosshair.add_theme_font_size_override("font_size", 24)
	crosshair.add_theme_color_override("font_color", Color.WHITE)
	canvas.add_child(crosshair)

	prompt_label = Label.new()
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.position = Vector2(220.0, 570.0)
	prompt_label.size = Vector2(840.0, 65.0)
	prompt_label.add_theme_font_size_override("font_size", 24)
	prompt_label.add_theme_color_override("font_color", Color("f1f4f7"))
	canvas.add_child(prompt_label)

	debug_label = Label.new()
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	debug_label.position = Vector2(220.0, 90.0)
	debug_label.size = Vector2(840.0, 45.0)
	debug_label.add_theme_font_size_override("font_size", 22)
	debug_label.add_theme_color_override("font_color", Color("ffc66d"))
	canvas.add_child(debug_label)

	var help_label := Label.new()
	help_label.text = "WASD — движение  |  Мышь — обзор  |  Esc — освободить курсор"
	help_label.position = Vector2(20.0, 20.0)
	help_label.add_theme_font_size_override("font_size", 16)
	help_label.add_theme_color_override("font_color", Color("c4cbd3"))
	canvas.add_child(help_label)


func _build_debug_panel() -> void:
	debug_panel = preload("res://scripts/debug_panel.gd").new()
	debug_panel.name = "DebugPanel"
	add_child(debug_panel)


func _update_interaction_target() -> void:
	target_station = null
	prompt_label.text = ""
	if camera == null:
		return

	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + -camera.global_transform.basis.z * INTERACTION_DISTANCE)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return

	var collider := result.get("collider") as StaticBody3D
	if collider != null and collider.has_meta("station_name"):
		target_station = collider
		prompt_label.text = str(collider.get_meta("station_name")) + "\nE — взаимодействовать"


func _interact_with_target() -> void:
	if target_station == null:
		return
	var station_name := str(target_station.get_meta("station_name"))
	debug_label.text = "DEBUG: взаимодействие — " + station_name
	debug_timer = 2.5


func _add_solid_box(node_name: String, box_position: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = box_position
	add_child(body)
	_add_box_to(body, Vector3.ZERO, size, material, true)


func _add_visual_box(node_name: String, box_position: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = box_position
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	add_child(mesh_instance)


func _add_box_to(parent: Node3D, local_position: Vector3, size: Vector3, material: StandardMaterial3D, collision_enabled: bool) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position = local_position
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)

	if collision_enabled:
		var collision := CollisionShape3D.new()
		collision.position = local_position
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		parent.add_child(collision)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material
