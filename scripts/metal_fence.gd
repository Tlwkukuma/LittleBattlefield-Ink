extends RefCounted
## One cached welded-grid mesh; bars and live damage cells also own collision.
const Aim=preload("res://scripts/aim_geometry.gd")

static func prepare(o: Dictionary):
	if o.component_id!="wall.metal-fence":return
	o.metal_fence=true;o.ballistic=true;o.size.y=clampf(o.size.y*.25,.05,.12)
	o.solid_parts=[];o.fence_cells=[]
	for i in range(o.hp.size()):o.fence_cells.append([])
	var width=float(o.size.x);var height=float(o.height);var depth=float(o.size.y)
	var posts=maxi(1,ceili(width/1.6))
	for i in range(posts+1):
		var x=lerpf(-width*.5+.04,width*.5-.04,float(i)/posts)
		add_bar(o,Vector3(x,height*.5,0),Vector3(.075,height,depth),Color("627879"))
	for y in [.10,height-.08]:add_bar(o,Vector3(0,y,0),Vector3(width,.045,minf(.05,depth)),Color("728b8c"))
	var wires=maxi(1,ceili(width/.18))
	for i in range(1,wires):
		add_bar(o,Vector3(-width*.5+i*width/wires,height*.5,0),Vector3(.018,height-.16,.018),Color("a5b7b0"))
	var rows=maxi(1,ceili((height-.2)/.20))
	for i in range(1,rows):
		add_bar(o,Vector3(0,.1+i*(height-.2)/rows,.013),Vector3(width-.08,.014,.014),Color("8daba7"))

static func add_bar(o: Dictionary,at: Vector3,size: Vector3,color: Color):
	var low=at-size*.5;var high=at+size*.5
	var first_col=clampi(floori((low.x+o.size.x*.5)/o.cell_width),0,o.columns-1)
	var last_col=clampi(floori((high.x+o.size.x*.5)/o.cell_width),0,o.columns-1)
	var first_row=clampi(floori(low.y/o.cell_height),0,o.rows-1)
	var last_row=clampi(floori(high.y/o.cell_height),0,o.rows-1)
	for row in range(first_row,last_row+1):
		for col in range(first_col,last_col+1):
			var a=low.max(Vector3(-o.size.x*.5+col*o.cell_width,row*o.cell_height,-o.size.y*.5))
			var b=high.min(Vector3(-o.size.x*.5+(col+1)*o.cell_width,(row+1)*o.cell_height,o.size.y*.5))
			if b.x-a.x<.00001 or b.y-a.y<.00001:continue
			var cell=row*o.columns+col
			var part={"at":(a+b)*.5,"size":b-a,"color":color,"cell":cell}
			o.solid_parts.append(part);o.fence_cells[cell].append(part)

static func hit(o: Dictionary,origin: Vector3,direction: Vector3,limit: float,radius: float,with_normal: bool=false) -> Dictionary:
	var pad=Vector3.ONE*radius
	var span=Aim.box_span(origin,direction,Vector3(-o.size.x*.5,0,-o.size.y*.5)-pad,Vector3(o.size.x*.5,o.height,o.size.y*.5)+pad,limit)
	if span.x==INF:return {}
	var start=origin+direction*span.x;var end=origin+direction*span.y
	var low=start.min(end)-pad;var high=start.max(end)+pad;var result={}
	var first_col=clampi(floori((low.x+o.size.x*.5-.00001)/o.cell_width),0,o.columns-1)
	var last_col=clampi(floori((high.x+o.size.x*.5+.00001)/o.cell_width),0,o.columns-1)
	var first_row=clampi(floori((low.y-.00001)/o.cell_height),0,o.rows-1)
	var last_row=clampi(floori((high.y+.00001)/o.cell_height),0,o.rows-1)
	for row in range(first_row,last_row+1):
		for col in range(first_col,last_col+1):
			var cell=row*o.columns+col
			if o.hp[cell]<=0:continue
			for part in o.fence_cells[cell]:
				var a: Vector3=part.at-part.size*.5-pad;var b: Vector3=part.at+part.size*.5+pad
				var distance=Aim.box_hit(origin,direction,a,b,limit)
				if distance<=limit:
					limit=distance;result={"distance":distance,"col":col,"row":row}
					if with_normal:
						result.normal=Aim.box_normal(origin+direction*distance,a,b)
						result.exit_distance=Aim.box_span(origin,direction,a,b,INF).y
	return result
