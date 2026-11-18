# TURN：P2P 整体架构候选方案与技术决策 RFC

> 版本：RFC v0.1 · 2026-11-18 · **设计讨论中，未授权施工**  
> **已确定**：用户最新要求采用 P2P 联机；Godot 4.7 + GDScript；2～12 人、默认 8 人；房主+全员准备、每轮 15 秒、普通成员掉线自动 PASS、结束回房、Bot 为 P1。  
> **未确定**：P2P 拓扑、谁是规则权威、穿透与中继、短房间码来源、主机离线处理、是否抗房主作弊、具体插件/网络服务。  
> 源文档 v0.1 的“公网权威专用服务端”与用户最新的 P2P 要求冲突：以**用户最新要求**覆盖拓扑，但原文的“不同网络可玩、明牌一致、秘密提交、统一揭晓、正确结算、掉线不阻塞”等产品目标仍需满足，不能偷降交付标准。

## 0. 四个不同维度（不能混为一谈）

| 维度 | 问题 | 目前的结论 |
| --- | --- | --- |
| 拓扑 Topology | 数据在玩家之间怎样走？ | **P2P 已确定**；但“房主星形”与“全员 Mesh”待决 |
| 权威 Authority | 谁决定发牌、15 秒截止、淘汰和赢家？ | **待决**；候选：房主负责 / 多端共识及核验 |
| 连通 Connectivity | 不同 NAT/校园网玩家怎样互连？ | **待决**；候选：直连、WebRTC+STUN/TURN、Steam 等平台 |
| 发现 Discovery | 输入 6 位房间码怎么找到房主？ | **待决**；需要映射服务/平台代理或更改房间码含义，单靠 ENet 不会自动完成 |

**P2P ≠ 没有 Host ≠ 不用任何服务。** 房主型 P2P 不需要 24 小时在线的**独立游戏计算服务器**，但房主的游戏进程会作为逻辑服务器；若要“短码自动公网加入且不配路由器”，通常需由平台或自己提供发现、信令或中继能力。

## 1. Godot 是怎样组织项目的？

- **场景 Scene（.tscn）**：可复用的界面/游戏对象树，例如主菜单、房间、轮盘、玩家卡牌组件。
- **节点 Node**：场景里的功能对象；2D 轮盘绘制可用 CanvasItem，交互按钮用 Control/Container。
- **脚本 Script（.gd）**：GDScript 写的行为，挂在节点或作为独立规则/数据模块；语法类似 Python，但**不是 Python**。
- **信号 Signal**：节点之间的事件订阅，按钮点击、房间变化、确认回执可使用，不必自己造全局事件总线。
- **资源 Resource（.tres）**：可复用配置；不能把秘密动作放在所有客户端同步的公共资源里。
- **MultiplayerAPI / MultiplayerPeer / RPC**：Godot 处理联网会话与远程调用的原生抽象；具体底层可以由 ENet、WebRTC 或合规的平台插件适配。

**建议只保留一个 Godot 工程**，但这是减少代码分叉的工程候选，而不是用户必须接受的架构定论。即使最终用平台插件，只要它适配 MultiplayerPeer，可尽量共用规则与 UI。

## 2. 候选拓扑及优劣

### 方案 A：房主型 P2P（Host-Client，推荐评估但未批准）

```text
              玩家 A 的游戏客户端（Host）
         同时运行房间协调、倒计时与规则结算
                  /      |      \
             玩家 B   玩家 C   玩家 D
```

- 所有玩家运行同一客户端；建房者成为 Host（在 Godot 的 ENet 高层范式可拥有网络 server peer ID 1），其他人通过网络连接 Host。**没有单独常驻运行的专用比赛服务器**。
- 客户端只向 Host 发送命令；Host 保留对局状态并广播公开快照、揭晓与结果。
- 优点：少连接、规则只有一个写入者、倒计时权威简单、适合 GameJam 的低频同步回合。
- 缺点：Host 可以在自己的机器上读取对手的未揭晓行动，可能知道/操纵随机数、截止、结果；Host 退出则整局失去协调者，除非做迁移。
- **关键冲突**：原文要求“统一揭晓前其他客户端不能获得行动”；Host 本身是其中一名玩家。如果直接把选牌发送给 Host，其程序就可看到其他人的动作，**即使 UI 不显示也没有真正保密**。必须在“接受信任房主”与“设计承诺/揭晓机制”之间做正式选择。

### 方案 B：全员 Mesh P2P（完全互联）

```text
 A ----- B
 | \   / |
 |  \ /  |   其他玩家也全互联
 |  / \  |
 | /   \ |
 C ----- D
```

