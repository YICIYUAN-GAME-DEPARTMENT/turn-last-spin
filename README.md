# TURN: Last Spin — 最小可玩 Demo

> Godot **4.7.1** / GDScript / Compatibility / Windows PC  
> **当前阶段：本机与局域网 Host-Client 技术 Demo。** 不是最终公网多人版本。

## 运行方法

1. 用 Godot 4.7.1 打开本目录的 `project.godot`，按 **F5** 运行，点击 **在线游戏**。
2. 在第一个实例点击 **创建房间 (Host)**，随后在大厅用 **「初始生命（全员相同）」SpinBox** 设置 1～5（默认 1）。设置会同步给所有玩家；比赛开始后锁定。默认监听 UDP 端口 `24680`。
3. 再开一个游戏实例（在 Godot 编辑器中使用“运行多个实例”或打开第二份导出的游戏），点击 **在线游戏**，输入房主地址，再点击 **直连加入 (Client)**。
   - 同一台电脑：输入 `127.0.0.1`。
   - 同一局域网的不同设备：输入房主电脑的局域网 IPv4 地址。
4. 两人分别点击 **准备**；房主点击 **房主开始**。
5. 轮盘显示所有人的明牌、生命和初始目标。点击左下角的手牌，选择 **加** 或 **减** 即锁定出牌，也可直接点击 **不出牌**。
6. **15 秒**内所有人确认可提前进入揭晓；否则尚未提交承诺者自动 PASS。Host 统一公布冻结承诺并发起自动 Reveal，最多等待 **5 秒**，随后进入超级卡结算窗口。
7. 轮盘每轮**命中一人并扣 1 点生命**。仍有生命的玩家继续参赛、保留未出手牌；生命归零时才淘汰并弃置手牌。逐轮自动推进，最终只剩一人时显示胜者。房主可点击 **返回房间**，全员重新准备。

### 本地界面测试

按 **F5** 后点击 **本地游戏** 直接进入轮盘。也可打开 `scenes/local_test.tscn`，按 **F6（运行当前场景）** 快速进入对局。默认 4 名玩家、每人 1 点生命，可在对应场景根节点的「本地测试」属性中调整。

测试只使用一个进程，无需建房或联网。你可以出牌或 PASS，其他测试席位自动 PASS。左上角的「生命」可选择每人 1～5 点初始生命，修改后会重开本地对局。右上角可切换人数或重开。

### 货币和特殊牌

每人开局有 **50r**。在对局左上角打开「商店」购买特殊牌。购买后会放入左下角的「我的手牌」，点击卡牌即可选择使用。存活玩家可在对局中购买，其他玩家只能看到轮盘上的牌背和张数。最终结算会翻开本轮使用的暗牌，并显示变化卡的加减点数。

- **防御卡 · 100r**。出牌阶段使用，保住本轮最后 1 点生命。只要打出就会消耗。
- **变化卡 · 100r**。出牌阶段点击手牌里的变化卡，选择 1～当前存活人数的点数，再选加或减打出。
- **超级卡 · 500r**。揭晓后进入结算窗口，从手牌使用可使最终位移 +1。每位玩家每轮最多使用一张，效果相加。可以点「确认结算」跳过，超时也会跳过。

每轮有玩家淘汰时，出过普通牌或特殊牌的人各得 **10 × 淘汰人数 × 奖励格数**。奖励格数取最终位移的绝对值按存活座位数折算，整圈按满圈算，零位移按 1 格算。随后把出局者余额均分给本轮出牌且存活的玩家，余数按座位顺序分配。没有符合条件的人时出局余额清零。

在 Godot 打开 `scenes/main.tscn`，选中 **Session → Economy Settings**。可调初始货币、出牌奖励倍率、遗产分配比例、各卡价格、超级卡位移和结算时长。参数在新对局开始时生效，联机使用房主的设置。

### 编辑界面

启动菜单在 `scenes/ui/mode_menu.tscn`，建房和大厅在 `scenes/main.tscn`。对局布局在 `scenes/ui/match_view.tscn`，左下手牌按钮和出牌菜单分别在 `scenes/ui/hand_card.tscn`、`scenes/ui/card_action_menu.tscn`，共用主题是 `ui/turn_theme.tres`。对局场景的轮盘节点可在检查器中切换预览人数。

### Host 是玩家，也是本局逻辑协调者

