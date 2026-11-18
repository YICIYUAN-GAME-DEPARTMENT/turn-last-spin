# P0 可实现性审计：逐条对照 turn.md v0.1

> **2026-11-18 重要勘误**：此文件初稿假定采用固定公网专用服务器，用户已明确改为 **P2P**。因此关于统一服务地址、服务器可达性与 Host 保密性的旧结论**不能直接沿用**；请优先阅读 [P2P RFC](../02-architecture/03-p2p-architecture-options.md) 和 [公网连接研究](../03-network/03-p2p-connectivity-options.md)，文末附本次重新评估。

> 调研日期：2026-11-17。状态：**技术可行性论证（未经运行验证）**。原需求请以用户提供的 TURN v0.1 为准；本文件不变更玩法，也不表示任何功能已完成。
>
> 环境证据：项目 project.godot 标记 Godot 4.7 / GL Compatibility；工程中没有场景、业务脚本、网络服务或测试。已查阅 Godot 4.7 官方文档、GUT 与 GdUnit4 官方仓库。

## 一、结论的证据等级

- **A 官方已确认能力**：Godot 4.7 对应 API/教程公开支持；不等于在当前项目通过。
- **B 可设计实现**：基于 A 能力，有明确业务算法与模块边界；仍需要实现、调试与联机验收。
- **C 必须先实测/获取条件**：依赖公网 UDP、UI 最小尺寸、多房隔离与时序竞态等客观条件。
- **D 尚未决策**：比赛主题、截止时间、部署资源、规则提案与插件安装等待审批。

**综合评估：原文的 P0 功能均有技术实现路径，未发现必须改变核心玩法才能完成的引擎级障碍；但不是“保证能按期交付”。真正的 P0 阻塞项是公网部署可达性、网络正确性和 12 人 UI 可读性。**

## 二、联网需求 NET-01～13 逐项结论

| ID | 需求 | 可复用基础 / 必要自研 | 判断 | 必须验证的证据 |
| --- | --- | --- | --- | --- |
| NET-01 | 公网连接与错误重试 | ENetMultiplayerPeer、MultiplayerAPI 的连接/失败信号；公网 UDP 主机属于外部条件 | **A+B+C** | 两处不同网络真机完成一次公网连接；断网失败能恢复 |
| NET-02 | 建房、房间码、入房及拒绝 | RPC；自研 RoomManager/短码唯一性/成员限制 | **A+B** | 不存在、已满、对局中、重复加入分别返回正确错误 |
| NET-03 | 成员、准备、人数列表 | 服务器公共快照；UI 原生容器 | **A+B** | 2～12 玩家身份/状态一致 |
| NET-04 | 房主开始与全员准备 | Godot RPC sender id + 服务端角色检查 | **A+B** | 非房主、未全准备、少于两人均拒绝 |
| NET-05 | 稳定席位和“你” | get_remote_sender_id()、get_unique_id() + 服务器 peer→player 映射 | **A+B** | 各客户端本地身份正确；淘汰重排不改变 player_id |
| NET-06 | 发牌及随机初始指向 | RandomNumberGenerator + 服务端权威事件 | **A+B** | 每存活者每轮新增 1 张；多端一致且重复快照不重发 |
| NET-07 | 秘密提交 | RPC 定向到服务端；服务端 pending_actions 非公共状态 | **A+B+C** | 抓取客户端收到的业务消息：对手行动不出现 |
| NET-08 | 全员确认或超时公开 | Timer/Time.get_ticks_msec + 唯一 finalize_round | **A+B+C** | 超时与最后提交碰撞只结算一次 |
| NET-09 | 规则权威计算与校验 | GDScript 纯规则层、自研合法性检查/牌状态迁移 | **B** | 数学及统计单测；客户端篡改动作无效 |
| NET-10 | 统一推进回合 | 服务端状态机、可靠有序 RPC | **A+B** | 客户端动画/按钮不推动服务端回合 |
| NET-11 | 超时与掉线 | MultiplayerAPI 断线信号 + 服务器自动 PASS 规则 | **A+B+C** | 掉线前已确认保留，未确认 PASS，其他人继续 |
| NET-12 | 胜负与重新准备 | MATCH_END→LOBBY 业务状态迁移 | **B** | 所有人同胜者，新局牌/统计/准备清空 |
| NET-13 | 多房间隔离、无人清理 | peer 定向 RPC；SceneMultiplayer.server_relay=false；RoomManager | **A+B+C** | A/B 房互不收到消息，连接元数据不互串；全断清理 |

