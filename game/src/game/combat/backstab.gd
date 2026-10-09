class_name BWBackstab
extends RefCounted
## D517: the dagger backstab's choreography (view only). When a dagger blow
## comes from behind (the attack event's "behind", BWBattle.behind), the
## cutscene plays the pair set's `strike_backstab` clip and this moves the
## root: from its own tile the unit slithers in a low S-curve round to the
## target's back on the clip's launch..land, stabs (the clip's hit), and
## slithers home on slide_back..slide_home. The rules position never changes;
## the target keeps its back turned (face) so the stab lands in it.

## How far behind the target's centre the stab is made (u).
const REACH := 0.62
## The S-curve's sideways swing (u), out and home (mirrored on the way home).
const SWAY := 0.32


## The target turns its back to the attacker (it doesn't see it coming).
static func face(t: Node3D, a: Node3D) -> void:
	if t.has_method("face"):
		t.face(t.global_position * 2.0 - a.global_position)


## The point behind `d` the stab is made from, in the views' parent space.
static func stab_point(home: Vector3, d: Vector3) -> Vector3:
	var back := home - d
	back.y = 0.0
	if back.length() < 0.01:
		back = Vector3(0, 0, -1)
	return d + back.normalized() * REACH


## The slither's position at u (0 = home, 1 = behind the target); `side`
## (+1 / -1) picks which way the S starts.
static func path(home: Vector3, to: Vector3, u: float, side: float) -> Vector3:
	var line := to - home
	var across := Vector3(line.z, 0.0, -line.x).normalized() if line.length() > 0.01 else Vector3.RIGHT
	var e := u * u * (3.0 - 2.0 * u)
	return home.lerp(to, e) + across * sin(e * TAU) * SWAY * (1.0 - 0.35 * e) * side


## Schedule the whole slither from now (the strike has just started): out on
## launch..land, home on slide_back..slide_home. Never awaits.
static func slide(screen: Node, a: Node3D, d: Node3D, home: Vector3) -> void:
	var t_launch: float = a.time_to_marker("launch")
	var t_land: float = a.time_to_marker("land")
	var t_back: float = a.time_to_marker("slide_back")
	var t_home: float = a.time_to_marker("slide_home")
	if t_launch < 0.0 or t_land <= t_launch:
		return
	var to := stab_point(home, d.position)
	var side := 1.0 if (hash(str(a.get("unit").id) if a.get("unit") else "") % 2) == 0 else -1.0
	var out := func(u: float) -> void:
		if not is_instance_valid(a):
			return
		a.position = path(home, to, u, side)
		_look(a, path(home, to, minf(u + 0.08, 1.0), side) - path(home, to, maxf(u - 0.08, 0.0), side), d, u)
	var back := func(u: float) -> void:
		if not is_instance_valid(a):
			return
		a.position = path(home, to, u, -side)
		if is_instance_valid(d):
			a.face(d.global_position)
	var done := func() -> void:
		if is_instance_valid(a):
			a.position = home
			if is_instance_valid(d):
				a.face(d.global_position)
	var tw: Tween = screen.create_tween()
	tw.tween_interval(t_launch)
	tw.tween_method(out, 0.0, 1.0, t_land - t_launch)
	if t_back > t_land and t_home > t_back:
		tw.tween_interval(t_back - t_land)
		tw.tween_method(back, 1.0, 0.0, t_home - t_back)
		tw.tween_callback(done)


## Face along the slither, turning onto the target for the stab.
static func _look(a: Node3D, tangent: Vector3, d: Node3D, u: float) -> void:
	tangent.y = 0.0
	if not is_instance_valid(d):
		return
	var to_d := d.global_position - a.global_position
	to_d.y = 0.0
	var k := smoothstep(0.55, 0.95, u)
	var dir := tangent.normalized().lerp(to_d.normalized(), k) if tangent.length() > 1e-4 else to_d
	if dir.length() > 1e-4:
		a.face(a.global_position + dir)
