extends RefCounted
const Item := preload("res://scripts/systems/item_instance.gd")
const Weapon := preload("res://scripts/data/weapon_definition.gd")
const Armor := preload("res://scripts/data/armor_definition.gd")
const Accessory := preload("res://scripts/data/accessory_definition.gd")
const Backpack := preload("res://scripts/data/backpack_definition.gd")
const SLOTS := ["belt", "body", "legs", "boots", "gloves", "helmet",
	"accessory_1", "accessory_2", "weapon_a", "weapon_b", "backpack"]
var slots: Dictionary = {}
var active_weapon_slot: String = "weapon_a"
func accepts(slot_name: String, item: Item) -> bool:
	if not SLOTS.has(slot_name) or item == null or item.definition == null or item.quantity != 1: return false
	var d = item.definition
	if slot_name.begins_with("weapon_"): return d is Weapon
	if slot_name.begins_with("accessory_"): return d is Accessory
	if slot_name == "backpack": return d is Backpack
	return d is Armor and d.slot == slot_name
func equip(slot_name: String, item: Item) -> Dictionary:
	if not accepts(slot_name, item): return {"ok": false, "error": "invalid_slot_or_item"}
	for key in slots:
		if key != slot_name and slots[key].instance_id == item.instance_id:
			return {"ok": false, "error": "already_equipped"}
	var previous = slots.get(slot_name)
	slots[slot_name] = item
	return {"ok": true, "previous": previous}
func active_weapon():
	return slots.get(active_weapon_slot)
func contributing_items() -> Array:
	var result: Array = []
	for key in SLOTS:
		if not slots.has(key): continue
		if key.begins_with("weapon_") and key != active_weapon_slot: continue
		result.append(slots[key])
	return result
