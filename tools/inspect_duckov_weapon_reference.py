"""Read installed reference metadata only; never export/import game assets."""
import json
from pathlib import Path
import UnityPy

source = Path(r"F:\steam\steamapps\common\Escape from Duckov\Duckov_Data\resources.assets")
env = UnityPy.load(str(source))
mesh_names = {"WPN_AK47", "WPN_M700", "WPN_SV98", "WPN_TOZ66_L", "WPN_MP5", "WPN_Glock", "WPN_AUGA3", "Shell", "ShotgunShell", "Bullet03", "Bullet04", "Bullet07"}
result = {"source": str(source), "note": "Mesh-local bounds are not final in-game size. Serialized materials are not a claim about all ammunition. No gameplay observations or assets copied.", "meshes": [], "materials": [], "projectile_objects": []}
for obj in env.objects:
    if obj.type.name == "Mesh":
        data = obj.read()
        if data.m_Name in mesh_names:
            size = data.m_LocalAABB.m_Extent
            result["meshes"].append({"name": data.m_Name, "local_size": [round(2 * getattr(size, k), 4) for k in "xyz"]})
    elif obj.type.name == "Material":
        data = obj.read_typetree()
        if data["m_Name"] in ["Bullet", "Shell"]:
            props = dict(data["m_SavedProperties"]["m_Colors"])
            result["materials"].append({"name": data["m_Name"], "base_color": props.get("_BaseColor"), "emission": props.get("_EmissionColor")})
    elif obj.type.name == "GameObject":
        data = obj.read()
        if data.m_Name in ["Bullet_SHT_Normal", "Bullet_SHOT_Normal", "Bullet_AR_Normal", "Bullet_SNP_Normal", "Bullet_SMG_Normal", "Shell", "ShellEmitter"]:
            if data.m_Name not in result["projectile_objects"]:
                result["projectile_objects"].append(data.m_Name)
output = Path(__file__).resolve().parents[1] / "docs/duckov-weapon-observations.json"
output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, ensure_ascii=False, indent=2))
