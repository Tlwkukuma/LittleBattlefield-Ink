extends RefCounted
## Solid furniture parts are shared by mesh, bullets, body collision and support.
const SIZES={"sofa":Vector3(2.7,1.0,1.05),"table":Vector3(2.2,.80,1.15),"chair":Vector3(.56,1.02,.60),"desk":Vector3(1.7,.82,.8),"bed":Vector3(1.9,1.0,2.25),"wardrobe":Vector3(1.5,2.15,.65),"shelf":Vector3(1.3,1.9,.42),"counter":Vector3(2.8,.94,.7),"fridge":Vector3(.78,1.85,.76),"dresser":Vector3(1.25,.88,.58),"coffee-table":Vector3(1.2,.46,.7),"plant":Vector3(.5,.9,.5)}
const LABELS={"sofa":"沙发","table":"餐桌","chair":"木椅","desk":"书桌","bed":"双人床","wardrobe":"衣柜","shelf":"书架","counter":"餐厨台","fridge":"冰箱","dresser":"抽屉柜","coffee-table":"茶几","plant":"盆栽"}
const WOOD=Color("a59274")
const INK=Color("545a57")

static func register(catalog):
	for id in SIZES:
		var size: Vector3=SIZES[id]
		catalog.components["furniture."+id]={"id":"furniture."+id,"label":LABELS[id],"primitive":"area","material":"metal" if id=="fridge" else "wood","defaults":{"length":size.x*40,"thickness":size.z*40},"runtime":{"kind":"barrier","output":"furniture","collision":true,"blocksProjectiles":true,"damageable":true}}

static func default_height(id: String) -> float:return SIZES.get(id.trim_prefix("furniture."),Vector3.ONE).y

static func box(list: Array,at: Vector3,size: Vector3,color: Color):list.append({"at":at,"size":size,"color":color})

static func legs(list: Array,w: float,d: float,h: float):
	for x in [-1,1]:
		for z in [-1,1]:box(list,Vector3(x*(w*.5-.09),h*.5,z*(d*.5-.09)),Vector3(.085,h,.085),WOOD.darkened(.15))

static func parts(id: String,size: Vector2,height: float) -> Array:
	var name=id.trim_prefix("furniture.");var original: Vector3=SIZES.get(name,Vector3.ONE);var list=[]
	var w=original.x;var h=original.y;var d=original.z
	match name:
		"sofa":
			box(list,Vector3(0,.28,0),Vector3(w,.45,d),Color("829b98"))
			box(list,Vector3(0,.73,-d*.39),Vector3(w,.54,.25),Color("788f8c"))
			for x in [-1,1]:box(list,Vector3(x*(w*.5-.13),.56,0),Vector3(.25,.60,d),Color("788f8c"))
			for i in range(3):box(list,Vector3((i-1)*.72,.54,.08),Vector3(.69,.17,.72),Color("a2b3a5"))
		"table","desk","coffee-table":
			legs(list,w,d,h-.09);box(list,Vector3(0,h-.05,0),Vector3(w,.10,d),WOOD.lightened(.08))
			if name=="desk":
				box(list,Vector3(w*.31,.50,0),Vector3(.48,.48,d*.91),WOOD)
				for y in [.37,.55,.72]:box(list,Vector3(w*.31,y,d*.46),Vector3(.17,.025,.022),INK)
				box(list,Vector3(-.35,h+.028,0),Vector3(.44,.05,.30),Color("d7d3bd"))
		"chair":
			legs(list,w,d,.44);box(list,Vector3(0,.47,0),Vector3(w,.09,d),WOOD)
			for x in [-1,1]:box(list,Vector3(x*.23,.73,-.25),Vector3(.065,.56,.07),WOOD)
			box(list,Vector3(0,.91,-.25),Vector3(w,.23,.075),WOOD.lightened(.07))
		"bed":
			box(list,Vector3(0,.22,0),Vector3(w,.40,d),WOOD.darkened(.08))
			box(list,Vector3(0,.53,.03),Vector3(w-.09,.25,d-.14),Color("d7d4c4"))
			box(list,Vector3(0,.70,-d*.46),Vector3(w,.60,.14),WOOD)
			box(list,Vector3(0,.675,.34),Vector3(w-.08,.05,d*.61),Color("94a6ae"))
			for x in [-.45,.45]:box(list,Vector3(x,.72,-.65),Vector3(.67,.15,.39),Color("ebe6d3"))
		"wardrobe","dresser","fridge":
			var color=Color("bbc4b7") if name=="fridge" else WOOD
			box(list,Vector3(0,h*.5,0),Vector3(w,h,d),color)
			var rows=2 if name=="fridge" else 3 if name=="dresser" else 1
			for i in range(rows):
				box(list,Vector3(0,h*(i+1)/rows-.03,d*.5+.005),Vector3(w*.94,.017,.015),INK)
				box(list,Vector3(-w*.30,h*(i+.6)/rows,d*.5+.025),Vector3(.04,.14,.04),INK)
			if name=="wardrobe":box(list,Vector3(0,h*.5,d*.5+.006),Vector3(.018,h*.96,.016),INK)
		"shelf":
			for x in [-1,1]:box(list,Vector3(x*(w*.5-.04),h*.5,0),Vector3(.08,h,d),WOOD)
			box(list,Vector3(0,h*.5,-d*.46),Vector3(w,.99*h,.04),WOOD.darkened(.13))
			for row in range(5):
				var y=.10+row*.43;box(list,Vector3(0,y,0),Vector3(w,.065,d),WOOD)
				if row<4:
					for k in range(6):box(list,Vector3(-.49+k*.16,y+.16,.02),Vector3(.10,.24+(k%3)*.035,.24),[Color("879eaa"),Color("b8ab83"),Color("a48678")][(k+row)%3])
		"counter":
			box(list,Vector3(0,.44,0),Vector3(w,.88,d),Color("aaa98d"))
			box(list,Vector3(0,.92,0),Vector3(w+.04,.06,d+.04),Color("cbd0c2"))
			for x in [-.92,0,.92]:
				box(list,Vector3(x,.45,d*.51),Vector3(.025,.76,.018),INK)
				box(list,Vector3(x+.18,.71,d*.54),Vector3(.22,.025,.025),INK)
			box(list,Vector3(.74,.963,0),Vector3(.68,.015,.45),Color("788d90"))
			for z in [-.16,.16]:box(list,Vector3(-.76,.966,z),Vector3(.30,.018,.25),INK)
		"plant":
			box(list,Vector3(0,.18,0),Vector3(.36,.36,.36),Color("b49b83"))
			box(list,Vector3(0,.46,0),Vector3(.055,.52,.055),WOOD.darkened(.25))
			for i in range(5):
				var angle=i*TAU/5;box(list,Vector3(cos(angle)*.12,.57+(i%2)*.16,sin(angle)*.12),Vector3(.18,.17,.18),Color("819775"))
	var scale=Vector3(size.x/original.x,height/original.y,size.y/original.z)
	for part in list:part.at*=scale;part.size*=scale
	return list
