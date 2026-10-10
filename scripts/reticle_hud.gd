extends Control
## Mouse-locked marks. Angular accuracy changes size, never position.
var center=Vector2.ZERO
var family="rifle"
var radius=4.0
var ink=Color("f6edcf")
var hit_time=0.0
var hit_fatal=false
var last_family=""
var paint
var shape_mesh: ArrayMesh

func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	z_index=-2
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func radius_for(kind: String,spread_angle: float) -> float:
	var angle=maxf(0,spread_angle)
	# Fixed UI units, independent of target distance, cover depth or camera zoom.
	# This expresses accuracy, rather than an exact projected footprint on a wall.
	match kind:
		"shotgun":return clampf(8.0+angle*120.0,12.0,32.0)
		"sniper":return clampf(3.0+angle*130.0,3.0,16.0)
		"launcher","launcher_low":return clampf(8.0+angle*80.0,8.0,22.0)
		"grenade","mortar":return 12.0
		"melee":return 0.0
		_:return clampf(3.0+angle*130.0,3.0,20.0)

static func segments(kind: String,gap: float) -> PackedVector2Array:
	var lines=PackedVector2Array()
	if kind=="shotgun":
		# One complete square: no perspective squeeze, pellet dots or extra ring.
		var corners=[Vector2(-gap,-gap),Vector2(gap,-gap),Vector2(gap,gap),Vector2(-gap,gap)]
		for i in range(4):lines.append(corners[i]);lines.append(corners[(i+1)%4])
	elif kind in ["launcher","launcher_low"]:
		for x in [-1,1]:
			for y in [-1,1]:
				var corner=Vector2(x,y)*gap
				lines.append(corner-Vector2(x,0)*6);lines.append(corner);lines.append(corner);lines.append(corner-Vector2(0,y)*6)
	elif kind not in ["melee","grenade","mortar"]:
		var length=9.0 if kind=="sniper" else 5.0 if kind=="pistol" else 6.0
		for axis in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			lines.append(axis*gap);lines.append(axis*(gap+length))
	return lines

func update_mark(at: Vector2,kind: String,spread_radius: float,color: Color,hit: float,delta: float):
	center=at;family=kind;ink=color;hit_time=hit
	# Expand promptly when accuracy worsens; settle without edge shimmer.
	if kind!=last_family or spread_radius>=radius:radius=spread_radius
	else:radius=lerpf(radius,spread_radius,1-exp(-delta*18))
	last_family=kind;queue_redraw()

func fine_line(a: Vector2,b: Vector2,color: Color,width: float=1.4):
	paint.line(center+a,center+b,Color(.06,.055,.075,color.a*.85),width+2.0,true)
	paint.line(center+a,center+b,color,width,true)

func _draw():
	paint=preload("res://scripts/canvas_mesh_batch.gd").new()
	var lines=segments(family,radius)
	for i in range(0,lines.size(),2):fine_line(lines[i],lines[i+1],ink,1.1 if family=="sniper" else 1.4)
	if family in ["grenade","mortar"]:
		paint.arc(center,radius,0,TAU,40,Color(.06,.055,.075,.85),3.4,true)
		paint.arc(center,radius,0,TAU,40,ink,1.4,true)
	paint.circle(center,2.5,Color(.06,.055,.075,.85))
	paint.circle(center,1.25,ink)
	if hit_time>0:
		for i in range(4):
			var axis=Vector2.from_angle(PI*.25+i*PI*.5)
			fine_line(axis*6,axis*(13 if hit_fatal else 11),Color("f3a398") if hit_fatal else Color("ead9b8"),2.0 if hit_fatal else 1.4)
	shape_mesh=paint.mesh();draw_mesh(shape_mesh,null)
