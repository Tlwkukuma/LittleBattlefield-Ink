extends SceneTree
## Geometry/resource checks, with no input sent to the game window.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Traversal=preload("res://scripts/soldier_traversal.gd")
const Visibility=preload("res://scripts/house_visibility.gd")
const Geometry=preload("res://scripts/house_geometry.gd")
const Structure=preload("res://scripts/house_structure.gd")
const House=preload("res://scripts/house_prefabs.gd")
var catalog=Catalog.new()
var checks=0
var failures=[]

func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)

func fixture(angle: float=0,scale: float=1) -> Dictionary:
	var plan=catalog.range_plan();plan.instances=[{"id":"house","prefabId":"building.residence-two-storey","x":2000,"y":1400,"rotation":angle,"scale":scale}]
	plan.looseSegments=[];plan.trees=[];plan.units.red=[];plan.world.groundFeatures=[]
	var world=World.new();var compiled=world.setup(plan,catalog)
	return {"world":world,"compiled":compiled,"plan":plan}

func place(w,point: Vector2,height: float=0):
	Traversal.reset(w.player);w.player.position=point;w.player.elevation=height
	w.player.velocity=Vector2.ZERO;w.player.requested_velocity=Vector2.ZERO

func walk(w,input: Vector2,frames: int):
	for i in range(frames):
		w.time+=1.0/60;Traversal.move(w,w.player,input,1.0/60,false,false)

func route(w,points: Array,angle: float,label: String):
	for point in points:
		var target: Vector2=Vector2(point).rotated(angle);var continuous=true;var clear=true
		for i in range(420):
			if w.player.position.distance_to(target)<.045:break
			var before: Vector2=w.player.position;var height: float=w.player.elevation
			walk(w,((target-before)*3.0).limit_length(1),1)
			continuous=continuous and before.distance_to(w.player.position)<.12 and absf(height-w.player.elevation)<.23
			clear=clear and not w.blocked(w.player.position,.28,1.95,-1,w.player.elevation)
		check(w.player.position.distance_to(target)<.06 and continuous and clear,"%s waypoint %s angle %.2f actual %s elevation %.3f continuous=%s clear=%s"%[label,point,angle,Vector2(w.player.position).rotated(-angle),w.player.elevation,continuous,clear])

func object(w,id: String) -> Dictionary:
	for o in w.objects:
		if o.id=="house."+id:return o
	return {}

