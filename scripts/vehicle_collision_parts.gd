extends RefCounted
## Authoring-space structural parts, fitted to vehicle_art.gd before its model scale.
## Parts exclude antennae and projecting gun barrels, and keep wheel / chassis gaps open.
static func box(parts: Array,at: Vector3,size: Vector3,gear: bool=false) -> void:
	parts.append({"at":at,"size":size,"gear":gear})

static func plate(parts: Array,at: Vector3,lower: Vector3,upper: Vector3,offset: float,rounding: float=.18) -> void:
	# Slice sloped armor by height and trim its rounded front / rear corners.
	for row in range(3):
		var lo=float(row)/3;var hi=float(row+1)/3
		var a=lower.lerp(upper,lo);var b=lower.lerp(upper,hi)
		var front=minf(-a.z*.5+offset*lo,-b.z*.5+offset*hi)
		var back=maxf(a.z*.5+offset*lo,b.z*.5+offset*hi)
		var width=maxf(a.x,b.x)*.5;var length=(back-front)*.5
		var curve=minf(width,length)*maxf(.18,rounding)
		var cuts=[-length,-length+curve*.5,-length+curve,length-curve,length-curve*.5,length]
		for i in range(5):
			var nearest=maxf(absf(cuts[i]),absf(cuts[i+1])) if cuts[i]*cuts[i+1]>0 else 0.0
			var end=maxf(0,nearest-(length-curve))
			var half_width=width-curve+sqrt(maxf(0,curve*curve-end*end))
			var center=at+Vector3(0,upper.y*(lo+hi)*.5,(cuts[i]+cuts[i+1]+front+back)*.5)
			box(parts,center,Vector3(half_width*2,upper.y/3,cuts[i+1]-cuts[i]))

static func body(kind: String,r: float,source_width: float) -> Array:
	var parts=[]
	match kind:
		"armedJeep":
			box(parts,Vector3(0,.38,0),Vector3(r*1.32,.12,r*2.55))
			box(parts,Vector3(0,.55,.20*r),Vector3(r*1.30,.22,r*1.96))
			plate(parts,Vector3(0,.57,-.82*r),Vector3(r*1.22,0,r*.99),Vector3(r*1.08,.25,r*.90),.02)
			plate(parts,Vector3(0,.79,.23*r),Vector3(r*1.27,0,r*1.42),Vector3(r*1.16,.61,r*1.42),0)
			box(parts,Vector3(0,1.405,.23*r),Vector3(r*1.24,.055,r*1.49))
			box(parts,Vector3(.14,.89,r*1.28),Vector3(.51,.51,.15))
			box(parts,Vector3(.14,.89,r*1.28),Vector3(.092,.092,.258))
			box(parts,Vector3(-.36,.82,r*1.20),Vector3(.20,.35,.16))
		"scoutCar":
			plate(parts,Vector3(0,.36,0),Vector3(r*1.44,0,r*2.64),Vector3(r*1.23,.37,r*2.30),.08*r)
			plate(parts,Vector3(0,.73,-.13*r),Vector3(r*1.24,0,r*1.98),Vector3(r*.92,.27,r*1.38),.13*r)
		"apc":
			plate(parts,Vector3(0,.39,0),Vector3(r*1.38,0,r*2.62),Vector3(r*1.28,.81,r*2.22),r*.15)
			box(parts,Vector3(0,1.215,r*.29),Vector3(r*1.20,.052,r*1.62))
			box(parts,Vector3(0,.82,r*1.305),Vector3(r*1.05,.76,.055))
		"ifv":
			plate(parts,Vector3(0,.38,0),Vector3(r*1.48,0,r*2.65),Vector3(r*1.24,.55,r*1.93),r*.25)
			box(parts,Vector3(0,.72,r*1.265),Vector3(r*.92,.52,.04))
		_:
			var deck=.84 if kind=="lightTank" else .95 if kind=="heavyTank" else .90
			plate(parts,Vector3(0,.38,0),Vector3(r*1.45,0,r*2.62),Vector3(r*1.22,deck-.38,r*2.14),r*.10)
			for side in [-1,1]:box(parts,Vector3(side*r*.67,deck+.018,r*.42),Vector3(r*.23,.19,r*.54))
	var wheeled=kind in ["armedJeep","scoutCar"]
	for side in [-1,1]:
		if wheeled:
			var wheel_radius=.29 if kind=="armedJeep" else .31
			var center=r*(.73 if kind=="armedJeep" else .74)
			for z in ([-r*.84,r*.86] if kind=="armedJeep" else [-r*.86,r*.85]):
				box(parts,Vector3(side*center,wheel_radius,z),Vector3(r*.26,wheel_radius*2,wheel_radius*2),true)
				box(parts,Vector3(side*center,wheel_radius,z),Vector3(r*.26+.108,wheel_radius*.36,wheel_radius*.36),true)
				box(parts,Vector3(side*r*(.70 if kind=="armedJeep" else .73),.66 if kind=="armedJeep" else .70,z),Vector3(r*.37,.055,.72 if kind=="armedJeep" else .71))
		else:
			var inner=r*.595;var outer=source_width*.5
			box(parts,Vector3(side*(inner+outer)*.5,.33,0),Vector3(outer-inner,.58,r*2.62),true)
			box(parts,Vector3(side*r*.74,.71,0),Vector3(r*.34,.062,r*2.62*1.01))
	var lamp_height=.69 if kind=="armedJeep" else .66 if kind=="scoutCar" else .74 if kind=="apc" else .64 if kind=="ifv" else .67
	var nose=-r*(1.33 if kind=="armedJeep" else 1.26 if kind=="apc" else 1.29 if kind in ["lightTank","tank","heavyTank"] else 1.31)
	box(parts,Vector3(0,lamp_height-.17,nose-.012),Vector3(r*1.22,.065,.07))
	for side in [-1,1]:box(parts,Vector3(side*r*.39,lamp_height-.25,nose-.0275),Vector3(.046,.126,.101))
	return parts

static func turret(kind: String,r: float) -> Array:
	var parts=[]
	match kind:
		"armedJeep":box(parts,Vector3(0,1.49,0),Vector3(.38,.14,.38))
		"scoutCar":plate(parts,Vector3(0,1.04,0),Vector3(r*.97,0,r*1.03),Vector3(r*.75,.27,r*.80),r*.06,.37)
		"apc":
			box(parts,Vector3(0,1.34,0),Vector3(.088,.28,.088))
			box(parts,Vector3(0,1.525,-r*.20+.0125),Vector3(r*.74,.33,.09))
		"ifv":plate(parts,Vector3(0,.99,-r*.13),Vector3(r*1.02,0,r*1.05),Vector3(r*.72,.35,r*.81),r*.09,.36)
		"heavyTank":plate(parts,Vector3(0,1.05,-r*.10),Vector3(r*1.18,0,r*1.37),Vector3(r*.98,.50,r*1.18),r*.08,.24)
		_:
			var light=kind=="lightTank"
			plate(parts,Vector3(0,.95 if light else 1.0,-r*(.17 if light else .12)),Vector3(r*(.92 if light else 1.14),0,r*(1.04 if light else 1.30)),Vector3(r*(.58 if light else .80),.34 if light else .47,r*(.68 if light else .92)),.02 if light else .09,.85)
	return parts
