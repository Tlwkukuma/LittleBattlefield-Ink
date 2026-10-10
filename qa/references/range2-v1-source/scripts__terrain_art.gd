extends RefCounted
## Original ink assets: readable material families, with every wall detail owned by a live cell.
const Art=preload("res://scripts/ink_art.gd")
const Batch=preload("res://scripts/mesh_batch.gd")

static func pigment(material: String) -> Color:
	if "wood" in material:return Color("a39171")
	if "brick" in material:return Color("b28e7d")
	if "metal" in material:return Color("829193")
	if material in ["sandbag","sand","fabric"]:return Color("b7b18a")
	if material in ["foliage","grass","hedge"]:return Color("829476")
	if material=="stone":return Color("a2a297")
	return Color("b5b7ad")

static func mesh_from(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray) -> ArrayMesh:
	var mesh=ArrayMesh.new()
	if v.is_empty():return mesh
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=v;arrays[Mesh.ARRAY_NORMAL]=n;arrays[Mesh.ARRAY_COLOR]=c
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func box(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,at: Vector3,size: Vector3,color: Color,mask: Array=[true,true,true,true,true,true],face_colors: Dictionary={}):
	var h=size*.5
	var points=[Vector3(-h.x,-h.y,-h.z),Vector3(h.x,-h.y,-h.z),Vector3(h.x,-h.y,h.z),Vector3(-h.x,-h.y,h.z),Vector3(-h.x,h.y,-h.z),Vector3(h.x,h.y,-h.z),Vector3(h.x,h.y,h.z),Vector3(-h.x,h.y,h.z)]
	var faces=[[0,1,2,3],[4,7,6,5],[0,4,5,1],[3,2,6,7],[1,5,6,2],[0,3,7,4]]
	var normals=[Vector3.DOWN,Vector3.UP,Vector3.FORWARD,Vector3.BACK,Vector3.RIGHT,Vector3.LEFT]
	for f in range(6):
		if not mask[f]:continue
		var tint: Color=face_colors.get(f,color.darkened([.24,0,.15,.07,.13,.09][f]))
		for k in [0,1,2,0,2,3]:v.append(at+points[faces[f][k]]);n.append(normals[f]);c.append(tint)

static func stroke(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,a: Vector3,b: Vector3,width: float,color: Color):
	var d=b-a;var side=Vector3(-d.y,d.x,0).normalized()*width*.5
	var corners=[a-side,a+side,b+side,b-side]
	for k in [0,1,2,0,2,3]:v.append(corners[k]);n.append(Vector3(0,0,signf(a.z)));c.append(color)

static func bag(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,at: Vector3,size: Vector3,color: Color):
	var rings=[]
	for row in range(5):
		var t=float(row)/4;var radius=.70+sin(t*PI)*.30;var ring=[]
		for i in range(10):
			var angle=i*TAU/10
			ring.append(at+Vector3(signf(cos(angle))*pow(absf(cos(angle)),.42)*size.x*.5*radius,(t-.5)*size.y,signf(sin(angle))*pow(absf(sin(angle)),.42)*size.z*.5*radius))
		rings.append(ring)
	for row in range(4):
		for i in range(10):
			var next=(i+1)%10;var corners=[rings[row][i],rings[row][next],rings[row+1][next],rings[row+1][i]]
			var normal=(corners[1]-corners[0]).cross(corners[2]-corners[0]).normalized()
			for k in [0,1,2,0,2,3]:v.append(corners[k]);n.append(normal);c.append(color.darkened((1-maxf(0,normal.y))*.15))
	for row in [0,4]:
		for i in range(1,9):
			for k in [0,i,i+1]:v.append(rings[row][k]);n.append(Vector3.UP if row==4 else Vector3.DOWN);c.append(color)

static func wall_mesh(o: Dictionary,cut_height: float=INF) -> ArrayMesh:
	var data=wall_geometry(o,cut_height)
	return mesh_from(data.v,data.n,data.c)