- 每个玩家直接与其他玩家建连接；12 人最多 66 条玩家对连接（无冗余假设下）。
- Godot ENetMultiplayerPeer 提供 create_mesh/add_mesh_peer，WebRTCMultiplayerPeer 提供 create_mesh；**这些只是网络拓扑 API，不自动完成公网 NAT 穿透与一致性协议**。
- 随机初始目标、发牌、确认收集、超时争议、出局、胜负等都要设计去中心化协调或选举协调者。即便所有人都收到动作，如果没有一致的顺序/随机种子/超时共识仍可能算出不同结果。
- 优点：理论上不依赖单个 Host 持续在线；可以做互相验证。
- 缺点：公网上连接数、调试和抗恶意玩家复杂度高得多；**全互联不等于自动公平**，也不等于 Host 退出后系统自动无缝继续。
- GameJam 首版不建议未经验证就采用彻底无协调者共识方案。

### 方案 C：P2P 房主型网络 + 密码学承诺（保密增强）

- 仍走方案 A 的星形拓扑，业务层在 15 秒决策阶段先传 `commit=SHA256(canonical_action + random_nonce + round_id + player_id)`，对 Host 只见哈希而不知道出牌。
- 所有人承诺完成或 15 秒到期后进入 reveal 阶段，提交 `action + nonce`，Host 验证哈希并统一计算。必须规定**没有提交承诺**与**承诺后不揭晓**分别怎么判定。
- 这样让 Host 不能在其他人仍选择时直接读明文动作，降低“最后行动的房主”优势；但不自动消除 Host 假报随机牌、选择性断线、拒绝转发、在揭晓前影响计时或“承诺后选择不揭晓”的作恶。
- 这比“直接发送行动给 Host”的首版协议复杂，且 15 秒究竟仅覆盖承诺还是连 reveal 一起覆盖，需先做产品决定。
- 若要求公平性进一步增强，可用多方种子承诺/揭晓生成随机数、每端核验确定性规则和事件日志；这是可选复杂化，而非自动承诺。

## 3. 不论拓扑如何都建议保持的业务层次

```text
┌─────────────────────────────────────────────┐
│ UI：主菜单 / 建房入房 / 房间准备 / 轮盘 / 结果 │
├─────────────────────────────────────────────┤
│ Presentation：展示公开状态、玩家本地草稿和反馈 │
├─────────────────────────────────────────────┤
│ Session：房间、玩家身份、回合阶段、15 秒截止   │
├─────────────────────────────────────────────┤
│ Transport Adapter：send、broadcast、connect、 │
│                   disconnect、receive        │
├─────────────────────────────────────────────┤
│ Rules（纯规则）：发牌、合法出牌、位移、弃牌、  │
│                淘汰、统计恒等式               │
└─────────────────────────────────────────────┘
```

**重要：上图是职责边界，不强制必须实现成五套大型框架。** 小项目可用简单 GDScript 类、少量 Autoload、Godot Signals 实现；只在确实需要时引入抽象。

拟定未来目录（仅供审议，尚未创建）：

```text
res://
  scenes/
    bootstrap.tscn
    ui/main_menu.tscn
    ui/lobby.tscn
    ui/match.tscn
    ui/result.tscn
    ui/components/wheel_view.tscn
    ui/components/player_cards.tscn
    ui/components/action_panel.tscn
  scripts/
    core/rules.gd               # 共享、确定性规则
    core/state.gd               # 玩家/牌/回合/统计
    session/room_session.gd      # 建房/准备/身份
    session/round_controller.gd  # 15 秒截止与阶段
    network/transport.gd        # 网络接入与事件
    network/protocol.gd         # 消息格式与校验
    ui/*.gd                     # 视图与输入
  tests/
    rules/
    connectivity/
    p2p_session/
  docs/                         # 本轮在写的设计文档
```

如果后来选用 Host-Client，可让 Host 的同一客户端进程额外运行 `room_session` 与 `round_controller` 的权威职责；其他客户端只读取 Host 的公共状态。如果选 Mesh，共享规则仍可复用，但协调与时间/身份机制需要重设计。

## 4. 一局完整游戏如何流动？（Host-Client 候选示例）

| 阶段 | 玩家操作 | Host/协调端职责 | 共享状态 |
| --- | --- | --- | --- |
| 找到游戏 | 创建/输入房间码 | 通过选定连接机制找到 Host；验证 2～12 人限制 | 房间码、成员 |
| 大厅 | 每人准备，房主开始 | 验证房主、至少 2 人、所有人准备 | 房间快照 |
| ROUND_START | 查看明牌和随机初始指向 | 为每个存活者发 1 张 1..N 明牌、生成起点 | 全体公开手牌、起点、轮次 |
| CHOOSING | 15 秒内选 PASS 或牌及方向，可改草稿 | 收集并锁定行动/承诺；仅公开确认总数 | 阶段、倒计时、确认计数 |
| REVEALING | 所有行动统一公开 | 将未确认者判 PASS；若承诺制，先验证揭晓；统一确定动作集合 | 公开行动与总位移 |
| ROUND_RESULT | 看轮盘移动和出局 | 用共享规则计算淘汰、弃牌和统计；生成唯一结果 | 结果事件 |
| NEXT/END | 下一轮或最终胜者 | 剩 1 人则结束，否则缩盘开始新轮 | 新一轮状态/赢家 |