**重要发现：** SceneMultiplayer 的 server_relay 在 4.7 默认 true；不仅会转发数据，还会通知客户端其他 peer 连接/断开。首版单一公网服务器承载多房间，应在连接建立前关闭 server_relay，并在服务端用明确的 room member 集合做 rpc_id 精准广播。不能依赖默认 peer_connected 事件作为房间成员列表。

## 三、UI-01～07 与统计逐项结论

| ID | 原始要求 | 实现路径 | 判断 / 风险 |
| --- | --- | --- | --- |
| UI-01 | n 扇区、姓名、方牌框、初始/结果指针、中心空白 | CanvasItem._draw / draw_colored_polygon / Control 子节点 | **A+B**；极窄扇区需验证排版 |
| UI-02 | 名字一致、本人标识 | 稳定 player_id + 客户端本地标记 | **B**；不得以轮盘序号当身份 |
| UI-03 | 公开手牌、已出临时标记、下轮移除 | 以 card_id 为 key 的视图节点/对象复用，状态驱动 | **B+C**；n=2 存牌最多时需检查可读性 |
| UI-04 | 本人选牌/加减/PASS/确认锁定 | Godot Button、信号、Control 焦点及 disabled 状态 | **A+B**；只按服务器确认更新真正锁定 |
| UI-05 | 轮次/存活/倒计时/确认/网络 | Godot Label/Timer 显示 + 权威状态 | **A+B**；本地倒计时不决定结算 |
| UI-06 | 淘汰、胜者与出局观察 | 阶段事件 + 动画 Player/Tween | **A+B**；观察者只读仍接收公共数据 |
| UI-07 | 1440×960、1180×820；2/8/12 人和积累手牌 | anchors + Container + 轮盘尺寸计算 + 详细手牌查看 | **A+B+C**；必须通过截图/人工可用性验收 |
| STATS | 已发/已出/淘汰弃/剩余，每数字与总量守恒 | 服务端卡牌状态派生汇总 | **B**；不能统计展示中的“已出”卡为 HELD |

**容量上界来自规则推算（并非性能测试）：** 初始 12 人直到 1 人，每轮存活人数为 12,11,...,2，总计 **11 个行动回合、最多发出 77 张牌**。每人每轮新增 1 张，故一名一路存活且不出牌的玩家最多拥有 **11 张未使用牌**。初始 8 人时最多 7 个行动回合、35 张发牌。模型规模很小，但 12 人轮盘扇区内同时展示完整牌列仍可能挤压，不能仅以总数据量小推断 UI 可读。

## 四、玩法基线逐项检查

| 规则 | 实现方式 | 边界测试 |
| --- | --- | --- |
| 2～12 真人、每轮只给存活者发 1 张 1..n 明牌，允许重复 | 服务端按 alive_order 调用 RNG；无牌堆 | 重复值、n=2、n=12、掉线保留席位 |
| 上轮未打牌保留且数值不变 | card_id 唯一；状态 HELD | 旧牌值大于 n、重复数字多卡 |
| 等概率随机初始目标 | 用 RNG.randi_range(0,n-1) 选择当前存活位置 | 同 seed 可复现、起点合法、统计抽样 |
| PASS 或出 1 张加/减 | 服务端每轮每 player 一次锁定；附 match/round | 非法牌 ID、方向、重复确认、过期消息 |
| 统一揭晓、加和后循环淘汰 | target=((s+delta)%n+n)%n | 负数、抵消、零位移、旧大牌 |
| 打出与淘汰弃置分别计数，不继承 | 显式 HELD→PLAYED 或 HELD→ELIMINATED | 出局者本轮已出一张不重复扣 |
| 每轮淘汰一人、剩 1 人停 | 单一 finalize 事务 | 同一时间多个触发、终局不再发牌 |

