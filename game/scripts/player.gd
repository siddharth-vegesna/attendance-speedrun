# First-person student. WASD to move, mouse to look, Shift to sprint, Space to jump.
extends CharacterBody3D

const WALK := 6.0
const SPRINT := 10.0
const JUMP := 6.0
const GRAVITY := 20.0
const SENS := 0.0025

var cam: Camera3D
var frozen := true
var knock := Vector3.ZERO
var shake := 0.0
var bob := 0.0


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	cam = Camera3D.new()
	cam.position.y = 1.6
	cam.fov = 80
	add_child(cam)
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50)


func _input(e: InputEvent) -> void:
	if frozen:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-e.relative.x * SENS)
		cam.rotation.x = clamp(cam.rotation.x - e.relative.y * SENS, -1.4, 1.4)


func knockback(dir: Vector3, force: float, up: float) -> void:
	dir.y = 0
	knock = dir.normalized() * force
	velocity.y = up
	shake = 0.35


func reset_to(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation = Vector3(0, yaw, 0)
	cam.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	knock = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var input := Vector2.ZERO
	if not frozen:
		input.x = float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) \
			- float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
		input.y = float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) \
			- float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
		if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
			velocity.y = JUMP
	var spd := SPRINT if Input.is_key_pressed(KEY_SHIFT) else WALK
	var dir := transform.basis * Vector3(input.x, 0, input.y)
	dir.y = 0
	if dir.length() > 0.01:
		dir = dir.normalized() * spd
	knock = knock.move_toward(Vector3.ZERO, 18.0 * delta)
	velocity.x = dir.x + knock.x
	velocity.z = dir.z + knock.z
	move_and_slide()

	if dir.length() > 0.1 and is_on_floor():
		bob += delta * spd * 1.6
	cam.position.y = 1.6 + sin(bob) * 0.05
	shake = max(shake - delta, 0.0)
	cam.h_offset = randf_range(-shake, shake) * 0.4
	cam.v_offset = randf_range(-shake, shake) * 0.4
