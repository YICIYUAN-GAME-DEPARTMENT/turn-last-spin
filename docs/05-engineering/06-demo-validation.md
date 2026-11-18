# TURN 最小 Demo · Summary + Validation

> 验收时间：2026-11-18；平台：Windows，实际 Godot `4.7.1.stable.mono.official.a13da4feb`，Compatibility。  
> 本阶段用户批准从空白工程开始制作**最小可玩 Demo**；没有安装任何插件、创建外部服务器或导入正式美术素材。

## Summary

- 创建 `scenes/main.tscn`：唯一主场景、固定 `/root/Main/Net` RPC 路径，Host 和 Client 使用同一个 UI。
- 创建 `scripts/core/game_rules.gd`：完整的存活玩家一张公开牌、旧牌留存、同数字不同 card_id、正负位移环绕、每轮淘汰、出牌/淘汰弃统计和胜负判断。
- 创建 `scripts/network/net_bridge.gd`：Godot 原生 ENetMultiplayerPeer + 高层 RPC；未实现自定义 UDP 传输、可靠重发或第三方联网框架。
- 创建 `scripts/network/action_commit.gd`：Godot Crypto 32 字节 nonce + String.sha256_text 的 Commit/Reveal；选择期只向 Host 发送 hash。
- 创建 `scripts/session/game_session.gd`：房间成员/准备、房主开始、15 秒决定、已确认人数、冻结承诺名单、自动揭晓、最多 5 秒等待、统一结算、2.5 秒后续轮和游戏结束。
- 创建 `scripts/ui/main.gd`、`scripts/ui/wheel_view.gd`：原生 Control/Container、CanvasItem 绘制占位轮盘、明牌方框及基本交互。**Host 没有单独管理 UI**。
- 修改 `project.godot`：设置主场景及 Demo 初始窗口为 1280×820。
- 增加测试 `tests/rules_smoke.gd` 以及自动的多进程操作模式；增加 `tests/visual_capture.gd` / `tests/visual_game_capture.gd` 用来核对真正的 Godot GUI 渲染。
- 根目录增加 `README.md`，提供手动操作和自动测试步骤。

## Validation（实际结果，不是预期）

| 编号 | 验证 | 结果 | 证据 |
| --- | --- | --- | --- |
| V01 | Godot 4.7.1 编辑器以 headless 初始化工程 | **通过** | 编辑器退出码 0，无 GDScript 解析报错 |
| V02 | Godot 启动主场景 | **通过** | `--headless --path <project> --quit-after 40` 退出 0 |
| V03 | 规则与 Commit 单元冒烟 | **通过** | `TURN_RULES_OK rounds=11 issued=77 repeated_values=pass negative=pass commitments=pass` |
| V04 | 2 个独立 Godot 进程（Host/Client）完整对局 | **通过** | 双方 `TURN_SMOKE_RESULT` 中相同 winner、阶段 ended |
| V05 | 4 个独立 Godot 进程完整对局 | **通过** | Host 日志三次 `TURN_ROUND`，4 个实例 winner 一致，`stats_ok=true` |
| V06 | 真正的 Windows GUI 起始页面渲染 | **通过** | 成功生成桌面渲染图片；发现并修复连接栏 Label 换行导致控件拉高 |
| V07 | Host 正在游玩中的轮盘 UI 渲染 | **通过** | Godot GUI 截图显示扇区、玩家名称、方形牌框、公开明牌、15 秒操作按钮、统计 |
| V08 | 15 秒未提交自动 PASS | **通过** | 客户端故意不提交，约 15 秒后 Host 按 PASS 完成结算；Host/Client 的 TURN_SMOKE_RESULT 胜者一致且均输出 TURN_SMOKE_FINAL phase=ended。首次测试因帧数上限过低提前退出，已调高上限并重测通过 |

## 明确未通过或未覆盖

