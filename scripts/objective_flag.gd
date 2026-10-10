extends MeshInstance3D
## Flag, plinth, mast, rope and near-zone dashes share one immutable mesh/pass.
const Zone=preload("res://scripts/capture_zone.gd")
var vertices=PackedVector3Array()
var colors=PackedColorArray()
var uv=PackedVector2Array()
var uv2=PackedVector2Array()
var point: Dictionary
var material=ShaderMaterial.new()

func triangle(a: Vector3,b: Vector3,c: Vector3,tint: Color,kind: float=0.0,coords: Array=[]):
	vertices.append_array(PackedVector3Array([a,b,c]))
	for i in range(3):colors.append(tint);uv.append(Vector2(kind,0));uv2.append(coords[i] if coords.size()==3 else Vector2.ZERO)

func primitive(shape: Mesh,at: Vector3,tint: Color):
	var data=shape.surface_get_arrays(0);var positions: PackedVector3Array=data[Mesh.ARRAY_VERTEX];var indices: PackedInt32Array=data[Mesh.ARRAY_INDEX]
	for i in range(0,indices.size(),3):
		var a=positions[indices[i]];var b=positions[indices[i+1]];var c=positions[indices[i+2]]
		var normal=(b-a).cross(c-a).normalized();var shade=.77+absf(normal.y)*.20+maxf(0,normal.x)*.08
		triangle(a+at,b+at,c+at,Color(tint.r*shade,tint.g*shade,tint.b*shade))

func build(host,p: Dictionary):
	vertices.clear();colors.clear();uv.clear();uv2.clear()
	point=p;name="ObjectiveFlag";cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var at: Vector2=p.position;position=Vector3(at.x,p.elevation,at.y)
	var visual: Vector2=p.get("visual_position",at)
	var marker=Vector3(visual.x-at.x,host.world.terrain.height(visual)-float(p.elevation),visual.y-at.y) if visual!=at else Vector3.ZERO
	var base=CylinderMesh.new();base.top_radius=.48;base.bottom_radius=.64;base.height=.12;base.radial_segments=12;base.rings=1
	primitive(base,marker+Vector3(0,.06,0),Color("9c9880"))
	var mast=CylinderMesh.new();mast.top_radius=.044;mast.bottom_radius=.064;mast.height=4.45;mast.radial_segments=8;mast.rings=1
	primitive(mast,marker+Vector3(0,2.3,0),Color("535956"))
	var cap=CylinderMesh.new();cap.top_radius=.10;cap.bottom_radius=.10;cap.height=.08;cap.radial_segments=8;cap.rings=1
	primitive(cap,marker+Vector3(0,4.55,0),Color("c6b58c"))
	var rope=BoxMesh.new();rope.size=Vector3(.014,3.85,.014)
	primitive(rope,marker+Vector3(-.10,2.40,0),Color("b5aa86"))
	for x in range(12):
		for y in range(4):
			var corners=[Vector2(x/12.0,y/4.0),Vector2((x+1)/12.0,y/4.0),Vector2((x+1)/12.0,(y+1)/4.0),Vector2(x/12.0,(y+1)/4.0)]
			var v=[]
			for q in corners:v.append(marker+Vector3(.06+q.x*1.38,q.y*.88,0))
			for idx in [[0,1,2],[0,2,3]]:triangle(v[idx[0]],v[idx[1]],v[idx[2]],Color.WHITE,1,[corners[idx[0]],corners[idx[1]],corners[idx[2]]])
	for segment in boundary_segments(p):
		var from: Vector2=segment[0];var to: Vector2=segment[1]
		var side=(to-from).normalized().orthogonal()*.035;var v=[]
		for q in [from+side,to+side,to-side,from-side]:v.append(Vector3(q.x-at.x,host.world.terrain.height(q)-p.elevation+.028,q.y-at.y))
		triangle(v[0],v[1],v[2],Color.WHITE,2);triangle(v[0],v[2],v[3],Color.WHITE,2)
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2
	mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	material.shader=preload("res://shaders/objective_flag.gdshader");material_override=material
	custom_aabb=mesh.get_aabb().expand(marker+Vector3(1.6,4.6,.15)).expand(marker+Vector3(-.7,0,-.15))
	refresh(host)

func refresh(host):
	material.set_shader_parameter("team_color",Zone.color(point))
	material.set_shader_parameter("control",absf(float(point.progress)))
	material.set_shader_parameter("show_zone",not host.armory.visible and host.world.player.position.distance_to(point.position)<point.radius+3.0)

static func boundary_segments(p: Dictionary) -> Array:
	# Authored polygons retain their exact edge/dash layout. Circular objectives
	# use the same physical radius as CaptureZone, baked once into this mesh.
	var result=[]
	var polygon: PackedVector2Array=p.get("zone",PackedVector2Array())
	if polygon.size()>=3:
		for i in range(polygon.size()):
			var a=polygon[i];var b=polygon[(i+1)%polygon.size()];var direction=(b-a).normalized()
			var distance=0.0
			while distance<a.distance_to(b):
				result.append([a+direction*distance,a+direction*minf(distance+.48,a.distance_to(b))]);distance+=.88
	else:
		var radius=maxf(0,float(p.get("radius",0)))
		if radius<=.001:return result
		var count=clampi(int(ceil(TAU*radius/.88)),8,128)
		var span=minf(.48/radius,TAU/count*.6)
		for i in range(count):
			var angle=TAU*i/count
			result.append([p.position+Vector2.from_angle(angle-span*.5)*radius,p.position+Vector2.from_angle(angle+span*.5)*radius])
	return result
