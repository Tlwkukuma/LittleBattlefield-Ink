extends RefCounted
## Rendering-independent planar combat. Heights belong to the view in this slice.

signal shot(origin: Vector2, endpoint: Vector2, team: int, unit_id: int)
signal impact(point: Vector2, kind: String)
signal unit_died(id: int)
signal wall_broken(id: String)
signal finished(won: bool)

var units: Array = []
var obstacles: Array = []
var definition: Dictionary
var weapon: Dictionary
var player: Dictionary
var objective: Vector2
var bounds: Vector2
var capture = 0.0
var elapsed = 0.0
var result = ""
var kills = 0
var shots = 0
var broken = 0
var rng = RandomNumberGenerator.new()
var navigation = AStarGrid2D.new()
const Layout = preload("res://scripts/house_layout.gd")
var crowd = false
var spatial: Dictionary = {}
var respawns = 0
var total_shots = 0
var obstacle_grid: Dictionary = {}
var exploration = false

func setup(level: Dictionary, profile: Dictionary) -> void:
	definition = level
	crowd = bool(level.get("crowd",false))
	exploration=false
	respawns=0
	total_shots=0
	weapon = profile
	rng.seed = int(level.seed)
	bounds = vec(level.bounds)
	objective = vec(level.objective)
	units.clear()
	obstacles.clear()
	capture = 0.0
	elapsed = 0.0
	result = ""
	kills = 0
	shots = 0
	broken = 0
	player = add_unit(vec(level.player), 0, true)
	for p in level.allies:
		add_unit(vec(p), 0, false)
	for p in level.enemies:
		add_unit(vec(p), 1, false)
	for b in level.buildings:
		for part in Layout.walls(b)+Layout.furniture(b):
			obstacles.append({"id":str(b.id)+"_"+str(obstacles.size()),"position":vec(b.position)+part.at,"size":part.size,"health":-1.0,"alive":true,"destructible":false})
	for w in level.walls:
		obstacles.append({"id": str(w.id), "position": vec(w.position), "size": vec(w.size), "health": float(w.health), "alive": true, "destructible": true})
	obstacle_grid.clear()
	for obstacle in obstacles:
		obstacle.rect=Rect2(obstacle.position-obstacle.size*.5,obstacle.size)
		var broad: Rect2=obstacle.rect.grow(.5)
		for x in range(floori(broad.position.x/2),floori(broad.end.x/2)+1):
			for y in range(floori(broad.position.y/2),floori(broad.end.y/2)+1):
				var cell=Vector2i(x,y)
				if not obstacle_grid.has(cell):obstacle_grid[cell]=[]
				obstacle_grid[cell].append(obstacle)
	if crowd:
		units.clear()
		for team in range(2):
			for row in range(5):
				for col in range(10):
					var p = Vector2(-4.35+col*0.96, (7.0+row*1.05) if team==0 else (-6.7-row*1.05))
					var u = add_unit(p,team,team==0 and row==4 and col==4)
					u.spawn=p
					if u.player: player=u
		objective=Vector2.ZERO
	rebuild_navigation()
	build_spatial()

static func vec(values: Array) -> Vector2:
	return Vector2(float(values[0]), float(values[1]))

func add_unit(position: Vector2, team: int, controlled: bool) -> Dictionary:
	var u = {"id": units.size(), "position": position, "team": team, "player": controlled,
		"health": 160.0 if controlled else (110.0 if team == 0 else 84.0), "alive": true,
		"facing": Vector2(0, -1), "velocity": Vector2.ZERO, "cooldown": 0.0,
		"ammo": int(weapon.mag), "reserve": int(weapon.reserve), "reload": 0.0,
		"brain": rng.randf_range(0.0, 0.3), "target": -1, "path": [], "repath": 0.0,
		"requested_velocity":Vector2.ZERO, "spawn":position, "walk": rng.randf()*TAU, "flash": 0.0, "hurt": 0.0, "death_age": 0.0}
	units.append(u)
	return u

func rebuild_navigation() -> void:
	navigation = AStarGrid2D.new()
	navigation.region = Rect2i(-34, -26, 69, 53)
	navigation.cell_size = Vector2.ONE*0.5
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for x in range(-34, 35):
		for y in range(-26, 27):
			if blocked(Vector2(x, y)*0.5, 0.34):
				navigation.set_point_solid(Vector2i(x, y))
	for u in units:
		u.repath = rng.randf_range(0.0,0.9)

