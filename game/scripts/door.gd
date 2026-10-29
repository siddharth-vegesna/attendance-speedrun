# Classroom door. Opens when the player walks up to it... or slams open into
# their face and launches them across the corridor.
extends Node3D

signal bonked

var into_sign := 1.0          # rotation sign that swings the door into the room
var corridor_dir := Vector3.BACK
var enabled := false
var is_open := false
var will_bonk := false
var pivot: Node3D
var shape: CollisionShape3D


func setup(p_into_sign: float, p_corridor_dir: Vector3, color: Color) -> void:
	into_sign = p_into_sign
	corridor_dir = p_corridor_dir
	pivot = Node3D.new()
	add_child(pivot)
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.position = Vector3(0.7, 1.2, 0)
	pivot.add_child(body)

	body.add_child(_box(Vector3(1.38, 2.38, 0.07), Vector3.ZERO, color))
	body.add_child(_box(Vector3(0.3, 0.7, 0.08), Vector3(0.3, 0.45, 0), Color(0.6, 0.8, 0.95)))
	body.add_child(_box(Vector3(0.18, 0.04, 0.16), Vector3(0.5, -0.1, 0), Color(0.75, 0.75, 0.78)))

	shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.38, 2.38, 0.07)
	shape.shape = bs
	body.add_child(shape)

	var trigger := Area3D.new()
	var ts := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(2.2, 2.4, 2.0)
	ts.shape = tb
	trigger.add_child(ts)
	trigger.position = Vector3(0.7, 1.2, 0) + corridor_dir * 1.1
	add_child(trigger)
	trigger.body_entered.connect(_on_enter)


func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	mi.material_override = m
	return mi


func reset(bonk: bool) -> void:
	is_open = false
	will_bonk = bonk
	pivot.rotation.y = 0
	shape.disabled = false


func open_instant() -> void:
	is_open = true
	pivot.rotation.y = into_sign * deg_to_rad(95)
	shape.disabled = true


func _on_enter(b: Node3D) -> void:
	if is_open or not enabled or not b.has_method("knockback"):
		return
	is_open = true
	shape.set_deferred("disabled", true)
	var tw := create_tween()
	if will_bonk:
		tw.tween_property(pivot, "rotation:y", -into_sign * deg_to_rad(100), 0.09) \
			.set_trans(Tween.TRANS_EXPO)
		var push := corridor_dir + Vector3(randf_range(-0.5, 0.5), 0, 0)
		b.knockback(push, 15.0, 6.0)
		bonked.emit()
		tw.tween_interval(0.5)
		tw.tween_callback(func(): shape.set_deferred("disabled", false))
	else:
		tw.tween_property(pivot, "rotation:y", into_sign * deg_to_rad(95), 0.35) \
			.set_trans(Tween.TRANS_SINE)