所有业务规则都需要定制代码，**不存在把规则交给某个 Godot 内置轮盘节点就自动完成的 API**；但可完全使用现成的语言、绘制和测试基础设施。

## 五、阻塞风险与最小证据

| 风险 | 严重性 | 处理方案（施工前/初期） | 阻塞 |
| --- | --- | --- | --- |
| R01 没有公网可达 UDP 主机 / 校园或热点禁 UDP | P0 | 第一个网络里程碑做公网 UDP 最小连接；若不通先检讨 WSS/WebSocketMultiplayerPeer 备选 | 公网验收 |
| R02 Godot RPC 的 NodePath 和双方声明签名不一致 | P0 | 固定两端共享同一 RPC 入口脚本与路径；双进程验证 | 联机 |
| R03 默认 server_relay 泄露连接状态/意外允许客户端互传 | P0 | 建连前关闭 relay，限定向各 room peer 单发；测试跨房 metadata | 隔离 |
| R04 CHOOSING 最后一人确认和超时同时发生 | P0 | phase CAS 风格入口守卫、一次性事务，旧 timer 无效 | 结算 |
| R05 客户端伪造牌、房主、旧回合及重复请求 | P0 | peer_id 取自 RPC 上下文；审查 match/round/phase/owner/locked | 公平性 |
| R06 ENet 不等于 TLS/WSS | P1 安全 | 用户侧业务保密靠服务端不广播；如要求防中间人窃听/认证服务器，另立加密需求 | 更强隐私 |
| R07 12 人窄扇区、每人最多 11 张明牌排版 | P0 | 原生 UI 最小布局原型测试；必要时增加查看完整公共手牌的面板，仍保持全部公开 | UI |
| R08 房间码猜测、滥建房、资源消耗 | P0 | Crypto 安全随机字节生成短码、限流、房间数/总连接数上限 | 公网稳健 |
| R09 可靠回执丢失导致客户端以为未确认 | P0 | 服务端幂等回执/权威状态复核、最终揭晓兜底 | 操作 |
| R10 服务器 crash 后整场消失 | 文档已接受 | P0 明确不恢复；客户端显示断线，不显示假胜负 | 非功能限制 |

## 六、原生复用与第三方的结论

- **优先原生**：ENetMultiplayerPeer、SceneMultiplayer/MultiplayerAPI、RPC、Time、Timer、RandomNumberGenerator、Crypto、CanvasItem、Control、Container、Tween、AnimationPlayer、Dedicated Server Export。
- **不适合当前业务的原生复制**：MultiplayerSpawner 适用于同步场景节点；TURN 规则只需紧凑状态。MultiplayerSynchronizer 默认同步配置属性，若把私有 pending_actions 放进去，会破坏秘密提交边界。
- **可选测试插件，绝不在本轮安装**：GUT 9.7.1（项目 README 列为 Godot 4.7.x 适配）或 GdUnit4 v6.2.x（其兼容矩阵覆盖 4.7），只选其一。
- **无需引入**：专门的 Web 后端、数据库、Steam 联机/邀请插件、通用 EventBus、大型状态机框架、自研 socket 重传或 UI 布局器。
- **保留备选**：如果 UDP 公网环境现实不可用，Godot 4.7 WebSocketMultiplayerPeer 也可接 MultiplayerAPI；WSS 需要证书/部署额外决策，不能声称切换即自动成功。

## 七、可行 ≠ 已完成：正式验收条件

- 全部 NET/UI 对照原始 A01～A11，必须留下可复现测试记录。
- 核心先验证 **独立网络的两名真人从建房到胜负完整结束**；不能用同机多开替代。
- 至少做 **双房并行** 与一个 **12 人满房** 的压力/隔离测试；满房不能等同并行房间数不限。
- 检查其他客户端在 REVEAL 前实际收到的**解码后业务消息**，确保不含秘密动作。若需要对抗链路旁观者，再单独设计加密传输。
- 当前状态全部标记 **未实现、未测试**。资料证实的是 API 的存在和设计路径，不是运行结果。

## 八、已核对的主要公开来源

