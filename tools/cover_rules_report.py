"""Generate design tables; does not edit game balance or simulate gameplay."""
from __future__ import annotations

import ast
import csv
import hashlib
import io
import json
import math
import re
from fractions import Fraction as F
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def csv_file(name, rows):
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
    (DOCS / name).write_text(buffer.getvalue(), encoding="utf-8-sig")


def table(headers, rows):
    return "\n".join(["| " + " | ".join(headers) + " |", "| " + " | ".join(["---"] * len(headers)) + " |"] + ["| " + " | ".join(map(str, row)) + " |" for row in rows])


def main():
    proposal = read_json(DOCS / "cover-balance-proposal.json")
    catalog = read_json(ROOT / "data/original/catalog.json")
    poses = read_json(DOCS / "cover-pose-measurements.json")
    source = (ROOT / "scripts/proving_world.gd").read_text(encoding="utf-8-sig")
    match = re.search(r"var multipliers=(\{[^\n]+\})", source)
    assert match, "Review current damage_object before updating the audit."
    multipliers = ast.literal_eval(match.group(1))
    assert 'amount*(o.blast_scale if explosive else float(multipliers.get(o.kind,.36)))' in source
    assert 'float(material.get("cellHealth",58))*float(o.health_scale)' in source
    assert 'else:damage_object(hit.target' in source and 'p.alive=false' in source
    materials = {m["id"]: m for m in proposal["materials"]}
    kinetic = proposal["kinetic_columns"]
    blast = proposal["blast_columns"]
    for material in materials.values():
        assert len(material["kinetic"]) == len(kinetic)
        assert len(material["blast"]) == len(blast)
        assert material["thickness_m"] > 0 and material["resistance"] > 0
        assert all(isinstance(n, int) and n >= 0 for n in material["kinetic"] + material["blast"])
    assert len(proposal["penetration_budget"]) == len(kinetic)
    assert len(proposal["blast_radius_m"]) == len(blast)
    bindings = {}
    for family, ids in proposal["weapon_bindings"].items():
        assert family in kinetic + blast + ["smoke"], family
        for weapon_id in ids:
            assert weapon_id not in bindings, weapon_id
            bindings[weapon_id] = family
    weapons = {w["id"]: w for w in catalog["weapons"]}
    assert set(bindings) == set(weapons), {"missing": sorted(set(weapons) - set(bindings)), "extra": sorted(set(bindings) - set(weapons))}
    mounted = {}
    for vehicle_id, vehicle in catalog["vehicles"].items():
        for mode in vehicle["weapons"]:
            mounted[vehicle_id + "/" + mode] = vehicle["weapons"][mode]
    mounted.update({"emplacement/" + key: value for key, value in catalog["emplacements"].items()})
    assert set(mounted) == set(proposal["mounted_bindings"])
    assert all(family in kinetic + blast for family in proposal["mounted_bindings"].values())

    coverage = []
    for c in poses["registered_components"]:
        family = proposal["component_overrides"].get(c["id"])
        if family is None:
            family = next((v for prefix, v in proposal["component_prefixes"].items() if c["id"].startswith(prefix)), None)
        assert family in materials or family in proposal["assembly_profiles"], c["id"]
        coverage.append({"component_id": c["id"], "current_material": c["material"], "proposed_profile": family, "status": "proposal_not_runtime"})
    csv_file("cover-component-coverage.csv", coverage)

    proposed_rows = []
    all_bindings = list(bindings.items()) + list(proposal["mounted_bindings"].items()) + list(proposal["hazard_bindings"].items())
    for weapon_id, family in all_bindings:
        for material in materials.values():
            counts = material["kinetic"] if family in kinetic else material["blast"]
            index = (kinetic if family in kinetic else blast).index(family) if family != "smoke" else -1
            count = counts[index] if index >= 0 else 0
            penetration = proposal["penetration_budget"][kinetic.index(family)] if family in kinetic else 0
            can_penetrate = penetration - material["resistance"] >= proposal["modifiers"]["minimum_residual_penetration_budget"]
            proposed_rows.append({"weapon_id": weapon_id, "family": family, "material": material["id"], "reference_thickness_m": material["thickness_m"], "events_to_remove_reference_panel": count if count else "NO_REMOVAL", "damage_per_event_exact": str(F(100, count)) if count else "0", "intact_reference_panel_penetrable": can_penetrate, "count_unit": "full_shell_all_pellets_on_one_panel" if family in ["buckshot", "canister"] else "contact_explosion" if family in blast else "no_structural_effect" if family == "smoke" else "single_hit", "geometry_scope": "panel_or_equivalent_erosion_volume_see_spec" if material["id"] in proposal["terrain_erosion"]["applicable_materials"] else "reference_panel", "status": "proposal_not_runtime"})
    csv_file("cover-proposed-counts.csv", proposed_rows)

    # Current code has no physical thickness term and stops bullets on object hits.
    # This is a catalogue/health_scale=1 audit, not an in-game shot-count measurement.
    baseline = []
    for c in poses["registered_components"]:
        if not (c["id"].startswith("wall.") or c["id"] in ["obstacle.earth-berm", "obstacle.concrete-barrier"]):
            continue
        runtime = c["runtime"]
        kind = runtime.get("kind", "barrier")
        hp = F(str(catalog["materials"].get(kind, catalog["materials"]["concrete"]).get("cellHealth", 58)))
        multiplier = F(str(multipliers.get(kind, .36)))
        for weapon_id, w in weapons.items():
            if w["kind"] not in ["bullet", "hitscan", "melee"]:
                continue
            eligible = bool(runtime.get("blocksProjectiles", True)) and bool(runtime.get("damageable", True))
            damage = F(str(w["damage"])) * multiplier
            pellets = w.get("pellets", 1)
            count = math.ceil(hp / damage) if eligible and damage else "NOT_BALLISTIC"
            shell_count = math.ceil(hp / (damage * pellets)) if eligible and damage else "NOT_BALLISTIC"
            baseline.append({"component_id": c["id"], "kind": kind, "weapon_id": weapon_id, "catalog_hp_health_scale_1": str(hp), "damage_per_projectile": str(damage), "projectile_hits_to_remove": count, "ideal_trigger_pulls_lower_bound": shell_count, "pellets_per_trigger": pellets, "scope": "one_cell" if c["id"].startswith("wall.") else "whole_object", "conditions": "health_scale=1; no falloff; exact same cell; catalogue audit; no support collapse; not gameplay test"})
    csv_file("cover-current-baseline.csv", baseline)

    # Fraction arithmetic validates ceiling behaviour, pellet accounting and scaling.
    numeric_checks = 0
    for material in materials.values():
        for count in material["kinetic"] + material["blast"]:
            if not count:
                continue
            damage = F(100, count)
            assert damage * (count - 1) < 100 <= damage * count
            assert math.ceil(F(200) / damage) == count * 2
            assert math.ceil(F(100) / (damage * F(13, 20))) >= count
            numeric_checks += 3
    assert math.ceil(F(100) / (F(100, 3) * F(7, 14))) == 6  # Half a shell hits a thin wood panel.
    assert math.ceil(F(100) / (F(100, 48) * F(1, 2))) == 96  # 60-degree oblique light rifle impact on brick.
    assert math.ceil(F(100) * F(28, 24) / F(100, 48)) == 56  # Existing 0.28m house wall if migrated unchanged.
    numeric_checks += 3

    sections = ["# 掩体数值表：设计草案 1", "**尚未接入运行游戏。** 本表由 `tools/cover_rules_report.py` 从唯一草案 JSON 生成。数字是本项目的游戏平衡值，不是鸭科夫 / PUBG 或真实枪弹数据。完整规则见 [统一规范](cover-combat-spec.md)。", "## 计数口径", "满血 0.5 × 0.5 米独立块、表中参考厚度、有效距离内、正面垂直、全部命中同块、不计承重坍塌。`—` 表示该攻击不移除结构，绝不表示能穿过；穿透另算。霰弹 / 榴霰弹按一发的所有弹粒都落在该块的理论下限计。爆炸为接触该块中心的次数，不等于能通行的破口次数。", "## 枪弹及近战：移除一块需要多少次命中", table(["材质", "厚度 m"] + kinetic, [[m["label"], m["thickness_m"]] + [n or "—" for n in m["kinetic"]] for m in materials.values()]), "## 爆炸：移除一块需要多少次接触爆炸", table(["材质"] + blast, [[m["label"]] + [n or "—" for n in m["blast"]] for m in materials.values()]), "## 穿透与爆压", "穿透预算与抗力均为抽象游戏单位；每层剩余预算至少 4 才能出射。下表系数尚未实装。", table(["材质", "抗力", "穿透后人体伤害系数", "爆压透射系数"], [[m["label"], m["resistance"], m["penetrated_damage_scale"], m["blast_pressure_transmission"]] for m in materials.values()]), table(["弹药家族", "穿透预算"], zip(kinetic, proposal["penetration_budget"])), "## 随身武器完整绑定", "这些是项目设计分组，不据枪名臆测真实口径 / 装药。现有武器没有独立弹种字段，第一期采用固定默认弹，不增加弹药菜单。", table(["家族", "现有武器 ID"], [[family, "、".join(ids)] for family, ids in proposal["weapon_bindings"].items()]), "## 载具 / 固定武器完整绑定", table(["模式 ID", "家族"], proposal["mounted_bindings"].items()), "## 原骨架静态测量", "脚下 0 米，目标水平距离 20 米、目标高 1.35 米，瞄准静止帧。仅 3 枪 × 3 姿势，不能代表全部动画和仰俯角。头顶是命中胶囊上沿；通行体另列。", table(["武器", "姿势", "枪口 m", "头顶 m", "最高命中部位 m", "通行体 m"], [[s["weapon"], ["站", "蹲", "卧"][s["stance"]], f'{s["muzzle_y"]:.3f}', f'{s["head_top_y"]:.3f}', f'{s["body_max_y"]:.3f}', s["collision_height"]] for s in poses["samples"]]), "## 数据完整性", f"已检查 {len(bindings)} 个随身武器、{len(mounted)} 个载具/固定武器模式、{len(coverage)} 个已注册组件的映射；{numeric_checks} 项算术检查通过。此处通过的是覆盖与算术，玩法状态仍为待实现 / 待用户验收。", "- [所有武器 × 材质的计算表](cover-proposed-counts.csv)", "- [全部组件迁移表](cover-component-coverage.csv)", "- [当前代码目录数值审计](cover-current-baseline.csv)", "- [源文件指纹和审计摘要](cover-audit-summary.json)"]
    sections.insert(6, "土、沙、雪、冰及山体表层应用为地形时，计数代表移除 `0.25 m² × 参考厚度` 的材料体积预算，不代表完整缺口；参考实现见规范第 10 节。载具爆炸模式首期统一为本表家族半径，若要保留车型差异须增加显式覆盖，不可只改运行值。")
    sections[1] = sections[1].replace("尚未接入运行游戏。", "墙格枪弹/近战数值与材料禁破规则已启用；整体道具正值耐久、爆炸发数、穿透和土体侵蚀仍待迁移。")
    (DOCS / "cover-balance-tables.md").write_text("\n\n".join(sections) + "\n", encoding="utf-8")
    tracked = ["scripts/proving_world.gd", "scripts/source_catalog.gd", "scripts/source_rig_motion.gd", "scripts/campaign_perception.gd", "scripts/campaign_ai.gd", "scripts/campaign_tactics.gd", "scripts/terrain_surface.gd", "scripts/terrain_structure.gd", "scripts/house_prefabs.gd", "data/original/catalog.json", "data/original/components.json", "docs/cover-balance-proposal.json", "docs/cover-pose-measurements.json"]
    version_source = (ROOT / "scripts/proving_ground.gd").read_text(encoding="utf-8-sig")
    summary = {"status": "design_audit_not_runtime_acceptance", "observed_project_build": re.search(r'BUILD_VERSION="([^"]+)"', version_source).group(1), "proposal_revision": proposal["revision"], "weapons": len(bindings), "mounted_modes": len(mounted), "components": len(coverage), "materials": len(materials), "proposal_rows": len(proposed_rows), "baseline_rows": len(baseline), "numeric_checks": numeric_checks, "sha256": {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in tracked}}
    (DOCS / "cover-audit-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in summary.items() if key != "sha256"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
