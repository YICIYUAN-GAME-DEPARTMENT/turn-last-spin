extends Resource
## 在对局开始时冻结参数，由房主或本地会话应用。

@export_range(0, 100000, 1) var starting_balance: int = 50
@export_range(0, 10000, 1) var play_reward_rate: int = 10
@export_range(0, 100, 1, "suffix:%") var inheritance_percent: int = 100

@export_group("特殊牌")
@export_range(0, 100000, 1) var defense_price: int = 100
@export_range(0, 100000, 1) var change_price: int = 100
@export_range(0, 100000, 1) var super_price: int = 500
@export_range(1, 12, 1) var super_steps: int = 1
@export_range(1.0, 30.0, 0.5, "suffix:s") var settlement_seconds: float = 5.0

func values() -> Dictionary:
	return {
		"starting_balance": clampi(starting_balance, 0, 100000),
		"play_reward_rate": clampi(play_reward_rate, 0, 10000),
		"inheritance_percent": clampi(inheritance_percent, 0, 100),
		"prices": {"defense": clampi(defense_price, 0, 100000), "change": clampi(change_price, 0, 100000), "super": clampi(super_price, 0, 100000)},
		"super_steps": clampi(super_steps, 1, 12),
		"settlement_seconds": clampf(settlement_seconds, 1.0, 30.0)
	}
