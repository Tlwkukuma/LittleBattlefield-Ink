extends RefCounted
## Reuse the capsules and sockets already evaluated by the existing pose scheduler.
## Queries never sample animation, run IK, load resources, or cast extra rays.
const HEAD_CENTER=[1.285,.945,.31]
const HEAD_TOP=[1.535,1.195,.61]
const MUZZLE_HEIGHT=[1.33,1.00,.425]

static func capture(u: Dictionary,view: Dictionary) -> void:
	# Bone shapes keep their sampled world-space origin. Translation is applied
	# only to queried candidates, using the current physics position.
	u.hit_shape_origin=base(u)
	var shapes: Array=u.get("hit_shapes",[])
	for shape in shapes:
		if shape.region=="head":u.cover_head_shape=shape;break
	if not shapes.is_empty():u.cover_body_shape=shapes[0]
	if view.has("muzzle_socket"):
		u.cover_muzzle_offset=view.muzzle_socket.global_position-view.root.global_position
		u.cover_muzzle_facing=u.facing.angle()
		u.cover_muzzle_stance=float(u.get("stance_blend",u.stance))

static func base(u: Dictionary) -> Vector3:
	return Vector3(u.position.x,float(u.get("elevation",0)),u.position.y)

static func shape_translation(u: Dictionary) -> Vector3:
	var current:=base(u)
	return current-Vector3(u.get("hit_shape_origin",current))

static func blended(values: Array,u: Dictionary) -> float:
	var blend=clampf(float(u.get("stance_blend",u.stance)),0,2)
	return lerpf(values[0],values[1],blend) if blend<=1 else lerpf(values[1],values[2],blend-1)

static func head(u: Dictionary) -> Vector3:
	if not u.get("hit_shapes",[]).is_empty():
		if u.has("cover_head_shape"):return Vector3(u.cover_head_shape.a)+shape_translation(u)
		for shape in u.hit_shapes:
			if shape.get("region","")=="head":return Vector3(shape.a)+shape_translation(u)
	var prone=clampf(float(u.get("stance_blend",u.stance))-1,0,1)
	return base(u)+Vector3(u.facing.x*.61*prone,blended(HEAD_CENTER,u),u.facing.y*.61*prone)

static func head_target(u: Dictionary) -> Vector3:
	var radius=float(u.get("cover_head_shape",{}).get("radius",.25))
	# A point inside the head capsule catches partial exposure over a wall lip.
	return head(u)+Vector3.UP*radius*.55

static func chest(u: Dictionary) -> Vector3:
	if not u.get("hit_shapes",[]).is_empty():
		var shape: Dictionary=u.get("cover_body_shape",u.hit_shapes[0])
		return Vector3(shape.a).lerp(shape.b,.72)+shape_translation(u)
	return base(u)+Vector3.UP*blended([.96,.68,.30],u)

static func eye(u: Dictionary) -> Vector3:return head(u)+Vector3.UP*.08

static func muzzle(u: Dictionary) -> Vector3:
	var stance=float(u.get("stance_blend",u.stance))
	if u.has("cover_muzzle_offset") and absf(float(u.get("cover_muzzle_stance",stance))-stance)<.08:
		var offset: Vector3=u.cover_muzzle_offset
		var planar=Vector2(offset.x,offset.z).rotated(u.facing.angle()-float(u.cover_muzzle_facing))
		return base(u)+Vector3(planar.x,offset.y,planar.y)
	var reach=1.53 if stance>1.8 else .95
	return base(u)+Vector3(u.facing.x*reach,blended(MUZZLE_HEIGHT,u),u.facing.y*reach)

static func candidate_head(point: Vector2,elevation: float,stance: int) -> Vector3:
	return Vector3(point.x,elevation+HEAD_TOP[stance],point.y)
