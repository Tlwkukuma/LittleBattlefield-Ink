extends RefCounted
const IDS=["defense.trench-firing-step","defense.trench-revetment"]

static func register(catalog):
	for i in range(IDS.size()):
		var id: String=IDS[i]
		catalog.components[id]={"id":id,"label":["战壕射击踏步 · 双端三级","战壕可破坏护壁"][i],"primitive":"segment","material":"wood","defaults":{"length":160,"thickness":36},"runtime":{"output":"ground","collision":false,"blocksProjectiles":false,"damageable":false}}
		catalog.prefabs[id]={"id":id,"label":catalog.components[id].label,"footprint":[[-80,-18],[80,-18],[80,18],[-80,18]],"godot_height":.36 if i==0 else 1.1,"trench_asset":true}
		catalog.templates[id]={"walls":[],"trees":[],"world":{"groundFeatures":[]}}

static func compile_instance(catalog,plan,out,instance):
	var spec=instance.get("godot3d",{}).duplicate(true);var offset=catalog.v(instance);var axis=Vector2.RIGHT.rotated(float(instance.get("rotation",0)))
	var length=float(spec.get("length_m",4))*40*float(instance.get("scaleX",instance.get("scale",1)))
	var a=offset-axis*length*.5;var b=offset+axis*length*.5
	spec.id=instance.id;spec.componentId=instance.prefabId;spec.points=[[a.x,a.y],[b.x,b.y]]
	if spec.has("height"):spec["step_height_m" if instance.prefabId==IDS[0] else "height_m"]=spec.height
	compile_feature(catalog,plan,out,spec)

static func compile_feature(catalog,plan,out,feature: Dictionary):
	var f=feature.duplicate(true)
	for key in f.get("godot3d",{}):
		if not f.has(key):f[key]=f.godot3d[key]
	var points=f.get("points",[])
	if points.size()<2:return
	var component=str(f.get("componentId",f.get("mapKitComponentId","")));var owner=str(f.get("id",component))
	var base=float(f.get("elevation_m",f.get("elevation",0)));var width=float(f.get("width_m",.9 if component==IDS[0] else .16))
	var index=0
	for segment in range(points.size()-1):
		var a=catalog.v(points[segment]);var b=catalog.v(points[segment+1]);var length=a.distance_to(b)/40;var direction=(b-a).normalized()
		if length<.05:continue
		var spans=[]
		if component==IDS[0]:
			var h=clampf(float(f.get("step_height_m",.36)),.1,1.2);var count=maxi(ceili(h/.18),int(f.get("step_count",3)))
			var run=minf(maxf(.28,float(f.get("step_run_m",.35))),length/(count*2))
			for i in range(count-1):
				spans.append([i*run,(i+1)*run,h*(i+1)/count]);spans.append([length-(i+1)*run,length-i*run,h*(i+1)/count])
			spans.append([(count-1)*run,length-(count-1)*run,h])
		else:spans.append([0,length,float(f.get("height_m",1.1))])
		for span in spans:
			var start=a+direction*float(span[0])*40;var end=a+direction*float(span[1])*40
			var details={"height":float(span[2]),"elevation":base,"health_scale":float(f.get("health_scale",2))}
			var material=str(f.get("material","wood"))
			var id="structure.stair" if component==IDS[0] else "wall.stone" if material=="stone" else "wall.wood-fence"
			var o=catalog.object_from_segment(owner+"."+str(index),id,start,end,width*40,plan,details,owner)
			o.terrain_absolute=f.has("elevation_m") or f.has("elevation");o.trench_asset=true
			if not o.terrain_absolute:o.terrain_relative=true
			o.windows=false;out.objects.append(o);index+=1