Host 和其他人使用**同一套普通游戏 UI**，没有额外管理界面。房主在后台运行房间、随机发牌、计时、统一揭晓和结算逻辑。普通玩家通过 Godot 原生 ENet/RPC 发消息给 Host。

### 美术资产

**当前所有美术使用占位色块、原生控件和 `CanvasItem._draw()`。** 没有下载或安装美术资源、第三方控件或音效包。

## 自动化验证

以下命令中的 `godot` 可替换为已安装的 Godot **console** 可执行文件。

```powershell
godot --headless --path . --script res://tests/rules_smoke.gd
```

期望输出 `TURN_RULES_OK`。检查可调生命还可运行：

```powershell
godot --headless --path . --script res://tests/lives_smoke.gd
```

期望输出 `TURN_LIVES_OK`；覆盖 3 生命连续命中以及 12 人、5 生命的多轮守恒。

双实例正常流程：分别在两个终端运行：

```powershell
godot --headless --path . -- --turn-smoke-host
godot --headless --path . -- --turn-smoke-join
```

默认自动创建两人局、准备并完成对局；期望所有实例打印 `TURN_SMOKE_RESULT` 和 `TURN_SMOKE_FINAL ... phase=ended`。

四人测试：Host 传入 `--turn-smoke-host --turn-smoke-players=4`，另外启动三个带 `--turn-smoke-join` 的实例。

**多生命联网测试**：Host 使用 `--turn-smoke-host --turn-smoke-lives=3`，Client 仍使用 `--turn-smoke-join`；应看到被命中者 HP 2→1→0 后才淘汰，双方最终胜者一致。

超时测试：普通 Client 额外传入 `--turn-smoke-silent`，该玩家会准备但不提交承诺，服务器在 **15 秒**后按 PASS 结算。注意测试时不要使用过低的 `--quit-after` 帧数上限提前中止进程。

运行以下命令可以验证货币、暗牌和奖励结算。

```powershell
godot --headless --path . --script res://tests/economy_smoke.gd
```

期望输出 `TURN_ECONOMY_OK`。

## 代码结构

| 路径 | 功能 |
| --- | --- |
| `scripts/core/game_rules.gd` | 纯规则：每轮发牌、PLAY/PASS、循环位移、淘汰、统计 |
| `scripts/network/net_bridge.gd` | 唯一 ENet/RPC 入口、连接/断开/消息收发 |
| `scripts/network/action_commit.gd` | 一次性随机盐、SHA-256 承诺与 Reveal 校验 |
| `scripts/session/game_session.gd` | 房间与成员、15 秒计时、承诺收集、揭晓、轮次和终局 |
| `scripts/ui/wheel_view.gd` | 占位轮盘：扇区、名字、明牌小方框、指向 |
| `scripts/ui/main.gd` | 主菜单和联机大厅 |
| `scenes/ui/match_view.tscn` | 联机与本地共用的轮盘、手牌和统计界面 |
| `scenes/main.tscn` | 联机入口与共用界面场景树 |
| `scenes/local_test.tscn` | 单进程本地对局测试入口 |
| `tests/` | 规则自动化、双实例自动模式以及真实 UI 截图工具 |
| `docs/` | 完整需求、P2P 方案与设计记录 |

## 当前 Demo 已实现与未实现的分界

已实现：**房主大厅调整初始生命 1～5、全员同步、每轮命中扣 1、归零才淘汰**；同机或局域网 IP 直连、2～12 玩家逻辑边界（**目前仅实际自动化验证 2 和 4 个实例**）、成员准备、15 秒决策承诺、Host 不在决策期获取他人的出牌明文、自动 Reveal、统一规则结算、淘汰、统计、胜利、返回大厅。

暂未实现：**公网短房间码发现、NAT 穿透/中继、两台异网设备整局验收**、12 人极端 UI 验收、主机迁移、人机补位、正式资源。

本 Demo 不承担商业级反作弊。Host 可以中止房间，也负责生成公开随机结果，尚无多方可验证的骰娘协议。

**特别限制**：在玩家已经提交 SHA-256 承诺、但自动揭晓前掉线时，Host 无法凭哈希恢复真实行动。本 Demo 会停止该次对局并提示异常，**不会私自改成 PASS**。这一边界仍待正式版决策；普通玩家未提交承诺时自动 PASS 已实现。

本版进度与具体测试记录见 [最小 Demo Validation](docs/05-engineering/06-demo-validation.md)。
