extends RefCounted
const Terrain=preload("res://scripts/terrain_art.gd")
static func triangle_key(data: Dictionary,i: int) -> String:
	return str(data.v[i],data.v[i+1],data.v[i+2],data.n[i],data.c[i])
static func compare(game,object,check: Callable):
	var member: Dictionary=game.wall_batches.members[object.id]
	for index: int in range(object.hp.size()):
		var chunk: Dictionary=member.chunks[index];var selected: int=chunk.selected
		if object.hp[index]<=0 or not object.alive:
			check.call(selected==-1 and chunk.data.v.is_empty(),"destroyed cell has no submitted geometry")
			continue
		check.call(selected>=0,"surviving cell has a baked variant")
		if selected<0:continue
		var fixture=object.duplicate();fixture.hp=object.hp.duplicate();fixture.impact_marks={}
		fixture.hp[index]=object.max_hp*game.wall_batches.HEALTH[selected%3]
		var expected=Terrain.wall_geometry(fixture,member.cut,index)
		expected.v=member.pose*expected.v;expected.n=Transform3D(member.pose.basis,Vector3.ZERO)*expected.n
		var triangles={}
		for i: int in range(0,chunk.data.v.size(),3):triangles[triangle_key(chunk.data,i)]=true
		for i: int in range(0,expected.v.size(),3):check.call(triangles.has(triangle_key(expected,i)),"all original exposed faces/details exist in baked variant")
		var packed: PackedByteArray=chunk.data.indices
		var surface=game.wall_batches.sectors[member.sector].surface
		for i: int in range(chunk.capacity):
			var actual: int=packed.decode_u32(i*4) if surface.index_stride==4 else packed.decode_u16(i*2)
			check.call(actual==(chunk.data.offset+i if i<chunk.data.v.size() else 0),"indices select only this variant, remainder degenerate")
