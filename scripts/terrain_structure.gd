extends RefCounted
## Architectural voids and damage use the same cells as shots, support and movement.

static func prepare(o: Dictionary) -> void:
	o.opening_cells={};o.impact_marks={}
	if o.get("windows",false) and not o.whole and o.height>=2.4 and o.size.x>=4.0:
		var count=maxi(1,int(o.size.x/3.0))
		var span=maxi(1,int(round(1.05/o.cell_width)))
		for window in range(count):
			var center=(window+.5)*o.columns/count
			var start=clampi(int(floor(center-span*.5)),1,o.columns-1-span)
			for col in range(start,start+span):
				for row in range(1,o.rows-1):
					var bottom=row*o.cell_height;var top=(row+1)*o.cell_height
					if bottom>=.85 and top<=2.15:
						var index=row*o.columns+col
						o.hp[index]=0.0;o.opening_cells[index]=true
	o.initial_solid_count=o.hp.filter(func(h):return h>0).size()

static func mark_impact(o: Dictionary,col: int,row: int,local: Vector2,height: float) -> bool:
	if o.whole or o.get("metal_fence",false):return false
	var index=row*o.columns+col
	if not o.impact_marks.has(index):o.impact_marks[index]=[]
	var marks: Array=o.impact_marks[index]
	if marks.size()>=3:return false
	var left=-o.size.x*.5+col*o.cell_width;var bottom=row*o.cell_height
	var mark=Vector3(clampf(local.x,left+.05,left+o.cell_width-.05),clampf(height-o.elevation,bottom+.05,bottom+o.cell_height-.05),signf(local.y))
	for previous in marks:
		if previous.distance_squared_to(mark)<.0081:return false
	marks.append(mark);return true
