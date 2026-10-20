extends RefCounted
## Transactional bridge between the grid and equipment. State owns all items.
const Instance := preload("res://scripts/systems/item_instance.gd")
const Backpack := preload("res://scripts/data/backpack_definition.gd")
const Weapon := preload("res://scripts/data/weapon_definition.gd")
const Armor := preload("res://scripts/data/armor_definition.gd")
var state
func _init(character_state) -> void:
	state = character_state
func size_for(slots: Dictionary) -> Vector2i:
	var bag = slots.get("backpack")
	return bag.definition.inventory_size.max(Vector2i.ONE) if bag != null else Vector2i(8, 6)
func footprint(item, rotated: bool) -> Vector2i:
	var shape: Vector2i = item.definition.grid_size.max(Vector2i.ONE)
	return Vector2i(shape.y, shape.x) if rotated and item.definition.can_rotate else shape
func rect_for(item) -> Rect2i:
	return Rect2i(item.position, footprint(item, item.rotated))
func can_place(item, cell: Vector2i, rotated: bool, items: Array, size: Vector2i) -> bool:
	var rect := Rect2i(cell, footprint(item, rotated))
	if cell.x < 0 or cell.y < 0 or rect.end.x > size.x or rect.end.y > size.y: return false
	for other in items:
		if other != item and rect.intersects(rect_for(other)): return false
	return true
func first_space(item, items: Array, size: Vector2i, rotated: bool) -> Vector2i:
	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			if can_place(item, cell, rotated, items, size): return cell
	return Vector2i(-1, -1)
func snapshot(extra = null) -> Dictionary:
	var records: Array = []
	var items: Array = state.inventory + state.equipment.slots.values()
	if extra != null and not items.has(extra): items.append(extra)
	for item in items:
		records.append({"item": item, "position": item.position, "rotated": item.rotated, "quantity": item.quantity})
	return {"inventory": state.inventory.duplicate(), "slots": state.equipment.slots.duplicate(), "records": records}
func restore(saved: Dictionary) -> void:
	state.inventory = saved.inventory
	state.equipment.slots = saved.slots
	for record in saved.records:
		record.item.position = record.position
		record.item.rotated = record.rotated
		record.item.quantity = record.quantity
func arrange(items: Array, size: Vector2i, preserve: bool = true) -> bool:
	var placed: Array = []
	var pending: Array = []
	for item in items:
		if item.locked or (preserve and can_place(item, item.position, item.rotated, placed, size)):
			if not can_place(item, item.position, item.rotated, placed, size): return false
			placed.append(item)
		else:
			pending.append(item)
	pending.sort_custom(func(a, b): return a.footprint().x * a.footprint().y > b.footprint().x * b.footprint().y)
	for item in pending:
		var location := first_space(item, placed, size, item.rotated)
		if location.x < 0 and item.definition.can_rotate:
			location = first_space(item, placed, size, not item.rotated)
			if location.x >= 0: item.rotated = not item.rotated
		if location.x < 0: return false
		item.position = location
		placed.append(item)
	return true
func item_at(cell: Vector2i):
	for item in state.inventory:
		if rect_for(item).has_point(cell): return item
	return null
func source_slot(item) -> String:
	for key in state.equipment.slots:
		if state.equipment.slots[key] == item: return key
	return ""
func owns(item) -> bool:
	return state.inventory.has(item) or not source_slot(item).is_empty()
func add(item, automatic: bool = false) -> Dictionary:
	if item == null or item.definition == null or owns(item): return {"ok": false, "error": "物品无效"}
	var saved := snapshot(item)
	var count: int = item.quantity
	# Fully atomic pickup; do not consume part of a ground stack on failure.
	for existing in state.inventory:
		if existing.definition.id == item.definition.id and is_equal_approx(existing.actual_weight_reduction, item.actual_weight_reduction) and not existing.locked:
			var space: int = maxi(0, existing.definition.max_stack - existing.quantity)
			var amount := mini(space, count)
			existing.quantity += amount
			count -= amount
			if count == 0: break
	if count > 0:
		item.quantity = count
		var location := first_space(item, state.inventory, size_for(state.equipment.slots), item.rotated)
		if location.x < 0 and item.definition.can_rotate:
			location = first_space(item, state.inventory, size_for(state.equipment.slots), not item.rotated)
			if location.x >= 0: item.rotated = not item.rotated
		if location.x < 0:
			restore(saved)
			return {"ok": false, "error": "背包空间不足"}
		item.position = location
		state.inventory.append(item)
	if automatic:
		var calculator = preload("res://scripts/systems/stat_calculator.gd")
		var result: Dictionary = calculator.calculate(state.profile, state.equipment, state.inventory, state.buffs, state.config)
		if result.stats.burden_ratio > 1.0:
			restore(saved)
			return {"ok": false, "error": "自动拾取会超过负重上限"}
	state.recalculate()
	return {"ok": true}
