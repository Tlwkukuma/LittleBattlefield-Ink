extends SceneTree
## Headless data/geometry checks only. Visual acceptance belongs to the user.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Terrain=preload("res://scripts/terrain_art.gd")
const Ground=preload("res://scripts/terrain_ground.gd")
const Showcase=preload("res://scripts/terrain_showcase.gd")
var catalog=Catalog.new()
var checks=0
var failures: Array=[]

func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)

func empty_plan() -> Dictionary:
	var p=Showcase.plan(catalog);p.instances=[];p.looseSegments=[];p.trees=[];p.units.red=[];return p

func wall_world(angle: float=0,elevation: float=0) -> RefCounted:
	var p=empty_plan();var center=Vector2(1200,900);var offset=Vector2.from_angle(angle)*100
	p.looseSegments=[{"id":"wall","componentId":"wall.brick","x1":center.x-offset.x,"y1":center.y-offset.y,"x2":center.x+offset.x,"y2":center.y+offset.y,"thickness":20,"godot3d":{"height":2.8,"elevation":elevation}}]
	var w=World.new();w.setup(p,catalog);return w

func _initialize():run.call_deferred()

func run():
	for angle in [0.0,.67,PI*.5]:
		var w=wall_world(angle);var o: Dictionary=w.objects[0];var col=int(o.columns/2);var row=2
		var x=-o.size.x*.5+(col+.5)*o.cell_width;var center=Vector2(x,0).rotated(angle);var normal=Vector2(0,1).rotated(angle)
		var origin=center+normal*2;var height=(row+.5)*o.cell_height
		check(not w.ray(origin,-normal,4,height,{},true).is_empty(),"intact wall blocks shots "+str(angle))
		var original_hp: Array=o.hp.duplicate()
		w.damage_object(o,center+normal*.25,height,10,false,col,row)
		check(o.hp[row*o.columns+col]<original_hp[row*o.columns+col] and o.hp[0]==original_hp[0],"bullet damages only selected cell "+str(angle))
		check(o.impact_marks.get(row*o.columns+col,[]).size()==1,"bullet mark recorded at actual hit "+str(angle))
		var damaged=Terrain.wall_mesh(o);check(damaged.get_surface_count()==1,"damaged wall creates bounded mesh")
		w.damage_cell(o,col,row,10000,origin,false)
		check(w.ray(origin,-normal,4,height,{},true).is_empty(),"shot crosses removed cell "+str(angle))
		check(w.blocked(center,.25,1.95),"remaining sill still blocks standing "+str(angle))
		for clear_col in range(maxi(0,col-1),mini(o.columns,col+2)):
			for clear_row in range(o.rows):w.damage_cell(o,clear_col,clear_row,10000,origin,true)
		w.resolve_support()
		check(not w.blocked(center,.30,1.95),"breach admits standing character "+str(angle))
		check(w.topology_revision>0 and w.navigation_dirty,"breach invalidates navigation "+str(angle))
		var cut=Terrain.wall_mesh(o,1.15)
		check(cut.get_aabb().end.y<=1.151,"cutaway mesh stays below requested height")
	var w=wall_world();var o: Dictionary=w.objects[0]
	for col in range(o.columns):w.damage_cell(o,col,0,10000,Vector2.ZERO,true)
	w.resolve_support()
	check(not o.alive and o.hp.all(func(h):return h==0),"unsupported wall collapses fully")
	check(Terrain.wall_mesh(o).get_surface_count()==0,"fully destroyed wall has no floating trim")
	w=wall_world();o=w.objects[0]
	w.blast(Vector2(0,.28),.85,200,{"kind":"shell"},2.55)
	check(o.hp.slice(0,o.columns).all(func(h):return h==o.max_hp),"high explosion leaves out-of-radius foundation intact")
	check(o.hp.slice((o.rows-1)*o.columns).any(func(h):return h<o.max_hp),"high explosion damages upper cells at real height")
	w=wall_world();o=w.objects[0]
	w.blast(Vector2(0,.28),.85,200,{"kind":"shell"},.25)
	check(o.hp.slice(0,o.columns).any(func(h):return h<o.max_hp),"ground explosion damages wall foundation")
	check(o.hp.slice((o.rows-1)*o.columns).all(func(h):return h==o.max_hp),"ground explosion does not reach distant wall top")
	for enabled in [true,false]:
		var p=empty_plan();p.instances=[{"id":"house","prefabId":"building.guard-post","x":1200,"y":900,"rotation":.4,"scale":1,"godot3d":{"height":2.8,"windows":enabled}}]
		w=World.new();var compiled=w.setup(p,catalog);o=w.objects[0]
		check(not o.opening_cells.is_empty() if enabled else o.opening_cells.is_empty(),"window switch affects physical openings "+str(enabled))
		check(o.initial_solid_count==o.hp.filter(func(h):return h>0).size(),"architectural voids excluded from roof damage ratio")
		if enabled:
			var cell=int(o.opening_cells.keys()[0]);var col=cell%o.columns;var row=int(cell/o.columns)
			var at=o.position+Vector2(-o.size.x*.5+(col+.5)*o.cell_width,0).rotated(o.angle)
			var normal=Vector2(0,1).rotated(o.angle);var height=(row+.5)*o.cell_height
			check(w.ray(at+normal*1.0,-normal,2.0,height,{},true).is_empty(),"architectural window passes bullets")
			check(w.blocked(at,.20,1.95),"window sill remains real cover")
			check(Terrain.wall_mesh(o).get_surface_count()==1,"window wall includes surviving reveals")
		check(Ground.roof_mesh(compiled.roofs[0]).get_surface_count()==1,"roof works with rotated footprint")
	var sample=Showcase.plan(catalog);w=World.new();var compiled=w.setup(sample,catalog)
	check(not w.blocked(w.player.position,.3,1.95),"acceptance spawn is clear")
	check(compiled.roofs.size()==2 and w.units.size()==5,"acceptance layout has buildings and four cover targets")
	for o2 in w.objects:
		if o2.output=="tree":check(is_equal_approx(o2.size.x,o2.cell_width),"tree hit cells match trunk footprint")
	# Exercise every inherited prefab as data/resources, without driving a game window.
	for id in catalog.prefabs:
		var p=empty_plan();p.instances=[{"id":"prefab","prefabId":id,"x":1200,"y":900,"rotation":.3,"scale":1,"godot3d":{}}]
		w=World.new();compiled=w.setup(p,catalog);var valid=true
		for o2 in w.objects:
			valid=valid and o2.hp.size()==o2.columns*o2.rows and o2.initial_solid_count>0
			if o2.component_id.begins_with("wall."):valid=valid and Terrain.wall_mesh(o2).get_surface_count()==1
		for roof in compiled.roofs:valid=valid and Ground.roof_mesh(roof).get_surface_count()==1
		check(valid,"prefab geometry "+id)
	var encoded=JSON.stringify(sample);var restored=JSON.parse_string(encoded)
	check(catalog.compile(restored).objects.size()==catalog.compile(sample).objects.size(),"layout round-trip preserves objects")
	check(restored.instances[0].godot3d.windows,"layout round-trip preserves architectural settings")
	print("TERRAIN_CONTRACT ",checks-failures.size(),"/",checks," passed; failures=",failures)
	quit(0 if failures.is_empty() else 1)
