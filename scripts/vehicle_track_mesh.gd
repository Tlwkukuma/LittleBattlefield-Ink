extends RefCounted
## A closed annular belt: tread, inner return surface and both side rims.
const Style=preload("res://scripts/vehicle_style.gd")
const OUTER_RADIUS=.29
const INNER_RADIUS=.235
const AXLE_HEIGHT=.33

static func quad(vertices: PackedVector3Array,normals: PackedVector3Array,colors: PackedColorArray,corners: Array) -> void:
	var normal: Vector3=(corners[1]-corners[0]).cross(corners[2]-corners[0]).normalized()
	for index in [0,2,1,0,3,2]:
		vertices.append(corners[index]);normals.append(normal);colors.append(Style.RUBBER)

static func build(radius: float) -> ArrayMesh:
	var length=radius*2.62;var half_width=radius*.145
	var outer=[];var inner=[]
	for end in [-1,1]:
		for i in range(7):
			var angle=float(i)/6*PI+(PI if end==-1 else 0.0)
			var center=Vector3(0,AXLE_HEIGHT,end*(length*.5-OUTER_RADIUS))
			var radial=Vector3(0,cos(angle),sin(angle))
			outer.append(center+radial*OUTER_RADIUS);inner.append(center+radial*INNER_RADIUS)
	var vertices=PackedVector3Array();var normals=PackedVector3Array();var colors=PackedColorArray()
	var left=Vector3.LEFT*half_width;var right=-left
	for i in range(outer.size()):
		var j=(i+1)%outer.size()
		quad(vertices,normals,colors,[outer[i]+left,outer[j]+left,outer[j]+right,outer[i]+right])
		quad(vertices,normals,colors,[inner[i]+right,inner[j]+right,inner[j]+left,inner[i]+left])
		quad(vertices,normals,colors,[outer[i]+left,inner[i]+left,inner[j]+left,outer[j]+left])
		quad(vertices,normals,colors,[outer[i]+right,outer[j]+right,inner[j]+right,inner[i]+right])
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