func _initialize():run.call_deferred()
func run():
	var f=fixture();var w=f.world;var roof=f.compiled.roofs[0]
	check(w.houses.size()==1 and w.objects.size()>240,"house compiles real structural pieces and furnishings")
	check(w.objects.filter(func(o):return o.get("house_role","")=="furniture").size()==22,"22 pieces of living, dining, kitchen and bedroom furniture")
	check(is_equal_approx(roof.points[0].distance_to(roof.points[1]),16) and is_equal_approx(roof.points[1].distance_to(roof.points[2]),12),"16 by 12 metre footprint")
	w.housing_support.resolve(w)
	check(w.objects.all(func(o):return o.alive),"intact building remains structurally stable")
	check(not w.blocked(Vector2(0,5),.28,1.95,-1,.04),"front foyer admits standing soldier")
	check(not w.blocked(Vector2(2.2,-2.4),.28,1.95,-1,3.4),"second floor corridor has standing headroom")
	check(is_equal_approx(w.ground_height(Vector2(2.2,-2.4),.28,3.401),3.4),"second floor physically supports standing soldier")
	check(is_equal_approx(w.ground_height(Vector2(2.2,-2.4),.28,.22),.04),"downstairs cannot snap to upstairs support")
	var hit=w.trace_3d(Vector3(2.2,1,-2.4),Vector3.UP,8,{},true)
	check(hit.get("type","")=="object" and hit.target.get("house_role","")=="floor" and absf(hit.distance-2.18)<.002,"real floor blocks shots from downstairs")
	check(w.blocked(Vector2(2.2,-2.4),.28,1.95,-1,1.4),"ceiling limits jumping body height")
	place(w,Vector2(2.2,-2.4),.04);Traversal.move(w,w.player,Vector2.ZERO,1.0/60,false,true)
	var highest=0.0
	for i in range(90):walk(w,Vector2.ZERO,1);highest=maxf(highest,w.player.elevation)
	check(highest<1.26 and w.player.grounded and is_equal_approx(w.player.elevation,.04),"jump collides with ceiling and lands downstairs: highest %.4f final %.4f grounded %s"%[highest,w.player.elevation,w.player.grounded])
	for angle in [0.0,.67]:
		for exterior in [false,true]:
			f=fixture(angle);w=f.world
			var path=[Vector2(9,6.2),Vector2(9,.9),Vector2(9,-4.1),Vector2(7.2,-4.1)] if exterior else [Vector2(0,5),Vector2(-6.9,4.6),Vector2(-6.9,1.5),Vector2(-6.9,-2.9),Vector2(-5,-2.9),Vector2(-5,1.6),Vector2(-5,3),Vector2(-3.5,3)]
			place(w,path[0].rotated(angle),.04)
			route(w,path.slice(1),angle,"exterior up" if exterior else "U stair up")
			check(w.player.elevation>3.39 and w.player.grounded,"stairs reach second floor through landing")
			path.reverse();route(w,path.slice(1),angle,"exterior down" if exterior else "U stair down")
			check(w.player.elevation<.041 and w.player.grounded,"stairs return to ground-floor foyer")
	f=fixture();w=f.world
	var lower=object(w,"inner-step-0");var landing=object(w,"inner-mid-landing")
	check(6.0-.14-(lower.house_local.y+lower.size.y*.5)>4.8,"stair foot has over 4.8 metres to the inside face of the front wall")
	check(landing.size.y>=1.999 and landing.size.x>=3.799,"U turn platform has real space across both flights")
	check(object(w,"outer-mid-landing").size.y>=1.799,"exterior stair has a full-width rest landing")
	for prefix in ["inner","outer"]:
		for step in range(20):
			var o=object(w,prefix+"-step-"+str(step))
			check(is_equal_approx(o.size.y,.30) and is_equal_approx(o.height,.04+(step+1)*House.STAIR_RISE),"uniform 30 cm treads and 16.8 cm risers: %s %d"%[prefix,step])
	for x in [-7.2,-6.4,-5.6,-4.7]:
		for z in [2.8,3.8,4.8]:check(not w.blocked(Vector2(x,z),.28,1.95,-1,.04),"clear full-body approach and turning area %s"%Vector2(x,z))
	place(w,Vector2(11,0));walk(w,Vector2.LEFT,65)
	check(w.player.elevation<.01 and w.player.position.x>10,"tall stair side cannot teleport soldier upward")
	var table: Dictionary=w.objects.filter(func(o):return o.component_id=="furniture.table")[0]
	check(is_inf(Geometry.ray(table,Vector3(0,.4,-2),Vector3.BACK,4,0)),"shot passes through open space between table legs")
	check(not is_inf(Geometry.ray(table,Vector3(0,.77,-2),Vector3.BACK,4,0)),"tabletop is a real ballistic solid")
	check(Geometry.depth(table,Vector2.ZERO,.15,.15,.3)==0,"table is not an invisible full cube")
	var upper=object(w,"floor-5-1");var groundwall=object(w,"south-left-0");var upperwall=object(w,"south-1")
	check(Visibility.state(roof,upper,Vector2.ZERO,0,false,0).opacity==0,"downstairs hides floor above")
	check(Visibility.state(roof,upper,Vector2.ZERO,3.4,false,0).opacity==1,"upstairs shows its supporting floor")
	check(Visibility.state(roof,groundwall,Vector2.ZERO,0,false,0).cut==1.15,"current floor walls cut for indoor readability")
	check(Visibility.state(roof,upperwall,Vector2(20,20),0,false,0).opacity==1,"outside reveals full building")
	for o in w.objects:o.camera_hidden=Visibility.state(roof,o,Vector2.ZERO,0,false,0).camera_hidden
	hit=w.trace_3d(Vector3(3,6,-3),Vector3.DOWN,5,{"camera_pick":true},true)
	check(hit.is_empty(),"camera pick ignores hidden upstairs objects")
	hit=w.trace_3d(Vector3(3,6,-3),Vector3.DOWN,5,{},true)
	check(not hit.is_empty() and hit.target.id==upper.id,"actual shot still hits visually hidden floor")
	Structure.break_whole(w,upper);w.housing_support.resolve(w)
	check(is_equal_approx(w.ground_height(Vector2(3,-3),.28,3.401),.04),"destroyed slab leaves actual unsupported hole")
	place(w,Vector2(3,-3),3.4);walk(w,Vector2.ZERO,100)
	check(w.player.elevation<.041 and w.player.grounded,"soldier falls through destroyed floor to downstairs")
	check(w.trace_3d(Vector3(3,1,-3),Vector3.UP,4.5,{},true).is_empty(),"floor breach opens vertical firing line")
	var stair=object(w,"inner-step-10");Structure.break_whole(w,stair);w.housing_support.resolve(w)
	check(not object(w,"inner-step-10-rail-1").alive,"destroying stair removes unsupported attached railing")
	Structure.break_whole(w,object(w,"inner-mid-landing"));w.housing_support.resolve(w)
	check(not object(w,"inner-mid-north").alive and is_equal_approx(w.ground_height(Vector2(-6.9,-3),.28,1.73),.04),"destroyed turn platform removes its guard and support")
	for o in w.objects:
		if o.get("house_role","")=="wall" and o.storey==0:Structure.break_whole(w,o)
	w.housing_support.resolve(w)
	check(w.objects.filter(func(o):return o.storey>0 and o.alive).is_empty(),"removing all supporting walls collapses upper floor, upper walls, roof and furniture")
	check(object(w,"outer-step-0").alive,"ground-supported exterior stairs survive upper building collapse")
	var reloaded=JSON.parse_string(JSON.stringify(f.plan));var roundtrip=catalog.compile(reloaded)
	check(roundtrip.objects.size()==f.compiled.objects.size() and roundtrip.houses.size()==1,"editor JSON roundtrip preserves housing geometry")
	f=fixture(.67,1.2);w=f.world
	check(absf(f.compiled.roofs[0].points[0].distance_to(f.compiled.roofs[0].points[1])-19.2)<.001,"prefab rotation and uniform scale preserve full house footprint")
	check(is_equal_approx(w.ground_height(Vector2(3,-3).rotated(.67)*1.2,.28,3.401),3.4),"rotated and scaled floor supports correct elevation")
	print("HOUSING_CONTRACT %d/%d passed; failures=%s"%[checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)



