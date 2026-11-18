# 先调研、后施工：Godot 原生能力与第三方复用报告

> **2026-11-18 更新**：原报告优先 ENet + 固定公网 Headless 的结论已不再作为默认方案。用户最新要求 **P2P**；现以 [P2P 联网调研](../03-network/03-p2p-connectivity-options.md) 和 [架构选项](../02-architecture/03-p2p-architecture-options.md) 为准。

> 调研日期：2026-11-17；目标引擎：Godot **4.7**（新工程配置）。  
> **承诺边界：此文是方案调研，不代表已下载、安装、集成或测试插件。**  
> 每次新增功能和重构前，必须先复查项目现有模块、Godot 对应版本原生 API、第三方复用方案，再确定是否有必要自研。

## 1. 初始结论

**TURN 的网络通信、UI 组件、专用服务器运行方式与测试工具都有现成基础。** 应避免「从零写 Socket 协议」「自己实现重传」「自己造 UI 布局器」「为了发牌和计时引入独立后端框架」。

但以下是**游戏业务本身**，仍需要我们写少量、明确、可测试的逻辑：
- 每轮发 1 张公开牌、旧牌保留、按存活人数重新建轮盘；
- 秘密确认与统一揭晓、服务端权威一次结算；
- 玩家身份与房间码、不同房间隔离、状态/超时幂等；
- 轮盘特色外观和反馈（复用 CanvasItem 而非自研渲染管线）。

## 2. 原生能力复用矩阵

| 能力需求 | Godot 4.7 原生能力 | 适用判断 | 决议 |
| --- | --- | --- | --- |
| 客户端连接权威服务端 | `ENetMultiplayerPeer`、`MultiplayerAPI` / RPC | 面向 PC、低消息量、高层 API 已提供连接与可靠传输 | **复用** |
| 断线检测 | `MultiplayerAPI` 连接/断开信号 | 不自建 TCP 心跳协议即可获知基础断线；业务超时另设计 | **复用** |
| 对局实体多端自动生成 | `MultiplayerSpawner` | 适合要同步节点的游戏；TURN 的权威牌/房间以数据表达更直接 | P0 **不引入** |
| 属性实时复制 | `MultiplayerSynchronizer` | 默认同步已配置属性，容易错误暴露秘密决策；需要细粒度广播和房间隔离 | P0 **不用作比赛权威同步** |
| 切换主菜单/房间/对局 | `SceneTree`、`PackedScene`、信号 | 无需自研场景导航框架 | **复用** |
| 全局连接会话 | `Autoload` | 仅长生命周期且跨场景必要的连接管理；局部状态用节点传参/信号 | **少量使用** |
| 发牌与初始目标 | `RandomNumberGenerator` | 由服务端持有独立 RNG，测试用固定 seed 复现 | **复用** |
| 决策截止/自动推进 | `Timer`/`SceneTreeTimer`、`Time.get_ticks_msec()` | Timer 用于唤醒，单调时钟用于严格到期校验；不要用各客户端时钟 | **复用** |
| 绘制轮盘 | `Control` 或 `Node2D` 的 `CanvasItem._draw()` | 原生 2D 绘制，按人数生成扇区；无需自建渲染器 | **复用基础 + 定制表现** |
| 手牌、按钮、名单 | `Button`、`Label`、`PanelContainer`、`GridContainer`、`ScrollContainer` | Godot 内置容器满足响应式布局大部分需求 | **复用** |
| 动画反馈 | `Tween`、`AnimationPlayer` | 平台稳定、利于控制表现与结算解耦 | **复用** |
| 服务器无头运行 | `--headless` 与 Dedicated Server Export | 官方支持同工程客户端/服务器角色 | **复用** |
| 配置及本地持久化 | `ConfigFile`、`user://` | 只用于客户端偏好等；服务器首版不接数据库 | 视需要复用 |
| UI 主题与字体 | `Theme`、Godot 字体资源 | 无需单独 UI 框架 | **复用** |

### 关于场景复制组件的具体风险

`MultiplayerSynchronizer` 不是「秘密行动专用提交系统」：如果把 `pending_actions` 放进被同步的属性，其他客户端可能在揭晓前直接收到该数据。应使用 **客户端 → 服务端的私有 RPC + 服务端 → 指定 room peers 的阶段性公共事件**。这不是抛弃原生联网，而是选择适合回合制公开状态的原生能力。

## 3. 第三方候选：只评估、不安装

