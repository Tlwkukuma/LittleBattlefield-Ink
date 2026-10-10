extends Node3D
## Prebaked cell appearances; HP/cut changes select indices, never rebuild cells.
const Terrain=preload("res://scripts/terrain_art.gd")
const Surface=preload("res://scripts/baked_wall_surface.gd")
const CUTS=[INF,1.15]
const HEALTH=[1.0,.75,.35]
var views: Dictionary={}
var sectors: Dictionary={}
var members: Dictionary={}
var dirty: Dictionary={}
var impacts
var last_ms=0.0
var last_cells=0
var last_bytes=0
var last_cut_cells=0
var last_damage_cells=0
var last_fallbacks=0
static func state(object: Dictionary,index: int,cut: float) -> int:
	if not object.alive or object.hp[index]<=0 or cut not in CUTS:return -1
	var damage: float=1.0-object.hp[index]/object.max_hp
	return CUTS.find(cut)*3+(0 if damage<=.06 else 1 if damage<.45 else 2)
func bake(object: Dictionary,index: int,cut: float,ratio: float,pose: Transform3D) -> Dictionary:
	# Neighbouring live cells occlude the prebuilt internal faces. Removing one
	# immediately exposes the correct break section, without neighbour rebuilding.
	var fixture=object.duplicate();fixture.hp=object.hp.duplicate();fixture.impact_marks={};fixture.alive=true
	fixture.hp[index]=object.max_hp*ratio
	var col: int=index%int(object.columns);var row: int=int(index/object.columns)
	for neighbor in [index-1 if col>0 else -1,index+1 if col+1<object.columns else -1,index-int(object.columns) if row>0 else -1,index+int(object.columns) if row+1<object.rows else -1]:
		if neighbor>=0:fixture.hp[neighbor]=0
	var data=Terrain.wall_geometry(fixture,cut,index)
	data.v=pose*data.v;data.n=Transform3D(pose.basis,Vector3.ZERO)*data.n
	return data
func configure(objects: Array,source_views: Dictionary):
	views=source_views;var mark_slots: int=0
	for object in objects:
		if object.has("house_role") or not views.has(object.id) or views[object.id].mesh==null:continue
		var view: Dictionary=views[object.id]
		if not view.mesh.material_override is ShaderMaterial:continue
		var cell=Vector2i.ZERO
		if not sectors.has(cell):
			var node=MeshInstance3D.new();node.name="BakedDestructibleWalls";node.material_override=view.mesh.material_override.duplicate()
			add_child(node);sectors[cell]={"node":node,"members":[],"surface":Surface.new()}
		var sector: Dictionary=sectors[cell];var chunks=[];var pose: Transform3D=view.mesh.global_transform
		var cut: float=view.get("cut_height",INF)
		for index: int in range(object.hp.size()):
			var variants=[]
			for height: float in CUTS:
				for health: float in HEALTH:variants.append(bake(object,index,height,health,pose))
			chunks.append(sector.surface.add(variants,state(object,index,cut)))
		sector.members.append(object)
		members[object.id]={"sector":cell,"chunks":chunks,"hp":object.hp.duplicate(),"marks":{},"alive":object.alive,"cut":cut,"pose":pose,"mark_offset":mark_slots,"layers":view.mesh.layers}
		mark_slots+=object.hp.size()*3;view.mesh.layers=0
	for sector in sectors.values():sector.surface.build();sector.node.mesh=sector.surface.mesh
	impacts=preload("res://scripts/wall_impact_batch.gd").new();add_child(impacts)
	var bounds=AABB()
	for sector in sectors.values():bounds=bounds.merge(sector.surface.mesh.get_aabb())
	impacts.configure(mark_slots,bounds)
	for object in objects:
		if members.has(object.id) and (not object.get("impact_marks",{}).is_empty() or members[object.id].cut not in CUTS):changed(object)
	flush()
func changed(object: Dictionary):
	if members.has(object.id):dirty[object.id]=object
func flush():
	var started=Time.get_ticks_usec();last_cells=0;last_bytes=0;last_cut_cells=0;last_damage_cells=0;last_fallbacks=0
	for object in dirty.values():
		var member: Dictionary=members[object.id];var marks: Dictionary=object.get("impact_marks",{})
		var cut: float=views[object.id].get("cut_height",INF);var cut_changed: bool=member.cut!=cut
		var surface=sectors[member.sector].surface;var before: int=surface.uploaded_bytes
		# Keep uncommon editor cut heights correct through the original resource.
		var fallback: bool=cut not in CUTS
		views[object.id].mesh.layers=member.layers if fallback else 0
		if fallback:views[object.id].mesh.mesh=Terrain.wall_mesh(object,cut);last_fallbacks+=1
		for index: int in range(object.hp.size()):
			var hp_changed: bool=member.alive!=object.alive or member.hp[index]!=object.hp[index]
			var marks_changed: bool=member.marks.get(index,[])!=marks.get(index,[])
			if not hp_changed and not marks_changed and not cut_changed:continue
			var selected: int=state(object,index,cut);var chunk: Dictionary=member.chunks[index]
			if selected!=chunk.selected:
				last_cells+=1
				if cut_changed:last_cut_cells+=1
				if hp_changed:last_damage_cells+=1
				surface.select(chunk,selected)
			if marks.has(index) or member.marks.has(index):impacts.write(member.mark_offset+index*3,[] if fallback else marks.get(index,[]),object,index,member.pose,cut)
		last_bytes+=surface.uploaded_bytes-before
		member.hp=object.hp.duplicate();member.marks=marks.duplicate(true);member.alive=object.alive;member.cut=cut
	if not dirty.is_empty():impacts.finish()
	dirty.clear();last_ms=(Time.get_ticks_usec()-started)/1000.0
