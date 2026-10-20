extends Control
const FONT := preload("res://assets/NotoSansSC.ttf")
const SLOT_LABELS := {"weapon_a": "武器 A", "weapon_b": "武器 B", "helmet": "头盔", "body": "身体", "legs": "腿部", "boots": "脚部", "gloves": "手套", "belt": "腰带", "accessory_1": "饰品 1", "accessory_2": "饰品 2", "backpack": "背包"}
const DISPLAY_SLOTS := ["weapon_a", "weapon_b", "helmet", "body", "legs", "boots", "gloves", "belt", "accessory_1", "accessory_2", "backpack"]
const GRID_ORIGIN := Vector2(22, 113)
const DESIGN_SIZE := Vector2(1090, 660)
var world
var model
var held
var selected
var held_rotation := false
var drag_offset := Vector2i.ZERO
var message := "拖动物品放置；右键穿戴或卸下；R旋转；L锁定；Shift+右键拆分；Delete丢弃"
var hovered
func configure(room, inventory_model) -> void:
	world = room
	model = inventory_model
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = DESIGN_SIZE
	visible = false
func open_panel() -> void:
	world.player.character_state.health = world.player.health
	world.player.character_state.mana = world.player.mana
	world.inventory_open = true
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	world.player.input_buffer = 0.0
	world.player.velocity = Vector2.ZERO
	world.get_tree().paused = true
	visible = true
	queue_redraw()
func close_panel() -> void:
	held = null
	selected = null
	world.inventory_open = false
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	world.player.attack_requires_release = true
	visible = false
	world.get_tree().paused = false
func cell_size() -> float:
	var dimensions: Vector2i = model.size_for(model.state.equipment.slots)
	return minf(40.0, minf(430.0 / dimensions.x, 250.0 / dimensions.y))
func grid_rect() -> Rect2:
	return Rect2(GRID_ORIGIN, Vector2(model.size_for(model.state.equipment.slots)) * cell_size())
func grid_cell(at: Vector2) -> Vector2i:
	return Vector2i(floor((at.x - GRID_ORIGIN.x) / cell_size()), floor((at.y - GRID_ORIGIN.y) / cell_size()))
func slot_rect(index: int) -> Rect2:
	return Rect2(Vector2(480 + (index % 2) * 113, 113 + int(index / 2) * 63), Vector2(105, 57))
func slot_at(at: Vector2) -> String:
	for i in range(DISPLAY_SLOTS.size()):
		if slot_rect(i).has_point(at): return DISPLAY_SLOTS[i]
	return ""
func get_item_at(at: Vector2):
	if grid_rect().has_point(at): return model.item_at(grid_cell(at))
	var key := slot_at(at)
	return model.state.equipment.slots.get(key) if not key.is_empty() else null
func _process(_delta: float) -> void:
	if not visible: return
	var view := get_viewport_rect().size
	var ratio := minf(1.0, minf((view.x - 24.0) / DESIGN_SIZE.x, (view.y - 24.0) / DESIGN_SIZE.y))
	scale = Vector2.ONE * maxf(0.2, ratio)
	position = (view - DESIGN_SIZE * scale) * 0.5
	hovered = get_item_at(get_local_mouse_position())
	queue_redraw()
