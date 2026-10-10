extends RefCounted
## Persistent loose quadtree; real movement/seat/network updates keep it current.
## Keep original unit order so equal-distance hits retain their original winner.
const Quad=preload("res://scripts/collision_quadtree.gd")
const BODY_HALF=1.6
const CELL=4.0
const COMMON_RADIUS=.6
const EMPTY_SPAN=Vector4i(0,-1,0,-1)
var active=false
var tree=Quad.new()
var grid: Dictionary={}
var marks=PackedInt32Array()
var query_serial=0
var entries: Array=[]
var by_id: Dictionary={}
var queries=0
var candidates=0
var possible=0
var build_ms=0.0

func begin(units: Array,measured: bool=false):
	var started=Time.get_ticks_usec() if measured else 0
	active=true
	queries=0;candidates=0;possible=0
	var rebuild: bool=entries.size()!=units.size()
	if not rebuild:
		for i: int in range(units.size()):
			if not is_same(entries[i].unit,units[i]):rebuild=true;break
	if rebuild or tree.nodes.is_empty():
		var extent=Rect2(-Vector2.ONE*64,Vector2.ONE*128)
		for unit in units:extent=extent.merge(Rect2(unit.position-Vector2.ONE*3,Vector2.ONE*6))
		tree.reset(extent,2.0);entries.clear();by_id.clear();grid.clear();marks.resize(units.size());marks.fill(0);query_serial=0;rebuild=true
	for unit in units:
		if rebuild:
			var rank: int=entries.size()
			entries.append({"unit":unit,"span":EMPTY_SPAN})
			by_id[unit.id]=rank
		update(unit)
	build_ms=(Time.get_ticks_usec()-started)/1000.0 if measured else 0.0

func update(unit: Dictionary):
	if not by_id.has(unit.id) or tree.nodes.is_empty():return
	var rank: int=by_id[unit.id]
	var entry: Dictionary=entries[rank];var span=EMPTY_SPAN
	if unit.alive:
		var extent=BODY_HALF+COMMON_RADIUS+.0001
		span=Vector4i(floori((unit.position.x-extent)/CELL),floori((unit.position.x+extent)/CELL),floori((unit.position.y-extent)/CELL),floori((unit.position.y+extent)/CELL))
		tree.update(rank,Rect2(unit.position-Vector2.ONE*BODY_HALF,Vector2.ONE*BODY_HALF*2),unit,.25)
	else:tree.remove(rank)
	if span==entry.span:return
	var old: Vector4i=entry.span
	for x in range(old.x,old.y+1):
		for y in range(old.z,old.w+1):
			var cell=Vector2i(x,y);var occupants: Array=grid[cell];occupants.erase(rank)
			if occupants.is_empty():grid.erase(cell)
	entry.span=span
	for x in range(span.x,span.y+1):
		for y in range(span.z,span.w+1):
			var cell=Vector2i(x,y)
			if not grid.has(cell):grid[cell]=[]
			grid[cell].append(rank)

func short_segment(a: Vector2,b: Vector2) -> Array:
	# The tight existing grid wins for a few crossed cells. Generation stamps
	# remove duplicates without allocating a Dictionary for every bullet segment.
	query_serial+=1
	if query_serial>=2147483647:marks.fill(0);query_serial=1
	var ids: Array[int]=[];var delta=b-a
	var cell=Vector2i(floori(a.x/CELL),floori(a.y/CELL));var end=Vector2i(floori(b.x/CELL),floori(b.y/CELL))
	var sx=1 if delta.x>=0 else -1;var sy=1 if delta.y>=0 else -1
	var dx=CELL/absf(delta.x) if delta.x!=0.0 else INF;var dy=CELL/absf(delta.y) if delta.y!=0.0 else INF
	var tx=((cell.x+(1 if sx>0 else 0))*CELL-a.x)/delta.x if dx<INF else INF
	var ty=((cell.y+(1 if sy>0 else 0))*CELL-a.y)/delta.y if dy<INF else INF
	for _step in range(absi(end.x-cell.x)+absi(end.y-cell.y)+3):
		for rank: int in grid.get(cell,[]):
			if marks[rank]!=query_serial:marks[rank]=query_serial;ids.append(rank)
		if cell==end:break
		if tx<ty:cell.x+=sx;tx+=dx
		else:cell.y+=sy;ty+=dy
	ids.sort();var result: Array=[]
	for rank: int in ids:result.append(entries[rank].unit)
	return result

func query(a: Vector2,b: Vector2,radius: float,measured: bool=false) -> Array:
	var result=short_segment(a,b) if radius<=COMMON_RADIUS and a.distance_squared_to(b)<=576 else tree.segment(a,b,maxf(0,radius),true,measured)
	if measured:queries+=1;candidates+=result.size();possible+=entries.size()
	return result

func nearby(point: Vector2,radius: float) -> Array:
	return tree.query(Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2))

func diagnostics() -> Dictionary:
	return {"queries":queries,"candidates":candidates,"full_scan_candidates":possible,"build_ms":build_ms,"quadtree":tree.diagnostics()}
