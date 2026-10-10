extends SceneTree
## Deterministic material arithmetic and isolated collision calls, not gameplay input.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Rules=preload("res://scripts/cover_rules.gd")
var catalog=Catalog.new()
var checks=0
var failures=[]
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func fixture(component: String,thickness: float) -> RefCounted:
	var plan={"world":{"w":800,"h":800,"groundFeatures":[]},"instances":[],"looseSegments":[{"id":"panel","componentId":component,"x1":390,"y1":400,"x2":410,"y2":400,"thickness":thickness*40,"godot3d":{"height":.5}}],"trees":[],"deployment":{"player":{"x":600,"y":600}}}
	var world=World.new();world.setup(plan,catalog)
	# Exact 0.5 x 0.5 reference panel, including bags which normally use shorter rows.
	var o=world.objects[0];o.rows=1;o.cell_height=.5;o.hp=[o.max_hp];Rules.annotate(o)
	return world
func impact(world,w: Dictionary,incidence: float=1,distance: float=0):
	var o=world.objects[0]
	world.damage_object(o,Vector2(0,o.size.y*.5),.25,float(w.get("damage",28)),false,0,0,w,distance,incidence)
func count_case(component: String,thickness: float,w: Dictionary,count: int,label: String,incidence: float=1,distance: float=0):
	var world=fixture(component,thickness);var o=world.objects[0]
	for i in range(300 if count==0 else count-1):impact(world,w,incidence,distance)
	check(o.hp[0]>0 and (count>0 or o.hp[0]==o.max_hp),label+" before threshold")
	if count>0:impact(world,w,incidence,distance);check(o.hp[0]==0,label+" exact threshold")
	else:check(world.topology_revision==0 and world.support_dirty.is_empty(),label+" cannot invalidate structure")
func _initialize():
	var weapons=[catalog.weapons.m416,catalog.weapons.akm,catalog.weapons.awm,catalog.weapons["lynx-amr"],catalog.data.emplacements.hmg]
	for row in [["wall.wood-fence",.06,[3,2,2,1,1]],["wall.brick",.24,[48,36,24,6,12]],["wall.stone",.4,[0,0,80,16,40]],["wall.concrete",.2,[0,0,96,20,48]],["wall.bunker",.4,[0,0,0,64,0]],["wall.sandbag",.5,[120,96,60,18,36]]]:
		for i in range(weapons.size()):count_case(row[0],row[1],weapons[i],row[2][i],"%s family %d"%[row[0],i])
	count_case("wall.brick",.48,catalog.weapons.m416,96,"double thickness")
	count_case("wall.brick",.28,catalog.weapons.m416,56,"house thickness")
	count_case("wall.brick",.24,catalog.weapons.m416,96,"60 degree incidence",.5)
	count_case("wall.brick",.24,catalog.weapons.m416,0,"grazing incidence",.14)
	count_case("wall.brick",.24,catalog.weapons.m416,74,"terminal structural falloff",1,float(catalog.weapons.m416.range)/40)
	var altered=catalog.weapons.m416.duplicate();altered.damage=99999
	count_case("wall.brick",.24,altered,48,"flesh damage cannot buff demolition")
	var shotgun=catalog.weapons.s1897
	count_case("wall.wood-fence",.06,shotgun,3*int(shotgun.pellets),"pellets share one shell budget")
	count_case("wall.concrete",.2,catalog.weapons["army-knife"],0,"knife cannot remove concrete")
	var oblique=fixture("wall.brick",.24);var panel=oblique.objects[0]
	var oblique_round={"weapon":catalog.weapons.m416,"position":Vector2(-sqrt(3.0)*.8,.92),"direction":Vector2(sqrt(3.0)*.5,-.5),"height":.25,"slope":0.0,"distance":0.0,"remaining":10.0,"alive":true,"source":0,"team":0,"hit":[],"penetration":0,"radius":0.0}
	oblique.advance_round(oblique_round,2)
	check(absf(panel.max_hp-panel.hp[0]-panel.max_hp/96.0)<.00001,"live collision face supplies 60-degree incidence to damage")
	var world=fixture("wall.concrete",.2);var o=world.objects[0];var rebuilds=[0]
	world.event.connect(func(e):
		if e.type=="object_changed":rebuilds[0]+=1)
	var started=Time.get_ticks_usec()
	for i in range(1000):
		var p={"weapon":catalog.weapons.m416,"position":Vector2(0,2),"direction":Vector2.UP,"height":.25,"slope":0.0,"distance":0.0,"remaining":10.0,"alive":true,"source":0,"team":0,"hit":[],"penetration":0,"radius":.005}
		world.advance_round(p,4)
		if i==0:check(not p.alive and p.position.y>0,"actual M4 projectile stops on concrete")
	check(o.hp[0]==o.max_hp and world.broken==0,"1000 actual M4 contact resolutions never chip away HP")
	check(rebuilds[0]<=3 and o.impact_marks[0].size()<=3,"cosmetic-only repeat hits cannot rebuild a wall every shot")
	print("COVER_CONTACT_COST 1000 isolated contacts ms=",(Time.get_ticks_usec()-started)/1000.0," mesh_notifications=",rebuilds[0]," topology_changes=",world.topology_revision)
	world.blast(Vector2(0,.11),2,2000,catalog.weapons.rpg,.25)
	check(not o.alive and world.broken>0,"concrete remains explosive-destructible")
	var plan=catalog.range_plan();var range_world=World.new();range_world.setup(plan,catalog)
	for object in range_world.objects:
		if object.get("cover_damage_index",-1)!=Rules.materials.concrete.index:continue
		var before=object.hp.duplicate()
		range_world.damage_object(object,object.position,object.elevation+.1,9999,false,0,0,catalog.weapons.m416)
		check(object.hp==before,"M4 prohibition includes concrete component "+object.component_id)
	check(Rules.load_count==1,"damage resolution never reparses registry")
	print("COVER_DAMAGE %d/%d passed; failures=%s"%[checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)
