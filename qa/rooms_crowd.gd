extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
var failures: Array=[]
var count=0
func check(ok: bool, label: String) -> void:
	count+=1
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func _initialize() -> void:
	var level=JSON.parse_string(FileAccess.get_file_as_string("res://data/street.json"))
	var weapon=JSON.parse_string(FileAccess.get_file_as_string("res://data/weapon.json"))
	var sim=Sim.new()
	sim.setup(level,weapon)
	for house in level.buildings:
		var p=Sim.vec(house.position)
		var d=float(house.size[1])
		check(not sim.blocked(p),str(house.id)+" interior is walkable")
		check(sim.line_clear(p+Vector2(0,d*.5+1),p-Vector2(0,d*.5+1)),str(house.id)+" shots pass through both doors")
		check(not sim.line_clear(p+Vector2(1.5,d*.5+1),p+Vector2(1.5,d*.5-1)),str(house.id)+" facade still stops bullets")
		check(sim.blocked(p+Vector2(float(house.size[0])*.5,0)),str(house.id)+" side wall is solid")
		sim.player.position=p+Vector2(0,d*.5+1)
		sim.player.requested_velocity=Vector2.ZERO
		for i in range(225): sim.move_unit(sim.player,Vector2(0,-2),1.0/60)
		check(sim.player.position.y<p.y-d*.5,str(house.id)+" actual movement enters, crosses partition, exits rear door")
		var path=sim.navigation.get_point_path(sim.nearest_cell(p+Vector2(0,d*.5+1)),sim.nearest_cell(p-Vector2(0,d*.5+1)))
		check(path.size()>0,str(house.id)+" AI navigation crosses doors")
	level.crowd=true
	sim.setup(level,weapon)
	check(sim.units.size()==100,"100 independent actors spawned")
	check(sim.units.filter(func(u):return u.team==0).size()==50 and sim.enemies_alive()==50,"Exactly 50 vs 50")
	check(sim.units.filter(func(u):return u.player).size()==1,"Exactly one player")
	check(sim.units.all(func(u):return not sim.blocked(u.position)),"All 100 spawns outside walls/furniture")
	sim.damage_unit(sim.player,1000)
	check(not sim.player.alive and sim.result.is_empty(),"Crowd mode death keeps match running")
	for i in range(125): sim.step(1.0/60,Vector2.ZERO,Vector2.ZERO,false)
	check(sim.player.alive and sim.respawns>0,"Player respawns after two seconds")
	for i in range(600):sim.step(1.0/60,Vector2.ZERO,Vector2.ZERO,false)
	check(sim.total_shots>100,"Crowd AI actually fires weapons")
	check(sim.units.size()==100 and sim.result.is_empty(),"Sustained battle retains 100 slots and no end-state stall")
	print("ROOMS_CROWD_RESULT ",count-failures.size(),"/",count)
	quit(0 if failures.is_empty() else 1)