| 候选 | 解决的问题 | 4.7 兼容性调查 | 首版判断 |
| --- | --- | --- | --- |
| **GUT**（Godot Unit Test） | GDScript 单元测试、断言、CLI | 官方项目 README 列出 `9.7.1` / `godot_4_7` 分支适配 4.7.x | **可选**，经批准后用于规则测试 |
| **GdUnit4** | GDScript/C# 测试、场景测试/Mock | 官方 README 列出 `v6.2.x` 支持 4.7；主线新版也覆盖 4.7 | **可选**，和 GUT 二选一，避免重复依赖 |
| Steam/在线平台多人插件 | Steam 房间邀请/平台好友 | 当前交付没有 Steam 接入要求 | **不引入** |
| 额外网络框架/自建 Web 服务 | 增加 HTTP、数据库、复杂匹配 | 当前仅需房间码和一台固定权威服务器 | **不引入** |
| 大型 UI 框架/存档插件 | 丰富动态界面或大型持久化 | 当前无跨局状态、UI 以 2D Container 为主 | **不引入** |

**原则：**外部组件不仅要能运行，还必须检查当前 Godot 补丁版本、开源许可证、维护活跃度、额外文件和依赖、平台支持、导出服务器是否包含这些插件，以及卸载/回滚成本。不能看到一个插件名字就直接安装。

## 4. 关键官方资料（优先按 Godot 4.7 查阅）

- Godot 4.7 发布及补丁记录：https://godotengine.org/download/archive/
- 高层多人游戏（含 RPC/ENet / UDP）：https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html
- ENetMultiplayerPeer：https://docs.godotengine.org/en/4.7/classes/class_enetmultiplayerpeer.html
- 专用服务器与无头导出：https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_dedicated_servers.html
- MultiplayerSynchronizer：https://docs.godotengine.org/en/4.7/classes/class_multiplayersynchronizer.html
- MultiplayerSpawner：https://docs.godotengine.org/en/4.7/classes/class_multiplayerspawner.html
- CanvasItem 2D 绘制：https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html
- Godot 渲染器兼容范围：https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html
- Autoload 与普通节点取舍：https://docs.godotengine.org/en/4.7/tutorials/best_practices/autoloads_versus_regular_nodes.html
- GUT 项目及各版本：https://github.com/bitwes/Gut
- GdUnit4 项目及兼容矩阵：https://github.com/godot-gdunit-labs/gdUnit4

> Godot 文档的 `latest` 可能包含未稳定功能，实施时优先针对已安装的 `4.7` 版本。第三方表格是查阅时的兼容声明，正式安装前必须再核对具体发布版和许可证。

## 5. 实施前强制复用审核（每个任务都过一次）

1. **项目内先查：**同类场景、脚本、信号、资源、工具代码是否已经有了？这一步在本空工程中尚无可复用脚本，但之后每次 PR 必须查。
2. **Godot 官方先查：**4.7 是否已有对应节点/API/模板/最佳实践？列出实际名称和资料链接。
3. **社区方案后查：**明确是否需要第三方；检查兼容/许可证/维护/部署，必要时做最小验证，而不是先全量接入。
4. **做取舍表：**原生复用、第三方复用、必要定制三种路径对比。若决定自研，写清楚**原生方案哪里不满足业务**。
5. **先评审再动手：**在任务卡中列出拟用引擎 API、会改的文件、验收方法、回滚办法；不经批准不安装新插件/SDK/软件。
6. **持续防重复：**代码审查遇到两处相同状态/算法/网络包装，优先合并或抽为共享规则；不因为方便就复制一份。

## 6. 下一步调研范围（施工时开展）

- 用当前本机 Godot 实际补丁版跑一个**最小 ENet demo**验证 Windows 客户端与本地 Headless 服务端是否可互通。
- 验证 Godot 4.7 在本工程的 RPC 固定 NodePath 和多房间 `rpc_id` 定向广播，避免猜 API 行为。
- 检验 WheelView 扇区数学、文本在极端扇区的清晰度；只做最小证明，不先做完整 UI。
- 插件安装前分别确定 GUT 与 GdUnit4 的真实版本、许可和测试运行命令，经用户批准后才加入工程。

## 7. 二次网页核验结果（2026-11-17）

新增复用判断，实施时以实际 Godot 4.7.x 的类文档及最小运行验证为准：