static func wall_geometry(o: Dictionary,cut_height: float=INF,only_cell: int=-1) -> Dictionary:
	var v=PackedVector3Array();var n=PackedVector3Array();var c=PackedColorArray()
	if o.get("metal_fence",false):
		for part in o.solid_parts:
			if only_cell>=0 and part.cell!=only_cell:continue
			if o.hp[part.cell]<=0:continue
			var bottom: float=part.at.y-part.size.y*.5;var top=minf(part.at.y+part.size.y*.5,cut_height)
			if top<=bottom:continue
			box(v,n,c,Vector3(part.at.x,(bottom+top)*.5,part.at.z),Vector3(part.size.x,top-bottom,part.size.z),part.color)
		return {"v":v,"n":n,"c":c}
	var base=pigment(o.material);var ink=Color("585d57")
	var wooden="wood" in str(o.material);var metal="metal" in str(o.material)
	var masonry=not wooden and not metal and o.kind!="sandbag"
	var brick=o.component_id in ["wall.brick","wall.ruin"] or o.material=="brick"
	var stone=o.component_id=="wall.stone" or o.material=="stone"
	# A retained-wall update requests one cell. Do not scan the entire wall to
	# rediscover its row/column for every changed cell in a collapse.
	var first_row=int(only_cell/int(o.columns)) if only_cell>=0 else 0
	var last_row=first_row+1 if only_cell>=0 else int(o.rows)
	var first_col=only_cell%int(o.columns) if only_cell>=0 else 0
	var last_col=first_col+1 if only_cell>=0 else int(o.columns)
	for row in range(first_row,last_row):
		var bottom=row*o.cell_height
		if bottom>=cut_height:continue
		for col in range(first_col,last_col):
			var index=row*o.columns+col;var hp: float=o.hp[index]
			if hp<=0:continue
			var cell_h=minf(o.cell_height,cut_height-bottom);var w: float=o.cell_width
			var at=Vector3(-o.size.x*.5+(col+.5)*w,bottom+cell_h*.5,0)
			var mask=[row==0 or o.hp[index-o.columns]<=0,row==o.rows-1 or bottom+o.cell_height>=cut_height or o.hp[index+o.columns]<=0,true,true,col==o.columns-1 or o.hp[index+1]<=0,col==0 or o.hp[index-1]<=0]
			var damage=clampf(1-hp/o.max_hp,0,1)
			var tint=base.darkened(float(posmod(col*7+row*11,5))*.012+damage*.16)
			var cell_at=at;var cell_w=w
			var jamb_width=minf(.18,w*.45)
			var jamb_left=jamb_width if col==0 and -1 in o.get("door_jambs",[]) else 0.0
			var jamb_right=jamb_width if col==o.columns-1 and 1 in o.get("door_jambs",[]) else 0.0
			var body_mask=mask.duplicate();var face_colors={}
			# Colour the actual section face, rather than laying another box on top of it.
			if o.get("house_role","")=="wall" and bottom+o.cell_height>=cut_height:face_colors[1]=Color("656c62")
			if jamb_left>0:body_mask[5]=false
			if jamb_right>0:body_mask[4]=false
			w-=jamb_left+jamb_right;at.x+=(jamb_left-jamb_right)*.5
			if o.kind=="sandbag":bag(v,n,c,at,Vector3(w*.99,cell_h*.96,o.size.y),tint)
			else:box(v,n,c,at,Vector3(w,cell_h,o.size.y),tint,body_mask,face_colors)
			for edge in [-1,1]:
				var width=jamb_left if edge<0 else jamb_right
				if width<=0:continue
				var jamb_mask=mask.duplicate();jamb_mask[4 if edge<0 else 5]=false
				var x=cell_at.x+edge*(cell_w-width)*.5
				# Partition the owning live cell into brick and stone: identical physical
				# extent, no overlapping end/top faces, no internal faces at their join.
				box(v,n,c,Vector3(x,at.y,0),Vector3(width,cell_h,o.size.y),Color("d9d0b9").darkened(damage*.16),jamb_mask)
			for side in [-1,1]:
				var z=side*(o.size.y*.5+.006)
				if brick:
					for course in range(2):
						var y=bottom+course*o.cell_height*.5
						if y>=bottom+cell_h:continue
						stroke(v,n,c,Vector3(at.x-w*.5,y+.01,z),Vector3(at.x+w*.5,y+.01,z),.016,base.darkened(.26))
						var joint=at.x+(.14 if (row*2+course)%2==0 else -.12)*w
						stroke(v,n,c,Vector3(joint,y,z),Vector3(joint,minf(y+o.cell_height*.5,bottom+cell_h),z),.012,base.darkened(.24))
				elif stone:
					# Irregular fieldstone faces stay inside their owning live wall cell.
					# Mortar and broken sections therefore vanish with the same HP cell.
					for course in range(2):
						var y0=bottom+course*o.cell_height*.5+.014;var y1=minf(bottom+cell_h-.014,bottom+(course+1)*o.cell_height*.5-.014)
						if y1<=y0:continue
						var split=at.x+w*(.12 if (row+col+course)%2==0 else -.18)
						for edges in [[at.x-w*.5+.014,split-.012],[split+.012,at.x+w*.5-.014]]:
							var x0: float=edges[0];var x1: float=edges[1];var bevel=minf(.035,(x1-x0)*.16)
							var outline=[Vector2(x0+bevel,y0),Vector2(x1-bevel,y0+.006),Vector2(x1,y0+bevel),Vector2(x1-.007,y1-bevel),Vector2(x1-bevel,y1),Vector2(x0+bevel,y1-.005),Vector2(x0,y1-bevel),Vector2(x0+.004,y0+bevel)]
							var face_color=tint.lightened(.035+float(posmod(col*13+row*7+course*3,5))*.017)
							for j in range(1,outline.size()-1):
								for k in [0,j,j+1]:v.append(Vector3(outline[k].x,outline[k].y,z));n.append(Vector3(0,0,side));c.append(face_color)
				elif wooden:
					for offset in [-.34,0,.34]:
						var x=at.x+offset*w
						stroke(v,n,c,Vector3(x,bottom+.01,z),Vector3(x,bottom+cell_h-.01,z),.014,base.darkened(.35))
					if row%2==0:box(v,n,c,Vector3(at.x,bottom+cell_h*.48,z),Vector3(w,.065,.025),base.darkened(.18))
				elif metal:
					for offset in [-.34,0,.34]:box(v,n,c,Vector3(at.x+offset*w,at.y,z),Vector3(.026,cell_h,.026),base.lightened(.05))
				elif o.kind=="sandbag":
					stroke(v,n,c,Vector3(at.x-w*.34,at.y,z*.94),Vector3(at.x+w*.34,at.y+.015,z*.94),.011,base.darkened(.28))
				else:
					if col%3==0:stroke(v,n,c,Vector3(at.x-w*.49,bottom,z),Vector3(at.x-w*.49,bottom+cell_h,z),.018,base.darkened(.20))
					if row%2==0:
						box(v,n,c,Vector3(at.x-w*.30,at.y,z),Vector3(.032,.032,.008),base.darkened(.32))
				# Plinth, coping and window reveals never bridge an absent cell.
				if row==0 and masonry:
					var plinth=minf(.22,cell_h);box(v,n,c,Vector3(at.x,plinth*.5,z),Vector3(w,plinth,.025),base.darkened(.23))
				if row==o.rows-1 and bottom+cell_h>=o.height-.01:
					var coping=minf(.09,cell_h);box(v,n,c,Vector3(at.x,o.height-coping*.5,z),Vector3(w,coping,.035),base.lightened(.09))
				if o.get("windows",false):
					if row+1<o.rows and o.get("opening_cells",{}).has(index+o.columns) and cell_h==o.cell_height:box(v,n,c,Vector3(at.x,bottom+cell_h-.04,z),Vector3(w,.08,.035),Color("d1cbba"))
					if row>0 and o.get("opening_cells",{}).has(index-o.columns):box(v,n,c,Vector3(at.x,bottom+.04,z),Vector3(w,.08,.025),Color("d1cbba"))
				# Damage is proportional to real HP and bounded inside its surviving cell.
				if damage>.06:
					var center=Vector3(at.x+(float(posmod(index*7,5))-.2*5)*w*.065,at.y,z+side*.003)
					var count=2 if damage<.45 else 4
					for crack in range(count):
						var angle=float(crack)*TAU/count+float(index)*.7
						var tip=center+Vector3(cos(angle)*w*.32,sin(angle)*cell_h*.37,0)
						var knee=center.lerp(tip,.48)+Vector3(.025,-.018,0)
						stroke(v,n,c,center,knee,.012+damage*.012,ink);stroke(v,n,c,knee,tip,.009+damage*.007,ink)
				for mark in o.get("impact_marks",{}).get(index,[]):
					if mark.y>=bottom+cell_h or int(mark.z)!=side:continue
					var dent=Vector3(mark.x,mark.y,z+side*.006)
					stroke(v,n,c,dent-Vector3(.0425,0,0),dent+Vector3(.0425,0,0),.075,base.darkened(.30))
					var center=dent+Vector3(0,0,side*.006)
					stroke(v,n,c,center-Vector3(.018,0,0),center+Vector3(.018,0,0),.032,ink)
			# Exposed break sections retain the full collision volume, with chipped aggregate ink.
			if masonry:
				for edge in [-1,1]:
					var neighbor=col+edge
					if neighbor<0 or neighbor>=o.columns or o.hp[row*o.columns+neighbor]>0:continue
					if o.get("opening_cells",{}).has(row*o.columns+neighbor):continue
					var x=cell_at.x+edge*cell_w*.5
					for chip in range(3):
						var y=bottom+cell_h*(.2+chip*.27);var z=o.size.y*(.18 if chip%2==0 else -.18)
						var corners=[Vector3(x+edge*.0045,y-.0275,z-.0375),Vector3(x+edge*.0045,y+.0275,z-.0375),Vector3(x+edge*.0045,y+.0275,z+.0375),Vector3(x+edge*.0045,y-.0275,z+.0375)]
						for k in [0,1,2,0,2,3]:v.append(corners[k]);n.append(Vector3(edge,0,0));c.append(base.darkened(.32))
	return {"v":v,"n":n,"c":c}

