class_name BWHex
## Pointy-top, odd-r offset hex math. Lifted from Temporal Sea V8 HexGrid,
## minus its global map bounds: everything here is pure and unbounded. Bounds
## and terrain live on BWBoard, which filters.
##
## Positions are Vector2i(col, row). Map JSON calls these q and r.

## The six cube direction vectors, in the same order neighbors() returns them.
const CUBE_DIRS := [
	Vector3i(1, -1, 0), Vector3i(1, 0, -1), Vector3i(0, 1, -1),
	Vector3i(-1, 1, 0), Vector3i(-1, 0, 1), Vector3i(0, -1, 1),
]


static func to_cube(h: Vector2i) -> Vector3i:
	var x: int = h.x - ((h.y - (h.y & 1)) / 2)
	return Vector3i(x, -x - h.y, h.y)


static func to_offset(c: Vector3i) -> Vector2i:
	return Vector2i(c.x + ((c.z - (c.z & 1)) / 2), c.z)


static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := to_cube(a) - to_cube(b)
	return maxi(absi(d.x), maxi(absi(d.y), absi(d.z)))


static func neighbors(h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c := to_cube(h)
	for d in CUBE_DIRS:
		out.append(to_offset(c + d))
	return out


## Every hex within `radius` of `center`, inclusive, unbounded.
static func area(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cc := to_cube(center)
	for dx in range(-radius, radius + 1):
		for dy in range(maxi(-radius, -dx - radius), mini(radius, -dx + radius) + 1):
			out.append(to_offset(cc + Vector3i(dx, dy, -dx - dy)))
	return out


static func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in area(center, radius):
		if distance(center, h) == radius:
			out.append(h)
	return out


static func cube_round(x: float, y: float, z: float) -> Vector2i:
	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return to_offset(Vector3i(int(rx), int(ry), int(rz)))


## Straight line a→b inclusive (line of sight, trails). The epsilon nudge
## breaks ties deterministically, as in V8.
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n := distance(a, b)
	if n == 0:
		var only: Array[Vector2i] = [a]
		return only
	var ac := to_cube(a)
	var bc := to_cube(b)
	var out: Array[Vector2i] = []
	for i in range(n + 1):
		var t := float(i) / float(n)
		var x: float = ac.x + (bc.x - ac.x) * t
		var z: float = ac.z + (bc.z - ac.z) * t
		out.append(cube_round(x + 1e-6, -x - z - 2e-6, z + 1e-6))
	return out


## Which of the six headings best points a→b; -1 if a == b. Ties break to
## the lower index.
static func direction_index(a: Vector2i, b: Vector2i) -> int:
	var n := distance(a, b)
	if n == 0:
		return -1
	var ac := to_cube(a)
	var best := -1
	var best_dist := 1 << 30
	for i in CUBE_DIRS.size():
		var probe := to_offset(ac + CUBE_DIRS[i] * n)
		var d := distance(probe, b)
		if d < best_dist:
			best_dist = d
			best = i
	return best


## Every hex strictly between a and b, plus b. Empty when a == b.
static func trail(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var whole := line(a, b)
	return whole.slice(1)


## Up to `dist` hexes outward from origin along the heading toward `toward`,
## excluding origin. Unbounded; BWBoard.ray() clips at the edge.
static func ray(origin: Vector2i, toward: Vector2i, dist: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var di := direction_index(origin, toward)
	if di < 0:
		return out
	var oc := to_cube(origin)
	for i in range(1, dist + 1):
		out.append(to_offset(oc + CUBE_DIRS[di] * i))
	return out


## Every hex within `radius` of any hex in `hexes`, deduplicated, inputs included.
static func fringe(hexes: Array, radius: int = 1) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for h in hexes:
		for n in area(h, radius):
			if not seen.has(n):
				seen[n] = true
				out.append(n)
	return out


## The hex one step past `through` on the from→through heading.
static func step_beyond(from: Vector2i, through: Vector2i) -> Vector2i:
	var di := direction_index(from, through)
	if di < 0:
		return through
	return to_offset(to_cube(through) + CUBE_DIRS[di])


## Hex centre on the XZ plane, unit = hex circumradius.
static func to_world(h: Vector2i, size: float = 1.0) -> Vector2:
	return Vector2(size * sqrt(3.0) * (h.x + 0.5 * (h.y & 1)), size * 1.5 * h.y)


static func from_world(p: Vector2, size: float = 1.0) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * p.x - 1.0 / 3.0 * p.y) / size
	var r := (2.0 / 3.0 * p.y) / size
	return cube_round(q, -q - r, r)
