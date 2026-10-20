extends RefCounted
const NAMES := ["剑", "刀", "鞭", "长枪", "弓"]
# Windup / active / recovery movement ratios; never fully root player attacks.
const MOVE_FACTORS := [[.85,.70,1.0],[.75,.65,.90],[.90,.80,1.0],[.80,.65,.95],[.80,.70,1.0]]
# name, windup, active, recovery, shape, reach, angle, damage, push fraction, thrust width
const TEMPLATES := [
 [["斜斩",.10,.06,.16,"arc",100,60,18,.12,0],["反手斩",.10,.06,.16,"arc",100,60,18,.12,0],["突刺",.13,.07,.18,"thrust",125,60,22,.18,22],["下劈",.20,.08,.28,"arc",108,60,32,.28,0]],
 [["大横斩",.24,.12,.30,"arc",112,150,32,.45,0],["反向斩",.26,.12,.32,"arc",112,180,34,.50,0],["斜重斩",.30,.14,.36,"arc",118,210,40,.60,0],["蓄力横扫",.42,.16,.46,"arc",125,240,58,.72,0]],
 [["左甩鞭",.18,.10,.24,"arc",175,150,22,.08,0],["右甩鞭",.18,.10,.24,"arc",175,150,22,.08,0],["展臂横扫",.24,.12,.28,"arc",180,210,28,.12,0],["周身回旋",.30,.24,.36,"arc",165,360,36,.18,0]],
 [["快刺",.17,.07,.23,"thrust",155,0,25,.18,24],["深刺",.19,.07,.24,"thrust",170,0,28,.22,24],["周身扫枪",.27,.20,.31,"arc",125,360,32,.30,0],["蓄力重刺",.36,.10,.40,"thrust",190,0,48,.55,36]],
 [["单射",.18,.001,.24,"arrow",390,90,23,.08,0],["单射",.18,.001,.24,"arrow",390,90,23,.08,0],["三箭散射",.25,.001,.32,"arrow",390,90,23,.10,0],["后撤强射",.38,.001,.40,"arrow",430,90,46,.35,0]]
]
static func step(weapon: int, index: int) -> Dictionary:
	var r: Array = TEMPLATES[weapon][index]
	return {"name":r[0],"windup":r[1],"active":r[2],"recovery":r[3],"shape":r[4],"range":float(r[5]),"arc":deg_to_rad(r[6]),"damage":float(r[7]),"push":r[8],"width":float(r[9]),"weapon":weapon,"index":index,"strength":10.0}
static func enemy(ranged: bool, rank: int) -> Dictionary:
	var d := step(4 if ranged else 1, 0)
	d.windup = .60 if rank == 2 else .46
	d.recovery = .55
	d.damage = 12.0 + rank * 6.0
	d.range = 310.0 if ranged else 95.0
	d.arc = PI / 2.0
	d.push = .20 + rank * .08
	d.name = "重砸" if rank == 2 else ("射击" if ranged else "挥砍")
	return d
static func max_range(weapon: int) -> float:
	var value := 0.0
	for r in TEMPLATES[weapon]:
		value = maxf(value, float(r[5]))
	return value

static func skill_step(weapon: int, skill: Dictionary) -> Dictionary:
	return {"name": skill.get("name", "技能"), "weapon": maxi(0, weapon), "index": 0,
		"windup": float(skill.get("windup", 0.06)), "active": float(skill.get("active", 0.12)),
		"recovery": float(skill.get("recovery", 0.08)), "shape": skill.get("shape", "none"),
		"range": float(skill.get("range", 90.0)), "arc": deg_to_rad(float(skill.get("arc", 60.0))),
		"width": float(skill.get("width", 24.0)), "damage": 0.0,
		"push": float(skill.get("push", 0.15)), "strength": 10.0,
		"target_limit": int(skill.get("targets", 0)), "movement": float(skill.get("movement", 0.85))}
