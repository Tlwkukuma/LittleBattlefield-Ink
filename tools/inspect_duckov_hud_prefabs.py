"""Read UI hierarchy/RectTransform metadata only. No artwork or game execution."""
import json
from pathlib import Path
import UnityPy

source=Path(r"F:\steam\steamapps\common\Escape from Duckov\Duckov_Data\resources.assets")
env=UnityPy.load(str(source))
wanted={"SimpleIndicatorEntry_Reload","SimpleIndicatorEntry_Focus","ActionProgress","Reload","AimMarkerDefault"}

def tree(go,depth=0):
    row={"name":go.m_Name,"scripts":[]}
    for component in go.m_Component:
        obj=component.component.deref()
        if obj.type.name=="MonoBehaviour":
            # Stripped game types have no complete typetree; only read the common header.
            data=obj.read(check_read=False)
            if data.m_Script: row["scripts"].append(data.m_Script.deref().read().m_ClassName)
        elif obj.type.name=="RectTransform":
            data=obj.read()
            row["rect"]={name:[getattr(data,name).x,getattr(data,name).y] for name in
                         ("m_AnchorMin","m_AnchorMax","m_AnchoredPosition","m_SizeDelta")}
            if depth<4: row["children"]=[tree(x.deref().read().m_GameObject.deref().read(),depth+1) for x in data.m_Children]
    return row

rows=[]
for obj in env.objects:
    if obj.type.name!="GameObject":continue
    go=obj.read()
    if go.m_Name in wanted:rows.append(tree(go))
output=Path(__file__).resolve().parents[1]/"docs/duckov-hud-prefabs.json"
output.write_text(json.dumps({"source":str(source),"note":"Serialized UI hierarchy only, not runtime screen dimensions, colors or playtest.","prefabs":rows},ensure_ascii=False,indent=2)+"\n",encoding="utf8")
print("Recorded",len(rows),"HUD hierarchies to",output)