func step(delta: float, movement: Vector2, aim: Vector2, fire: bool) -> void:
	if not result.is_empty():
		return
	elapsed += delta
	build_spatial()
	for u in units:
		u.flash = maxf(0.0, float(u.flash) - delta)
		u.hurt = maxf(0.0, float(u.hurt) - delta)
		if not u.alive:
			u.death_age += delta
			if crowd and u.death_age>2.0:
				respawn(u)
			continue
		u.cooldown = maxf(0.0, float(u.cooldown) - delta)
		if u.reload > 0:
			u.reload = maxf(0.0, float(u.reload) - delta)
			if u.reload == 0:
				var amount = mini(int(weapon.mag) - int(u.ammo), int(u.reserve))
				u.ammo += amount
				u.reserve -= amount
		if u.player:
			move_unit(u, movement.limit_length() * 3.6, delta)
			if aim.distance_squared_to(u.position) > 0.03:
				u.facing = (aim - u.position).normalized()
			if fire:
				fire_unit(u, aim)
		else:
			update_ai(u, delta)
		if u.ammo == 0:
			start_reload(u)
		if not result.is_empty():
			return
	if not crowd and not exploration and player.position.distance_to(objective) <= 2.7 and enemies_alive() == 0:
		capture = minf(float(definition.capture_seconds), capture + delta)
		if capture >= float(definition.capture_seconds):
			result = "victory"
			finished.emit(true)
	else:
		capture = maxf(0.0, capture - delta * 0.3)

func update_ai(u: Dictionary, delta: float) -> void:
	u.brain -= delta
	u.repath -= delta
	if u.brain <= 0:
		u.brain = 0.32+rng.randf()*0.10 if crowd else 0.23
		var closest = 24.0*24.0
		u.target = -1
		for other in units:
			if not other.alive or other.team == u.team:
				continue
			var d = u.position.distance_squared_to(other.position)
			if d < closest:
				closest = d
				u.target = other.id
	if u.target>=0 and not line_clear(u.position,units[int(u.target)].position):
			u.target=-1
	var target: Dictionary = units[int(u.target)] if u.target >= 0 else {}
	var destination: Vector2 = objective + Vector2(-1.4, 1.6) if u.team == 0 else objective
	var speed = 2.1 if u.team == 0 else 1.8
	if not target.is_empty() and target.alive:
		var direction: Vector2 = target.position - u.position
		u.facing = direction.normalized()
		if direction.length() < 15.0:
			if elapsed > 2.0 and u.cooldown<=0 and u.reload<=0 and line_clear(u.position, target.position):
				fire_unit(u, target.position)
			var strafe = Vector2(-direction.y, direction.x).normalized() * sin(elapsed * 0.65 + float(u.id) * 2.0)
			move_unit(u, strafe * (1.05 if crowd else 0.55), delta)
			return
		destination = target.position
	if u.position.distance_to(destination) < 1.4:
		move_unit(u, Vector2.ZERO, delta)
		return
	if u.repath <= 0:
		u.repath = 0.8 + rng.randf() * 0.3
		var a = nearest_cell(u.position)
		var b = nearest_cell(destination)
		u.path = Array(navigation.get_point_path(a, b))
		if not u.path.is_empty():
			u.path.pop_front()
	while not u.path.is_empty() and u.position.distance_to(u.path[0]) < 0.28:
		u.path.pop_front()
	if not u.path.is_empty():
		var direction: Vector2 = (u.path[0] - u.position).normalized()
		u.facing = direction
		move_unit(u, direction * speed, delta)
	else:
		move_unit(u, Vector2.ZERO, delta)

func nearest_cell(point: Vector2) -> Vector2i:
	var cell = Vector2i(roundi(point.x*2), roundi(point.y*2))
	cell.x = clampi(cell.x, -33, 33)
	cell.y = clampi(cell.y, -25, 25)
	if not navigation.is_point_solid(cell):
		return cell
	for r in range(1, 5):
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				var probe = cell + Vector2i(x, y)
				if navigation.is_in_boundsv(probe) and not navigation.is_point_solid(probe):
					return probe
	return cell

func blocked(point: Vector2, radius: float = 0.32) -> bool:
	if absf(point.x) > bounds.x - radius or absf(point.y) > bounds.y - radius:
		return true
	var cell=Vector2i(floori(point.x/2),floori(point.y/2))
	for o in obstacle_grid.get(cell,[]):
		if o.alive and o.rect.grow(radius).has_point(point):
			return true
	return false

func move_unit(u: Dictionary, velocity: Vector2, delta: float) -> void:
	u.requested_velocity = u.requested_velocity.move_toward(velocity,delta*(11.0 if velocity.length_squared()>0.01 else 16.0))
	velocity=u.requested_velocity
	var p: Vector2 = u.position
	var previous = p
	var next = p + Vector2(velocity.x * delta, 0)
	if not blocked(next):
		p.x = next.x
	next = p + Vector2(0, velocity.y * delta)
	if not blocked(next):
		p.y = next.y
	for other in nearby(p):
		if other.id == u.id or not other.alive:
			continue
		var separation: Vector2 = p - other.position
		var distance = separation.length()
		if distance < 0.62 and distance > 0.001:
			var corrected = p + separation / distance * (0.62 - distance) * 0.5
			if not blocked(corrected):
				p = corrected
	u.position = p
	u.velocity = (p - previous) / maxf(delta, 0.0001)
	u.walk += u.velocity.length()*delta*TAU/lerpf(1.2,1.9,clampf(u.velocity.length()/3.4,0,1))

