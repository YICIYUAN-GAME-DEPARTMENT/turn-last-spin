# TURN 总体技术架构：P2P 优先、方案待选（2026-11-18）

> **当前状态：架构评审中，不允许直接施工。** 最新用户要求**P2P 联机**，因此旧的“固定公网专用权威服务器 + 每人一个客户端”不再作为默认架构。原始 `turn.md` 的“公网两台不同网络设备完成整局”仍是必须满足的产品验收。
>
> **已确认**：Godot 4.7 + GDScript；2～12 人（默认 8）；房主创建、全员准备后房主开始；15 秒秘密决策；普通玩家掉线保留席位/自动 PASS；结束回房重新准备；人机补位 P1。  
> **仍待确认**：P2P 房主星形还是 Mesh、如何穿透公网、怎样生成短房间码、房主是否可得知他人动作、Host 掉线怎么处理、是否需要外部信令/平台服务。

完整候选对比及流程请读：[P2P 设计 RFC](03-p2p-architecture-options.md)、[公网连通与服务选项](../03-network/03-p2p-connectivity-options.md)。

## 1. 避免混淆：P2P、结算权威、传输是三种不同决策

- **P2P**：玩家设备承担游戏会话计算或交换，不采用原先默认的常驻专用比赛服务器。
- **Host-Client P2P**：房主游戏进程承担对局权威；其他人把操作发送给房主。这虽使用 Godot 的“server/client” API，**却没有独立的专用服务器进程**。
- **Mesh P2P**：所有玩家之间互连，但还必须决定如何管理时钟、动作一致性、初始随机、掉线与结果共识。
- **连接技术**：ENet 适合直连，WebRTC 可借信令/STUN/TURN 协商连接，Steam 等平台可提供自己的 Lobby/中继。它们都不能替代上面的权威/保密设计决策。

## 2. 候选 A：房主型 P2P（推荐比较，不是已选定）

```text
房主（玩家）= Godot 游戏客户端 + Session Coordinator / GameRules
          |           |           |
        玩家 B       玩家 C       玩家 D
                 P2P 游戏流量
```

- 所有人运行同一客户端。房主开房、作为逻辑权威端发牌/随机初始目标/计时/收集行动/统一结算。
- 房主同时也玩游戏，不能把它称作“不参加对局的专用服务器”。
- 所有规则、输入验证、统计只需一个可变权威状态，其他节点显示公开快照。
- **核心不足：** 房主可访问别人的明文秘密选择；Host 掉线会丢失权威端。这两个风险必须单独拍板，不能把它们当作已经解决。

## 3. 候选 B：全员 Mesh（尚未选择）

Godot 的 ENetMultiplayerPeer 与 WebRTCMultiplayerPeer 都提供 Mesh 模式接口。12 人全互联最多 66 条玩家间连接；同时还需协议解决统一倒计时、随机、公示、结果一致性、恶意/延迟玩家与断线。Mesh 不意味着自动公平，也不保证在不同 NAT 后自动连接。

## 4. 候选 C：房主型网络 + 提交承诺/统一揭晓

保留房主型 P2P 的轻量网络拓扑，把“其他玩家明文动作直接发给房主”替换为哈希承诺、揭晓校验，避免房主在决策阶段直接读取对手选择。需要额外定义 reveal 阶段、没有 reveal 的后果，以及随机数是否可被房主操控；**该方案仍待决**。

## 5. 拟议的分层与代码边界（非强制框架）

| 层 | 要解决的问题 | 建议复用 |
| --- | --- | --- |
| UI/Presentation | 菜单、轮盘、公开手牌、确认、倒计时、动画、结果 | Godot Control/Container/CanvasItem/Tween/Signals |
| GameRules（共享） | 发牌、旧牌保留、合法行动、位移、弃牌、淘汰、统计守恒 | GDScript 纯数据/纯函数，不依赖网络或 NodePath |
| Session | 房间、成员身份、准备/开始、MATCH/ROUND、15 秒阶段与失联策略 | GDScript 类/少量 Node；拓扑决定权威所在 |
| Transport | 发现、建连、断开、可靠业务消息、快照/错误 | Godot MultiplayerAPI/MultiplayerPeer/RPC 或平台适配 |
| 测试 | 规则确定性、异常消息、保密、公网可达、多网络一致性 | 内置手段或经批准的 GUT/GdUnit4 |

**不应制造五套重量级框架。** 如果一个稳定的 GDScript 脚本、几个 Node/Signal 就能实现模块，就不要额外写 EventBus、自制 UDP 重传、自己的 UI 容器或复杂状态机框架。

## 6. 未来工程目录建议（尚未施工）

```text
scenes/
  bootstrap.tscn
  ui/main_menu.tscn
  ui/lobby.tscn
  ui/match.tscn
  ui/result.tscn
  ui/components/wheel_view.tscn
  ui/components/player_cards.tscn
scripts/
  core/rules.gd
  core/state.gd
  core/statistics.gd
  session/room_session.gd
  session/round_controller.gd
  network/transport.gd
  network/protocol.gd
  ui/...
tests/
  rules/
  networking/
docs/  # 已存在
```

这只是按职责划分的候选目录。采用哪种 NetworkPeer、插件或平台前不能在运行代码中写死 ENet 或 Headless 逻辑。

## 7. 核心数据原则（即使 P2P 也必须保持）

- `player_id` / `card_id` 在一局中唯一；`wheel_index` 会随淘汰重排，但玩家名字与身份稳定。
- 所有公开手牌、初始目标、淘汰和统计在所有玩家屏幕一致。
- 15 秒倒计时由选择的**协调/权威机制**统一定义，不以每台玩家电脑的本地倒计时分别判定。
- 回合消息要包含 match、round、sequence/version，重复或过期操作不能二次结算。
- 规则独立于 UI/网络，结算后每种牌值及总量满足 `已发 = 已出 + 淘汰弃 + 剩余`。
- 谁可以看见还未揭晓的动作，是需要**数据级保密**的产品要求。Host 明文获取动作即可能违背对手保密预期，不能以“不显示 UI”充数。
- 断线的**普通玩家**可自动 PASS；**主持会话的 Host 掉线**仍是特别风险（现 D-06 未单独解决）。

## 8. 分阶段试验（仅在方案获批及用户允许施工之后）

1. 选定 P2P 拓扑、房间码来源、Host 权限与掉线策略。
2. 先实现纯规则，固定输入的自动化模拟 2～12 人。
3. 最小 P2P 连接：同机多实例 → 局域网 → 不同网络；实际跨网不可达时先解决连接方案。
4. 房间准备、15 秒行动、秘密揭晓、超时/断线、正确淘汰。
5. UI 极端布局、真人 5～8 人参与感与多轮手牌验证。
6. 完整跨网对局和 A01～A11，导出包与网络连接说明。

## 9. 需进一步讨论的事项

请到 [决策登记簿](../00-product/02-open-decisions.md) 的 D-03a～h 核对。**本轮不安装插件、不启动服务、不创建业务脚本和场景。**

### 官方参考

- https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html
- https://docs.godotengine.org/en/4.7/classes/class_enetmultiplayerpeer.html
- https://docs.godotengine.org/en/4.7/classes/class_webrtcmultiplayerpeer.html
- https://docs.godotengine.org/en/4.7/tutorials/networking/webrtc.html