static func prop(root: Node3D,o: Dictionary):
	var wood=pigment("wood");var metal=pigment("metal");var dark=Color("565e59")
	var w: float=o.size.x;var d: float=o.size.y;var h: float=o.height
	if o.has("nature_parts"):
		var node=Art.mesh_node(root,preload("res://scripts/nature_geometry.gd").mesh(o),Vector3.ZERO,Color.WHITE)
		node.material_override=Art.ink_material(Color.WHITE,true,.11)
		return
	if o.has("solid_parts"):
		for part in o.solid_parts:Art.box(root,part.at,part.size,part.color)
		if o.get("house_role","") in ["floor","roof"]:
			if o.get("floor_finish","")=="entry-stone":
				# Paved approach/landing ends at the physical doorway; no floating guidance icons.
				for x in range(1,ceili(w/.4)):
					Art.line(root,Vector3(-w*.5+x*.4,h+.002,-d*.5),Vector3(-w*.5+x*.4,h+.002,d*.5),Color("707d76"))
				for z in range(1,ceili(d/.4)):
					Art.line(root,Vector3(-w*.5,h+.002,-d*.5+z*.4),Vector3(w*.5,h+.002,-d*.5+z*.4),Color("707d76"))
				var west=o.get("entry_edge","")=="west"
				var inset=float(o.get("entry_start",0))*d
				var at=Vector3(-w*.5+.12 if west else 0,h-.008,inset*.5 if west else -d*.5+.12)
				Art.box(root,at,Vector3(.24 if west else w,.018,d-inset if west else .24),Color("d9d0b9"))
				return
			var spacing=.5 if o.get("floor_finish","")=="tile" else .24
			for i in range(1,maxi(2,int(w/spacing))):
				var x=-w*.5+i*spacing
				if x<w*.5:Art.line(root,Vector3(x,h+.002,-d*.49),Vector3(x,h+.002,d*.49),Color("a39e87") if o.house_role=="floor" else Color("a3b0a4"))
			if o.get("floor_finish","")=="tile":
				for i in range(1,int(d/.5)):Art.line(root,Vector3(-w*.49,h+.002,-d*.5+i*.5),Vector3(w*.49,h+.002,-d*.5+i*.5),Color("8c9b91"))
		elif o.component_id=="structure.stair" and not o.get("stair_landing",false):Art.box(root,Vector3(0,h-.012,float(o.get("stair_nose",1))*(d*.5-.024)),Vector3(w,.025,.048),Color("d1c9ad"))
		return
	if o.output=="tree":
		tree(root,o);return
	if o.component_id=="prop.barrel":
		Art.cylinder(root,Vector3(0,h*.5,0),d*.42,h,Color("8d9a89"))
		for y in [.10,.30,.72,.94]:Art.ring(root,Vector3(0,h*y,0),d*.43,dark,.018,20)
		Art.cylinder(root,Vector3(d*.17,h+.01,0),.035,.018,dark)
		Art.box(root,Vector3(0,h*.53,d*.426),Vector3(d*.30,h*.22,.012),Color("ccc4a4"))
		Art.box(root,Vector3(0,h*.54,d*.435),Vector3(d*.18,.022,.013),Color("796651"))
	elif o.component_id=="prop.crate":
		Art.box(root,Vector3(0,h*.5,0),Vector3(w,h,d),wood)
		for side in [-1,1]:
			for y in range(1,4):Art.line(root,Vector3(-w*.5,h*y/4,side*d*.505),Vector3(w*.5,h*y/4,side*d*.505),wood.darkened(.32))
			for x in [-.42,.42]:Art.box(root,Vector3(x*w,h*.5,side*d*.506),Vector3(w*.10,h,.035),wood.lightened(.08))
			Art.cloth_limb(root,Vector3(-w*.36,h*.10,side*d*.53),Vector3(w*.36,h*.90,side*d*.53),.026,.026,wood.darkened(.20))
		for x in [-.32,.32]:Art.box(root,Vector3(w*x,h+.013,0),Vector3(.05,.026,d),dark)
	elif o.component_id=="prop.container":
		var color=[Color("81958e"),Color("a28273"),Color("919cac")][posmod(hash(o.id),3)]
		Art.box(root,Vector3(0,h*.5,0),Vector3(w,h,d),color)
		for side in [-1,1]:
			for i in range(maxi(1,int(w/.28))):Art.box(root,Vector3(-w*.5+.13+i*.28,h*.5,side*d*.505),Vector3(.035,h*.89,.028),color.lightened(.09))
			for y in [.05,h-.05]:Art.box(root,Vector3(0,y,side*d*.51),Vector3(w,.07,.035),dark)
			for z in [-.23,.23]:
				Art.box(root,Vector3(side*w*.505,h*.5,z*d),Vector3(.030,h*.83,.027),Color("c0c3b8"))
			Art.box(root,Vector3(side*w*.508,h*.48,0),Vector3(.015,h*.92,.016),dark)
		for i in range(maxi(1,int(w/.35))):Art.box(root,Vector3(-w*.5+.15+i*.35,h+.015,0),Vector3(.04,.027,d*.96),color.lightened(.12))
	elif o.component_id.begins_with("obstacle.rock"):
		Art.loft(root,Vector3.ZERO,[Vector4(0,w*.5,d*.5,0),Vector4(h*.24,w*.48,d*.43,.03),Vector4(h*.72,w*.36,d*.38,-.05),Vector4(h,w*.22,d*.22,0)],pigment("stone"),8)
	elif o.component_id in ["prop.utility-pole","prop.road-light"]:
		Art.cylinder(root,Vector3(0,h*.5,0),.065,h,dark)
		Art.box(root,Vector3(.28,h-.12,0),Vector3(.68,.055,.07),metal)
		Art.box(root,Vector3(.58,h-.21,0),Vector3(.24,.12,.28),Color("d6ccb0"))
	elif o.component_id=="obstacle.concrete-barrier":
		# Keep the base footprint and its cover height legible.
		Art.box(root,Vector3(0,h*.5,0),Vector3(w,h,d),pigment("concrete"))
		for side in [-1,1]:
			Art.box(root,Vector3(0,h*.70,side*d*.505),Vector3(w,.14,.014),Color("c0ae78"))
			for i in range(maxi(1,int(w/.35))):Art.box(root,Vector3(-w*.5+.16+i*.35,h*.70,side*d*.515),Vector3(.12,.14,.014),dark)
	elif o.component_id in ["vegetation.shrub","wall.hedge"]:
		Art.loft(root,Vector3.ZERO,[Vector4(0,w*.42,d*.42,0),Vector4(h*.55,w*.50,d*.50,0),Vector4(h,w*.26,d*.28,0)],Color("899a7b"),9)
	else:
		Art.box(root,Vector3(0,h*.5,0),Vector3(w,h,d),pigment(o.material))
		for side in [-1,1]:Art.box(root,Vector3(0,h*.15,side*d*.505),Vector3(w,.05,.02),dark)

