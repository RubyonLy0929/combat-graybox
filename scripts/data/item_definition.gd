extends Resource
## Shared immutable definition. Per-copy state belongs to ItemInstance.
@export var id: String = ""
@export var display_name: String = ""
@export var item_type: String = "material"
@export var rarity: String = "common"
@export var price: int = 0
@export var weight: float = 0.0
@export var grid_size: Vector2i = Vector2i.ONE
@export var can_rotate: bool = true
@export var max_stack: int = 1
@export var weightless: bool = false
## Flat additions and additive percent bonuses; 0.10 means +10%.
@export var flat: Dictionary = {}
@export var percent: Dictionary = {}
@export var effects: Array[Dictionary] = []

## Equipped actives are selected separately from always-on passive effects.
@export var active_skill: Dictionary = {}
@export_multiline var description: String = ""