两个不同的“动作提交”协议不能混用：
- 简单版：15 秒内向 Host 提交 **明文最终动作**，其他参与者未收到；**Host 可以看到**。
- 保密版：15 秒内提交 **动作哈希承诺**，截止后有额外 reveal 步骤。Host 不能从哈希直接看到动作，但要求规定揭晓超时及异常处理。
**最终采用哪一种，尚未获用户批准**。

## 5. 状态与消息协议（不依赖具体网络库）

建议所有回合消息都能定位 `room_id / match_id / round_id / sequence / sender_id`。消息类型包括：
- `ROOM_CREATED`、`JOIN_REQUEST`、`ROOM_SNAPSHOT`、`READY`、`START`
- `ROUND_START`：存活顺序、全部公开牌、初始指向、15 秒截止
- `ACTION_SUBMIT` 或 `ACTION_COMMIT` + `ACTION_REVEAL`（**二选一**）
- `LOCKED_COUNT`、`ROUND_REVEALED`、`ROUND_RESULT`、`MATCH_END`
- `DISCONNECT`、`ERROR`、`PUBLIC_SNAPSHOT`

- 消息接收端要校验阶段、版本、牌 ID、所属玩家、重复提交和过期轮次；不能以用户可自报的玩家 ID 作为身份凭证。
- 卡牌 ID 与玩家 ID 在一局中稳定，轮盘位置随淘汰重排。
- 规则层不依赖网络 Node、轮盘动画或计时器，输入状态和动作、输出下一状态与结果。
- 各种状态的公开边界要分清：公开牌与秘密决定不是一回事。若采用承诺制，哈希本身不是动作。

## 6. 主机退出的**未决冲突**（必须讨论）

已确认 D-06 只规定“普通玩家掉线时自动 PASS、保留席位”。在 Host-Client 中，如果**作为协调者的房主掉线**：
- A：整局中断并提示其他玩家（容易实现，但不是“所有掉线都不中断”）。
- B：选举新 Host 并迁移公共状态、未完成的回合、时钟与秘密承诺（复杂）。
- C：引入专用协调/继任服务（基础设施又增加）。

不能把普通玩家的自动 PASS 原样套用到 Host 掉线；应新增独立 D-24 决策并调整 A07 验收。

## 7. 具体施工阶段（草案，仅讨论）

1. **设计冻结前**：确定拓扑、身份、可访问性、房间码、保密方案、Host 退出策略与平台约束。
2. **规则实验**：纯 GDScript 数据/结算测试（2、8、12 人、重复数字、负位移、所有 PASS、统计守恒）。
3. **最小网络实验**：两台设备通过选定传输方式相连；再做校园网 + 热点等不同网络。
4. **房间实验**：同一网络角色下建立房间、准备和开始，验证 12 人限制、房间码与错误。
5. **秘密行动实验**：15 秒、提前确认、掉线 PASS、网络重复消息与揭晓严格一致。
6. **UI 与表现**：原生 Control/CanvasItem/Container/Tween，验证 1440×960、1180×820 与 12 人/长手牌。
7. **验证与交付**：跨公网两设备完成整局，一致胜负；以 A01～A11 验收；不强制加 P1 Bot。

每一阶段施工前仍需先查当前项目内现成组件、Godot 4.7 原生能力及第三方组件，再提交变更范围与 Validation，经用户批准才动工。

## 8. 需要用户决策的最小集合

| 决策 ID | 问题 | 候选 |
| --- | --- | --- |
| D-03a | P2P 拓扑 | **房主星形** / 全员 Mesh / 分层混合 |
| D-03b | 公网连通和邀请 | 直连 ENet+端口映射 / WebRTC+信令、STUN、TURN / Steam 平台联网 / 其他 |
| D-03c | 房间码从哪里来 | 自有轻量发现服务 / 平台 Lobby ID / 含地址或分享信息的连接码 |
| D-03d | 玩家含 Host 在内的出牌保密程度 | 信任 Host、简单明文提交 / 哈希承诺-揭晓 / 更强公平方案 |
| D-03e | 发牌与初始目标随机谁决定 | Host RNG 可核验但需信任 / 多方种子联合随机 |
| D-03f | Host 掉线怎么办 | 终止本局并提示 / 主机迁移 / 其他 |
| D-03g | 可接受的外部基础设施 | 必须零自建常驻服务 / 可用第三方平台 / 接受轻量信令或中继 |
| D-03h | 交付平台与账号要求 | Windows 独立 EXE / 可使用 Steamworks / 必须 Web 等 |