1. Godot 4.7 High-level multiplayer（RPC 约束、UDP、网络与权限）：https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html
2. ENetMultiplayerPeer（UDP 与 create_server/create_client）：https://docs.godotengine.org/en/4.7/classes/class_enetmultiplayerpeer.html
3. SceneMultiplayer（server_relay 默认 true、对象解码风险）：https://docs.godotengine.org/en/4.7/classes/class_scenemultiplayer.html
4. MultiplayerAPI（peer 身份与连接事件）：https://docs.godotengine.org/en/4.7/classes/class_multiplayerapi.html
5. MultiplayerSynchronizer（默认可见与 Resource 限制）：https://docs.godotengine.org/en/4.7/classes/class_multiplayersynchronizer.html
6. Dedicated Server Export：https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_dedicated_servers.html
7. CanvasItem（_draw/queue_redraw）：https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html
8. Control：https://docs.godotengine.org/en/4.7/classes/class_control.html
9. Time 单调时钟：https://docs.godotengine.org/en/4.7/classes/class_time.html
10. RNG 与 Crypto：https://docs.godotengine.org/en/4.7/tutorials/math/random_number_generation.html
11. WebSocketMultiplayerPeer：https://docs.godotengine.org/en/4.7/classes/class_websocketmultiplayerpeer.html
12. GUT：https://github.com/bitwes/Gut
13. GdUnit4：https://github.com/godot-gdunit-labs/gdUnit4

> 使用这些资料时优先固定到 4.7 版本，不以 Godot latest（开发版）文档替代 4.7。落地阶段仍需验证当前 Godot 4.7.x 实际可执行文件及选定插件的具体版本。
## 十、2026-11-18 需求决策对可行性审计的影响

- D-02：确认 Godot 4.7 + GDScript；团队补丁号仍待统一。
- D-03：**联网架构仍待讨论**；ENet/Headless 论证仅是候选方案能力，不是已批准选型。
- D-04：房主创建、凭码入房、至少 2 人且全部准备后房主开始。
- D-05：**15 秒**，全部确认提前揭晓，到期未确认自动 PASS；超时竞态验证仍必需。
- D-06：进行中掉线保持席位和已确认动作、未确认与以后回合自动 PASS，不立即淘汰。
- D-07：终局回房、重新准备、禁止对局中途加入；D-08：人机 P1。
- 原始范围 2～12 人和 A01～A11 公网与多端一致性验收不变；本轮仅变更文档，不执行代码。

## 十一、2026-11-18 P2P 重新评估（优先于旧集中式前提）

**原审计在“固定公网 Headless 专用权威服务器 + ENet”前提下给出的 P0 技术路线已不再是当前默认方案。** 用户最新明确要 P2P：Godot API 仍有能力基础，但原审计的公网可达性、NET-07 保密、Host 退出、房间码、托管和多房间隔离部分需要重新评价。

| 原需求 | P2P 下的新挑战 |
| --- | --- |
| NET-01 公网 | 端口映射/CGNAT/校园网；WebRTC 信令与中继或 Steam 平台服务 |
| NET-02 房间码 | 要有短码→Host/会话的网络发现能力，不能假定 ENet 原生支持 |
| NET-07 秘密提交 | 房主也是玩家，直接接收明文动作可提前知道其他人的选择 |
| NET-08 统一公开 | 15 秒用户已确认；Commit-Reveal 如采用需另定义揭晓期 |
| NET-09/10 权威结算/推进 | Host-Client 可以由 Host 裁决；Mesh 则需共识与统一随机/截止协议 |
| NET-11 掉线 | 一般玩家自动 PASS 已确认；Host 掉线单独决定结束/迁移 |
| NET-13 隔离 | 房间会话可能由平台 Lobby/Host 组织，不再默认固定公网多房间服务器 |
| A01/A11 交付 | 公网两台不同网络设备及非开发机仍必须真机验证 |

最新架构和决策见 [P2P RFC](../02-architecture/03-p2p-architecture-options.md)、[联机选项](../03-network/03-p2p-connectivity-options.md)、[决策 D-03a～h](../00-product/02-open-decisions.md)。**没有一个联网方案已在当前工程完成或运行验证**。
