extends RefCounted
## Gameplay-scale 1940s-inspired civilian-pattern cargo truck, not a model attribution.
## No turret, armor shell, mounted weapon, weapon state or ammunition is supplied.
const Art=preload("res://scripts/ink_art.gd")
const Style=preload("res://scripts/vehicle_style.gd")
const KIND="truck"

static func profile() -> Dictionary:
	return {"name":"公路运输卡车","health":420.0,"trackHealth":150.0,"radius":64.0,
		"maxSpeed":152.0,"reverseSpeed":48.0,"steerRate":.55,"turnRate":.55,
		"armor":{"front":1.0,"side":1.0,"rear":1.0},"smallArmsMultiplier":1.0,
		"weaponOrder":[],"weapons":{},"effects":{"radius":100}}

static func parts() -> Array:
	# Local -Z is the nose. Four tires, engine, cab panels and open cargo bed.
	var result=[
		{"at":Vector3(0,.54,0),"size":Vector3(1.72,.18,4.55),"gear":false},
		{"at":Vector3(0,.98,-1.67),"size":Vector3(1.60,.70,1.10),"gear":false},
		{"at":Vector3(0,.90,-.65),"size":Vector3(1.84,.40,.95),"gear":false},
		{"at":Vector3(0,1.97,-.67),"size":Vector3(1.96,.12,1.14),"gear":false},
		{"at":Vector3(0,1.44,-.13),"size":Vector3(1.84,1.0,.09),"gear":false},
		{"at":Vector3(0,.83,1.09),"size":Vector3(2.0,.14,2.43),"gear":false},
		{"at":Vector3(0,1.13,2.26),"size":Vector3(2.0,.60,.10),"gear":false}]
	for side in [-1,1]:
		result.append({"at":Vector3(side*.95,1.13,1.10),"size":Vector3(.10,.60,2.40),"gear":false})
		result.append({"at":Vector3(side*.92,1.22,-.68),"size":Vector3(.08,.40,.96),"gear":false})
		for z in [-1.20,-.20]:result.append({"at":Vector3(side*.91,1.67,z),"size":Vector3(.09,.55,.09),"gear":false})
		for z in [-1.464,1.464]:result.append({"at":Vector3(side*.91,.38,z),"size":Vector3(.38,.76,.76),"gear":true})
	return result

static func build(body: Node3D,wheels: Array) -> void:
	for part in parts():
		if part.gear:continue
		Style.box(body,part.at,part.size,Style.HULL if part.at.z<0 else Style.CLOTH)
	# Glass is a thin pane with a matching collision panel, not a solid cab box.
	Style.box(body,Vector3(0,1.68,-1.205),Vector3(1.73,.45,.025),Style.GLASS,false)
	Style.box(body,Vector3(0,.96,-2.23),Vector3(1.38,.48,.055),Style.DARK)
	for x in [-.50,-.25,0,.25,.50]:Style.box(body,Vector3(x,.97,-2.267),Vector3(.065,.38,.024),Style.STEEL,false)
	Style.box(body,Vector3(0,.56,-2.34),Vector3(2.08,.13,.10),Style.STEEL)
	for side in [-1,1]:
		Style.box(body,Vector3(side*.81,1.12,-2.25),Vector3(.16,.16,.055),Style.MARK,false)
		Style.recognition(body,Vector3(side*1.01,1.16,.96),Vector2(.42,.17),1,Vector3(side,0,0))
		for z in [-1.464,1.464]:
			var wheel=Node3D.new();wheel.name="TruckWheel";body.add_child(wheel)
			wheel.position=Vector3(side*.91,.38,z);wheel.rotation.z=PI*.5
			Style.tire(wheel,.38,.38,Style.RUBBER)
			for edge in [-1,1]:Art.cylinder(wheel,Vector3(0,edge*.197,0),.20,.018,Style.STEEL)
			wheels.append(wheel)

static func collision_parts() -> Array:
	var result=parts()
	result.append({"at":Vector3(0,1.68,-1.205),"size":Vector3(1.73,.45,.025),"gear":false})
	result.append({"at":Vector3(0,.56,-2.34),"size":Vector3(2.08,.13,.10),"gear":false})
	return result

static func seat(index: int) -> Vector3:
	# Feet/root positions, not four copies of the vehicle origin.
	return [Vector3(-.43,.76,-.65),Vector3(-.48,.91,.45),Vector3(.48,.91,1.10),Vector3(-.48,.91,1.75)][clampi(index,0,3)]