**当前没有任何一项 D-03a～h 被自动替你选择。** D-04（全员准备/房主开始）、D-05（15 秒）、D-06（普通成员断线 PASS）、D-07（结束回房）、D-08（Bot P1）仍已确认。

## 官方资料

- Godot 4.7 高层多人联网与房主范例：https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html
- ENet 与 mesh 模式：https://docs.godotengine.org/en/4.7/classes/class_enetmultiplayerpeer.html
- WebRTC 与原生插件/信令：https://docs.godotengine.org/en/4.7/tutorials/networking/webrtc.html
- WebRTC mesh API：https://docs.godotengine.org/en/4.7/classes/class_webrtcmultiplayerpeer.html
- Godot 4.7 脚本语言指南：https://docs.godotengine.org/en/4.7/getting_started/step_by_step/scripting_languages.html
- WebRTC 官方 ICE / STUN / TURN：https://webrtc.org/getting-started/peer-connections
- Valve Steam Datagram Relay 条件：https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay

> 所有 API 和服务均**只调研未集成**。用户尚未批准安装插件、购买服务、构建代码或部署。

## 10. 2026-11-18 重点讨论：可替换网络层与保密界限

### 10.1 不能轻率保证“换 ENet/WebRTC 零重构”

Godot 的 `MultiplayerPeer` 抽象使 ENetMultiplayerPeer 和 WebRTCMultiplayerPeer 可被同一个高层 `MultiplayerAPI` 消费（WebRTC 的 Host/Client 模式不强制全员 Mesh）。**如果拓扑仍然是 Host-Client、业务协议及 RPC/节点路径不变**，规则、公开数据模型和大部分 UI 可以复用。

但以下部分随网络技术变化必须重新实现或验证：建连流程、NAT/信令、短码到会话的发现、peer 身份生命周期、断线恢复、平台插件/导出配置、端到端回归测试。若转向 Mesh 或另建完整裁决服务器、变更秘密提交协议，Session/权威层也会发生明显改动。

建议仅建立足够薄的边界：
```text
UI  → GameSession → GameRules (纯规则)
             │
             ├── ActionProtocol (15 秒、Commit/Reveal)
             │
             ├── LobbyDiscovery (房间码与会话查找)
             │
             └── TransportAdapter (连接/收发/错误事件)
                        ├── ENetHostAdapter (候选)
                        └── WebRTCHostAdapter (候选)
```

不要为尚未批准的技术堆出多套大框架；实际代码文件数量按最小需要决定。

### 10.2 房主秘密与 Hash Commit-Reveal 的精确能力

所有玩家在选择阶段先锁定 `commit=SHA256(编码后的动作 + match/round/player 标识 + 高熵随机 nonce)`；Host 只能看到承诺值，无法直接从中知道行动。承诺阶段结束后各人揭晓 `action+nonce`，所有人验证并结算。

- **能做到**：15 秒选择期内，Host 不会收到对手的明文动作；并且 Host 不能在看到他人明文后改变自己**已经提交**的承诺。
- **不能自动做到**：保证每人的明文在完全同一毫秒到达；防止 Host 刻意拒绝转发、终止整局、操纵随机数，或最后揭晓者利用不揭晓制造异常。
- 这意味着需要产品确定：15 秒只限于提交承诺、还是要求含后续揭晓？不揭晓者如何处理？不能擅自新增隐藏计时规则。
- 如果要求房主完全无法提前获取并且能保证公正出结果，可能需要独立可信协调服务；此时应坦诚说明 P2P 的实际角色和服务器职责。

### 10.3 骰娘式公共随机

“骰娘”通常指向多人公布掷骰结果的工具。首版可以用共享的随机结果事件 + 统一结果日志；Godot RandomNumberGenerator 可固定 seed 复现，但**Host 独占 RNG**无法仅凭公开结果证明没有重掷。若要排除单方操控，可考虑多人随机种子承诺/揭晓或由中立服务发布随机结果，不能仅把模块命名为“骰娘”便宣称公平。

来源：
- https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html
- https://docs.godotengine.org/en/4.7/tutorials/networking/webrtc.html
- https://docs.godotengine.org/en/4.7/tutorials/math/random_number_generation.html
- https://webrtc.org/getting-started/peer-connections
- https://v2docs.kokona.tech/zh/stable/CookBook.html
