extends Node3D
## Equipment stands inside the joint range, sharing the live player art/animation.
const Classes=preload("res://scripts/soldier_classes.gd")
const Art=preload("res://scripts/ink_art.gd")
const Motion=preload("res://scripts/soldier_motion.gd")
const Batch=preload("res://scripts/mesh_batch.gd")
var game
var figures: Array=[]
var interactions: Array=[]
var turn=0.0
func _ready():
	for i in range(Classes.IDS.size()):
		var id: String=Classes.IDS[i];var info=Classes.profile(id);var at=Vector2(i*2.7,16)
		var pedestal=Node3D.new();add_child(pedestal)
		Art.box(pedestal,Vector3(at.x,.025,at.y),Vector3(1.7,.05,1.6),Color("a5a3aa"))
		Art.ring(pedestal,Vector3(at.x,.055,at.y),.66,info.accent,.022,32)
		Classes.pouch(pedestal,Vector3(at.x,.20,at.y+1.65),Vector3(.62,.40,.42),info.accent)
		Batch.collapse(pedestal)
		var title=Label3D.new();add_child(title);title.text=info.name;title.font_size=48;title.pixel_size=.0055;title.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		title.position=Vector3(at.x,.27,at.y+.95);title.modulate=Color("ede9ed");title.outline_modulate=Art.INK;title.outline_size=8
		var u: Dictionary=game.world.player.duplicate(true);u.player=false;u.id=-100-i;u.team=0;u.position=at;u.elevation=.055;u.facing=Vector2(.15,1).normalized();u.aim_point=at+u.facing*8
		u.velocity=Vector2.ZERO;u.requested_velocity=Vector2.ZERO;u.weapon_id=info.weapon if game.catalog.weapons.has(info.weapon) else "m416";u.class_id=id;u.shot_index=0;u.aiming=false
		var view=Art.soldier(self,0,false);game.replace_weapon(view,game.catalog.weapons[u.weapon_id]);view.root.position=Vector3(at.x,u.elevation,at.y)
		Classes.apply(view,id,0);Motion.update(view,u,0,0,2.1)
		figures.append({"view":view,"unit":u})
		interactions.append({"kind":"class","class_id":id,"position":Vector3(at.x,.40,at.y+1.65),"label":"E  换装："+str(info.name)})
func _process(delta: float):
	if game.paused or game.editing:return
	for figure in figures:Motion.update(figure.view,figure.unit,delta,game.world.time,2.1)
func rotate_figures():
	turn+=PI*.5
	for figure in figures:
		figure.unit.facing=Vector2(.15,1).normalized().rotated(turn)
		figure.unit.aim_point=figure.unit.position+figure.unit.facing*8
