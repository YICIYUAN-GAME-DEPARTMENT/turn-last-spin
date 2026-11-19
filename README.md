# TURN: Last Spin

Godot **4.7.1** / GDScript / Compatibility。客户端和专服共用项目与 Godot WebSocket/RPC。专服负责游客会话、房间、计时、发牌和结算。

## 本机运行

在工程根目录启动专服。下列命令中的 `godot` 可换成 Godot 4.7.1 的 console 可执行文件完整路径。

```powershell
godot --headless --path . -- --turn-server
```

看到 `TURN_SERVER_READY port=24680 protocol=2 transport=WS` 后：

1. 在编辑器的 **Debug → Customize Run Instances** 里开启两个实例，给 **Main Run Args** 填 `-- --turn-address=127.0.0.1`，按 **F5**。
2. 两个客户端自动连接本机专服。需要连公网服时，清空这行运行参数再按 **F5**。导出的客户端默认自动连接公网服。
3. A 点 **创建房间**，把六位房间码给 B。B 输码后点 **加入房间**。
4. 房主可设置初始生命 **1～5**，默认 **1**。两人点 **准备**，再由房主点 **房主开始**。
5. 每轮选择出牌加减或 PASS，再点 **确认并锁定**。选择期为 **15 秒**。全员确认可提前结算，超时未确认按 PASS。轮盘命中扣 1 点生命，生命归零才淘汰。
6. 提交后，选牌、加减、PASS 和确认都会禁用。结算时橙色箭头标出最终落点，生命归零显示「已淘汰」。两边应看到同一个胜者。
7. 大厅中，房主可选择其他成员并转交房主或移出成员。点击「离开房间」后保留服务器连接，可以直接再建房或加入其他房间。

专服可用 `--turn-port=24711` 改端口。默认本机 WS 只监听 `127.0.0.1`，供 F5 双开和自动化使用。

## 验收掉线重连

保留专服，再开两个 PowerShell 终端，在工程根目录执行下面两条命令。先运行第一条，把输出的六位 `TURN_SMOKE_ROOM` 房间码填到第二条。

```powershell
godot --headless --path . --script res://tests/network_upgrade_smoke.gd
godot --headless --path . --script res://tests/network_upgrade_smoke.gd -- --turn-room=ABC234
```

脚本会测试非房主操作被拒、互相转交房主、移出及重新入房、锁牌后更换连接、相同玩家身份和手牌、双方同一胜者、主动离房。客人端应输出 `TURN_UPGRADE_RESUME_OK ... locked=true` 和 `TURN_UPGRADE_LEAVE_OK`，房主端应输出 `TURN_UPGRADE_LOBBY_OK`。

跨设备手测时，开局后先让 B 确认，然后断开 B 的网络再接回，保持 B 的游戏进程运行。会话从专服检测到断线起保留 60 秒。对局继续按服务端计时，所以重连后可能已经进入结算或下一轮。主动点击「离开房间」则放弃原席位的恢复资格。游客会话和对局存在服务器内存中，客户端退出或专服重启后需重新入房。

## 自动化验证

```powershell
godot --headless --path . --script res://tests/rules_smoke.gd
godot --headless --path . --script res://tests/lives_smoke.gd
```

预期分别输出 `TURN_RULES_OK` 和 `TURN_LIVES_OK`。验证网络时保留专服终端，在第二个终端启动建房客户端：

```powershell
godot --headless --path . --script res://tests/network_smoke.gd
```

复制 `TURN_SMOKE_ROOM=` 后的房间码，从第三个终端启动加入客户端，把示例码换成实际值：

```powershell
godot --headless --path . --script res://tests/network_smoke.gd -- --turn-room=ABC234
```

两个客户端应打印相同的 `TURN_SMOKE_RESULT`，并以 `TURN_SMOKE_FINAL phase=ended` 结束。加入端会检查错误房间码，并验证另一人确认后仍处于选择阶段。超时测试在加入端追加 `--turn-silent`，预期打印 `TURN_SMOKE_TIMEOUT ... action=pass`。多轮测试可在建房端追加 `-- --turn-lives=3`。多人测试为每个进程指定相同的 `--turn-players=12`。

## 代码入口

| 模块 | 职责 |
| --- | --- |
| `scenes/bootstrap.tscn`、`scripts/bootstrap.gd` | 根据启动参数选择客户端或专服场景 |
| `scripts/network/net_bridge.gd` | 共用 WebSocket/RPC 入口，保持 `/root/Main/Net` |
| `scripts/server/server_main.gd` | 启动监听、版本握手、接线 |
| `scripts/server/player_session_manager.gd` | 稳定游客身份、连接绑定及短期恢复凭证 |
| `scripts/server/room_manager.gd` | 房间码、成员、准备、房主与房间生命周期 |
| `scripts/server/match_session.gd` | 每局独立计时、行动校验、揭晓和回合推进 |
| `scripts/core/game_rules.gd` | 共享纯规则、牌和生命统计 |
| `scripts/session/game_session.gd`、`scripts/ui/main.gd` | 客户端请求、公开状态与游戏界面 |

## 公网 WSS 启动方式

在目标专服机器上提供与域名匹配的 TLS 证书链和私钥，再启动 WSS：

```sh
godot --headless --path . -- --turn-server --turn-port=24680 --turn-wss-cert=/path/to/fullchain.pem --turn-wss-key=/path/to/privkey.pem
```

启动日志应显示 `transport=WSS`。客户端启动时自动连接 [project.godot](project.godot) 的 `turn/network/server_address`，连接失败时可以点 **重试连接**。换服时将这个地址改为与证书匹配的完整 WSS 地址，再重新导出客户端。ECS 安全组和启用的系统防火墙放行入站 **TCP 24680**。队友试玩方式、云服维护和公网实测结果见[联机专服交接](docs/05-engineering/07-dedicated-server-handoff.md)。

仓库的 [历史 P2P 方案](docs/03-network/03-p2p-connectivity-options.md) 和 [旧原型验证](docs/05-engineering/06-demo-validation.md) 供查阅。旧原型由玩家房主监听端口，并用 Commit–Reveal 隐藏玩家选择。当前运行链路由独立专服接收行动，其他客户端在揭晓前只收到确认人数；两个版本使用各自的客户端。
