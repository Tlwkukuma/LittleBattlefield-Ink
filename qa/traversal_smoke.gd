extends SceneTree
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Traversal=preload("res://scripts/soldier_traversal.gd")
var catalog=Catalog.new()
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(value: bool,label: String):
	checks+=1
	if not value:failures.append(label);push_error(label)
func plan() -> Dictionary:
	var p=catalog.range_plan();p.instances=[];p.looseSegments=[];p.trees=[];p.vehicles=[];p.emplacements=[];p.units.red=[];p.deployment.player={"x":2000,"y":1400};return p
func wall(height: float=1.0,angle: float=0.0,thickness: float=.5,elevation: float=0.0) -> Dictionary:
	var center=Vector2(0,-2);var axis=Vector2.RIGHT.rotated(angle)*2
	return {"id":"test-wall","componentId":"wall.brick","x1":2000+(center.x-axis.x)*40,"y1":1400+(center.y-axis.y)*40,"x2":2000+(center.x+axis.x)*40,"y2":1400+(center.y+axis.y)*40,"thickness":thickness*40,"godot3d":{"height":height,"elevation":elevation}}
func fresh(p: Dictionary={}) -> RefCounted:
	var world=World.new();world.setup(plan() if p.is_empty() else p,catalog);return world
func tick(w,frames: int=1,move: Vector2=Vector2.ZERO,sprint: bool=false,jump: bool=false,aiming: bool=false,fire: bool=false):
	for i in range(frames):w.step(1.0/60,move,w.player.position+Vector2.UP*10,fire,fire and i==0,aiming,false,sprint,jump and i==0)
