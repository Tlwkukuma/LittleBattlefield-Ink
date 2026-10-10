extends RefCounted
## Single-owner planar broad phase. Exact height/shape tests remain with callers.
## Flat nodes avoid recursion and per-query dictionaries for deduplication.
const CAPACITY=8
const MAX_DEPTH=6
const EPS=.00001
class Branch:
	extends RefCounted
	var bounds: Rect2
	var core: Rect2
	var depth: int
	var items: Array[int]=[]
	var children: Array[int]=[]
class Entry:
	extends RefCounted
	var id: int
	var bounds: Rect2
	var value: Dictionary
	var node: int
	var slot: int
var nodes: Array[Branch]=[]
var entries: Dictionary[int,Entry]={}
var looseness=1.0
var queries=0
var visits=0
var tests=0
var reinserts=0

func reset(bounds: Rect2,loose: float=1.0):
	nodes.clear();entries.clear();queries=0;visits=0;tests=0;reinserts=0
	looseness=maxf(1.0,loose)
	add_node(bounds.abs().grow(.01),0)

func add_node(bounds: Rect2,depth: int) -> int:
	var id=nodes.size()
	var branch=Branch.new();branch.bounds=bounds.grow((looseness-1.0)*maxf(bounds.size.x,bounds.size.y)*.5);branch.core=bounds;branch.depth=depth
	nodes.append(branch)
	return id

static func overlaps(a: Rect2,b: Rect2) -> bool:
	return a.position.x<=b.end.x and a.end.x>=b.position.x and a.position.y<=b.end.y and a.end.y>=b.position.y

static func contains(outer: Rect2,inner: Rect2) -> bool:
	return outer.position.x<=inner.position.x and outer.position.y<=inner.position.y and outer.end.x>=inner.end.x and outer.end.y>=inner.end.y

func update(id: int,bounds: Rect2,value: Dictionary,margin: float=0.0):
	var actual=bounds.abs().grow(EPS)
	if entries.has(id) and contains(entries[id].bounds,actual):entries[id].value=value;return
	var expanded=actual.grow(margin)
	if not contains(nodes[0].bounds,expanded):
		# Rare setup/teleport expansion, never silently lose an out-of-root actor.
		var extent: Rect2=nodes[0].core.merge(expanded).grow(1.0)
		var previous=entries.values();reset(extent,looseness)
		for entry in previous:put(entry.id,entry.bounds,entry.value)
	remove(id);put(id,expanded,value);reinserts+=1

func put(id: int,bounds: Rect2,value: Dictionary):
	var entry=Entry.new();entry.id=id;entry.bounds=bounds;entry.value=value;entries[id]=entry
	insert(id,0)

func remove(id: int):
	if not entries.has(id):return
	var entry: Entry=entries[id];var items: Array[int]=nodes[entry.node].items
	var last: int=items.back();items[entry.slot]=last;items.pop_back()
	if last!=id:entries[last].slot=entry.slot
	entries.erase(id)

func child_for(node: Branch,bounds: Rect2) -> int:
	var center: Vector2=node.core.get_center();var at=bounds.get_center()
	var quadrant=(1 if at.x>=center.x else 0)+(2 if at.y>=center.y else 0)
	var child: int=node.children[quadrant]
	return child if contains(nodes[child].bounds,bounds) else -1

func insert(id: int,node_id: int):
	while true:
		var node: Branch=nodes[node_id]
		if not node.children.is_empty():
			var child=child_for(node,entries[id].bounds)
			if child>=0:node_id=child;continue
		entries[id].node=node_id;entries[id].slot=node.items.size();node.items.append(id)
		if node.children.is_empty() and node.items.size()>CAPACITY and int(node.depth)<MAX_DEPTH:split(node_id)
		return

func split(node_id: int):
	var node: Branch=nodes[node_id];var half: Vector2=node.core.size*.5
	for quadrant in range(4):node.children.append(add_node(Rect2(node.core.position+half*Vector2(quadrant%2,quadrant>>1),half),node.depth+1))
	var former: Array[int]=node.items.duplicate();node.items.clear()
	for id in former:insert(id,node_id)