func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_I, KEY_B:
			close_panel()
		KEY_ESCAPE:
			if held != null: held = null
			else: close_panel()
		KEY_2, KEY_3:
			var index: int = 0 if event.physical_keycode == KEY_2 else 1
			world.player.runtime.cycle_equipment_key(index)
			message = "已切换装备主动来源；冷却不会重置"
		KEY_R:
			if held != null and held.definition.can_rotate:
				held_rotation = not held_rotation
				drag_offset = Vector2i.ZERO
		KEY_L:
			var item = hovered if hovered != null else selected
			if item != null:
				item.locked = not item.locked
				message = "物品已锁定" if item.locked else "物品已解锁"
		KEY_DELETE:
			var item = hovered if hovered != null else selected
			if item != null:
				var result: Dictionary = model.remove_for_drop(item)
				report(result, "已丢弃")
				if result.ok:
					world.spawn_item_drop(item, world.player.position, true)
					selected = null
					held = null
		_:
			pass
	get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if not visible or not event is InputEventMouseButton: return
	var at := get_local_mouse_position()
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if held != null:
			held = null
			accept_event()
			return
		var item = get_item_at(at)
		if item != null:
			if event.shift_pressed:
				report(model.split(item), "已拆分堆叠")
			else:
				var source: String = model.source_slot(item)
				var destination: String = model.preferred_slot(item)
				if not source.is_empty(): report(model.unequip(source), "已卸下")
				elif not destination.is_empty(): report(model.equip(item, destination), "已穿戴")
				else: message = "该物品无法穿戴"
		accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT: return
	if event.pressed:
		if Rect2(480, 509, 221, 30).has_point(at):
			world.player.runtime.cycle_equipment_key(0)
		elif Rect2(480, 546, 221, 30).has_point(at):
			world.player.runtime.cycle_equipment_key(1)
		elif Rect2(958, 18, 110, 32).has_point(at):
			close_panel()
		elif Rect2(340, 58, 108, 30).has_point(at):
			report(model.sort_items(), "已整理")
		elif Rect2(480, 58, 221, 30).has_point(at):
			world.auto_materials = not world.auto_materials
		elif Rect2(738, 58, 310, 30).has_point(at):
			world.auto_consumables = not world.auto_consumables
		else:
			held = get_item_at(at)
			selected = held
			if held != null:
				if held.locked:
					message = "物品已锁定，按L解锁"
					held = null
				else:
					held_rotation = held.rotated
					drag_offset = grid_cell(at) - held.position if grid_rect().has_point(at) else Vector2i.ZERO
	else:
		if held != null:
			var destination := slot_at(at)
			if not destination.is_empty():
				report(model.equip(held, destination), "已穿戴")
			elif grid_rect().has_point(at):
				report(model.move_to_grid(held, grid_cell(at) - drag_offset, held_rotation), "已放置")
			else:
				message = "已取消移动；丢弃请按Delete"
			held = null
	accept_event()
	queue_redraw()
func report(result: Dictionary, success: String) -> void:
	message = success if result.ok else str(result.get("error", "操作失败"))
func text(at: Vector2, value: String, size_px: int = 15, color: Color = Color("ddd8c5"), width: float = -1.0) -> void:
	draw_string(FONT, at, value, HORIZONTAL_ALIGNMENT_LEFT, width, size_px, color)
func item_color(item) -> Color:
	return {"weapon": Color("739ca7"), "armor": Color("829374"), "accessory": Color("a18ab4"), "backpack": Color("aa9368"), "material": Color("777c82")}.get(item.definition.item_type, Color("777c82"))
func item_box(item, rect: Rect2, ghost: bool = false) -> void:
	var color := item_color(item)
	if ghost: color.a = 0.7
	draw_rect(rect.grow(-2), color.darkened(0.65))
	draw_rect(rect.grow(-2), color, false, 2.0)
	text(rect.position + Vector2(6, 19), item.definition.display_name, 13, color.lightened(0.6), rect.size.x - 10.0)
	if item.quantity > 1: text(rect.end - Vector2(26, 8), str(item.quantity), 13)
	if item.locked: text(rect.position + Vector2(5, 36), "锁", 12, Color("f1c576"))
