extends RefCounted
## Native-color UI triangles, including one-pixel alpha edges. No render targets.
var vertices:=PackedVector2Array()
var colors:=PackedColorArray()
var uvs:=PackedVector2Array()
var indices:=PackedInt32Array()
var enabled:=true
func append_batch(other):
	var base: int=vertices.size()
	vertices.append_array(other.vertices);colors.append_array(other.colors);uvs.append_array(other.uvs)
	var shifted: PackedInt32Array=other.indices.duplicate()
	for i: int in range(shifted.size()):shifted[i]+=base
	indices.append_array(shifted)
func triangle(a: Vector2,b: Vector2,c: Vector2,ca: Color,cb: Color,cc: Color):
	var base: int=vertices.size()
	vertices.append(a);vertices.append(b);vertices.append(c)
	colors.append(ca);colors.append(cb);colors.append(cc)
	uvs.append(Vector2.ZERO);uvs.append(Vector2.ZERO);uvs.append(Vector2.ZERO)
	indices.append(base);indices.append(base+1);indices.append(base+2)
func quad(rect: Rect2,uv: Rect2,color: Color):
	if not enabled:return
	var base=vertices.size();vertices.append_array(PackedVector2Array([rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]));colors.append_array(PackedColorArray([color,color,color,color]));uvs.append_array(PackedVector2Array([uv.position,uv.position+Vector2(uv.size.x,0),uv.end,uv.position+Vector2(0,uv.size.y)]));indices.append_array(PackedInt32Array([base,base+1,base+2,base,base+2,base+3]))
func contour(rect: Rect2,radius: float) -> PackedVector2Array:
	var result=PackedVector2Array();radius=clampf(radius,0,minf(rect.size.x,rect.size.y)*.5)
	var centers=[rect.position+Vector2(radius,radius),rect.position+Vector2(rect.size.x-radius,radius),rect.end-Vector2(radius,radius),rect.position+Vector2(radius,rect.size.y-radius)]
	for corner in range(4):
		for step in range(7):result.append(centers[corner]+Vector2.from_angle(PI+corner*PI*.5+step*PI/12)*radius)
	return result
func ring(outer: PackedVector2Array,inner: PackedVector2Array,out_color: Color,in_color: Color):
	for i in range(outer.size()):
		var j=(i+1)%outer.size();triangle(outer[i],outer[j],inner[j],out_color,out_color,in_color);triangle(outer[i],inner[j],inner[i],out_color,in_color,in_color)
func polygon(points: PackedVector2Array,color: Color):
	for i in range(1,points.size()-1):triangle(points[0],points[i],points[i+1],color,color,color)
func style(style_box: StyleBox,rect: Rect2):
	if not enabled:return
	if not style_box is StyleBoxFlat:return
	var width=float(style_box.border_width_left);var radius=float(style_box.corner_radius_top_left)
	var outer=contour(rect,radius);var inner=contour(rect.grow(-width),maxf(0,radius-width))
	if width>0:ring(outer,inner,style_box.border_color,style_box.border_color)
	if style_box.draw_center:polygon(inner if width>0 else outer,style_box.bg_color)
	if style_box.anti_aliasing:
		var color=style_box.border_color if width>0 else style_box.bg_color;var transparent=color;transparent.a=0
		ring(contour(rect.grow(.65),radius+.65),outer,transparent,color)
func line(a: Vector2,b: Vector2,color: Color,width: float=1.0,antialiased: bool=true):
	if not enabled:return
	var normal=(b-a).orthogonal().normalized()*width*.5
	var points=PackedVector2Array([a+normal,b+normal,b-normal,a-normal]);polygon(points,color)
	if antialiased:
		var transparent=color;transparent.a=0;var extra=normal.normalized()*.65
		for sign_value in [-1,1]:
			var p=a+normal*sign_value;var q=b+normal*sign_value;var e=extra*sign_value
			triangle(p,q,q+e,color,color,transparent);triangle(p,q+e,p+e,color,transparent,transparent)
func arc(center: Vector2,radius: float,start: float,end: float,segments: int,color: Color,width: float,antialiased: bool=true):
	if not enabled:return
	for i in range(segments):line(center+Vector2.from_angle(lerpf(start,end,float(i)/segments))*radius,center+Vector2.from_angle(lerpf(start,end,float(i+1)/segments))*radius,color,width,antialiased)
func circle(center: Vector2,radius: float,color: Color):
	var points=PackedVector2Array()
	for i in range(24):points.append(center+Vector2.from_angle(i*TAU/24)*radius)
	polygon(points,color)
	var transparent=color;transparent.a=0;var outer=PackedVector2Array()
	for i in range(24):outer.append(center+Vector2.from_angle(i*TAU/24)*(radius+.65))
	ring(outer,points,transparent,color)
func mesh() -> ArrayMesh:
	var result=ArrayMesh.new()
	if vertices.is_empty():return result
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_INDEX]=indices
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES);return result
