extends Node3D
## One terrain-conforming draw, bounded event work, no per-mark nodes or physics.
const Surface=preload("res://scripts/blast_surface.gd")
const LIMIT=64
const LIFETIME=90.0
var world
var camera: Camera3D
var entries: Array=[]
var pending: Array=[]
var drawing: MeshInstance3D
var material: ShaderMaterial
var serial=0
var poll=0.0
var dirty=false
var uploads=0
var upload_wait=0.0

func _ready():
	material=ShaderMaterial.new();material.shader=preload("res://shaders/blast_mark.gdshader")
	drawing=MeshInstance3D.new();drawing.material_override=material;drawing.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(drawing);set_process(false)
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
	arrays[Mesh.ARRAY_TEX_UV2]=PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
	arrays[Mesh.ARRAY_COLOR]=PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE])
	var warmup=ArrayMesh.new();warmup.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);drawing.mesh=warmup
	RenderingServer.frame_post_draw.connect(finish_warmup,CONNECT_ONE_SHOT)

func finish_warmup():
	if entries.is_empty():drawing.hide()

func add_blast(e: Dictionary):
	var at: Vector2=e.position;var ground: float=world.terrain.height(at)
	var normal: Vector3=e.get("normal",Vector3.ZERO)
	# An impact on armor, a wall or a roof must not stamp the ground below it.
	if normal.length_squared()>.1 and normal.y<.65:return
	if str(e.get("material","")) in ["metal","wood","glass"]:return
	var height=float(e.get("height",ground+.25))-ground
	if height<-.15 or height>.65 or at.distance_squared_to(world.player.position)>4096:return
	if pending.size()>=3:return
	var w: Dictionary=e.get("weapon",{});var kind=str(w.get("kind","shell"))
	var radius=clampf(float(e.radius)*.27,.22,1.45)
	if float(w.get("impactBlastRadius",0))>0:radius=minf(radius,.36)
	elif kind in ["grenadeProjectile","vehicleGrenade"]:radius=minf(radius,.52)
	elif kind=="grenade":radius=minf(radius,.70)
	elif kind=="shell":
		var caliber=str(preload("res://scripts/weapon_profile.gd").get_profile(w).flight_identity)
		radius*=.78 if caliber=="45" else 1.12 if caliber=="88" else 1.0
	var palette=Surface.palette(world,at)
	serial+=1
	var entry={"at":at,"radius":radius,"birth":float(world.time),"seed":fposmod(serial*.618033989,1.0),"soil":palette.soil,
		"relief":0.0 if palette.hard or str(w.get("blastStyle",""))=="fuel" else 1.0,"vertices":PackedVector3Array(),"uv":PackedVector2Array()}
	for queued in pending:
		if at.distance_squared_to(queued.at)<pow(minf(radius,float(queued.radius))*.55,2):
			queued.radius=maxf(radius,float(queued.radius));return
	# Repeated fire reuses a nearby footprint rather than piling opaque discs.
	for old in entries:
		if at.distance_squared_to(old.at)<pow(minf(radius,float(old.radius))*.55,2):
			if world.time-float(old.birth)<.4:return
			entry.at=old.at;entry.radius=maxf(radius,float(old.radius));entries.erase(old);break
	pending.append(entry);set_process(true)

func bake(entry: Dictionary):
	var r=float(entry.radius)*1.25;var at: Vector2=entry.at
	var terrain=world.terrain;var cell=float(terrain.cell)
	var begin: Vector2i=Vector2i(((at-Vector2.ONE*r+terrain.bounds)/cell).floor())
	var finish: Vector2i=Vector2i(((at+Vector2.ONE*r+terrain.bounds)/cell).ceil())
	var v=PackedVector3Array();var uv=PackedVector2Array()
	# Match the source terrain's diagonal exactly: slopes cannot intersect a flat disc.
	for z in range(maxi(0,begin.y),mini(terrain.size.y,finish.y)):
		for x in range(maxi(0,begin.x),mini(terrain.size.x,finish.x)):
			var corners=[terrain.vertex(x,z),terrain.vertex(x,z+1),terrain.vertex(x+1,z),terrain.vertex(x+1,z+1)]
			for triangle in [[0,1,2],[2,1,3]]:
				var a: Vector3=corners[triangle[0]];var b: Vector3=corners[triangle[1]];var c: Vector3=corners[triangle[2]]
				if absf((b-a).cross(c-a).normalized().y)<.65:continue
				# Subdivide on the source plane for a low raised lip without cutting terrain.
				var ab=(a+b)*.5;var bc=(b+c)*.5;var ca=(c+a)*.5
				for point in [a,ab,ca,ab,b,bc,ca,bc,c,ab,bc,ca]:
					var p: Vector3=point;p.y+=.022+entry.seed*.001
					v.append(p);uv.append((Vector2(p.x,p.z)-at)/float(entry.radius))
	entry.vertices=v;entry.uv=uv
	var data=PackedVector2Array();data.resize(v.size());data.fill(Vector2(entry.birth,entry.seed))
	var color: Color=entry.soil;color.a=entry.relief
	var colors=PackedColorArray();colors.resize(v.size());colors.fill(color)
	entry.data=data;entry.colors=colors

func rebuild():
	var v=PackedVector3Array();var uv=PackedVector2Array();var data=PackedVector2Array();var colors=PackedColorArray()
	for entry in entries:
		v.append_array(entry.vertices);uv.append_array(entry.uv)
		data.append_array(entry.data);colors.append_array(entry.colors)
	var mesh=ArrayMesh.new()
	if not v.is_empty():
		var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=v;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=data;arrays[Mesh.ARRAY_COLOR]=colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	drawing.mesh=mesh;drawing.visible=not v.is_empty();uploads+=1

func _process(delta: float):
	material.set_shader_parameter("effect_clock",float(world.time));poll-=delta;upload_wait-=delta
	# At most one new footprint is baked per frame; existing vertex arrays are reused.
	if not pending.is_empty():
		var entry: Dictionary=pending.pop_front();bake(entry);entries.append(entry)
		if entries.size()>LIMIT:entries.pop_front()
		dirty=true
	if poll<=0:
		poll=1.0
		for i in range(entries.size()-1,-1,-1):
			if world.time-float(entries[i].birth)>LIFETIME:entries.remove_at(i);dirty=true
	if dirty and upload_wait<=0:rebuild();dirty=false;upload_wait=.10
	if entries.is_empty() and pending.is_empty() and not dirty:set_process(false)

func clear():
	entries.clear();pending.clear();drawing.mesh=null;drawing.hide();dirty=false;upload_wait=0;set_process(false)

func stats() -> Dictionary:
	return {"count":entries.size(),"capacity":LIMIT,"batches":1 if drawing.visible else 0,"uploads":uploads,"pending":pending.size()}
