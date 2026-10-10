extends RefCounted
const Library=preload("res://scripts/nature_library.gd")
const BARK=Color("897e68")
const LEAF=Color("879b7d")
const STONE=Color("a6aaa1")

static func hull(parts: Array,vertices: Array,faces: Array,color: Color,solid: bool=true):
	parts.append({"vertices":vertices,"faces":faces,"color":color,"solid":solid})

static func rings(parts: Array,rows: Array,color: Color,solid: bool=true):
	var vertices=[];var faces=[];var count: int=rows[0].size()
	for row in rows:vertices.append_array(row)
	faces.append(range(count));faces.append(range((rows.size()-1)*count,rows.size()*count))
	for j in range(rows.size()-1):
		for i in range(count):faces.append([j*count+i,j*count+(i+1)%count,(j+1)*count+(i+1)%count,(j+1)*count+i])
	hull(parts,vertices,faces,color,solid)

static func loft(parts: Array,at: Vector3,levels: Array,rx: float,rz: float,color: Color,solid: bool=true,sides: int=8,lean: Vector2=Vector2.ZERO):
	var rows=[];var top: float=levels.back()[0]
	for level in levels:
		var row=[];var offset=lean*float(level[0])/maxf(.001,top)
		for i in range(sides):
			var angle=i*TAU/sides
			row.append(at+Vector3(cos(angle)*rx*float(level[1])+offset.x,float(level[0]),sin(angle)*rz*float(level[1])+offset.y))
		rows.append(row)
	rings(parts,rows,color,solid)

static func branch(parts: Array,a: Vector3,b: Vector3,r0: float,r1: float,color: Color=BARK,solid: bool=true):
	var axis=(b-a).normalized();var side=axis.cross(Vector3.UP if absf(axis.y)<.9 else Vector3.RIGHT).normalized();var other=axis.cross(side);var rows=[]
	for end in [0,1]:
		var row=[]
		for i in range(7):row.append((a if end==0 else b)+(side*cos(TAU*i/7)+other*sin(TAU*i/7))*(r0 if end==0 else r1))
		rows.append(row)
	rings(parts,rows,color,solid)

static func crown(parts: Array,at: Vector3,wide: float,deep: float,height: float,color: Color=LEAF):
	loft(parts,at,[[0,.38],[height*.22,.9],[height*.57,1],[height*.84,.72],[height,.12]],wide,deep,color,false,9)

static func blade(parts: Array,a: Vector3,b: Vector3,width: float,color: Color):
	var direction=(b-a).normalized();var side=direction.cross(Vector3.UP).normalized()*width
	var middle=a.lerp(b,.43);var upper=[a,middle+side,b,middle-side];var lower=[]
	for p in upper:lower.append(p-Vector3.UP*.035)
	rings(parts,[upper,lower],color,false)

static func rock(parts: Array,at: Vector3,size: Vector3,color: Color=STONE,sides: int=7,lean: Vector2=Vector2.ZERO):
	loft(parts,at,[[0,.76],[size.y*.22,1],[size.y*.72,.83],[size.y,.37]],size.x*.5,size.z*.5,color,true,sides,lean)