static func tree(root: Node3D,o: Dictionary):
	var h: float=o.height;var rng=RandomNumberGenerator.new();rng.seed=hash(o.id)
	Art.cylinder(root,Vector3(0,h*.35,0),.175,h*.70,Color("807765"))
	if "conifer" in str(o.component_id):
		for i in range(3):
			var radius=h*(.32-i*.065)
			Art.loft(root,Vector3(0,h*(.26+i*.20),0),[Vector4(0,radius,radius,0),Vector4(h*.35,.035,.035,0)],[Color("7c9275"),Color("8fa381"),Color("a2b38d")][i],9)
			if "snow" in str(o.get("surface","")):
				Art.loft(root,Vector3(0,h*(.26+i*.20)+.10,0),[Vector4(0,radius*.91,radius*.91,0),Vector4(h*.33,.035,.035,0)],Color("dee3d9"),9)
	else:
		var small=o.component_id=="tree.broadleaf-small";var radius=maxf(.45,float(o.get("crown_radius",h*.42)))
		var count=3 if small else 5
		for i in range(count):
			var angle=i*TAU/count+rng.randf()*.23;var r=radius*.32
			var at=Vector3(cos(angle)*r,h*(.48+rng.randf()*.06),sin(angle)*r)
			Art.cloth_limb(root,Vector3(0,h*.42,0),at+Vector3(0,h*.08,0),.055,.028,Color("807765"))
			Art.loft(root,at,[Vector4(0,radius*.47,radius*.46,0),Vector4(h*.19,radius*.68,radius*.64,0),Vector4(h*.42,radius*.24,radius*.25,0)],Color("9aa986") if small else Color("899c78").darkened(i*.016),9)

static func object(parent: Node3D,o: Dictionary) -> Dictionary:
	var root=Node3D.new();parent.add_child(root);root.position=Vector3(o.position.x,o.elevation,o.position.y);root.rotation.y=-o.angle
	var mesh: MeshInstance3D
	if o.component_id.begins_with("wall."):
		mesh=Art.mesh_node(root,wall_mesh(o),Vector3.ZERO,Color.WHITE);mesh.material_override=Art.ink_material(Color.WHITE,true,.11)
	elif o.output in ["water","ground","decal"]:
		pass # The ground pass owns the surface; keep its gameplay data without a raised solid box.
	else:
		prop(root,o);Batch.collapse(root)
	var materials=[]
	for child in root.get_children():
		if child is MeshInstance3D and child.material_override is ShaderMaterial:
			# HouseVisibility mutates opacity per object. Do not mutate Art's shared materials:
			# hiding an upper brick wall used to erase every brick wall, including outdoors.
			if o.has("house_role"):child.material_override=child.material_override.duplicate()
			materials.append(child.material_override)
	return {"root":root,"mesh":mesh,"revision":o.revision,"materials":materials}
