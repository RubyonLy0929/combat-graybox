extends RefCounted
const WEAPON_IDS := ["starter_sword", "starter_blade", "starter_whip", "starter_spear", "starter_bow"]
const BD_IDS := ["blood_sword", "pursuit_sword", "hurt_amulet", "sustain_gloves", "echo_gloves", "mana_ring", "sidestep_boots", "unyielding_body"]
const IDS := ["starter_sword", "starter_blade", "starter_whip", "starter_spear", "starter_bow", "belt_cloth", "belt_light", "belt_heavy", "body_cloth", "body_light", "body_heavy", "legs_cloth", "legs_light", "legs_heavy", "boots_cloth", "boots_light", "boots_heavy", "gloves_cloth", "gloves_light", "gloves_heavy", "helmet_cloth", "helmet_light", "helmet_heavy", "crit_ring", "vampire_ring", "basic_pack", "harness_pack", "iron_fragment", "old_city_rune"]
static func weapon(index: int):
	return load("res://data/items/" + WEAPON_IDS[clampi(index, 0, 4)] + ".tres")
static func examples() -> Array:
	var result: Array = []
	for id in IDS + BD_IDS: result.append(load("res://data/items/" + id + ".tres"))
	return result
