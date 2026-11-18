extends RefCounted
## 无需第三方密码学依赖；所有玩家使用同一规范化字段顺序。
static func create_nonce() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()

static func compute(match_id: int, round_id: int, peer_id: int, action: Dictionary, nonce: String) -> String:
	var kind: String = str(action.get("type", "pass"))
	var card_id: int = int(action.get("card_id", 0)) if kind == "play" else 0
	var sign_value: int = int(action.get("sign", 0)) if kind == "play" else 0
	var material: String = "TURN-ACTION-V1|%d|%d|%d|%s|%d|%d|%s" % [
		match_id, round_id, peer_id, kind, card_id, sign_value, nonce
	]
	return material.sha256_text()

static func valid_reveal(expected_hash: String, match_id: int, round_id: int, peer_id: int, action: Dictionary, nonce: String) -> bool:
	if expected_hash.length() != 64 or nonce.length() != 64:
		return false
	return compute(match_id, round_id, peer_id, action, nonce) == expected_hash