func run():
	var w=fresh();tick(w,180,Vector2.RIGHT);var walk_distance=w.player.position.x
	w=fresh();tick(w,180,Vector2.RIGHT,true);var run_distance=w.player.position.x
	check(w.player.sprinting and absf(w.player.velocity.length()-5.8)<.01,"Shift reaches 5.8m/s")
	check(run_distance>walk_distance*1.6 and run_distance<walk_distance*1.85,"Sprint materially faster than walk")
	w=fresh();tick(w,180,Vector2.ONE,true);check(absf(w.player.position.length()-run_distance)<.01,"Diagonal sprint has no speed bonus")
	for stance in [1,2]:
		w=fresh();w.set_stance(stance);tick(w,120,Vector2.RIGHT,true)
		check(not w.player.sprinting and w.player.velocity.length()<1.7,"Stance blocks sprint "+str(stance))
	w=fresh();tick(w,60,Vector2.RIGHT,true,false,true);check(not w.player.sprinting and w.player.velocity.length()<3.4,"Aiming cancels sprint")
	w=fresh();tick(w,60,Vector2.RIGHT,true,false,false,true);check(not w.player.sprinting and w.shots>0,"Firing cancels sprint")
	w=fresh();w.player.ammo=1;w.reload_weapon();tick(w,30,Vector2.RIGHT,true);check(not w.player.sprinting,"Reloading cancels sprint")
	w=fresh();var events=[];w.event.connect(func(e):if e.type in ["jump","land"]:events.append(e.type))
	tick(w,1,Vector2.ZERO,false,true);check(not w.player.grounded,"Space takes off")
	var peak=0.0
	for i in range(85):
		tick(w,1,Vector2.ZERO,false,i==10);peak=maxf(peak,w.player.elevation)
	check(peak>1.05 and peak<1.2,"Jump apex approximately 1.1m")
	check(w.player.grounded and is_zero_approx(w.player.elevation),"Jump lands at original ground")
	check(events.count("jump")==1 and events.count("land")==1,"Airborne press cannot double jump")
	w=fresh();w.set_stance(2);tick(w,30,Vector2.ZERO,false,true);check(w.player.grounded and w.player.stance==2,"Prone must stand before jumping")
	w=fresh();w.set_stance(1);tick(w,1,Vector2.ZERO,false,true);check(not w.player.grounded and w.player.stance==0,"Crouch jump transitions to standing")
	w=fresh();tick(w,60,Vector2.RIGHT,true);tick(w,1,Vector2.RIGHT,true,true);tick(w,12,Vector2.RIGHT,true)
	check(w.player.velocity.length()>5.7 and not w.player.grounded,"Sprint jump carries takeoff speed")
	var p=plan();var beam=wall(.4,0,3,2.20);beam.y1=1400;beam.y2=1400;p.looseSegments=[beam];w=fresh(p)
	peak=0
	for i in range(80):tick(w,1,Vector2.ZERO,false,i==0);peak=maxf(peak,w.player.elevation)
	check(peak<=.251 and w.player.grounded,"Ceiling blocks upward motion without getting stuck")
	for height in [.65,1.0,1.65,1.8]:
		for angle in [0.0,.7,PI*.5]:
			p=plan();p.looseSegments=[wall(height,angle)];w=fresh(p)
			var direction=Vector2.UP.rotated(angle);w.player.position=Vector2(0,-2)-direction*1.1
			var path=Traversal.find_vault(w,w.player,direction)
			check(not path.is_empty(),"Vault available h=%.2f rotation=%.2f"%[height,angle])
			if path.is_empty():continue
			w.step(1.0/60,direction,w.player.position+direction*10,false,false,false,false,false,true)
			check(not w.player.vault.is_empty(),"Vault enters active state")
			var ammo=w.player.ammo
			w.fire(w.player,w.weapon_for(w.player),w.player,w.player.position,0,World.muzzle_height(w.player),Vector2(10,0))
			check(w.player.ammo==ammo and not w.reload_weapon(),"Vault occupies hands, no fire or reload")
			# Current climb timings include hand support, leg transfer and landing.
			# The old fixed 80 frames ended before higher climbs could finish.
			for i in range(ceili(float(path.duration)*60)+3):w.step(1.0/60,Vector2.ZERO,w.player.position+direction*10,false,false)
			check(w.player.vault.is_empty() and w.player.grounded and w.player.position.distance_to(path.end)<.01,"Vault completes at safe landing")
			check(not w.blocked(w.player.position,.28,1.95,-1,w.player.elevation),"Vault landing outside live geometry")
	p=plan();p.looseSegments=[wall(2.3)];w=fresh(p);w.player.position=Vector2(0,-.9)
	check(Traversal.find_vault(w,w.player,Vector2.UP).is_empty(),"2.3m wall rejects vault")
	tick(w,120,Vector2.UP,true,true);check(w.player.position.y>-1.48,"Jump/sprint cannot tunnel through high wall")
	p=plan();p.looseSegments=[wall(1,0,2)];w=fresh(p);check(Traversal.find_vault(w,w.player,Vector2.UP).is_empty(),"Thick obstacle rejects vault")
	p=plan();var rear=wall(2.8);rear.id="rear";rear.y1=1276;rear.y2=1276;p.looseSegments=[wall(),rear];w=fresh(p);w.player.position=Vector2(0,-.9)
	check(Traversal.find_vault(w,w.player,Vector2.UP).is_empty(),"Blocked landing rejects vault")
	p=plan();p.looseSegments=[wall()];w=fresh(p);w.player.position=Vector2(0,-.9)
	var o=w.objects[0]
	for col in range(o.columns):
		for row in range(o.rows):w.damage_cell(o,col,row,10000,Vector2.ZERO,true)
	check(Traversal.find_vault(w,w.player,Vector2.UP).is_empty(),"Destroyed wall cannot trigger phantom vault")
	tick(w,80,Vector2.UP);check(w.player.position.y<-3,"Destroyed wall remains traversable")
	p=plan();p.looseSegments=[wall()];w=fresh(p);w.player.position=Vector2(0,-.9);w.player.ammo=0;tick(w,1,Vector2.UP,false,true)
	check(not w.player.vault.is_empty() and w.player.reload==0,"Vault cancels reload before ammo transfer")
	var remaining_vault_frames=ceili(float(w.player.vault.duration)*60)+3
	tick(w,20);check(w.player.reload==0 and w.player.ammo==0,"Auto reload waits while vault occupies hands")
	tick(w,maxi(1,remaining_vault_frames-20));check(w.player.reload>0,"Auto reload resumes after safe landing")
	p=plan();p.looseSegments=[wall()];p.vehicles=[{"id":"moving-car","type":catalog.data.vehicles.keys()[0],"x":2500,"y":1400,"angle":0}];w=fresh(p);w.player.position=Vector2(0,-.9)
	tick(w,1,Vector2.UP,false,true);tick(w,26);w.vehicles[0].position=Vector2(0,-3)
	tick(w,80)
	check(w.player.vault.is_empty() and w.player.grounded,"Moving vehicle interrupts vault and player lands")
	check(not w.blocked(w.player.position,.28,1.95,-1,w.player.elevation),"Interrupted vault cannot leave player inside wall")
	p=plan();p.looseSegments=[wall(2.3)];w=fresh(p);w.player.position=Vector2(0,-.9);o=w.objects[0]
	for col in range(o.columns):
		for row in range(3,o.rows):w.damage_cell(o,col,row,10000,Vector2.ZERO,true)
	check(not Traversal.find_vault(w,w.player,Vector2.UP).is_empty(),"Destroyed upper rows lower actual vault height")
	p=plan();p.looseSegments=[wall(.7,0,1.4)];w=fresh(p);w.player.position=Vector2(0,-2);w.player.elevation=1.1;w.player.grounded=false
	tick(w,60);check(w.player.grounded and absf(w.player.elevation-.7)<.001,"Airborne soldier lands on obstacle top")
	tick(w,120,Vector2.RIGHT);check(w.player.grounded and w.player.elevation==0,"Walking off elevated support falls to ground")
	w=fresh();var target=w.add_unit(Vector2(5,0),false);target.elevation=1.1;target.grounded=false
	check(w.ray(Vector2.ZERO,Vector2.RIGHT,10,.5,{"source":0,"team":0}).is_empty(),"Low shot passes below airborne soldier")
	check(not w.ray(Vector2.ZERO,Vector2.RIGHT,10,2.1,{"source":0,"team":0}).is_empty(),"Elevated shot hits airborne soldier")
	w.player.elevation=1.1;check(absf(World.muzzle_height(w.player)-2.45)<.001,"Airborne muzzle follows actual elevation")
	w.invulnerable=false;w.damage_unit(w.player,10000,Vector3.ZERO,w.weapon_for(w.player),false);w.refill()
	check(w.player.alive and w.player.grounded and w.player.elevation==0 and w.player.position==w.player.spawn,"Resupply revives dead airborne player safely")
	p=plan();p.vehicles=[{"id":"car","type":catalog.data.vehicles.keys()[0],"x":2300,"y":1400,"angle":0}];w=fresh(p)
	tick(w,1,Vector2.ZERO,false,true);check(not w.enter_vehicle(0),"Cannot mount while airborne")
	tick(w,70);check(w.enter_vehicle(0),"Can mount after landing")
	w.step(.1,Vector2.UP,Vector2(20,0),false,false,false,true,true,true)
	check(w.player.grounded and w.player.vault.is_empty() and w.player.elevation==0,"Vehicle Space stays brake, not jump")
	print("TRAVERSAL SMOKE: ",checks-failures.size(),"/",checks," passed; walk=",walk_distance," run=",run_distance," jump=",events," failures=",failures)
	quit(0 if failures.is_empty() else 1)