static func ray_rect(origin: Vector2, direction: Vector2, box: Rect2, max_distance: float) -> float:
	var near = 0.0
	var far = max_distance
	for axis in range(2):
		if absf(direction[axis]) < 0.00001:
			if origin[axis] < box.position[axis] or origin[axis] > box.end[axis]:
				return -1.0
		else:
			var a = (box.position[axis] - origin[axis]) / direction[axis]
			var b = (box.end[axis] - origin[axis]) / direction[axis]
			near = maxf(near, minf(a, b))
			far = minf(far, maxf(a, b))
			if near > far:
				return -1.0
	return near

func line_clear(a: Vector2, b: Vector2) -> bool:
	var distance = a.distance_to(b)
	if distance < 0.001:
		return true
	var direction = (b - a) / distance
	for o in obstacles:
		if o.alive and ray_rect(a, direction, o.rect, distance) >= 0:
			return false
	return true

func start_reload(u: Dictionary) -> bool:
	if not u.alive or u.reload > 0 or u.ammo >= weapon.mag or u.reserve <= 0:
		return false
	u.reload = float(weapon.reload)
	return true

func fire_unit(u: Dictionary, target: Vector2) -> bool:
	if not result.is_empty() or not u.alive or u.cooldown > 0 or u.reload > 0 or u.ammo <= 0:
		return false
	var origin: Vector2 = u.position
	var direction = (target - origin).normalized()
	if direction.length_squared() < 0.1:
		return false
	var spread = float(weapon.spread) if u.player else 0.13
	direction = direction.rotated(rng.randf_range(-spread, spread))
	u.cooldown = 60.0 / float(weapon.rpm) if u.player else rng.randf_range(0.7, 1.25)
	total_shots += 1
	u.ammo -= 1
	u.flash = 0.06
	if u.player:
		shots += 1
	var nearest = float(weapon.prototype_range)
	var hit_obstacle: Dictionary = {}
	var hit_unit: Dictionary = {}
	for o in obstacles:
		if not o.alive:
			continue
		var t = ray_rect(origin, direction, o.rect, nearest)
		if t >= 0 and t < nearest:
			nearest = t
			hit_obstacle = o
	for other in units:
		if not other.alive or other.team == u.team:
			continue
		var offset: Vector2 = other.position - origin
		var along = offset.dot(direction)
		var side_squared = offset.length_squared() - along * along
		if along < 0 or side_squared > 0.38 * 0.38:
			continue
		var t = maxf(0.0, along - sqrt(maxf(0.0, 0.38 * 0.38 - side_squared)))
		if t < nearest:
			nearest = t
			hit_unit = other
			hit_obstacle = {}
	var endpoint = origin + direction * nearest
	# Start the visual at the barrel, but never move it beyond a close obstruction.
	shot.emit(origin + direction * minf(0.72, nearest), endpoint, int(u.team),int(u.id))
	if not hit_unit.is_empty():
		var damage = float(weapon.damage) if u.player else (13.0 if u.team == 1 else 18.0)
		damage_unit(hit_unit, damage, bool(u.player))
		impact.emit(endpoint, "hit")
	elif not hit_obstacle.is_empty():
		impact.emit(endpoint, "stone")
		if hit_obstacle.destructible:
			damage_wall(hit_obstacle, float(weapon.damage))
	return true

func damage_unit(u: Dictionary, amount: float, player_credit: bool = false) -> void:
	if not u.alive:
		return
	u.health = maxf(0.0, float(u.health) - amount)
	u.hurt = 0.15
	if u.health <= 0:
		u.alive = false
		if u.team == 1 and player_credit:
			kills += 1
		unit_died.emit(int(u.id))
		if u.player and not crowd:
			result = "defeat"
			finished.emit(false)

func damage_wall(wall: Dictionary, amount: float) -> void:
	if not wall.alive or not wall.destructible:
		return
	wall.health -= amount
	if wall.health <= 0:
		wall.alive = false
		broken += 1
		rebuild_navigation()
		wall_broken.emit(str(wall.id))

func enemies_alive() -> int:
	var count = 0
	for u in units:
		if u.alive and u.team == 1:
			count += 1
	return count

func build_spatial() -> void:
	spatial.clear()
	for u in units:
		if not u.alive: continue
		var cell = Vector2i(floori(u.position.x/1.5),floori(u.position.y/1.5))
		if not spatial.has(cell): spatial[cell]=[]
		spatial[cell].append(u)

func nearby(point: Vector2) -> Array:
	var result: Array = []
	var cell = Vector2i(floori(point.x/1.5),floori(point.y/1.5))
	for x in range(-1,2):
		for y in range(-1,2):
			result.append_array(spatial.get(cell+Vector2i(x,y),[]))
	return result

func respawn(u: Dictionary) -> void:
	var p: Vector2 = u.spawn
	for i in range(12):
		var probe = u.spawn+Vector2(rng.randf_range(-0.4,0.4),rng.randf_range(-0.4,0.4))
		if not blocked(probe):
			p=probe
			break
	u.position=p
	u.health=160.0 if u.player else (110.0 if u.team==0 else 84.0)
	u.alive=true
	u.death_age=0.0
	u.ammo=int(weapon.mag)
	u.reserve=int(weapon.reserve)
	u.reload=0.0
	u.target=-1
	u.path=[]
	u.velocity=Vector2.ZERO
	u.requested_velocity=Vector2.ZERO
	respawns+=1