func _draw() -> void:
	if not visible or model == null: return
	draw_rect(Rect2(Vector2.ZERO, DESIGN_SIZE), Color("1b252a"))
	draw_rect(Rect2(Vector2.ZERO, DESIGN_SIZE), Color("a6936d"), false, 2.0)
	text(Vector2(22, 36), "行囊与装备  /  打开时暂停战斗", 24)
	draw_rect(Rect2(958, 18, 110, 32), Color("493d34"))
	text(Vector2(974, 40), "关闭 [I / B]", 14)
	text(Vector2(22, 81), "金币 %d   ·   格子 %d × %d" % [model.state.gold, model.size_for(model.state.equipment.slots).x, model.size_for(model.state.equipment.slots).y], 16)
	draw_rect(Rect2(340, 58, 108, 30), Color("394a49"))
	text(Vector2(359, 79), "自动整理", 14)
	draw_rect(Rect2(480, 58, 221, 30), Color("394a49"))
	text(Vector2(493, 79), "材料自动拾取：" + ("开" if world.auto_materials else "关"), 14)
	draw_rect(Rect2(738, 58, 310, 30), Color("394a49"))
	text(Vector2(750, 79), "消耗品只补已有堆叠：" + ("开" if world.auto_consumables else "关"), 14)
	var size: Vector2i = model.size_for(model.state.equipment.slots)
	var cell := cell_size()
	for y in range(size.y):
		for x in range(size.x):
			var rect := Rect2(GRID_ORIGIN + Vector2(x, y) * cell, Vector2.ONE * cell)
			draw_rect(rect.grow(-1), Color("25343a"))
			draw_rect(rect, Color("445157"), false, 1.0)
	for item in model.state.inventory:
		item_box(item, Rect2(GRID_ORIGIN + Vector2(item.position) * cell, Vector2(item.footprint()) * cell))
	for i in range(DISPLAY_SLOTS.size()):
		var key: String = DISPLAY_SLOTS[i]
		var rect := slot_rect(i)
		draw_rect(rect, Color("28373b"))
		draw_rect(rect, Color("c2a56c") if key == model.state.equipment.active_weapon_slot else Color("536268"), false, 1.5)
		text(rect.position + Vector2(5, 16), SLOT_LABELS[key], 12, Color("cab58f"))
		var item = model.state.equipment.slots.get(key)
		if item != null:
			text(rect.position + Vector2(5, 35), item.definition.display_name, 13, item_color(item).lightened(0.6), 95)
			text(rect.position + Vector2(5, 50), "%.1f kg" % item.actual_weight(), 11)
		else: text(rect.position + Vector2(5, 37), "空", 13, Color("6b777c"))
	for i in range(2):
		var skill: Dictionary = world.player.runtime.skill_for_key(i + 2)
		var rect: Rect2 = Rect2(480, 509 + i * 37, 221, 30)
		draw_rect(rect, Color("394a49"))
		text(rect.position + Vector2(8, 21), "[%d] %s · 点击切换" % [i + 2, skill.get("name", "无")], 13, Color("ddd8c5"), 205)
	var stats: Dictionary = model.state.stats
	text(Vector2(738, 119), "角色最终属性", 20)
	var lines: Array[String] = [
		"力量 %.0f  敏捷 %.0f  体质 %.0f  精神 %.0f" % [stats.strength, stats.agility, stats.constitution, stats.spirit],
		"生命 %.0f / %.0f   法力 %.0f / %.0f" % [model.state.health, stats.max_health, model.state.mana, stats.max_mana],
		"伤害 %.1f   防御 %.1f" % [stats.damage, stats.defense],
		"移速 %.0f   攻速 × %.2f" % [stats.final_move_speed, stats.final_attack_speed],
		"暴击 %.1f%%   吸血 %.1f%%" % [stats.crit_chance * 100, stats.lifesteal * 100],
		"实际重量 %.1f kg" % stats.actual_weight,
		"有效负担 %.1f / %.1f kg" % [stats.effective_burden, stats.carry_capacity],
		"负担减免 %.0f%%   抗击退 %.0f%%" % [stats.burden_reduction * 100, stats.final_knockback_resistance * 100],
		"移动惩罚 %.0f%%   攻速惩罚 %.0f%%" % [(1 - stats.move_burden_factor) * 100, (1 - stats.attack_burden_factor) * 100]
	]
	for i in range(lines.size()): text(Vector2(738, 151 + i * 26), lines[i], 14)
	draw_rect(Rect2(738, 396, 310, 12), Color("343e42"))
	draw_rect(Rect2(738, 396, 310 * clampf(stats.burden_ratio, 0, 1), 12), Color("c27d59") if stats.burden_ratio > 1 else Color("8ca976"))
	text(Vector2(738, 434), "负担 %.0f%%" % (stats.burden_ratio * 100), 14)
	text(Vector2(738, 465), "任务物品（不占格、不计重）", 14)
	var quest_y := 489
	for key in model.state.quest_items:
		var definition = load("res://data/items/" + str(key) + ".tres")
		text(Vector2(738, quest_y), "%s ×%d" % [definition.display_name if definition != null else key, model.state.quest_items[key]], 13)
		quest_y += 21
		if quest_y > 531: break
	var detail = held if held != null else hovered
	if detail == null: detail = selected
	draw_rect(Rect2(22, 391, 426, 202), Color("202c31"))
	if detail != null:
		text(Vector2(34, 417), detail.definition.display_name, 20)
		text(Vector2(34, 440), "%s  |  %s  |  %.2f kg  |  %d × %d" % [detail.definition.item_type, detail.definition.rarity, detail.actual_weight(), detail.footprint().x, detail.footprint().y], 13)
		var row := 462
		if detail.definition.get("base_damage") != null:
			text(Vector2(34, row), "基础伤害 %.0f；力量系数 %.2f；敏捷系数 %.2f" % [detail.definition.base_damage, detail.definition.strength_scaling, detail.definition.agility_scaling], 13)
			row += 20
		if detail.definition.get("defense") != null:
			text(Vector2(34, row), "防御 %.0f；装备抗击退 %.0f%%" % [detail.definition.defense, detail.definition.knockback_resistance * 100], 13)
			row += 20
		if detail.definition.get("inventory_size") != null:
			text(Vector2(34, row), "格数 %d×%d；负重 +%.0fkg；负担减免 %.0f%%" % [detail.definition.inventory_size.x, detail.definition.inventory_size.y, detail.definition.carry_capacity_bonus, detail.definition.burden_reduction * 100], 12)
			row += 20
		text(Vector2(34, row), "加成：" + str(detail.definition.flat), 12, Color("b8c9ba"), 398)
		text(Vector2(34, row + 20), "价格 %d 金币；数量 %d" % [detail.definition.price, detail.quantity], 12)
		row += 40
		var active: Dictionary = detail.definition.active_skill
		if not active.is_empty():
			text(Vector2(34, row), "主动 %s：蓝%.0f / CD%.1f秒" % [active.get("name", "技能"), active.get("mana", 0), active.get("cooldown", 0)], 12, Color("b9dce6"), 398)
			row += 18
		var description: String = detail.definition.description
		var count: int = mini(3, int(ceil(description.length() / 30.0)))
		for i in range(count):
			var line: String = description.substr(i * 30, 30)
			if i == 2 and description.length() > 90: line = line.substr(0, 28) + "…"
			text(Vector2(34, row + i * 18), line, 12, Color("c7b7db"), 398)
	else:
		text(Vector2(34, 419), "悬停查看物品；右键快速装备", 16)
		text(Vector2(34, 448), "金币不占格，重量与空间分别计算。", 14)
		text(Vector2(34, 477), "放不下的装备会保留在原处。", 14)
	text(Vector2(22, 620), message, 13, Color("dfc18d"), 1040)
	text(Vector2(22, 648), "左键拖放  ·  R旋转  ·  L锁定  ·  Shift+右键拆分  ·  Delete丢弃  ·  Esc取消  ·  2/3选择装备技能", 13)
	if held != null:
		var cell_at := grid_cell(get_local_mouse_position()) - drag_offset
		var shape: Vector2i = model.footprint(held, held_rotation)
		var rect := Rect2(GRID_ORIGIN + Vector2(cell_at) * cell, Vector2(shape) * cell)
		if grid_rect().has_point(get_local_mouse_position()):
			var valid: bool = model.can_place(held, cell_at, held_rotation, model.state.inventory, size)
			draw_rect(rect, Color(0.3, 0.8, 0.5, 0.25) if valid else Color(1.0, 0.3, 0.2, 0.25))
		else: rect.position = get_local_mouse_position() + Vector2(10, 10)
		item_box(held, rect, true)
