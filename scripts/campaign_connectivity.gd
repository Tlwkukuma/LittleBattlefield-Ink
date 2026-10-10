extends RefCounted
## Cached graph components. No geometry query or A* per spawn candidate.
var labels: Dictionary={}
var ready=false
var ids=PackedInt64Array()
var queue=PackedInt64Array()
var cursor=0
var seed_cursor=0
var label=0
var building=false

func invalidate():ready=false;building=false;labels.clear()
func begin(graph: AStar2D):
	invalidate();ids=graph.get_point_ids();queue.clear();cursor=0;seed_cursor=0;label=0;building=true

func pump(graph: AStar2D,maximum: int=128,budget_usec: int=450) -> void:
	if not building:return
	var started=Time.get_ticks_usec();var count=0
	while count<maximum and Time.get_ticks_usec()-started<budget_usec:
		if cursor>=queue.size():
			queue.clear();cursor=0
			while seed_cursor<ids.size() and (labels.has(ids[seed_cursor]) or graph.is_point_disabled(ids[seed_cursor])):
				seed_cursor+=1
				if Time.get_ticks_usec()-started>=budget_usec:return
			if seed_cursor>=ids.size():ready=true;building=false;return
			label+=1;queue.append(ids[seed_cursor]);labels[ids[seed_cursor]]=label;seed_cursor+=1
		var id=queue[cursor];cursor+=1;count+=1
		for next in graph.get_point_connections(id):
			if not graph.is_point_disabled(next) and not labels.has(next):labels[next]=label;queue.append(next)

func connected(a: int,b: int) -> bool:
	return ready and a>=0 and b>=0 and labels.has(a) and labels.has(b) and int(labels[a])==int(labels[b])