func equip(item, slot_name: String) -> Dictionary:
	if not owns(item) or item.locked: return {"ok": false, "error": "物品已锁定或不在背包"}
	if not state.equipment.accepts(slot_name, item): return {"ok": false, "error": "装备位置不匹配"}
	var old_slot := source_slot(item)
	if old_slot == slot_name: return {"ok": true}
	var saved := snapshot()
	var previous = state.equipment.slots.get(slot_name)
	if previous != null and previous.locked: return {"ok": false, "error": "原装备已锁定"}
	state.inventory.erase(item)
	if not old_slot.is_empty(): state.equipment.slots.erase(old_slot)
	state.equipment.slots[slot_name] = item
	item.position = Vector2i(-1, -1)
	if previous != null:
		previous.position = Vector2i(-1, -1)
		state.inventory.append(previous)
	if not arrange(state.inventory, size_for(state.equipment.slots)):
		restore(saved)
		return {"ok": false, "error": "替换装备或缩小背包后空间不足"}
	state.recalculate()
	return {"ok": true}
func move_to_grid(item, cell: Vector2i, rotated: bool) -> Dictionary:
	if not owns(item) or item.locked: return {"ok": false, "error": "物品已锁定"}
	var saved := snapshot()
	var old_slot := source_slot(item)
	if not old_slot.is_empty(): state.equipment.slots.erase(old_slot)
	var size := size_for(state.equipment.slots)
	if not can_place(item, cell, rotated, state.inventory, size):
		restore(saved)
		return {"ok": false, "error": "无法放在这里"}
	item.position = cell
	item.rotated = rotated
	if not state.inventory.has(item): state.inventory.append(item)
	if not arrange(state.inventory, size):
		restore(saved)
		return {"ok": false, "error": "卸下背包后空间不足"}
	state.recalculate()
	return {"ok": true}
func unequip(slot_name: String) -> Dictionary:
	var item = state.equipment.slots.get(slot_name)
	if item == null: return {"ok": false, "error": "这个位置没有装备"}
	if item.locked: return {"ok": false, "error": "物品已锁定"}
	var saved := snapshot()
	state.equipment.slots.erase(slot_name)
	item.position = Vector2i(-1, -1)
	state.inventory.append(item)
	if not arrange(state.inventory, size_for(state.equipment.slots)):
		restore(saved)
		return {"ok": false, "error": "卸下装备后空间不足"}
	state.recalculate()
	return {"ok": true}
func sort_items() -> Dictionary:
	var saved := snapshot()
	if not arrange(state.inventory, size_for(state.equipment.slots), false):
		restore(saved)
		return {"ok": false, "error": "整理失败，物品已保留原位置"}
	state.recalculate()
	return {"ok": true}
func split(item) -> Dictionary:
	if not state.inventory.has(item) or item.locked or item.quantity < 2: return {"ok": false, "error": "无法拆分"}
	var saved := snapshot()
	var part := Instance.new(item.definition, int(item.quantity / 2))
	part.actual_weight_reduction = item.actual_weight_reduction
	var location := first_space(part, state.inventory, size_for(state.equipment.slots), false)
	if location.x < 0: return {"ok": false, "error": "拆分需要空格"}
	item.quantity -= part.quantity
	part.position = location
	state.inventory.append(part)
	state.recalculate()
	return {"ok": true, "item": part}
func remove_for_drop(item) -> Dictionary:
	if not owns(item) or item.locked: return {"ok": false, "error": "物品已锁定"}
	var saved := snapshot()
	var slot := source_slot(item)
	if not slot.is_empty(): state.equipment.slots.erase(slot)
	state.inventory.erase(item)
	if not arrange(state.inventory, size_for(state.equipment.slots)):
		restore(saved)
		return {"ok": false, "error": "缩小背包后空间不足"}
	item.position = Vector2i(-1, -1)
	state.recalculate()
	return {"ok": true, "item": item}
func preferred_slot(item) -> String:
	var d = item.definition
	if d is Armor: return d.slot
	if d is Backpack: return "backpack"
	if d is Weapon: return state.equipment.active_weapon_slot
	if d.item_type == "accessory":
		return "accessory_1" if not state.equipment.slots.has("accessory_1") else "accessory_2"
	return ""
