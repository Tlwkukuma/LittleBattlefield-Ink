extends SceneTree
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Art=preload("res://scripts/proving_art.gd")
var c=Catalog.new()
var count=0
var failures: Array=[]
func check(value: bool,message: String):
	count+=1
	if not value:failures.append(message);push_error(message)
func empty_plan() -> Dictionary:
	var p=c.range_plan();p.instances=[];p.looseSegments=[];p.trees=[];p.vehicles=[];p.emplacements=[];p.units.red=[];p.deployment.player={"x":2000,"y":1400};return p
func fresh() -> RefCounted:
	var w=World.new();w.setup(empty_plan(),c);return w
func _initialize():run.call_deferred()
func run():
	check(c.weapons.size()==84 and c.data.vehicles.size()==7 and c.data.emplacements.size()==2,"Original catalog totals")
	check(c.prefabs.size()==52 and c.components.size()==63 and c.scenes.size()==30,"Original scene library totals")
	check(c.weapons.m416.damage==28 and c.weapons.m416.mag==30 and c.weapons.awm.damage==760,"Original final weapon tuning")
	for id in c.weapons:
		var w=fresh();w.equip(id);var profile: Dictionary=c.weapons[id];var before=w.player.ammo
		check(w.fire(w.player,profile,w.player,Vector2.ZERO,0,1.35,Vector2(12,0)),"Fires "+id)
		check(w.player.ammo==before-(0 if profile.kind=="melee" else 1),"Ammo accounting "+id)
		check(not w.fire(w.player,profile,w.player,Vector2.ZERO,0,1.35,Vector2(12,0)),"RPM gate "+id)
		if profile.kind not in ["melee","hitscan"]:check(w.projectiles.size()==int(profile.get("pellets",1)),"Pellet count "+id)
		for i in range(240):w.step(1.0/60,Vector2.ZERO,Vector2(12,0),false,false)
		check(w.projectiles.is_empty(),"Projectile lifetime "+id)
	var w=fresh();w.equip("m416");var u=w.add_unit(Vector2(0,-6),false)
	for i in range(130):w.step(1.0/60,Vector2.ZERO,u.position,true,i==0,true)
	check(not u.alive and w.kills==1,"Real physical bullets kill a target")
	w=fresh();w.equip("p92")
	for i in range(90):w.step(1.0/60,Vector2.ZERO,Vector2(0,-6),true,i==0)
	check(w.shots==1,"Semiautomatic requires another press")
	w=fresh();w.player.ammo=0;w.player.reserve=7;w.reload_weapon()
	for i in range(180):w.step(1.0/60,Vector2.ZERO,Vector2(0,-6),false,false)
	check(w.player.ammo==7 and w.player.reserve==0,"Finite reserve reload")
	var distances=[]
	for stance in range(3):
		w=fresh();w.set_stance(stance)
		for i in range(120):w.step(1.0/60,Vector2.RIGHT,Vector2(5,0),false,false)
		distances.append(w.player.position.x);check(absf(w.player.stance_blend-stance)<.01,"Smooth stance reaches "+str(stance))
	check(distances[0]>distances[1]*1.7 and distances[1]>distances[2]*2,"Stance locomotion speeds differ")
	w=fresh();u=w.add_unit(Vector2(5,0),false);u.stance=2
	check(w.ray(Vector2.ZERO,Vector2.RIGHT,10,1.3,{"source":0,"team":0}).is_empty(),"High bullet passes over prone target")
	check(not w.ray(Vector2.ZERO,Vector2.RIGHT,10,.3,{"source":0,"team":0}).is_empty(),"Low bullet hits prone target")
	var plan=empty_plan();plan.looseSegments=[{"id":"wall","componentId":"wall.concrete","x1":1920,"y1":1200,"x2":2080,"y2":1200,"thickness":32,"godot3d":{"height":2}}]
	w=World.new();w.setup(plan,c);var wall: Dictionary=w.objects[0];var col=int(wall.columns/2);var x=-wall.size.x*.5+(col+.5)*wall.cell_width
	check(not w.ray(Vector2(x,0),Vector2.UP,10,1.2,{},true).is_empty(),"Intact wall blocks bullets")
	var hp: Array=wall.hp.duplicate();w.damage_cell(wall,col,2,1000,Vector2.ZERO,false)
	check(wall.hp[col]==hp[col] and wall.alive,"Local bullet breach preserves other rows")
	check(w.ray(Vector2(x,0),Vector2.UP,10,1.2,{},true).is_empty(),"Shot crosses only the opened height")
	check(w.blocked(Vector2(x,-5),.1,1.8),"Bullet hole is not automatically walkable")
	for row in range(wall.rows):w.damage_cell(wall,col,row,1000,Vector2.ZERO,true)
	check(not w.blocked(Vector2(x,-5),.1,1.8),"Full height breach removes collision")
	check(w.topology_revision>=wall.rows and w.navigation_dirty,"Destruction invalidates navigation")
	var intact_column=0;wall.destructible=false;var original=wall.hp[intact_column];w.damage_cell(wall,intact_column,0,10000,Vector2.ZERO,true)
	check(wall.hp[intact_column]==original,"Indestructible cells reject damage")
	wall.destructible=true;check(Art.wall_mesh(wall).get_surface_count()==1,"Damaged wall generates geometry")
	for xcol in range(wall.columns):w.damage_cell(wall,xcol,0,10000,Vector2.ZERO,true)
	w.resolve_support();check(not wall.alive,"Detached wall islands lose structural support and collapse")
	w=World.new();w.setup(plan,c);wall=w.objects[0];w.blast(Vector2(0,-5),2.2,200,{"kind":"shell","name":"test"})
	check(w.broken>0 and w.broken<wall.hp.size(),"Blast damages a local wall region")
	plan=empty_plan();plan.looseSegments=[{"id":"barrel","componentId":"prop.barrel","x1":1990,"y1":1400,"x2":2010,"y2":1400,"thickness":30}]
	w=World.new();w.setup(plan,c);var explosions=[0];w.event.connect(func(e):if e.type=="explosion":explosions[0]+=1)
	w.damage_object(w.objects[0],Vector2.ZERO,.5,10000,true);check(explosions[0]==1 and not w.objects[0].alive,"Barrel chain detonates exactly once")
	for id in c.data.vehicles:
		plan=empty_plan();plan.vehicles=[{"id":"v","type":id,"x":2000,"y":1400,"angle":0}]
		w=World.new();w.setup(plan,c);check(w.enter_vehicle(0),"Enter vehicle "+id)
		for i in range(60):w.step(1.0/60,Vector2(0,-1),Vector2(20,0),false,false)
		check(w.vehicles[0].position.x>1 and w.vehicles[0].speed>1,"Drives "+id)
		var v: Dictionary=w.vehicles[0]
		for mode in v.modes:
			var weapon: Dictionary=v.profile.weapons[mode];check(w.fire(w.player,weapon,v.states[mode],v.position,0,1.3,Vector2(25,0),0),"Vehicle weapon "+id+" / "+mode)
		check(w.leave_vehicle() and not w.blocked(w.player.position),"Safe exit "+id)
		w.damage_vehicle(v,100000,Vector2(-10,0),{"kind":"rocket","name":"RPG"},true)
		check(v.destroyed and w.blocked(v.position),"Destroyed wreck collision "+id)
	for id in c.data.emplacements:
		plan=empty_plan();plan.emplacements=[{"id":"e","type":id,"x":2000,"y":1400,"angle":0}]
		w=World.new();w.setup(plan,c);w.enter_vehicle(0)
		w.step(.1,Vector2(0,-1),Vector2(10,0),true,true)
		check(w.shots==1 and w.vehicles[0].position==Vector2.ZERO,"Emplacement fires, stays fixed "+id)
	for id in c.prefabs:
		plan=empty_plan();plan.instances=[{"id":"item","prefabId":id,"x":2000,"y":1400,"rotation":.3,"scale":1}]
		var compiled=c.compile(plan);check(not compiled.objects.is_empty() or not compiled.ground.is_empty(),"Compile prefab "+id)
	for source in c.scenes:
		var scenario=World.new();var compiled=scenario.setup(source,c);check(compiled.bounds.x>0 and compiled.bounds.y>0 and scenario.units.size()>0,"Compile source scene "+str(source.id))
	print("PROVING SMOKE: ",count-failures.size(),"/",count," passed. Failures: ",failures)
	quit(0 if failures.is_empty() else 1)