static func parts(component: String,seed_value: int,snow: bool=false) -> Array:
	var spec: Array=Library.SPECS[component];var h: float=spec[1];var w: float=spec[2].x;var d: float=spec[2].y;var form: String=spec[3];var result=[]
	var rng=RandomNumberGenerator.new();rng.seed=seed_value;var spin=rng.randf_range(-.20,.20)
	match form:
		"oak","young":
			var trunk=.29 if form=="oak" else .12
			branch(result,Vector3.ZERO,Vector3(.08,h*.58,0),trunk,trunk*.58)
			for i in range(5):
				var angle=i*TAU/5+spin;var reach=Vector3(cos(angle),0,sin(angle))
				branch(result,reach*.65,Vector3(0,.20,0),trunk*.30,trunk*.85)
				var end=reach*w*.23+Vector3.UP*h*(.66+(i%2)*.035)
				branch(result,Vector3(0,h*.38,0),end,trunk*.55,.055)
				crown(result,end-Vector3.UP*h*.15,w*.265,d*.265,h*.43,LEAF.lightened((i%3)*.025))
		"birch":
			for i in range(2):
				var start=Vector3((i-.5)*.50,0,(i-.5)*.18);var end=start+Vector3((i-.5)*.55,h*(.83+i*.06),.12)
				branch(result,start,end,.13,.055,Color("d1d0bd"))
				for j in range(1,9):
					var t=j/11.0;var point=start.lerp(end,t)
					branch(result,point,point+Vector3.UP*.045,lerpf(.135,.060,t),lerpf(.135,.060,t),Color("686f65"),false)
				for j in range(3):
					var p=end+Vector3((j-1)*.55,-h*.36+j*.35,(j%2)*.25)
					branch(result,start.lerp(end,.48),p,.055,.025)
					crown(result,p-Vector3.UP*.3,w*.25,d*.26,h*.31,Color("a2ad81").darkened(j*.025))
		"poplar":
			branch(result,Vector3.ZERO,Vector3(0,h*.93,0),.21,.045,Color("a7a897"))
			for i in range(4):crown(result,Vector3((i%2-.5)*.20,h*(.30+i*.115),0),w*(.42-i*.06),d*(.42-i*.06),h*.355,Color("8f9e78").lightened(i*.025))
		"fir","snow-fir":
			branch(result,Vector3.ZERO,Vector3(0,h*.98,0),.23,.03)
			for i in range(5):
				var y=h*(.23+i*.14);var radius=w*(.47-i*.085);var tall=h*.21
				loft(result,Vector3(0,y,0),[[0,1],[tall,.015]],radius,radius*d/w,Color("718b78").lightened(i*.022),false,9)
				if i<3:
					for j in range(4):
						var a=j*TAU/4+spin;branch(result,Vector3(0,y+.16,0),Vector3(cos(a)*radius*.7,y+.05,sin(a)*radius*.7),.07,.02)
				if snow or form=="snow-fir":loft(result,Vector3(0,y+.07,0),[[0,.91],[tall-.035,.014]],radius,radius*d/w,Color("e1e6df"),false,9)
		"dead":
			var mid=Vector3(-.22,h*.46,.08);var top=Vector3(.22,h*.96,-.1)
			branch(result,Vector3.ZERO,mid,.26,.19);branch(result,mid,top,.19,.065)
			for i in range(5):
				var a=i*2.3;var start=Vector3(0,h*(.35+i*.10),0);var end=start+Vector3(cos(a)*w*.36,h*.12,sin(a)*d*.36)
				branch(result,start,end,.105,.04);branch(result,end,end+Vector3(cos(a+.5)*.3,h*.14,sin(a+.5)*.3),.04,.018)
		"acacia":
			branch(result,Vector3.ZERO,Vector3(.18,h*.50,0),.24,.15)
			for i in range(5):
				var a=i*TAU/5+spin;var p=Vector3(cos(a)*w*.23,h*.71,sin(a)*d*.23)
				branch(result,Vector3(.18,h*.45,0),p,.13,.04)
				crown(result,p,w*.27,d*.27,h*.26,Color("919975").darkened(i*.015))
		"palm":
			var last=Vector3.ZERO
			for i in range(6):
				var t=(i+1)/6.0;var p=Vector3(sin(t*PI*.65)*.6,h*.80*t,0)
				branch(result,last,p,.22-i*.015,.22-(i+1)*.015,Color("a39272"));last=p
			for i in range(10):
				var a=i*TAU/10+spin;var dir=Vector3(cos(a),0,sin(a));var mid=last+dir*w*.22+Vector3.UP*h*.18;var end=last+dir*w*.47-Vector3.UP*h*.025
				blade(result,last,mid,.25,Color("8e9d75"));blade(result,mid,end,.20,Color("9cac7f"));branch(result,last,mid,.025,.008,BARK,false)
		"log":
			branch(result,Vector3(-w*.48,.32,0),Vector3(w*.48,.35,.05),.33,.26)
			branch(result,Vector3(-w*.485,.32,0),Vector3(-w*.49,.32,0),.295,.295,Color("c8b698"),false)
			branch(result,Vector3(.1,.38,0),Vector3(.7,h,.4),.12,.07)
		"stump":
			loft(result,Vector3.ZERO,[[0,1],[h*.78,.70],[h,.60]],.46,.40,BARK,true,8)
			loft(result,Vector3(0,h+.002,0),[[0,1],[.012,1]],.255,.225,Color("c3af8b"),false,8)
			for i in range(5):
				var a=i*TAU/5;branch(result,Vector3(cos(a)*w*.45,.08,sin(a)*d*.45),Vector3(0,h*.37,0),.085,.18)
		"granite":
			rock(result,Vector3(-.3,0,0),Vector3(w*.82,h,d*.9),STONE,9,Vector2(.15,-.08))
			rock(result,Vector3(w*.29,0,.10),Vector3(w*.42,h*.67,d*.62),STONE.darkened(.08),7)
		"low":loft(result,Vector3.ZERO,[[0,.8],[h*.38,1],[h,.68]],w*.5,d*.5,STONE,true,8)
		"slate":
			for i in range(4):
				loft(result,Vector3((i-1.5)*w*.20,0,(i%2-.5)*d*.33),[[0,1],[h*(.60+(i%3)*.18),.35]],w*.16,d*.25,Color("838e92").lightened(i*.025),true,5,Vector2(.32,.13))
		"sandstone","mesa":
			for i in range(4):
				var size=1.0-i*.16 if form=="mesa" else [.80,1.0,.82,.64][i]
				loft(result,Vector3(.055*i,h*i/4,0),[[0,size],[h*.25,size*.94]],w*.5,d*.5,Color("ad8268").lightened(i*.035) if form=="mesa" else Color("c0ac86").lightened((i%2)*.07),true,8)
		"arch":
			for side in [-1,1]:loft(result,Vector3(side*w*.35,0,0),[[0,1],[h*.76,.92]],w*.15,d*.5,Color("baa57e"),true,7,Vector2(-side*.12,0))
			loft(result,Vector3(0,h*.73,0),[[0,.93],[h*.15,1],[h*.27,.80]],w*.5,d*.46,Color("c4b18a"),true,8)
		"basalt":
			for i in range(6):
				var a=i*TAU/6;var tall=h*(.65+(i%3)*.175)
				loft(result,Vector3(cos(a)*w*.26,0,sin(a)*d*.24),[[0,1],[tall,1]],w*.18,d*.20,Color("7d8888").lightened(i*.018),true,6)
		"scree":
			for i in range(9):
				var a=i*2.4;var r=.2+.65*(i%3)/2.0
				rock(result,Vector3(cos(a)*w*.4*r,0,sin(a)*d*.4*r),Vector3(.48+(i%3)*.21,h*(.5+(i%3)*.25),.40+(i%2)*.25),STONE.darkened((i%3)*.035),6)
	if snow and component.begins_with("rock.") and form in ["granite","low"]:
		loft(result,Vector3(-.3 if form=="granite" else 0,h*.72+.025,0),[[0,.87],[h*.28+.035,.42]],w*.41,d*.44,Color("dee5dd"),true,8)
	return result