- **公网异网连接：未执行。** 暂时只支持输入 IP:UDP 端口。本地可连通不等于解决 NAT、CGNAT、短房间码的发现或中继。
- **正式 12 人图形布局：未执行。** 当前 2、4 人联网通过；逻辑单测 12 人通过。
- **冻结承诺后的掉线继续执行：未实现。** 仅存 hash 无法恢复行动明文，Demo 中止并明确提示，不把已承诺行动悄悄改成 PASS。
- **强公平/抗恶意 Host：不在此 Demo 内。** 不做签名名单 ACK、多方随机、主机迁移、可信动作托管或商业级防作弊。
- **正式美术/音频资源：未接入。** 当前全为 Godot 原生占位 UI。
- **最终 Windows EXE 导出：未执行。** 目前从 Godot 工程运行，未安装/操作导出模板。

## 复现流程

1. 使用 Godot 4.7.1 打开 `H:/Godot/turn--last-spin/project.godot`，按 F5。
2. 首个实例点击“创建房间 (Host)”；第二实例输入 `127.0.0.1` + `24680` 点击“直连加入”。
3. 两端准备，Host 开始。
4. 选择出牌+方向或 PASS 并确认，观察 15 秒内只同步确认人数；全部确认后自动揭晓。
5. 检查双方的初始指向、全部公开牌、最终淘汰、赢家和统计是否一致。
6. 必要时运行 [根目录 README](../../README.md) 所列的 headless 规则及多进程自动化命令。

## 下阶段 P0 工作（尚未动工）

- 确定 ENet 直连的公网可行性；若因 NAT 不可达，再评估成熟 WebRTC + 信令/STUN/TURN 实现。**不得因方便就写自制打洞轮子。**
- 设计并集成真正的短房间码查找功能，不能用本地房间标签冒充公网发现。
- 明确“已承诺但未揭晓掉线”的最终行为，以不偷偷改变已批准玩法为准。
- 扩展 8/12 人真实 UI 检查、正常导出、游戏体验和正式美术；继续先调研后编码。

当前本报告中的结果均来自实际测试或明确标明未执行；如果后续修改代码，需重跑相应 Validation。

## V09～V12：初始生命可调扩展（2026-11-18）

本次实现额外的 `initial_lives` 与 `lives[player_id]`，房主在大厅使用原生 SpinBox 设置初始生命 **1～5（默认1）**，通过原有 `lobby` 快照同步给 Client。轮盘命中玩家后扣 1，归零才淘汰并丢弃未用牌。

| 编号 | 实际验证 | 结果 |
| --- | --- | --- |
| V09 | Godot 4.7.1 编辑器重新加载 + 原 `tests/rules_smoke.gd` | **通过**：EXIT=0；默认1生命的12人11轮、77张发牌、重复牌/负位移/统计守恒正常 |
| V10 | `tests/lives_smoke.gd` 纯规则 | **通过**：EXIT=0；2人3生命依次 HP 2→1→0，存活前两轮不弃牌，第三轮淘汰；12人5生命、连续命中最先存活者，共55回合、385张累计发牌、牌数守恒 |
| V11 | 2个 Godot Headless 进程；Host `--turn-smoke-lives=3` | **通过**：Host 日志轮1 HP2/eliminated0、轮2 HP1/eliminated0、轮3 HP0/eliminated=玩家ID，Host/Client 的 TURN_SMOKE_RESULT 胜者一致 |
| V12 | Windows 实际 GUI 大厅/对局截图 | **通过**：大厅显示 Host 可调整的原生 SpinBox（当前3），对局轮盘上显示 HP 3，右侧明牌列表显示每人生命 3/3；没有增加额外美术素材 |

### 本轮仍未测的场景

- 人工同时操作两个 GUI 实例，手动改变大厅生命并在 Client 查看同值（已实现快照同步，并通过代码检查，**独立的客户端手动 GUI 验收尚待用户执行**）。
- 12 人、初始生命5时的极长手牌/长期对局布局，可读性尚未验收；不要继续引用原规则的“12人最多11轮”为通用上界。
- 公网短房间码/NAT/中继、正式 Windows EXE 导出、掉线已提交但未揭晓恢复，仍是后续阶段。

参见 [初始生命规范](../01-gameplay/03-initial-lives.md) 和 [根目录操作指南](../../README.md)。
