#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
《地牢冒险记》数据生成脚本

批量生成 data/ 下的 .tres 资源文件。
改数据表 -> 跑脚本 -> 全量重新生成，避免手工维护 40+ 个文件。

用法：python tools/generate_data.py
"""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 枚举值映射（与 docs/数据字段规范 一致）
CARD_CLASS = {"ATTACK": 0, "DEFENSE": 1, "SPECIAL": 2}
DAMAGE_TYPE = {"PHYSICAL": 0, "MAGICAL": 1, "NONE": 2}
TARGET_TYPE = {
    "SINGLE_ALLY": 0, "SINGLE_ENEMY": 1, "ALL_ENEMIES": 2,
    "ALL_ALLIES": 3, "SELF": 4, "FIELD": 5,
}
RARITY = {"COMMON": 0, "RARE": 1, "EPIC": 2, "LEGENDARY": 3}
MONSTER_TIER = {"NORMAL": 0, "ELITE": 1, "BOSS": 2}
AI_PATTERN = {"AGGRESSIVE": 0, "RANDOM": 1, "DEFENSIVE": 2}
DANGER = {"D": 0, "C": 1, "B": 2, "A": 3, "S": 4}
ITEM_CLASS = {
    "EQUIPMENT": 0, "CONSUMABLE": 1, "COLLECTIBLE": 2,
    "TROPHY": 3, "JUNK": 4,
}
SLOT = {
    "HEAD": 0, "NECK": 1, "BODY": 2, "HAND": 3, "LEG": 4, "FOOT": 5,
    "WEAPON": 6, "NONE": 7,
}

# ---------------------------------------------------------------------------
# 行动消耗换算表（9-22 修改意见 7 配套）
# 行动点从「每回合回满」改成「每回合只回 1 点」后，卡牌消耗必须整体下调，
# 否则一场仗的行动点总预算只剩原来的 1/4 左右（实测第 1 层 Boss 胜率 94%→0%）。
#
# 经 AI 对战采样标定（每档 60 局，见 scripts/_sim_balance.gd）：
#   保持原消耗         → Boss 40%
#   重档(20 张)保留 2  → Boss 38%     ← 只要有一批卡是 2 点就崩
#   全部 ≤1            → Boss 85%
#   全 ≤1 + 陨石术 2 点 → Boss 75% / 第 2 层 72%   ← 采用：落在 60–80% 区间
#
# CARDS 表里保留"原设计值"（便于对照与回退），写入 .tres 时统一走映射。
ACTION_COST_MAP = {0: 0, 1: 1, 2: 1, 3: 1, 4: 1, 5: 1}

# 例外：顶级卡保留 2 点，作为「终极法术」的分量标记
#   联合卡本体也吃 2 点 —— 它是"要攒前置条件才能放的终结技"，
#   2 点行动值意味着打出它的那一回合基本做不了别的事。
ACTION_COST_OVERRIDE = {"meteor": 2, "fire_tornado": 2, "frost_thunder": 2}

# 占位色（按卡牌定位取色，美术阶段直接替换）
C_PHYS = "#B4B2A9"      # 物理 - 灰
C_MAG = "#85B7EB"       # 法术 - 蓝
C_FIRE = "#D85A30"      # 火 - 珊瑚
C_ICE = "#9FE1CB"       # 冰 - 青
C_HOLY = "#FAC775"      # 神圣 - 琥珀
C_DARK = "#AFA9EC"      # 暗影 - 紫
C_GUARD = "#5DCAA5"     # 防御 - 绿
C_HEAL = "#C0DD97"      # 治疗 - 浅绿
C_SUPPORT = "#F4C0D1"   # 辅助 - 粉


# ---------------------------------------------------------------------------
# 战斗卡牌数据表
# 字段：(id, 名称, 描述, card_class, damage_type, multiplier, shield_multiplier,
#        heal_multiplier, action_cost, mana_cost, target_type, rarity, tags, color)
# ---------------------------------------------------------------------------
CARDS = [
    # ============ 攻击卡 · 物理 ============
    ("strike", "普通物理攻击", "造成 1.0 倍物理伤害。",
     "ATTACK", "PHYSICAL", 1.0, None, None, 2, 0, "SINGLE_ENEMY", "COMMON", [], C_PHYS),
    ("heavy_strike", "强力物理攻击", "造成 1.8 倍物理伤害。",
     "ATTACK", "PHYSICAL", 1.8, None, None, 3, 0, "SINGLE_ENEMY", "RARE", [], C_PHYS),
    ("cleave", "横扫", "对所有敌人造成 0.8 倍物理伤害。",
     "ATTACK", "PHYSICAL", 0.8, None, None, 3, 0, "ALL_ENEMIES", "RARE", [], C_PHYS),
    ("quick_jab", "快速突刺", "造成 0.6 倍物理伤害，消耗行动值极低。",
     "ATTACK", "PHYSICAL", 0.6, None, None, 1, 0, "SINGLE_ENEMY", "COMMON", [], C_PHYS),
    ("execute", "处决斩", "造成 1.4 倍物理伤害，对低血量目标额外提升。",
     "ATTACK", "PHYSICAL", 1.4, None, None, 3, 0, "SINGLE_ENEMY", "EPIC", [], C_PHYS),
    ("whirlwind", "旋风斩", "对所有敌人造成 1.2 倍物理伤害。",
     "ATTACK", "PHYSICAL", 1.2, None, None, 4, 0, "ALL_ENEMIES", "EPIC", [], C_PHYS),
    ("shield_bash", "盾击", "造成 0.9 倍物理伤害，并削弱目标物抗。",
     "ATTACK", "PHYSICAL", 0.9, None, None, 2, 0, "SINGLE_ENEMY", "RARE",
     ["DEBUFF_DEFENSE"], C_PHYS),
    ("piercing_shot", "穿甲箭", "造成 1.3 倍物理伤害，无视部分物抗。",
     "ATTACK", "PHYSICAL", 1.3, None, None, 3, 0, "SINGLE_ENEMY", "EPIC", [], C_PHYS),
    ("assassinate", "致命一击", "造成 2.4 倍物理伤害。",
     "ATTACK", "PHYSICAL", 2.4, None, None, 4, 0, "SINGLE_ENEMY", "LEGENDARY", [], C_PHYS),

    # ============ 攻击卡 · 法术 ============
    ("thunder", "雷击术", "造成 1.2 倍法术伤害。",
     "ATTACK", "MAGICAL", 1.2, None, None, 2, 8, "SINGLE_ENEMY", "COMMON", [], C_MAG),
    ("fireball", "烈焰术", "造成 2.0 倍法术伤害。",
     "ATTACK", "MAGICAL", 2.0, None, None, 3, 15, "SINGLE_ENEMY", "EPIC", [], C_FIRE),
    ("frost_bolt", "寒冰箭", "造成 1.0 倍法术伤害，并降低目标行动能力。",
     "ATTACK", "MAGICAL", 1.0, None, None, 2, 8, "SINGLE_ENEMY", "RARE",
     ["DEBUFF_DEFENSE"], C_ICE),
    ("chain_lightning", "连锁闪电", "对所有敌人造成 1.3 倍法术伤害。",
     "ATTACK", "MAGICAL", 1.3, None, None, 4, 20, "ALL_ENEMIES", "EPIC", [], C_MAG),
    ("meteor", "陨石术", "对所有敌人造成 2.2 倍法术伤害。",
     "ATTACK", "MAGICAL", 2.2, None, None, 5, 30, "ALL_ENEMIES", "LEGENDARY", [], C_FIRE),
    ("arcane_missile", "奥术飞弹", "造成 0.7 倍法术伤害，消耗低。",
     "ATTACK", "MAGICAL", 0.7, None, None, 1, 4, "SINGLE_ENEMY", "COMMON", [], C_MAG),
    ("holy_smite", "神圣制裁", "造成 1.6 倍法术伤害。",
     "ATTACK", "MAGICAL", 1.6, None, None, 3, 14, "SINGLE_ENEMY", "RARE", [], C_HOLY),
    ("shadow_bolt", "暗影箭", "造成 1.5 倍法术伤害，可汲取少量生命。",
     "ATTACK", "MAGICAL", 1.5, None, None, 3, 12, "SINGLE_ENEMY", "EPIC", [], C_DARK),
    ("drain_life", "生命汲取", "造成 1.1 倍法术伤害，并将伤害的一半转化为治疗。",
     "ATTACK", "MAGICAL", 1.1, None, None, 3, 14, "SINGLE_ENEMY", "RARE",
     ["HEAL_OVER_TIME"], C_DARK),

    # ---- 9-23 需求：补 5 张廉价法术（多法术流卡池缺口）----
    # 原法术链最便宜的只有奥术飞弹（4 蓝），其余全在 8 蓝以上，
    # 凑不出"每回合铺 4–6 张小法术"的循环。
    # docs/数值设计_v2.0.md §B 里这 5 张按 v2.0 费用（0–1 费 / 1–3 蓝）设计；
    # 本工程当前跑的还是 v1.0 数值，蓝耗折算到「最廉价档(4 蓝)与常规档(8 蓝)之间」，
    # 保证确实能每回合连发、又不至于零成本。
    # ⚠️ v2.0 正式落地时这 5 张会被统一重写（改回 0–1 费 / 1–3 蓝），请勿以本处数值为准。
    # 默认卡组不动（22 张基准不动摇平衡基线），新法术从商人 / 任务 / 宝箱获取。
    ("spark", "火花术", "造成 0.5 倍法术伤害，蓝耗极低。",
     "ATTACK", "MAGICAL", 0.5, None, None, 0, 3, "SINGLE_ENEMY", "COMMON", [], C_FIRE),
    ("wind_blade", "风刃", "造成 1.0 倍法术伤害，蓝耗低，适合连打。",
     "ATTACK", "MAGICAL", 1.0, None, None, 1, 6, "SINGLE_ENEMY", "COMMON", [], C_MAG),
    ("ice_shard", "冰锥", "造成 0.9 倍法术伤害，并削弱目标物抗。",
     "ATTACK", "MAGICAL", 0.9, None, None, 1, 6, "SINGLE_ENEMY", "COMMON",
     ["DEBUFF_DEFENSE"], C_ICE),
    ("static_bolt", "静电束", "造成 1.0 倍法术伤害；目标带盾时提升至 1.5 倍。",
     "ATTACK", "MAGICAL", 1.0, None, None, 1, 6, "SINGLE_ENEMY", "RARE",
     ["BONUS_VS_SHIELD"], C_MAG),
    ("flame_wave", "焰浪", "对所有敌人造成 0.6 倍法术伤害。",
     "ATTACK", "MAGICAL", 0.6, None, None, 1, 6, "ALL_ENEMIES", "RARE", [], C_FIRE),

    # ============ 防御卡 ============
    ("guard_phys", "普通物理防御", "获得 2.0 倍物抗的护盾，持续到本回合结束。",
     "DEFENSE", "NONE", None, 2.0, None, 1, 0, "SELF", "COMMON", [], C_GUARD),
    ("guard_mag", "普通法术防御", "获得 2.0 倍法抗的护盾，持续到本回合结束。",
     "DEFENSE", "MAGICAL", None, 2.0, None, 1, 6, "SELF", "COMMON", [], C_GUARD),
    ("iron_wall", "铁壁", "获得 3.5 倍物抗的护盾，持续到本回合结束。",
     "DEFENSE", "NONE", None, 3.5, None, 2, 0, "SELF", "RARE", [], C_GUARD),
    ("mana_barrier", "法力屏障", "获得 3.5 倍法抗的护盾，持续到本回合结束。",
     "DEFENSE", "NONE", None, 3.5, None, 2, 8, "SELF", "RARE", [], C_MAG),
    ("bulwark", "壁垒", "为全体队友提供 1.5 倍物抗的护盾。",
     "DEFENSE", "NONE", None, 1.5, None, 3, 0, "ALL_ALLIES", "EPIC", [], C_GUARD),
    ("ward", "守护结界", "为全体队友提供 1.5 倍法抗的护盾。",
     "DEFENSE", "NONE", None, 1.5, None, 3, 15, "ALL_ALLIES", "EPIC", [], C_MAG),
    ("parry", "格挡", "获得 1.2 倍物抗的护盾，几乎不消耗行动值。",
     "DEFENSE", "NONE", None, 1.2, None, 0, 0, "SELF", "COMMON", [], C_GUARD),
    ("aegis", "神盾", "获得 5.0 倍物抗的护盾，持续到本回合结束。",
     "DEFENSE", "PHYSICAL", None, 5.0, None, 3, 0, "SELF", "LEGENDARY", [], C_HOLY),

    # ============ 特殊卡 · 治疗 ============
    ("heal", "治愈术", "恢复相当于 2.0 倍智力的血量。",
     "SPECIAL", "NONE", None, None, 2.0, 2, 10, "SINGLE_ALLY", "RARE", [], C_HEAL),
    ("greater_heal", "高级治愈术", "恢复相当于 3.5 倍智力的血量。",
     "SPECIAL", "NONE", None, None, 3.5, 3, 20, "SINGLE_ALLY", "EPIC", [], C_HEAL),
    ("mass_heal", "群体治愈", "为全体队友恢复相当于 1.5 倍智力的血量。",
     "SPECIAL", "NONE", None, None, 1.5, 4, 28, "ALL_ALLIES", "LEGENDARY", [], C_HEAL),
    ("resurrect", "复活术", "使一名濒死成员以 1 点血量回到战斗。",
     "SPECIAL", "NONE", None, None, None, 3, 25, "SINGLE_ALLY", "LEGENDARY",
     ["REVIVE"], C_HOLY),

    # ============ 特殊卡 · 增益 ============
    ("inspire", "激励", "使一名队友的行动值提升。",
     "SPECIAL", "NONE", None, None, None, 1, 0, "SINGLE_ALLY", "COMMON",
     ["BUFF_ACTION"], C_SUPPORT),
    ("battle_cry", "战吼", "使全体队友的行动值提升。",
     "SPECIAL", "NONE", None, None, None, 3, 12, "ALL_ALLIES", "EPIC",
     ["BUFF_ACTION"], C_SUPPORT),
    ("focus", "专注", "提升一名队友的技巧，增加暴击概率。",
     "SPECIAL", "NONE", None, None, None, 2, 8, "SINGLE_ALLY", "RARE", [], C_SUPPORT),
    ("blessing", "祝福", "提升一名队友的物攻与法攻。",
     "SPECIAL", "NONE", None, None, None, 2, 12, "SINGLE_ALLY", "EPIC", [], C_HOLY),
    ("haste", "疾行", "使一名队友立即获得额外行动值。",
     "SPECIAL", "NONE", None, None, None, 1, 8, "SINGLE_ALLY", "RARE",
     ["BUFF_ACTION"], C_SUPPORT),

    # ============ 特殊卡 · 减益 ============
    ("weaken", "弱化", "使一名敌人的物抗大幅下降。",
     "SPECIAL", "NONE", None, None, None, 2, 8, "SINGLE_ENEMY", "RARE",
     ["DEBUFF_DEFENSE"], C_DARK),
    ("sunder", "破甲", "使一名敌人的物抗下降。",
     "SPECIAL", "NONE", None, None, None, 2, 10, "SINGLE_ENEMY", "RARE",
     ["DEBUFF_DEFENSE"], C_DARK),
    ("curse", "诅咒", "使一名敌人的法抗下降。",
     "SPECIAL", "NONE", None, None, None, 2, 10, "SINGLE_ENEMY", "RARE",
     ["DEBUFF_DEFENSE"], C_DARK),
    ("terror", "恐惧", "使全体敌人的技巧下降，降低其暴击概率。",
     "SPECIAL", "NONE", None, None, None, 3, 18, "ALL_ENEMIES", "EPIC", [], C_DARK),
    ("disarm", "卸甲", "使一名敌人的物攻下降。",
     "SPECIAL", "NONE", None, None, None, 2, 12, "SINGLE_ENEMY", "RARE", [], C_DARK),

    # ============ 特殊卡 · 抽牌 / 功能 ============
    ("insight", "洞察", "抽 2 张牌。",
     "SPECIAL", "NONE", None, None, None, 1, 0, "SELF", "COMMON",
     ["DRAW"], C_SUPPORT),
    ("deep_thought", "深思", "抽 3 张牌，并获得少量蓝量。",
     "SPECIAL", "NONE", None, None, None, 2, 0, "SELF", "RARE",
     ["DRAW"], C_MAG),
    ("second_wind", "重整旗鼓", "使一名队友恢复行动值并抽 1 张牌。",
     "SPECIAL", "NONE", None, None, None, 2, 5, "SINGLE_ALLY", "RARE",
     ["BUFF_ACTION", "DRAW"], C_SUPPORT),

    # ============ 共鸣体系 · 组件卡（9-23 需求，9-24 按用户意见重构）============
    # 组件卡打出后没有任何直接效果，只把本组的一个部件登记进「共鸣槽」（全队共享）。
    # 本回合内凑齐同组全部部件后，才能打出该组的「联合卡本体」（见下方）。
    # 0 行动点、只吃 2 点蓝 —— 刻意让"凑不齐"也不至于卡手。
    # ⚠️ 描述必须短：卡面下半框在城镇卡尺寸下只装得下约 3 行 8px 字。
    #    （用 scripts/_probe_descfit.gd 量，见 SKILL 的卡面文字预算一节）
    ("rune_wind", "风之符文",
     "与同组组件同回合打出，本卡无直接效果。",
     "SPECIAL", "MAGICAL", None, None, None, 0, 2, "SELF", "RARE", ["COMBO"], C_MAG),
    ("rune_fire", "火之符文",
     "与同组组件同回合打出，本卡无直接效果。",
     "SPECIAL", "MAGICAL", None, None, None, 0, 2, "SELF", "RARE", ["COMBO"], C_FIRE),
    ("rune_frost", "霜之符文",
     "与同组组件同回合打出，本卡无直接效果。",
     "SPECIAL", "MAGICAL", None, None, None, 0, 2, "SELF", "RARE", ["COMBO"], C_ICE),
    ("rune_thunder", "雷之符文",
     "与同组组件同回合打出，本卡无直接效果。",
     "SPECIAL", "MAGICAL", None, None, None, 0, 2, "SELF", "RARE", ["COMBO"], C_MAG),

    # ============ 共鸣体系 · 联合卡本体 ============
    # 高强度卡，但有前置条件：必须在本回合内先打出该组全部组件卡才能打出，
    # 打出后消耗掉这些部件（本回合该组不能再发动）。
    # multiplier 由 PAYOFFS 表统一注入（CARDS 这一列必须写 None，避免两处数值打架）。
    ("fire_tornado", "风火龙卷",
     "凑齐前置后，对全体敌人造成 3.0 倍法伤。",
     "ATTACK", "MAGICAL", None, None, None, 5, 30, "ALL_ENEMIES", "LEGENDARY",
     ["COMBO"], C_FIRE),
    ("frost_thunder", "霜雷裁决",
     "凑齐前置后，对全体敌人造成 2.0 倍法伤。",
     "ATTACK", "MAGICAL", None, None, None, 5, 22, "ALL_ENEMIES", "EPIC",
     ["COMBO", "BONUS_VS_SHIELD"], C_ICE),
]


# ---------------------------------------------------------------------------
# 共鸣（联合卡牌）表 —— 9-23 需求，9-24 重构为「组件 → 前置条件 → 联合卡本体」
#
# COMPONENTS：组件卡 → 属于哪一组、自己是哪个部件、本组需要哪些部件。
# PAYOFFS   ：联合卡本体 → 本组需要哪些部件、打出后的全体伤害倍率、卡面前置提示。
#
# 单独打出组件卡没有任何效果；同一回合内凑齐本组全部部件后，
# 该组的联合卡本体才可打出（部件可以由同一名角色连出，也可以两名角色各出一张）。
# ---------------------------------------------------------------------------
COMPONENTS = {
    "rune_wind": {
        "key": "fire_tornado", "name": "风火龙卷", "part": "wind",
        "need": ["wind", "fire"],
    },
    "rune_fire": {
        "key": "fire_tornado", "name": "风火龙卷", "part": "fire",
        "need": ["wind", "fire"],
    },
    "rune_frost": {
        "key": "frost_thunder", "name": "霜雷裁决", "part": "frost",
        "need": ["frost", "thunder"],
    },
    "rune_thunder": {
        "key": "frost_thunder", "name": "霜雷裁决", "part": "thunder",
        "need": ["frost", "thunder"],
    },
}

PAYOFFS = {
    "fire_tornado": {
        "key": "fire_tornado", "name": "风火龙卷",
        "need": ["wind", "fire"], "mult": 3.0,
        "desc": "风 + 火",
    },
    "frost_thunder": {
        "key": "frost_thunder", "name": "霜雷裁决",
        "need": ["frost", "thunder"], "mult": 2.0,
        "desc": "霜 + 雷",
    },
}


def build_card_tres(c):
    (cid, name, desc, cclass, dtype, mult, smult, hmult,
     acost, mcost, ttype, rarity, tags, color) = c

    # 9-22 修改意见 7：六分类（物理/法术 × 进攻/防御/特殊）。
    # 规则：物理卡不耗蓝、法术卡耗蓝 —— 所以按蓝耗推导 damage_type，
    # 保证「物理卡蓝耗 == 0 且法术卡蓝耗 > 0」永远成立。
    effective_dtype = "MAGICAL" if (mcost or 0) > 0 else "PHYSICAL"

    # 行动消耗按新经济下调（见 ACTION_COST_MAP / ACTION_COST_OVERRIDE）
    acost = ACTION_COST_OVERRIDE.get(cid, ACTION_COST_MAP.get(acost, acost))

    # 联合卡本体的伤害倍率只在 PAYOFFS 表里写一份，CARDS 那一列必须留空，
    # 否则两处数值迟早打架。
    payoff = PAYOFFS.get(cid)
    if payoff is not None:
        assert mult is None, "联合卡 %s 的 multiplier 请写 None，由 PAYOFFS 表统一注入" % cid
        mult = payoff["mult"]

    lines = [
        '[gd_resource type="Resource" script_class="CardData" load_steps=2 format=3]',
        '',
        '[ext_resource type="Script" path="res://scripts/core/card_data.gd" id="1"]',
        '',
        '[resource]',
        'script = ExtResource("1")',
        f'id = "{cid}"',
        f'display_name = "{name}"',
        f'description = "{desc}"',
        f'card_class = {CARD_CLASS[cclass]}',
        f'damage_type = {DAMAGE_TYPE[effective_dtype]}',
    ]
    if mult is not None:
        lines.append(f'multiplier = {mult}')
    if smult is not None:
        lines.append(f'shield_multiplier = {smult}')
    if hmult is not None:
        lines.append(f'heal_multiplier = {hmult}')
    lines.append(f'action_cost = {acost}')
    lines.append(f'mana_cost = {mcost}')
    lines.append(f'target_type = {TARGET_TYPE[ttype]}')
    lines.append(f'rarity = {RARITY[rarity]}')
    if tags:
        joined = ", ".join(f'"{t}"' for t in tags)
        lines.append(f'effect_tags = [{joined}]')
    else:
        lines.append('effect_tags = []')
    lines.append(f'art_placeholder = "{color}"')

    # 共鸣体系：组件卡写"自己是什么部件"，联合卡本体写"需要哪些前置条件"
    comp = COMPONENTS.get(cid)
    if comp is not None:
        need = ", ".join(f'"{p}"' for p in comp["need"])
        lines.append(f'combo_key = "{comp["key"]}"')
        lines.append(f'combo_name = "{comp["name"]}"')
        lines.append(f'combo_part = "{comp["part"]}"')
        lines.append(f'combo_complete = [{need}]')
        lines.append('combo_multiplier = 0.0')
        lines.append(f'combo_desc = "解锁「{comp["name"]}」"')
        lines.append('combo_payoff = false')
    elif payoff is not None:
        need = ", ".join(f'"{p}"' for p in payoff["need"])
        lines.append(f'combo_key = "{payoff["key"]}"')
        lines.append(f'combo_name = "{payoff["name"]}"')
        lines.append('combo_part = ""')
        lines.append(f'combo_complete = [{need}]')
        lines.append(f'combo_multiplier = {payoff["mult"]}')
        lines.append(f'combo_desc = "{payoff["desc"]}"')
        lines.append('combo_payoff = true')

    lines.append('')
    return "\n".join(lines)

# ---------------------------------------------------------------------------
# 物品卡牌数据表
# 字段：(id, 名称, 描述, item_class, slot, stats_bonus, precious, sell,
#        usable_in_battle, color)
# ---------------------------------------------------------------------------
ITEMS = [
    # ============ 装备 · 头部 ============
    ("leather_cap", "皮帽", "冒险者的入门装备。", "EQUIPMENT", "HEAD",
     {"phys_res": 3, "hp": 10}, 5, 5, False, "#D3D1C7"),
    ("iron_helm", "铁盔", "厚重的铁制头盔。", "EQUIPMENT", "HEAD",
     {"phys_res": 8, "hp": 20}, 20, 25, False, "#888780"),
    ("mage_hood", "法师兜帽", "织入符文的兜帽，提升法力。", "EQUIPMENT", "HEAD",
     {"mag_res": 10, "mana": 15}, 35, 60, False, "#85B7EB"),
    ("crown_of_wisdom", "智慧之冠", "传说中贤者的冠冕。", "EQUIPMENT", "HEAD",
     {"mag_res": 18, "mag_atk": 12, "mana": 30}, 80, 400, False, "#FAC775"),

    # ============ 装备 · 颈部 ============
    ("wooden_charm", "木质护符", "刻着粗陋纹路的护符。", "EQUIPMENT", "NECK",
     {"technique": 4}, 8, 8, False, "#D3D1C7"),
    ("silver_pendant", "银质吊坠", "微微发光的银色吊坠。", "EQUIPMENT", "NECK",
     {"technique": 8, "luck": 2}, 30, 50, False, "#B5D4F4"),
    ("lucky_clover", "幸运四叶草", "据说是幸运的象征。", "EQUIPMENT", "NECK",
     {"luck": 8}, 45, 120, False, "#97C459"),
    ("eye_of_fate", "命运之眼", "能窥见命运轨迹的宝石。", "EQUIPMENT", "NECK",
     {"technique": 15, "luck": 6, "mag_atk": 8}, 75, 350, False, "#AFA9EC"),

    # ============ 装备 · 身体 ============
    ("cloth_robe", "布袍", "最普通的旅行衣物。", "EQUIPMENT", "BODY",
     {"hp": 15, "phys_res": 2}, 4, 4, False, "#D3D1C7"),
    ("chain_mail", "锁子甲", "由细密铁环编成的护甲。", "EQUIPMENT", "BODY",
     {"hp": 35, "phys_res": 10}, 25, 40, False, "#888780"),
    ("plate_armor", "板甲", "全身覆盖的重甲。", "EQUIPMENT", "BODY",
     {"hp": 60, "phys_res": 18}, 60, 180, False, "#5F5E5A"),
    ("arcane_vestment", "奥术法袍", "以魔力编织的长袍。", "EQUIPMENT", "BODY",
     {"hp": 25, "mag_res": 15, "mag_atk": 10}, 50, 150, False, "#AFA9EC"),
    ("dragon_scale", "龙鳞甲", "以幼龙鳞片打造的甲胄。", "EQUIPMENT", "BODY",
     {"hp": 90, "phys_res": 22, "mag_res": 15}, 95, 800, False, "#E24B4A"),

    # ============ 装备 · 手部 ============
    ("leather_gloves", "皮手套", "磨损的皮制手套。", "EQUIPMENT", "HAND",
     {"phys_atk": 3}, 5, 5, False, "#D3D1C7"),
    ("gauntlet", "铁护手", "包覆铁片的护手。", "EQUIPMENT", "HAND",
     {"phys_atk": 7, "phys_res": 3}, 22, 35, False, "#888780"),
    ("marksman_glove", "射手手套", "便于搭弦的精细手套。", "EQUIPMENT", "HAND",
     {"phys_atk": 9, "technique": 6}, 40, 100, False, "#85B7EB"),
    ("gauntlet_of_might", "巨力护手", "蕴含巨人之力的护手。", "EQUIPMENT", "HAND",
     {"phys_atk": 22, "phys_res": 8}, 78, 450, False, "#D85A30"),

    # ============ 装备 · 腿部 ============
    ("cloth_pants", "布裤", "普通的布料裤子。", "EQUIPMENT", "LEG",
     {"action": 1, "hp": 8}, 4, 4, False, "#D3D1C7"),
    ("greaves", "胫甲", "保护小腿的金属护具。", "EQUIPMENT", "LEG",
     {"phys_res": 6, "hp": 15}, 24, 35, False, "#888780"),
    ("swift_leggings", "疾行护腿", "轻便的皮革护腿。", "EQUIPMENT", "LEG",
     {"action": 2, "technique": 5}, 45, 130, False, "#97C459"),
    ("boots_of_hermes", "神行之腿甲", "让穿戴者步履如飞。", "EQUIPMENT", "LEG",
     {"action": 4, "phys_res": 10}, 85, 500, False, "#FAC775"),

    # ============ 装备 · 脚部 ============
    ("worn_boots", "破旧靴子", "走了很多路的靴子。", "EQUIPMENT", "FOOT",
     {"action": 1}, 3, 3, False, "#D3D1C7"),
    ("iron_boots", "铁靴", "沉重的金属战靴。", "EQUIPMENT", "FOOT",
     {"phys_res": 5, "mag_res": 3}, 20, 30, False, "#888780"),
    ("shadow_boots", "影靴", "落地无声的软靴。", "EQUIPMENT", "FOOT",
     {"action": 2, "technique": 6}, 48, 140, False, "#AFA9EC"),
    ("windwalkers", "风行者", "踏风而行的秘靴。", "EQUIPMENT", "FOOT",
     {"action": 3, "mag_res": 12, "technique": 8}, 82, 480, False, "#9FE1CB"),

    # ============ 装备 · 单手武器 ============
    ("rusty_sword", "锈剑", "锈迹斑斑的单手剑。", "EQUIPMENT", "WEAPON",
     {"phys_atk": 5}, 4, 4, False, "#B4B2A9"),
    ("short_sword", "短剑", "轻便可靠的短剑。", "EQUIPMENT", "WEAPON",
     {"phys_atk": 10, "technique": 3}, 22, 35, False, "#888780"),
    ("flame_blade", "烈焰之刃", "剑刃常燃不灭。", "EQUIPMENT", "WEAPON",
     {"phys_atk": 18, "mag_atk": 8}, 55, 200, False, "#D85A30"),
    ("frost_rapier", "寒霜细剑", "剑身覆着永不融化的霜。", "EQUIPMENT", "WEAPON",
     {"phys_atk": 20, "technique": 10}, 65, 260, False, "#9FE1CB"),
    ("warlord_blade", "战王之刃", "属于某位战王的遗物。", "EQUIPMENT", "WEAPON",
     {"phys_atk": 32, "technique": 12, "hp": 20}, 92, 900, False, "#E24B4A"),

    # ============ 装备 · 双手武器 ============
    ("wooden_staff", "木杖", "法师的入门法器。", "EQUIPMENT", "WEAPON",
     {"mag_atk": 6, "mana": 8}, 6, 6, False, "#D3D1C7"),
    ("battle_axe", "战斧", "沉重的双手斧。", "EQUIPMENT", "WEAPON",
     {"phys_atk": 20}, 30, 60, False, "#888780"),
    ("greatsword", "巨剑", "需要全力才能挥动的大剑。", "EQUIPMENT", "WEAPON",
     {"phys_atk": 30, "phys_res": 5}, 58, 220, False, "#5F5E5A"),
    ("archmage_staff", "大法师法杖", "顶端嵌着硕大魔晶的法杖。", "EQUIPMENT", "WEAPON",
     {"mag_atk": 35, "mana": 40, "mag_res": 10}, 88, 650, False, "#AFA9EC"),
    ("world_breaker", "碎界", "传说能劈开山岳的巨斧。", "EQUIPMENT", "WEAPON",
     {"phys_atk": 55, "phys_res": 15}, 98, 1500, False, "#501313"),

    # ============ 装备 · 远程武器 ============
    ("short_bow", "短弓", "猎人常用的短弓。", "EQUIPMENT", "WEAPON",
     {"phys_atk": 7, "technique": 4}, 8, 10, False, "#D3D1C7"),
    ("hunting_bow", "猎弓", "做工精良的猎弓。", "EQUIPMENT", "WEAPON",
     {"phys_atk": 14, "technique": 7}, 32, 70, False, "#97C459"),
    ("elven_bow", "精灵长弓", "以精灵工艺打造的长弓。", "EQUIPMENT", "WEAPON",
     {"phys_atk": 24, "technique": 14}, 70, 380, False, "#5DCAA5"),
    ("storm_bow", "风暴之弓", "拉弦时有雷鸣相伴。", "EQUIPMENT", "WEAPON",
     {"phys_atk": 38, "technique": 20}, 94, 1100, False, "#85B7EB"),

    # ============ 道具 · 消耗品 ============
    ("health_potion", "回血瓶", "恢复少量血量。", "CONSUMABLE", "NONE",
     {}, 5, 15, True, "#E24B4A"),
    ("greater_health_potion", "高级回血瓶", "恢复大量血量。", "CONSUMABLE", "NONE",
     {}, 25, 50, True, "#A32D2D"),
    ("mana_potion", "回蓝瓶", "恢复少量蓝量。", "CONSUMABLE", "NONE",
     {}, 5, 15, True, "#378ADD"),
    ("greater_mana_potion", "高级回蓝瓶", "恢复大量蓝量。", "CONSUMABLE", "NONE",
     {}, 25, 50, True, "#185FA5"),
    ("antidote", "解毒剂", "解除负面状态。", "CONSUMABLE", "NONE",
     {}, 12, 25, True, "#97C459"),
    ("luck_potion", "幸运提升药水", "暂时提升幸运值。", "CONSUMABLE", "NONE",
     {}, 60, 200, True, "#FAC775"),
    ("bomb", "爆裂弹", "对全体敌人造成伤害。", "CONSUMABLE", "NONE",
     {}, 18, 40, True, "#D85A30"),
    ("smoke_bomb", "烟雾弹", "立即脱离战斗。", "CONSUMABLE", "NONE",
     {}, 35, 90, True, "#888780"),

    # ============ 收集品 ============
    ("victory_crown", "胜利王冠", "胜者才能戴上的王冠。", "COLLECTIBLE", "NONE",
     {}, 90, 500, False, "#EF9F27"),
    ("radiant_crystal", "光辉水晶", "内部流转着光辉的晶体。", "COLLECTIBLE", "NONE",
     {}, 70, 300, False, "#B5D4F4"),
    ("ancient_coin", "古代金币", "早已停止流通的古老货币。", "COLLECTIBLE", "NONE",
     {}, 55, 200, False, "#FAC775"),
    ("jade_idol", "翡翠神像", "雕刻着未知神祇的翠绿雕像。", "COLLECTIBLE", "NONE",
     {}, 80, 400, False, "#5DCAA5"),
    ("musical_box", "八音盒", "打开会响起陌生旋律。", "COLLECTIBLE", "NONE",
     {}, 40, 120, False, "#ED93B1"),
    ("hero_medal", "勇者勋章", "授予真正勇者的勋章。", "COLLECTIBLE", "NONE",
     {}, 100, 1000, False, "#E24B4A"),

    # ============ 战利品 ============
    ("boar_tusk", "野猪怪獠牙", "野猪怪掉落的粗糙獠牙。", "TROPHY", "NONE",
     {}, 10, 12, False, "#C0DD97"),
    ("boar_king_tusk", "野猪人王獠牙", "巨大而锋利的獠牙。", "TROPHY", "NONE",
     {}, 40, 80, False, "#993C1D"),
    ("bat_wing", "吸血蝙蝠翅膀", "薄如蝉翼的黑色翅膀。", "TROPHY", "NONE",
     {}, 12, 15, False, "#AFA9EC"),
    ("goblin_ear", "地精耳朵", "尖长的绿色耳朵。", "TROPHY", "NONE",
     {}, 8, 10, False, "#97C459"),
    ("wolf_pelt", "狼皮", "厚实保暖的狼皮。", "TROPHY", "NONE",
     {}, 15, 22, False, "#B4B2A9"),
    ("spider_silk", "蛛丝腺", "能纺出坚韧丝线的腺体。", "TROPHY", "NONE",
     {}, 20, 30, False, "#D3D1C7"),
    ("dragon_scale_trophy", "龙鳞", "坚硬的龙鳞，极为稀有。", "TROPHY", "NONE",
     {}, 75, 300, False, "#E24B4A"),
    ("demon_horn", "恶魔之角", "散发不祥气息的弯角。", "TROPHY", "NONE",
     {}, 85, 450, False, "#712B13"),

    # ============ 杂物 ============
    ("broken_sword", "破旧的剑", "已经折断无法使用的剑。", "JUNK", "NONE",
     {}, 2, 2, False, "#B4B2A9"),
    ("torn_notebook", "残破的笔记本", "字迹模糊，只剩几页可读。", "JUNK", "NONE",
     {}, 3, 3, False, "#D3D1C7"),
    ("cracked_pot", "裂缝陶罐", "缺了口子的陶罐。", "JUNK", "NONE",
     {}, 1, 1, False, "#D3D1C7"),
    ("old_bone", "陈旧骨头", "不知是什么生物的骨头。", "JUNK", "NONE",
     {}, 1, 1, False, "#F1EFE8"),
    ("rusty_key", "生锈的钥匙", "不知道能打开什么。", "JUNK", "NONE",
     {}, 4, 5, False, "#854F0B"),
    ("torn_cloth", "破烂布条", "散发着霉味的布条。", "JUNK", "NONE",
     {}, 1, 1, False, "#D3D1C7"),
]


def build_item_tres(it):
    (iid, name, desc, iclass, slot, bonus, precious, sell, usable, color) = it

    if bonus:
        parts = []
        for k, v in bonus.items():
            parts.append(f'"{k}": {v}')
        bonus_str = "{" + ", ".join(parts) + "}"
    else:
        bonus_str = "{}"

    lines = [
        '[gd_resource type="Resource" script_class="ItemData" load_steps=2 format=3]',
        '',
        '[ext_resource type="Script" path="res://scripts/core/item_data.gd" id="1"]',
        '',
        '[resource]',
        'script = ExtResource("1")',
        f'id = "{iid}"',
        f'display_name = "{name}"',
        f'description = "{desc}"',
        f'item_class = {ITEM_CLASS[iclass]}',
        f'slot = {SLOT[slot]}',
        f'stats_bonus = {bonus_str}',
        f'precious_value = {precious}',
        f'sell_price = {sell}',
        f'usable_in_battle = {"true" if usable else "false"}',
        f'art_placeholder = "{color}"',
        '',
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# 怪物数据表（数值遵循 数值设计 v1.0 第八节的层级基准）
# 字段：(id, 名称, 描述, hp, phys_atk, mag_atk, phys_res, mag_res,
#        technique, tier, level, ai, drop_table, color)
# ---------------------------------------------------------------------------
MONSTERS = [
    # ===== 第 1 层：战力 70–110，血量 35–50，物攻 10–14 =====
    ("boar", "野猪怪", "地牢入口常见的野兽，皮糙肉厚。",
     42, 12, 0, 6, 4, 4, "NORMAL", 1, "AGGRESSIVE", "boar_drop", "#97C459"),
    ("cave_bat", "洞穴蝙蝠", "群居于地牢顶部，行动迅速而难以命中。",
     35, 14, 0, 3, 6, 8, "NORMAL", 1, "RANDOM", "cave_bat_drop", "#AFA9EC"),
    ("goblin", "地精", "矮小狡猾，惯于偷袭。",
     38, 11, 4, 5, 5, 6, "NORMAL", 1, "RANDOM", "goblin_drop", "#C0DD97"),
    ("skeleton", "骷髅兵", "不知疲倦的亡灵守墓者。",
     45, 13, 0, 8, 5, 3, "NORMAL", 1, "AGGRESSIVE", "skeleton_drop", "#F1EFE8"),
    ("giant_rat", "巨鼠", "地牢下水道里肥硕的老鼠。",
     30, 10, 0, 2, 2, 5, "NORMAL", 1, "AGGRESSIVE", "rat_drop", "#B4B2A9"),
    ("goblin_shaman", "地精萨满", "手持骨杖，能施放微弱法术。",
     70, 12, 18, 8, 10, 10, "ELITE", 1, "DEFENSIVE", "shaman_drop", "#5DCAA5"),
    ("boar_king", "野猪人王", "野猪人的首领，獠牙上挂着旧日冒险者的护符。",
     160, 26, 10, 9, 10, 8, "BOSS", 1, "AGGRESSIVE", "boar_king_drop", "#993C1D"),

    # ===== 第 2 层：战力 150–220，血量 55–75，物攻 18–24 =====
    ("hobgoblin", "大地精", "比地精更强壮、更有组织的战士。",
     68, 20, 0, 12, 8, 6, "NORMAL", 2, "AGGRESSIVE", "hobgoblin_drop", "#97C459"),
    ("dire_wolf", "凶狼", "成群狩猎，配合默契。",
     60, 23, 0, 8, 6, 14, "NORMAL", 2, "RANDOM", "wolf_drop", "#888780"),
    ("cave_spider", "洞穴巨蛛", "结网捕猎，毒液致命。",
     65, 19, 8, 7, 10, 16, "NORMAL", 2, "RANDOM", "spider_drop", "#AFA9EC"),
    ("ghoul", "食尸鬼", "以腐肉为食的亡灵。",
     75, 21, 6, 10, 12, 5, "NORMAL", 2, "AGGRESSIVE", "ghoul_drop", "#D3D1C7"),
    ("hobgoblin_captain", "大地精队长", "率领地精部队的指挥官。",
     140, 26, 8, 16, 12, 12, "ELITE", 2, "AGGRESSIVE", "captain_drop", "#854F0B"),
    ("goblin_chief", "地精酋长", "统御回廊的残暴统治者。",
     380, 34, 18, 20, 16, 12, "BOSS", 2, "AGGRESSIVE", "chief_drop", "#3B6D11"),

    # ===== 第 3 层：战力 280–420，血量 80–110，物攻 28–38 =====
    ("ogre", "食人魔", "力大无穷，行动迟缓。",
     100, 34, 0, 15, 8, 4, "NORMAL", 3, "AGGRESSIVE", "ogre_drop", "#993C1D"),
    ("dark_knight", "黑暗骑士", "背叛誓约的堕落骑士。",
     95, 32, 10, 22, 16, 10, "NORMAL", 3, "AGGRESSIVE", "knight_drop", "#5F5E5A"),
    ("wraith", "幽魂", "由怨恨凝结而成的虚影。",
     80, 12, 34, 6, 22, 18, "NORMAL", 3, "RANDOM", "wraith_drop", "#AFA9EC"),
    ("basilisk", "石化蜥蜴", "目光所及之处皆化为石头。",
     110, 30, 14, 20, 14, 12, "NORMAL", 3, "DEFENSIVE", "basilisk_drop", "#5DCAA5"),
    ("troll", "巨魔", "伤口会迅速愈合的怪物。",
     160, 36, 6, 24, 12, 8, "ELITE", 3, "AGGRESSIVE", "troll_drop", "#3B6D11"),
    ("abyss_warden", "深渊守门人", "镇守深渊裂口的古老存在。",
     600, 46, 30, 30, 24, 16, "BOSS", 3, "DEFENSIVE", "warden_drop", "#5F5E5A"),

    # ===== 第 4 层：战力 500–750，血量 120–160，物攻 42–58 =====
    ("fire_elemental", "火元素", "燃烧着永恒之焰的元素生物。",
     130, 30, 44, 14, 26, 14, "NORMAL", 4, "AGGRESSIVE", "elemental_drop", "#D85A30"),
    ("stone_golem", "石魔像", "由魔法驱动的岩石巨像。",
     160, 48, 0, 34, 18, 4, "NORMAL", 4, "DEFENSIVE", "golem_drop", "#888780"),
    ("vampire", "吸血鬼", "以鲜血维生的贵族亡灵。",
     140, 46, 30, 22, 24, 22, "NORMAL", 4, "RANDOM", "vampire_drop", "#993556"),
    ("wyvern", "双足飞龙", "喷吐毒液的亚龙。",
     150, 50, 24, 26, 20, 18, "NORMAL", 4, "AGGRESSIVE", "wyvern_drop", "#97C459"),
    ("death_knight", "死亡骑士", "被诅咒束缚的传奇战士。",
     260, 58, 20, 36, 28, 18, "ELITE", 4, "AGGRESSIVE", "dk_drop", "#2C2C2A"),
    ("witch_king", "巫王", "墓庭的主人，掌握着禁忌之术。",
     900, 62, 60, 40, 38, 24, "BOSS", 4, "DEFENSIVE", "witchking_drop", "#26215C"),

    # ===== 第 5 层+：战力 800+，血量 180+ =====
    ("abyss_lord", "深渊领主", "自深渊裂隙中降下的灾厄。",
     1500, 85, 70, 50, 46, 30, "BOSS", 5, "AGGRESSIVE", "abyss_drop", "#501313"),
]

# ---------------------------------------------------------------------------
# 关卡数据表
# 字段：(id, 名称, level_index, danger, pmin, pmax, entry_cost,
#        battle_w, treasure_w, event_w, monster_pool, elite_pool, boss_id, color)
# ---------------------------------------------------------------------------
DUNGEONS = [
    ("level_01", "新手地穴", 1, "D", 60, 100, 0, 70, 10, 20,
     ["boar", "cave_bat", "goblin", "giant_rat"], [], "boar_king", "#F1EFE8"),
    ("level_02", "幽暗回廊", 2, "C", 150, 220, 100, 70, 10, 20,
     ["hobgoblin", "dire_wolf", "cave_spider"], ["hobgoblin_captain"],
     "goblin_chief", "#E6F1FB"),
    ("level_03", "深渊裂口", 3, "B", 300, 420, 400, 70, 10, 20,
     ["ogre", "dark_knight", "wraith", "basilisk"], ["troll"],
     "abyss_warden", "#EFE9FE"),
    ("level_04", "巫王墓庭", 4, "A", 550, 750, 900, 70, 10, 20,
     ["fire_elemental", "stone_golem", "vampire", "wyvern"], ["death_knight"],
     "witch_king", "#F1EFE8"),
    ("level_05", "深渊之底", 5, "S", 900, 1300, 1600, 70, 10, 20,
     ["stone_golem", "vampire", "wyvern"], ["death_knight"],
     "abyss_lord", "#FCEBEB"),
]


def build_monster_tres(m):
    (mid, name, desc, hp, patk, matk, pres, mres, tech,
     tier, level, ai, drop, color) = m

    lines = [
        '[gd_resource type="Resource" script_class="MonsterData" load_steps=2 format=3]',
        '',
        '[ext_resource type="Script" path="res://scripts/core/monster_data.gd" id="1"]',
        '',
        '[resource]',
        'script = ExtResource("1")',
        f'id = "{mid}"',
        f'display_name = "{name}"',
        f'description = "{desc}"',
        f'hp = {hp}',
        f'phys_atk = {patk}',
        f'mag_atk = {matk}',
        f'phys_res = {pres}',
        f'mag_res = {mres}',
        f'technique = {tech}',
        f'monster_tier = {MONSTER_TIER[tier]}',
        f'dungeon_level = {level}',
        f'ai_pattern = {AI_PATTERN[ai]}',
        f'drop_table = "{drop}"',
        f'art_placeholder = "{color}"',
        '',
    ]
    return "\n".join(lines)


def build_dungeon_tres(d):
    (did, name, idx, danger, pmin, pmax, cost, bw, tw, ew,
     pool, elites, boss, color) = d

    pool_str = ", ".join(f'"{p}"' for p in pool)
    elite_str = ", ".join(f'"{e}"' for e in elites)

    lines = [
        '[gd_resource type="Resource" script_class="DungeonData" load_steps=2 format=3]',
        '',
        '[ext_resource type="Script" path="res://scripts/core/dungeon_data.gd" id="1"]',
        '',
        '[resource]',
        'script = ExtResource("1")',
        f'id = "{did}"',
        f'display_name = "{name}"',
        f'level_index = {idx}',
        f'danger_rating = {DANGER[danger]}',
        f'recommend_power_min = {pmin}',
        f'recommend_power_max = {pmax}',
        f'entry_cost = {cost}',
        'grid_cols = 3',
        'grid_rows = 7',
        f'node_weight_battle = {bw}',
        f'node_weight_treasure = {tw}',
        f'node_weight_event = {ew}',
        f'monster_pool = [{pool_str}]',
        f'elite_pool = [{elite_str}]',
        f'boss_id = "{boss}"',
        f'bg_placeholder = "{color}"',
        '',
    ]
    return "\n".join(lines)


def main():
    out_dir = os.path.join(ROOT, "data", "cards")
    os.makedirs(out_dir, exist_ok=True)

    written = 0
    for c in CARDS:
        path = os.path.join(out_dir, f"{c[0]}.tres")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(build_card_tres(c))
        written += 1

    print(f"[cards] generated {written} files -> {out_dir}")

    from collections import Counter
    by_class = Counter(c[3] for c in CARDS)
    by_rarity = Counter(c[11] for c in CARDS)
    print(f"  by class : {dict(by_class)}")
    print(f"  by rarity: {dict(by_rarity)}")

    item_dir = os.path.join(ROOT, "data", "items")
    os.makedirs(item_dir, exist_ok=True)

    written_items = 0
    for it in ITEMS:
        path = os.path.join(item_dir, f"{it[0]}.tres")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(build_item_tres(it))
        written_items += 1

    print(f"[items] generated {written_items} files -> {item_dir}")
    by_item = Counter(i[3] for i in ITEMS)
    print(f"  by class : {dict(by_item)}")

    mon_dir = os.path.join(ROOT, "data", "monsters")
    os.makedirs(mon_dir, exist_ok=True)

    written_mons = 0
    for m in MONSTERS:
        path = os.path.join(mon_dir, f"{m[0]}.tres")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(build_monster_tres(m))
        written_mons += 1

    print(f"[monsters] generated {written_mons} files -> {mon_dir}")
    by_tier = Counter(m[9] for m in MONSTERS)
    print(f"  by tier  : {dict(by_tier)}")

    dun_dir = os.path.join(ROOT, "data", "dungeons")
    os.makedirs(dun_dir, exist_ok=True)

    written_dun = 0
    for d in DUNGEONS:
        path = os.path.join(dun_dir, f"{d[0]}.tres")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(build_dungeon_tres(d))
        written_dun += 1

    print(f"[dungeons] generated {written_dun} files -> {dun_dir}")

    # 交叉校验：关卡引用的怪物必须存在
    monster_ids = {m[0] for m in MONSTERS}
    errors = []
    for d in DUNGEONS:
        refs = list(d[10]) + list(d[11]) + [d[12]]
        for r in refs:
            if r not in monster_ids:
                errors.append(f"{d[0]} references missing monster '{r}'")
    if errors:
        print("[validate] ERRORS:")
        for e in errors:
            print("  -", e)
    else:
        print("[validate] OK - all dungeon monster references resolved")


if __name__ == "__main__":
    main()
