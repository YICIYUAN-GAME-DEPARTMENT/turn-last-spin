# TURN: Last Spin

Godot **4.7.1** / GDScript / Windows / Compatibility。

当前集成版：**PR #2 的完整对局 UI、经典/贪婪模式、货币和特殊牌 + PR #1 的 Dedicated Server / WebSocket / WSS / 60 秒重连**。客户端与专服共用项目；网络协议 **v3**，旧 v2 专服不能直接配合使用。

## 启动方式

### 本地试玩（不联网）

打开工程按 **F5**，在启动菜单选择「本地游戏 → 经典模式/贪婪模式」。也可以用 **F6** 运行 `scenes/local_test.tscn`。本地自动玩家与联网对局共用 `MatchSession`、`GameRules` 和 `Economy`；可以调整玩家人数与初始生命，并体验扇形手牌、商店、金币奖励动画和轮盘结算。

### 本地专服联机

在一个终端启动服务器：

```powershell
godot --headless --path . -- --turn-server --turn-port=24680
```

不配置证书时仅监听 **127.0.0.1 TCP**，只能本机测试。再启动两份客户端，点击「在线游戏」，填写服务器地址 `127.0.0.1` 和端口 `24680`，点击「连接专服」。连接后：

1. 一人点「创建房间」，把显示的 **6 位房间码**发给其他人。
2. 其他人在房间码输入框内填码并点击「加入房间」。
3. 房主设置经典/贪婪模式及经典模式的初始生命；全员点「准备」，房主点「房主开始」。
4. 进入轮盘，点击手牌选择加减、特殊牌或 PASS。15 秒内锁定承诺，最多再等待 5 秒揭晓，之后进入超级卡结算窗口。
5. 结算后自动下一轮；终局由房主请求返回大厅。

### 公网 WSS

专服需配置 TLS 证书与私钥，并将 TCP 24680 开放给客户端：

```bash
godot --headless --path . -- --turn-server --turn-port=24680 --turn-wss-cert=/path/cert.pem --turn-wss-key=/path/key.pem
```

客户端的服务器地址填写 `wss://域名或证书匹配的IP:24680`，并由 Godot/TLS 校验证书。默认地址配置于 `project.godot` 的 `turn/network/server_address`。**客户端只在选择在线游戏后发起连接**，保留 PR #2 的启动菜单。

已有的阿里云部署来自 PR #1 的协议 v2。**升级到本集成版之前，须先部署 v3 服务端和游戏逻辑，再使用 v3 客户端；本地验证不代表新版已部署云端。**运维步骤参考 [专服交接](docs/05-engineering/07-dedicated-server-handoff.md)。

## 玩法和资源

- **经典模式：** 存活玩家每轮各得 1 张明牌；被命中扣生命，归零后淘汰；最终存活者获胜。
- **贪婪模式：** 玩家通过参与结算积累金币，达到 **1000r** 后登记名次离场；被命中钱包清零但保留席位；同轮达标按座次排列。
- **经济：** 默认初始 **50r**，经典模式的防御/变化/超级卡价格分别为 **100/100/500r**；贪婪模式半价为 **50/50/250r**。
- **特殊牌：** 防御卡在命中时保护相应生命/金币；变化卡在行动阶段自选位移；超级卡在结算阶段追加正向位移。购买后的库存是服务端私有状态，其他玩家看到暗牌数量和公开余额；余额变动可能暴露购买的卡牌类型，这一点属于当前玩法信息边界。
- **奖励：** 由 `scripts/core/economy.gd` 统一计算，规则参数在 `economy_settings.gd` 中定义。联网对局使用**服务端配置**，本地试玩使用 `scenes/main.tscn` Session 上的 `Economy Settings`。
- **断线：** 服务器将玩家身份与 WebSocket 连接分离，保留约 **60 秒**恢复窗口；客户端运行中短暂断线可以恢复当前玩家 ID、公开状态、私人钱包和锁定状态。尚未实现客户端完全退出再启动的持久凭证恢复。

## 代码职责

| 路径 | 职责 |
| --- | --- |
| `scripts/core/game_rules.gd`, `economy.gd` | 纯规则、发牌、位移、奖励、货币和库存 |
| `scripts/network/net_bridge.gd` | **唯一 WebSocket / WSS RPC 入口**、TLS、连接和消息收发 |
| `scripts/network/action_commit.gd` | SHA-256 行动承诺和揭晓校验 |
| `scripts/server/server_main.gd` | 专服监听、协议版本、接入限制和分发 |
| `scripts/server/player_session_manager.gd` | 会话令牌、身份绑定和过期清理 |
| `scripts/server/room_manager.gd` | 房间码、成员、权限、模式选择、对局生命周期 |
| `scripts/server/match_session.gd` | **唯一权威对局状态**：计时、承诺/揭晓、购买、结算及快照；本地模式复用该实现 |
| `scripts/session/game_session.gd` | 客户端状态、动作提交、重连与本地测试协调 |
| `scripts/ui/main.gd`, `scenes/ui/match_view.tscn` | 启动菜单、联机大厅、共用轮盘 UI |

## 验证

在项目目录执行（`godot` 替换为 Godot 4.7.1 console 程序）：

```powershell
godot --headless --path . --script res://tests/rules_smoke.gd
godot --headless --path . --script res://tests/lives_smoke.gd
godot --headless --path . --script res://tests/economy_smoke.gd
godot --headless --path . --script res://tests/greed_smoke.gd
godot --headless --path . --script res://tests/local_session_smoke.gd
```

网络测试先启动上述本地专服，再在两个终端运行：

```powershell
# 房主：会打印 TURN_SMOKE_ROOM=XXXXXX
godot --headless --path . --script res://tests/network_smoke.gd -- --turn-port=24680

# 客人：将房间码替换为第一条命令输出
godot --headless --path . --script res://tests/network_smoke.gd -- --turn-port=24680 --turn-room=XXXXXX
```

贪婪模式购买与使用变化卡的联网回归：房主额外传入 `--turn-mode=2 --turn-rounds=1 --turn-test-special`，客人传入 `--turn-rounds=1`。断线恢复回归改用 `tests/network_upgrade_smoke.gd`，同样以 `--turn-room` 指定客人房间码。测试应显示 `TURN_SMOKE_FINAL`、`TURN_SMOKE_SPECIAL_OK` 或 `TURN_UPGRADE_RESUME_OK`。

## 当前边界

已在同一台 Windows 设备上完成**独立 WS 专服 + 两客户端**的经典整局、贪婪模式特殊牌、承诺锁定、重连恢复与本地经典/贪婪回归。**尚未对本次集成后的 v3 新版本执行阿里云 WSS 双设备异网验收**，也未完成高并发压力测试、正式美术资源及退出客户端后重登恢复。历史 PR #1 的公网验证不可直接代替新协议验收。