| 业务点 | 原生方案 | 复用结论及注意事项 |
| --- | --- | --- |
| 房间内点对点通信隔离 | `SceneMultiplayer.server_relay` 和 `rpc_id` | **必须审计**：server_relay 默认 true，会向客户端通知其它 peer，不能仅靠“业务消息房间过滤”宣称隔离；建议 false 后按房间成员列表单播 |
| RPC 权限 | `@rpc`、`get_remote_sender_id()` | any_peer 只表示可以请求，不代表已获房主/玩家授权；服务端独立校验 |
| RPC 路径约束 | 统一 NodePath 和两侧 RPC 声明 | 固定跨场景网络入口，不因切换游戏画面导致路径不同 |
| 安全反序列化 | `SceneMultiplayer.allow_object_decoding` | 保持默认 false；参数采用限长的基础 Variant 类型并在业务层校验 |
| 房间码随机值 | `Crypto.generate_random_bytes()` | 游戏伪随机与房间码用途分离；还要检验撞码及限流 |
| 连通性备选 | `WebSocketMultiplayerPeer` | 若公网 UDP 不可达，可评估 WebSocket/WSS，不需全新后端，但重新部署和验收 |
| 服务器连接容量 | `ENetMultiplayerPeer.create_server(port,max_clients)` | 默认 max_clients=32 是总连接数，不是单房上限；多房间须显式设容量 |
| UI 绘制/互动 | `CanvasItem`、`Control`、`Container`、`Tween` | 原生满足轮盘绘制、布局与动画；数学扇区布局是必要定制，12 人需实测 |
| 隐私与链路安全 | 自定义定向 RPC、可选 WSS | “不把秘密发给其他客户端”不等价于 ENet 链路加密；有强隐私要求再单独审议 |

### 第三方库选择门槛

没有发现原需求 P0 **必须引入**的第三方插件。规则单测可评估 GUT 或 GdUnit4（二选一）；不得因为插件可用就直接安装。需要记录：许可、实际支持 Godot 4.7.x 的 tag/release、是否支持 headless、导出影响、团队成员安装步骤、删除后的回滚路径。

### 来源与研究局限

官方功能存在不等于现工程通过网络联调，也不等于公网服务器已具备。细节参考 [P0 可行性审计](04-feasibility-audit.md)，项目落地仍需 Phase 0/1 的实验数据。

- https://docs.godotengine.org/en/4.7/classes/class_scenemultiplayer.html
- https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html
- https://docs.godotengine.org/en/4.7/classes/class_websocketmultiplayerpeer.html
- https://docs.godotengine.org/en/4.7/classes/class_crypto.html
- https://docs.godotengine.org/en/4.7/classes/class_enetmultiplayerpeer.html

## 9. 2026-11-18 选型审批状态

官方 API 存在只说明候选实现可行，**不代表 D-03 已选择 ENet/Headless**。当前用户已确认 D-02 使用 Godot 4.7 + GDScript、D-05 每轮 15 秒及 D-04/D-06～D-08 的房间、掉线、再开、人机优先级。实现前仍按「项目现有轮子 → Godot 原生功能 → 第三方成熟方案 → 必要自研」顺序审查。引入 GUT/GdUnit4、部署网络服务仍须单独批准。

## 10. P2P 新的复用判断（覆盖旧集中式优先级）

1. 房主直连：Godot 4.7 原生 ENetMultiplayerPeer.create_server/create_client 与 RPC 可复用；Godot 也有 mesh API，但没有自动可靠的短码发现和万能 NAT 穿透。
2. WebRTC：原生 WebRTCMultiplayerPeer 提供 P2P/mesh 适配；**Windows 原生客户端需要额外 WebRTC GDExtension**，以及信令/STUN/TURN 或外部服务，未安装。
3. Steam：Valve Steam Datagram Relay 和 Networking Sockets 支持 P2P/中继，但实际 Steamworks 资格、游戏分发与第三方插件兼容需先核对；GodotSteam 旧 GitHub MultiplayerPeer 仓库已归档，不能照旧仓库直接安装。
4. Godot 的 Control/Container/CanvasItem/Tween、GDScript 规则与信号仍优先复用，不需要自造完整 UI 系统或 UDP 重传。
5. 过去文档所写的“公网固定 Headless 专用游戏服务器”是**已被最新 P2P 决策覆盖的旧候选**，不属于批准选型。

完整技术证据见 [P2P 网络评审](../03-network/03-p2p-connectivity-options.md) 与 [架构评审](../02-architecture/03-p2p-architecture-options.md)。尚未批准安装或集成任何联网插件。
