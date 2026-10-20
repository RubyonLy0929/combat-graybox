# 角色、物品与最终属性数据层

本版本新增数据结构、最终属性计算器和现有灰盒的连接。按用户要求未运行测试、Godot解析检查或实机验证。旧 tests/validation.txt 仅代表此前战斗灰盒，不代表本版本验证结果。

## 文件与编辑入口

| 入口 | 用途 |
|---|---|
| data/default_character.tres | 角色基础属性；在Godot Inspector编辑 |
| data/stat_config.tres | 成长、上限、负重和减伤系数；目前为初始调参值 |
| data/items/*.tres | 29个可编辑示例：5武器、18防具、2饰品、2背包、1材料、1任务物品 |
| scripts/data/*_definition.gd | 共享物品定义及各类型字段 |
| scripts/systems/item_instance.gd | 单个物品实体、数量、旋转、坐标、锁定与真实减重 |
| scripts/systems/equipment_loadout.gd | 11个装备位置与当前武器 |
| scripts/systems/stat_calculator.gd | 无场景依赖的计算器及减伤/击退函数 |
| scripts/systems/character_state.gd | 角色实时状态、重算、穿脱、武器切换、恢复与金币接口 |

共享定义只存配置；不同物品实体引用同一份定义。不能在某一件物品上直接修改共享definition；实际减重与未来随机词缀属于实体数据。

## 通用物品字段

- id：稳定字符串ID，存档引用，不随显示名称变化。
- display_name、item_type、rarity：名称、类型、品质。
- price：非负整数金币价格，暂未实现买卖UI。
- weight：单件原始重量，统一以kg作为设计单位。
- grid_size、can_rotate：占格尺寸、是否允许90度旋转。
- max_stack：堆叠上限；装备必须单件。
- weightless：任务物品等免重标记。金币直接存角色gold，不是占格物品。
- flat：固定数值相加；概率字段用0.05表示5个百分点。
- percent：同属性百分比相加；0.10表示乘以1.10。
- effects：未来条件触发特效描述入口，当前不执行。

支持的flat/percent字段：strength、agility、constitution、spirit、max_health、max_mana、health_regen、mana_regen、magic_power、damage、defense、move_speed、move_multiplier、attack_speed、crit_chance、crit_multiplier、lifesteal、carry_capacity、knockback_resistance、burden_reduction。未知字段会列入breakdown.unknown_stats，不会静默影响属性。

例如flat={"agility": 3.0, "crit_chance": 0.05}与percent={"damage": 0.10}。

## 专用字段

| 类型 | 专用字段 |
|---|---|
| 武器 | weapon_type、base_damage、strength_scaling、agility_scaling、attack_template、damage_type、attack_range、impact_multiplier |
| 防具 | slot、armor_material、defense、knockback_resistance |
| 饰品 | 使用通用flat、percent、effects |
| 背包 | inventory_size、carry_capacity_bonus、burden_reduction |

布/轻/重标签仅作描述。每件防具靠实际防御、重量、抗击退和属性区分；自由混穿，无整体甲型隐含惩罚。专用defense与flat.defense会相加，避免无意重复配置。

weapon_type固定为sword/blade/whip/spear/bow；attack_template引用现有五种四连击模板。不同招式伤害比例沿用模板，以第一段为基准。attack_range、damage_type是后续技能与新攻击系统入口；当前灰盒判定范围仍来自weapons.gd，伤害按物理伤害处理。

## 装备位置

belt、body、legs、boots、gloves、helmet、accessory_1、accessory_2、weapon_a、weapon_b、backpack，共11个。

两把武器均计重量；仅active_weapon_slot对应的武器提供攻击力和通用属性。被切出的武器不再提供力量、负重上限等属性。装备系统没有持握方式或职业限制。

Q在就绪时切换已有实体，不创建新武器，不回生命/法力；0.35秒切换冷却，不能取消当前攻击。旧1–5直接替换快捷键已移除，武器通过拾取与背包换装。

## 计算顺序

1. 收集生效装备与buffs的固定和百分比数值；buffs/技能被动可用相同的flat/percent结构，临时效果的持续时间由调用方管理。
2. 核心属性=(基础核心属性+固定值)×(1+百分比之和)。
3. 核心属性产生派生值。增长按max(0,属性-10)计算，默认10点为基线。
4. 派生属性=(基础派生值+成长值+装备固定值)×(1+百分比之和)。
5. 应用概率、攻速、移速、负担减免等上限。
6. 按实际重量、有效负担计算移动与攻速惩罚。

buffs同样受上限和负重影响；不允许临时加成绕过上限。breakdown包含stats、sources、flat_totals、percent_totals、unknown_stats。

## 初始成长系数（可调）

- 体质超过10的每点：生命+10、生命回复+0.05/秒。
- 精神超过10的每点：法力+5、法力回复+0.10/秒、魔法强度+1。
- 力量超过10的每点：负重上限+2kg；武器伤害按该武器力量系数增长。
- 敏捷增量x=max(0,敏捷-10)，收益曲线x/(x+40)。
- 移动倍率=1+0.4×x/(x+40)，所有装备和Buff合计的无负担移动速度最多基础移速1.4倍。
- 攻速=1+0.3×x/(x+40)，加成后上限1.3倍。
- 敏捷暴击收益最多15个百分点；总暴击率上限75%，默认暴击伤害1.5倍。
- 吸血上限30%；实际恢复按敌人实际损失生命计算，过量伤害/木偶/无敌目标不产生吸血。

生命上限增加不会立即回血；降低时当前生命截断到新上限。法力同理。死亡不自然复活。武器切换不会重设攻击剩余时间。

## 重量、减重与负担

单实体实际重量=单件重量×数量×(1-真实减重率)。

实际重量W=所有携带与装备实体重量之和；按instance_id去重，避免同一实体在背包和装备引用中重复计算。

有效负担E=W×(1-负担减免)，负担比r=E/负重上限。

真实减重改变W，因此也降低抗击退；支撑/背包优化只改变E；增加负重上限只改变负担比，不改变实际重量。

初值：70%负担以内不惩罚；70%至100%线性达到移速-20%、攻速-15%；100%以上继续加重惩罚。最终移动负担系数最低25%，攻速负担系数最低40%。这些曲线系数都在StatConfig内。

穿脱只更换物品归属，实际携带重量保持。inventory现在仅存背包物品，equipment存穿戴物品，统计时合计两处。CharacterState.equip/unequip是底层接口，不做空间检查；UI与拾取必须走GridInventory，它负责格子、换装、背包扩缩容及失败回滚。

## 伤害与击退

第一段伤害=武器基础伤害+力量增量×力量系数+敏捷增量×敏捷系数+damage固定值，再应用damage百分比。

每招伤害乘其模板倍率；一次攻击开始时判定一次暴击，整次攻击和散射箭共用该倍率。

实际物理伤害=原始伤害×100/(100+防御)，100为可调参数。先减伤，再按实际扣血吸血。

质量抗击退=W/(W+50)。防具抗击退先相加，上限80%。合成抗击退=1-(1-质量抗击退)×(1-防具抗击退)。

击退冲量=-ln(1-clamp(招式击退系数,0,0.99))×(0.7+0.2×来源力量/10+0.1×伤害比)×(1-合成抗击退)。

距离=碰撞体直径×(1-exp(-冲量))。保留现有连续受击总预算与墙体阻挡，最多一个碰撞体直径。

## 接口示例

```gdscript
const State = preload("res://scripts/systems/character_state.gd")
const Instance = preload("res://scripts/systems/item_instance.gd")
const Catalog = preload("res://scripts/data/starter_catalog.gd")
var state = State.new()
var sword = Instance.new(Catalog.weapon(0))
state.inventory.append(sword)
state.equip("weapon_a", sword) # same instance counted only once
state.set_active_weapon("weapon_a")
state.buffs.append({"flat": {"strength": 5.0}, "percent": {"damage": 0.10}})
state.recalculate()
print(state.stats.final_move_speed)
print(state.breakdown.unknown_stats)
state.add_gold(10)
state.spend_gold(3)
```

inventory数量、真实减重、profile或buffs发生变化后调用recalculate。界面可订阅stats_changed。ItemInstance.to_record输出存档字段，完整存档加载/迁移尚未实现。

## 当前实现与边界

本版已连接鼠标全向攻击、八向占位动画、格子背包与装备界面、金币/任务物品收集、敌人/地形掉落以及自动与手动拾取；详见FEATURES_v05.md与README.md。

完整存档、正式任务流程、消耗品使用、商店和正式角色美术仍未实现。数值是调参起点，按用户安排尚未运行本版测试。
