extends SceneTree
## Bake the actual native model into a transparent inventory vector asset.
## Production asset generation only; no gameplay input or screenshot acceptance.
const Props=preload("res://scripts/proving_art.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
func _initialize():bake.call_deferred()
func bake():
	var parent=Node3D.new();root.add_child(parent)
	var catalog=Catalog.new();var gun=Props.weapon(parent,catalog.weapons.minigun)
	var forward=Vector3(2.8,1.7,-1.6).normalized()
	var right=Vector3.UP.cross(forward).normalized();var up=forward.cross(right)
	var light=Vector3(1,3,-2).normalized();var faces=[];var bounds=Rect2();var first=true
	for child in gun.get_children():
		if not child is MeshInstance3D:continue
		var matrix: Transform3D=child.global_transform
		for surface in range(child.mesh.get_surface_count()):
			var data=child.mesh.surface_get_arrays(surface)
			var v: PackedVector3Array=data[Mesh.ARRAY_VERTEX];var n: PackedVector3Array=data[Mesh.ARRAY_NORMAL];var c: PackedColorArray=data[Mesh.ARRAY_COLOR]
			for i in range(0,v.size(),3):
				var normal=(matrix.basis*n[i]+matrix.basis*n[i+1]+matrix.basis*n[i+2]).normalized()
				if normal.dot(forward)<=0:continue
				var points=[];var depth=0.0
				for k in range(3):
					var p=matrix*v[i+k];var xy=Vector2(p.dot(right),-p.dot(up))
					points.append(xy);depth+=p.dot(forward)
					bounds=Rect2(xy,Vector2.ZERO) if first else bounds.expand(xy);first=false
				var color: Color=c[i]*(.73+.27*maxf(0,normal.dot(light)))
				faces.append({"points":points,"depth":depth/3,"color":color.to_html(false)})
	faces.sort_custom(func(a,b):return a.depth<b.depth)
	var scale=minf(244.0/bounds.size.x,116.0/bounds.size.y)
	var center=Vector2(128,64)-bounds.get_center()*scale
	var svg='<svg xmlns="http://www.w3.org/2000/svg" width="256" height="128" viewBox="0 0 256 128">\n'
	for face in faces:
		var points=PackedStringArray()
		for p in face.points:
			var xy: Vector2=p*scale+center;points.append("%.2f,%.2f"%[xy.x,xy.y])
		# Matching fill/stroke closes rasterization hairline cracks between triangles.
		svg+='<polygon points="%s" fill="#%s" stroke="#%s" stroke-width="0.35" stroke-linejoin="round"/>\n'%[" ".join(points),face.color,face.color]
	svg+='</svg>\n'
	DirAccess.make_dir_recursive_absolute("res://assets/weapons")
	var file=FileAccess.open("res://assets/weapons/minigun-icon.svg",FileAccess.WRITE);file.store_string(svg);file.close()
	print("MINIGUN_ICON baked from native geometry: ",faces.size()," visible triangles, 256x128")
	parent.free();quit()
