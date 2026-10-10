extends RefCounted
## Immutable wall vertices. Combat only selects prepacked triangle indices.
var mesh=ArrayMesh.new()
var chunks: Array=[]
var vertex_count: int=0
var index_count: int=0
var uploaded_bytes: int=0
var update_count: int=0
var index_stride: int=4
var zero_bytes: Dictionary={}
func add(variants: Array,selected: int) -> Dictionary:
	var capacity: int=0
	for data in variants:
		data.offset=vertex_count;vertex_count+=data.v.size();capacity=maxi(capacity,data.v.size())
	var chunk={"offset":index_count,"capacity":capacity,"variants":variants,"selected":selected,"data":variants[selected] if selected>=0 else empty()}
	chunks.append(chunk);index_count+=capacity
	return chunk
static func empty() -> Dictionary:
	return {"v":PackedVector3Array(),"n":PackedVector3Array(),"c":PackedColorArray()}
func build():
	var vertices=PackedVector3Array();var normals=PackedVector3Array();var colors=PackedColorArray()
	var indices=PackedInt32Array();indices.resize(index_count)
	for chunk in chunks:
		for data in chunk.variants:
			vertices.append_array(data.v);normals.append_array(data.n);colors.append_array(data.c)
		if chunk.selected>=0:
			for i: int in range(chunk.data.v.size()):indices[chunk.offset+i]=chunk.data.offset+i
	if vertices.is_empty():vertices.append(Vector3.ZERO);normals.append(Vector3.UP);colors.append(Color.WHITE)
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	index_stride=RenderingServer.mesh_surface_get_format_index_stride(mesh.surface_get_format(0),vertices.size())
	for chunk in chunks:
		if not zero_bytes.has(chunk.capacity):
			var bytes=PackedByteArray();bytes.resize(chunk.capacity*index_stride);zero_bytes[chunk.capacity]=bytes
		for data in chunk.variants:
			var packed=PackedInt32Array();packed.resize(chunk.capacity)
			for i: int in range(data.v.size()):packed[i]=data.offset+i
			if index_stride==4:data.indices=packed.to_byte_array()
			else:
				var bytes=PackedByteArray();bytes.resize(chunk.capacity*2)
				for i: int in range(data.v.size()):bytes.encode_u16(i*2,packed[i])
				data.indices=bytes
func select(chunk: Dictionary,selected: int):
	if chunk.selected==selected:return
	var data: Dictionary=chunk.variants[selected] if selected>=0 else empty()
	var bytes: PackedByteArray=data.indices if selected>=0 else zero_bytes[chunk.capacity]
	if not bytes.is_empty():RenderingServer.mesh_surface_update_index_region(mesh.get_rid(),0,chunk.offset*index_stride,bytes)
	uploaded_bytes+=bytes.size();update_count+=1
	chunk.selected=selected;chunk.data=data
