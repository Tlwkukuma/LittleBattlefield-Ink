"""Read-only renderer bindings, not asset exports or runtime/visual measurements."""
import json
from pathlib import Path
import UnityPy

source = Path(r"F:\steam\steamapps\common\Escape from Duckov\Duckov_Data\resources.assets")
env = UnityPy.load(str(source))
rows = []
normal_projectiles = []
material_colors = {}

def walk_normal(go):
    comps = {c.component.deref().type.name: c.component.deref() for c in go.m_Component}
    entry = {"name": go.m_Name, "active": go.m_IsActive, "components": list(comps)}
    if "TrailRenderer" in comps:
        trail = comps["TrailRenderer"].read_typetree()
        entry["trail"] = {"time": trail["m_Time"], "emitting": trail["m_Emitting"],
                          "width": trail["m_Parameters"]["widthMultiplier"]}
    if "Transform" in comps:
        entry["children"] = [walk_normal(p.deref().read().m_GameObject.deref().read())
                             for p in comps["Transform"].read().m_Children]
    return entry

for obj in env.objects:
    if obj.type.name == "GameObject":
        go = obj.read()
        if go.m_Name in ("BulletNormal", "BulletSMG"):
            normal_projectiles.append(walk_normal(go))
    if obj.type.name == "Material":
        mat = obj.read_typetree()
        if mat["m_Name"] in ("Bullet", "BulletTrail", "Shell"):
            colors = dict(mat["m_SavedProperties"]["m_Colors"])
            material_colors[mat["m_Name"]] = {k: colors.get(k) for k in ("_BaseColor", "_EmissionColor")}
    if obj.type.name not in ("MeshRenderer", "ParticleSystemRenderer"):
        continue
    data = obj.read()
    materials = [p.deref().read().m_Name for p in data.m_Materials if p]
    if not any(n in ("Bullet", "Shell") for n in materials):
        continue
    go = data.m_GameObject.deref().read()
    comps = {c.component.deref().type.name: c.component.deref() for c in go.m_Component}
    transform = comps["Transform"].read()
    row = {"object": go.m_Name, "id": obj.path_id, "renderer": obj.type.name,
           "materials": materials, "local_scale": str(transform.m_LocalScale)}
    parents = []
    for _ in range(6):
        if not transform.m_Father:
            break
        transform = transform.m_Father.deref().read()
        parents.append({"name": transform.m_GameObject.deref().read().m_Name,
                        "scale": str(transform.m_LocalScale)})
    row["parents"] = parents
    ptr = data.m_Mesh if obj.type.name == "ParticleSystemRenderer" else comps["MeshFilter"].read().m_Mesh
    if ptr:
        mesh = ptr.deref().read()
        row["mesh"] = {"name": mesh.m_Name, "local_bounds": str(mesh.m_LocalAABB)}
    if "ParticleSystem" in comps:
        ps = comps["ParticleSystem"].read_typetree()
        initial, collision = ps["InitialModule"], ps["CollisionModule"]
        row["particle_settings"] = {
            "size": initial["startSize"]["scalar"], "size3D": initial["size3D"],
            "life_min_max": [initial["startLifetime"]["minScalar"], initial["startLifetime"]["scalar"]],
            "speed_min_max": [initial["startSpeed"]["minScalar"], initial["startSpeed"]["scalar"]],
            "gravity": initial["gravityModifier"]["scalar"], "collision": collision["enabled"],
            "bounce": collision["m_Bounce"]["scalar"]}
    rows.append(row)

output = Path(__file__).resolve().parents[1] / "docs/duckov-ammo-renderer-observations.json"
output.write_text(json.dumps({"source": str(source),
    "note": "Serialized bindings only. Local scales are not runtime size. No meshes/textures/sounds exported. The mesh named Shell under IG_Special_SeaShell is a seashell, not an ejected casing.",
    "materials": material_colors, "normal_projectiles": normal_projectiles,
    "renderers": rows}, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
unique = {}
for row in rows:
    key = (row["object"], row["renderer"], str(row.get("mesh")), str(row.get("particle_settings")))
    unique.setdefault(key, row)
print("Matched renderers:", len(rows), "Unique signatures:", len(unique))
for row in list(unique.values())[:12]:
    print(json.dumps(row, ensure_ascii=False))
