extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
var failures: Array = []
var checks: Array = []
var level: Dictionary
var weapon: Dictionary

func check(condition: bool, description: String) -> void:
	checks.append({"name":description,"passed":condition})
	if not condition:
		failures.append(description)
	print("PASS " if condition else "FAIL ",description)

func fresh():
	var sim = Sim.new()
	sim.setup(level,weapon)
	return sim

func _initialize() -> void:
	level = JSON.parse_string(FileAccess.get_file_as_string("res://data/street.json"))
	weapon = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapon.json"))
	var sim = fresh()
	check(sim.units.size()==8 and sim.enemies_alive()==5,"Eight actors spawn; five defenders")
	check(not sim.blocked(sim.player.position),"Player spawn is traversable")
	for u in sim.units:
		check(not sim.blocked(u.position),"Actor %d spawn is traversable" % u.id)
	# A standing wall blocks movement and shots; three real M416 shots open it.
	var wall: Dictionary = sim.obstacles.filter(func(o): return o.id=="wall-a")[0]
	var p: Vector2 = wall.position
	sim.player.position = p+Vector2(0,2)
	check(sim.blocked(p),"Intact wall blocks movement")
	check(not sim.line_clear(p+Vector2(0,2),p-Vector2(0,2)),"Intact wall blocks line of fire")
	for i in range(3):
		sim.player.cooldown = 0
		sim.fire_unit(sim.player,p-Vector2(0,2))
	check(not wall.alive and sim.broken==1,"Three weapon hits destroy the 84 HP wall")
	check(not sim.blocked(p),"Destroyed wall releases movement collision")
	check(sim.line_clear(p+Vector2(0,2),p-Vector2(0,2)),"Destroyed wall releases line of fire")
	check(not sim.navigation.is_point_solid(Vector2i(roundi(p.x*2),roundi(p.y*2))),"Destroyed wall updates navigation")
	# Weapon cadence, real damage and ammunition bookkeeping.
	sim = fresh()
	for u in sim.units:
		if not u.player:
			u.alive = false
	var target: Dictionary = sim.units[3]
	target.alive = true
	target.position = Vector2(0,7)
	sim.player.position = Vector2(0,11)
	check(sim.fire_unit(sim.player,target.position),"Ready weapon fires")
	check(not sim.fire_unit(sim.player,target.position),"Weapon cadence rejects immediate second shot")
	check(is_equal_approx(target.health,56.0),"M416 applies original 28 damage")
	check(sim.player.ammo==29,"Shot consumes one round")
	check(sim.start_reload(sim.player),"Partial magazine can reload")
	check(not sim.fire_unit(sim.player,target.position),"Reload blocks shooting")
	# Disable combat while the simulation advances the full reload duration.
	target.alive = false
	for i in range(127):
		sim.step(1.0/60,Vector2.ZERO,Vector2.ZERO,false)
	check(sim.player.ammo==30 and sim.player.reserve==179,"Reload transfers rounds from finite reserve")
	sim = fresh()
	sim.player.position = sim.objective
	for i in range(30):
		sim.step(1.0/60,Vector2.ZERO,Vector2.ZERO,false)
	check(sim.capture==0.0,"Defenders prevent capture")
	sim.damage_unit(sim.player,200)
	check(sim.result=="defeat","Player death ends match in defeat")
	sim.setup(level,weapon)
	check(sim.result.is_empty() and sim.player.health==160 and sim.enemies_alive()==5,"Restart restores actors, health, ammunition and result")
	# End-to-end battle with actual AI, firing, destruction, pathing and capture.
	var runs: Array = []
	for seed_value in [260924,260925,260926]:
		var result = play_full_loop(seed_value)
		runs.append(result)
		check(result.result=="victory","Autoplay completes shoot -> breach -> capture at seed %d" % seed_value)
	var report = {"checks":checks,"failures":failures,"runs":runs,"engine":Engine.get_version_info().string}
	FileAccess.open("res://qa/smoke-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("RESULT ",checks.size()-failures.size(),"/",checks.size()," passed")
	quit(0 if failures.is_empty() else 1)

func play_full_loop(seed_value: int) -> Dictionary:
	var sim = fresh()
	sim.rng.seed = seed_value
	for frame in range(60*90):
		if not sim.result.is_empty():
			break
		var aim: Vector2 = sim.objective
		var movement = Vector2.ZERO
		var nearest = 1.0e10
		for enemy in sim.units:
			if enemy.team != 1 or not enemy.alive:
				continue
			var distance = sim.player.position.distance_squared_to(enemy.position)
			if distance < nearest:
				nearest = distance
				aim = enemy.position
		if sim.enemies_alive()==0:
			var path = sim.navigation.get_point_path(sim.nearest_cell(sim.player.position),sim.nearest_cell(sim.objective))
			var next: Vector2 = path[1] if path.size()>1 else sim.objective
			if sim.player.position.distance_to(sim.objective)>1.0:
				movement = (next-sim.player.position).normalized()
		sim.step(1.0/60,movement,aim,sim.enemies_alive()>0)
	return {"seed":seed_value,"result":sim.result,"time":sim.elapsed,"health":sim.player.health,"kills":sim.kills,"broken":sim.broken,"shots":sim.shots}