static func segment_intersects(rect: Rect2,a: Vector2,b: Vector2,pad: float) -> bool:
	var low=rect.position-Vector2.ONE*pad;var high=rect.end+Vector2.ONE*pad
	var delta=b-a;var enter=0.0;var exit=1.0
	if absf(delta.x)<.00000001:
		if a.x<low.x or a.x>high.x:return false
	else:
		var t0=(low.x-a.x)/delta.x;var t1=(high.x-a.x)/delta.x
		enter=maxf(enter,minf(t0,t1));exit=minf(exit,maxf(t0,t1))
		if enter>exit:return false
	if absf(delta.y)<.00000001:
		return a.y>=low.y and a.y<=high.y
	var t0=(low.y-a.y)/delta.y;var t1=(high.y-a.y)/delta.y
	return maxf(enter,minf(t0,t1))<=minf(exit,maxf(t0,t1))

func query(bounds: Rect2,stable: bool=false,measured: bool=false) -> Array:
	var ids: Array[int]=[];var stack: Array[int]=[0];var visited=0;var tested=0
	while not stack.is_empty():
		var node: Branch=nodes[stack.pop_back()];visited+=1
		if not node.bounds.intersects(bounds,true):continue
		for id: int in node.items:
			tested+=1
			if entries[id].bounds.intersects(bounds,true):ids.append(id)
		stack.append_array(node.children)
	if measured:queries+=1;visits+=visited;tests+=tested
	if stable:ids.sort()
	var result=[]
	for id in ids:result.append(entries[id].value)
	return result

static func segment_overlap(rect: Rect2,a: Vector2,inv: Vector2,pad: float,parallel_x: bool,parallel_y: bool) -> bool:
	var low=rect.position-Vector2.ONE*pad;var high=rect.end+Vector2.ONE*pad
	var enter=0.0;var exit=1.0
	if parallel_x:
		if a.x<low.x or a.x>high.x:return false
	else:
		var t0=(low.x-a.x)*inv.x;var t1=(high.x-a.x)*inv.x
		enter=maxf(0,minf(t0,t1));exit=minf(1,maxf(t0,t1))
		if enter>exit:return false
	if parallel_y:return a.y>=low.y and a.y<=high.y
	var t0=(low.y-a.y)*inv.y;var t1=(high.y-a.y)*inv.y
	return maxf(enter,minf(t0,t1))<=minf(exit,maxf(t0,t1))

func segment(a: Vector2,b: Vector2,pad: float,stable: bool=true,measured: bool=false) -> Array:
	# Short segments use native Rect2 pruning; the same exact slab test filters
	# entries. Inverse direction is computed once, rather than twice per branch.
	var delta=b-a;var parallel_x=absf(delta.x)<.00000001;var parallel_y=absf(delta.y)<.00000001
	var inv=Vector2(0 if parallel_x else 1.0/delta.x,0 if parallel_y else 1.0/delta.y)
	var broad=Rect2(a,delta).abs().grow(pad+EPS);var short=delta.length_squared()<16
	var ids: Array[int]=[];var stack: Array[int]=[0];var visited=0;var tested=0
	while not stack.is_empty():
		var node: Branch=nodes[stack.pop_back()];visited+=1
		if not node.bounds.intersects(broad,true):continue
		if not short and not segment_overlap(node.bounds,a,inv,pad,parallel_x,parallel_y):continue
		for id: int in node.items:
			tested+=1
			if segment_overlap(entries[id].bounds,a,inv,pad,parallel_x,parallel_y):ids.append(id)
		stack.append_array(node.children)
	if measured:queries+=1;visits+=visited;tests+=tested
	if stable:ids.sort()
	var result=[]
	for id in ids:result.append(entries[id].value)
	return result

func diagnostics() -> Dictionary:
	return {"nodes":nodes.size(),"entries":entries.size(),"queries":queries,"node_visits":visits,"bounds_tests":tests,"reinserts":reinserts}
