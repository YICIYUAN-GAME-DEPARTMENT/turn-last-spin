# TURN · 最小可玩 Demo 实施基线（精简版）

> 2026-11-18 · 状态：**具备开工条件的建议方案，未开始施工**。  
> 用户强调：只覆盖常见流程和最必要的错误；不要为了少见攻击提前引入签名、多方共识、托管服务、主机迁移；先查询 Godot 原生 API/已有组件，再写自己的逻辑。Host 也是普通玩家，用**相同的 UI** 游玩，额外的房间/计时/结算职责在同一进程后台执行，无 Host 专用控制台。
>
> 原始 P0 最终目标仍是 **2～12 人、默认 8、独立 Windows EXE、跨不同网络实际联机完整整局**。本 Demo 验证 **Host-Client 技术路线 + 秘密提交 + 一次结算**；局域网/同机成功不能被标记为 P0 公网交付完成。

## 一、最小选型，不提前定死正式公网方案

- 使用现成的 Godot 4.7 **GDScript + ENetMultiplayerPeer + MultiplayerAPI/RPC** 做第一轮本机/局域网联机试验。Host 使用 `create_server()`，其他客户端 `create_client()`。Host 仍使用与其他玩家相同的 UI；没有单独 Headless 服务端程序。
- Godot 官方高层多人示例已经示范节点 RPC、`rpc_id()`、`call_local`、`peer_connected`、`connected_to_server` 等，不重复实现传输可靠性。
- 设计上网络连接方法与 GameRules/展示代码分离，将来切 WebRTC 时优先只改连接层及其测试，**不承诺零重构**。
- 最小 Demo 临时允许通过 **127.0.0.1 / 局域网 IP + 端口**连入 Host。正式的“输入房间码 → 公网找到 Host”另行验证发现/信令/中继；Demo 可以显示示意性房间码但**不能宣称已实现真实短码发现**。
- 不安装 GUT/GdUnit4、WebRTC 插件、Steam 或信令服务；如未来确有必要再单独评审。

## 二、最小 UI：一个普通玩家界面，Host 不增加专用 UI

- 所有人共用：建房/直连入口、简要成员/准备信息、轮盘/公开手牌、自己的 PLAY(+/-)/PASS 按钮、确认状态、15 秒倒计时、最终落点及胜者。
- 前期允许使用朴素 Control/Label/Buttons 呈现关键状态；2D 轮盘可调用原生 CanvasItem._draw，初版不实现复杂动画、音频、拖拽或自制窗口布局器。
- Host 额外工作仅存在于逻辑内部：房间成员管理、发牌与随机、15 秒截止、收集承诺、统一 Reveal/结算、向 peers 同步事件。Host 也提交自己的选择。
- 只做 2～4 个实例验证完整流程，域模型支持 2～12 人，但 Demo 不宣称已验证 12 人布局。

## 三、简化 Commit–Reveal（用户已确认 15 秒选择 + 独立揭晓）

1. Host 向全员发本轮公开手牌/轮盘起点/round_id，开始 **15 秒 COMMIT**。
2. 每名玩家在本机选定 PASS 或 PLAY(card_id,+/-)，点击确认后用 Godot Crypto 安全随机生成 nonce，计算 SHA-256 hash。**只发 hash，不发明文**；Host 自己同样先锁定 hash。
3. Host 收齐承诺或者 15 秒到期后，固定**每名存活者唯一的承诺名单**并广播。未提交者本轮默认 PASS。
4. 所有端看到本轮冻结名单之后**自动**向 Host 发送 action+nonce；Host 按列表汇集并发布 Reveal 结果，客户端自行核对哈希、轮盘结算。
5. Host 统一产生结果，客户端显示同一淘汰目标、弃牌和统计。每轮只进入下一轮一次；剩 1 人停止。

**本 Demo 不做**：全体签名 ACK、抗恶意 Host 分叉、随机数多人联合承诺、可信 Escrow、掉线重连、Host Migration、复杂防刷/异常重试框架。它们在原 RFC 保留为以后可选的风险清单，而不是 Demo 的阻塞项。

**唯一不可忽略的边界**：玩家已经提交 hash 但揭晓前掉线，Host 无法从哈希恢复原行动。Demo 仅显示“本轮揭晓失败”并停止该次测试，**不偷偷把它当作 PASS、不谎称满足 D-06 的已确认行动保留**。正式版如何兼顾掉线连续性仍需要单独决定。未提交承诺则正常按 PASS。

## 四、DiceService（骰娘）Demo

- Host 调用 Godot 原生 RandomNumberGenerator 生成当轮牌和随机初始指向，向所有人广播相同结果。游戏规则独立计算与校验，客户端只显示公共结果。
- Demo 只保证全员看到同一公开随机事件，不宣称 Host 无法篡改/重掷。若要求更高公平性，之后再单独评审多人联合种子/可信骰娘。

## 五、最小文件/模块（仅计划，不是必须照名字创建）

```text
scenes/demo.tscn                     # Host/Client 共用界面
scripts/core/game_rules.gd           # 无网络依赖：发牌结算、统计守恒
scripts/session/game_session.gd      # Host 角色管理房间与回合
scripts/network/game_transport.gd    # ENet/RPC 连接与消息
scripts/network/action_commit.gd     # 承诺、冻结、Reveal 和校验
tests/                               # 规则与网络最小验证
```

避免巨型全局 EventBus、额外状态机框架、多份玩家规则、专属 Host UI。细节代码以实施时 Godot 4.7 现成 Node/API 调研结果精简。

## 六、Demo 的完成定义（可复现）

- 启动一份 Host 和一份 Client（同机或局域网），两者都能准备并开始比赛。Host 也正常参与出牌。
- 双方看到相同初始指向及公开手牌；实际通信中 Host **只收到对手的 commit hash**，15 秒内无法读取对手明文 card_id/sign。
- 全员确认可提前 Reveal；若超时无 Commit 则 PASS。Reveal 自动执行且哈希验证通过，所有端获得相同目标并且恰好淘汰一人。
- 2 人局能结束；可添加第 3/4 个实例测试多轮、旧牌保留、统计守恒。
- 正常流程结束后有可读结果、无 Godot 运行错误。用具体操作步骤+日志记录 **Summary + Validation**。
- 明确**未通过/未开发**：短码公网发现、异网 NAT 穿透与中继、12 人 UI 满载测试、正式掉线后继续执行已承诺动作、复杂防作弊。它们属于后续阶段，不能冒充已经完成 P0。

## 七、启动编码前仍需一个明确动作

用户本轮问“是否已具备最小 Demo 开工条件”，所以**文档已准备但不视为已经下令编码**。如果用户下一步明确说“按这份最小方案施工”，再创建场景/脚本、进行最小 Godot 运行验证。若进行外部组件安装、服务器采购或网络发布，仍需单独沟通。

## 参考：Godot 4.7 官方 API

- Host/Client 及 RPC：https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html
- RNG 与 Crypto 说明：https://docs.godotengine.org/en/4.7/tutorials/math/random_number_generation.html
- HashingContext：https://docs.godotengine.org/en/4.7/classes/class_hashingcontext.html
- Crypto：https://docs.godotengine.org/en/4.7/classes/class_crypto.html
