extends RefCounted
## GPU buffers survive damage. Unused indices form degenerate triangles at
## vertex zero, avoiding vertex shader work for reserved, unused vertices.
var mesh=ArrayMesh.new()
var chunks: Array=[]
var vertex_count=0
var uploaded_bytes=0
var update_count=0
var index_stride=0
const FLAGS=(Mesh.ARRAY_CUSTOM_RGB_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)|Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE
func add(data: Dictionary) -> Dictionary:
	# Extra break faces (24), cracks (192), six impact marks (432), chips (216).
	var capacity=int(ceil(float(data.v.size()+864)/48))*48
	var chunk={"offset":vertex_count,"capacity":capacity,"data":data}
	chunks.append(chunk);vertex_count+=capacity;return chunk
func build():
	var vertices=PackedVector3Array();vertices.resize(vertex_count)
	var normals=PackedFloat32Array();normals.resize(vertex_count*3)
	var colors=PackedFloat32Array();colors.resize(vertex_count*4)
	var indices=PackedInt32Array();indices.resize(vertex_count)
	for chunk in chunks:
		var data: Dictionary=chunk.data
		for i in range(data.v.size()):
			var at: int=chunk.offset+i;vertices[at]=data.v[i];indices[at]=at
			var normal: Vector3=data.n[i];var color: Color=data.c[i]
			normals[at*3]=normal.x;normals[at*3+1]=normal.y;normals[at*3+2]=normal.z
			colors[at*4]=color.r;colors[at*4+1]=color.g;colors[at*4+2]=color.b;colors[at*4+3]=color.a
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_CUSTOM0]=normals;arrays[Mesh.ARRAY_CUSTOM1]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},FLAGS)
	var format=mesh.surface_get_format(0)
	index_stride=RenderingServer.mesh_surface_get_format_index_stride(format,vertex_count)
	assert(RenderingServer.mesh_surface_get_format_vertex_stride(format,vertex_count)==12)
	assert(RenderingServer.mesh_surface_get_format_attribute_stride(format,vertex_count)==28)
	assert(RenderingServer.mesh_surface_get_format_offset(format,vertex_count,Mesh.ARRAY_CUSTOM0)==0)
	assert(RenderingServer.mesh_surface_get_format_offset(format,vertex_count,Mesh.ARRAY_CUSTOM1)==12)
static func prepare(data: Dictionary) -> Dictionary:
	if data.has("vertex_bytes"):return data
	var attributes=PackedFloat32Array();attributes.resize(data.v.size()*7)
	for i: int in range(data.v.size()):
		var normal: Vector3=data.n[i];var color: Color=data.c[i];var at: int=i*7
		attributes[at]=normal.x;attributes[at+1]=normal.y;attributes[at+2]=normal.z
		attributes[at+3]=color.r;attributes[at+4]=color.g;attributes[at+5]=color.b;attributes[at+6]=color.a
	data.vertex_bytes=data.v.to_byte_array();data.attribute_bytes=attributes.to_byte_array()
	return data
func update(chunk: Dictionary,data: Dictionary):
	assert(data.v.size()<=chunk.capacity,"Wall cell exceeded its reserved geometry range")
	if data.v.size()>chunk.capacity:return
	if not data.v.is_empty():
		prepare(data)
		mesh.surface_update_vertex_region(0,chunk.offset*12,data.vertex_bytes)
		mesh.surface_update_attribute_region(0,chunk.offset*28,data.attribute_bytes)
		uploaded_bytes+=data.v.size()*40
	# Indices depend only on the active count and fixed offset, never on damage
	# colour/position. Preserve the existing index buffer when that count is equal.
	if data.v.size()!=chunk.data.v.size():
		var indices=PackedInt32Array();indices.resize(chunk.capacity)
		for i in range(data.v.size()):indices[i]=chunk.offset+i
		var bytes: PackedByteArray
		if index_stride==4:bytes=indices.to_byte_array()
		else:
			bytes.resize(indices.size()*2)
			for i in range(indices.size()):bytes.encode_u16(i*2,indices[i])
		RenderingServer.mesh_surface_update_index_region(mesh.get_rid(),0,chunk.offset*index_stride,bytes)
		uploaded_bytes+=bytes.size()
	update_count+=1;chunk.data=data
