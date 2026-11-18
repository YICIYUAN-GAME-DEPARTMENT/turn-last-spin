# TURN 技术语言入门：GDScript、Godot 场景与备选语言

> 2026-11-18 · 说明文档，**没有实际游戏代码**。D-02 曾由用户选择“采用推荐：Godot 4.7 + GDScript”；如团队比较后有更好的技术理由，可以重新评审。它与 P2P 网络架构是**两个独立的决策**。

## 1. GDScript 是什么

GDScript 是 Godot 团队为 Godot 开发的高级脚本语言，语法类似 Python，但**不是 Python**，并不等同于“在 Godot 里使用 Python 解释器”。Godot 能直接把 `.gd` 文件与场景节点关联，支持信号、资源、对象与可选静态类型。

- 文件名：`room_session.gd`、`rules.gd` 等。
- `extends Node`：表示当前脚本继承 Godot 中某个节点的能力。
- `func`：声明函数，`var` 变量，`const` 常量。
- `signal`：可定义事件，让 UI 和逻辑之间耦合更低。
- `@export`：可在 Godot 编辑器里配置部分变量。
- `int`、`String`、`Array`、`Dictionary`：常见数据类型。
- `var n: int = 12`：可显式写类型；并非所有 GDScript 必须动态类型。

## 2. 一小段只为展示语法的伪项目示例

```gdscript
extends Node
class_name TurnRules

const DECISION_SECONDS: int = 15

static func target_index(start: int, delta: int, n: int) -> int:
    assert(n >= 2)
    return posmod(start + delta, n)
```

说明：这是语法参考，**不是已实现或验证的游戏代码**。
- `static func` 表示无需实例化便可调用的辅助函数。
- `posmod` 对负位移做非负模计算，适合轮盘循环。
- 规则层可设计为只接受输入、返回结果，不需要依赖场景或网络；便于单元测试。
- UI 通过 Godot 的 `Control`、`Button`、`CanvasItem`、`Container` 绘制，不需要自己做窗口控件框架。

## 3. Godot 里的 Scene / Node / Script

- **Scene（场景）**：可序列化的节点树，常见是一个主菜单、游戏轮盘、房间界面等；通常是 `.tscn`。
- **Node（节点）**：场景组成单元。2D 绘制、文本、按钮、音频等都有现成节点。
- **Script（脚本）**：给节点增加行为，如按键回调、接收网络消息，或做独立逻辑工具。
- **Signal（信号）**：事件通知，例如按钮按下、成员准备变化、牌面公开，不必互相直接依赖具体实现。

## 4. 与 C#、C++ 的选择

| 方案 | 优点 | 代价 | 在 TURN 的定位 |
| --- | --- | --- | --- |
| GDScript | Godot 原生结合紧密、开发速度快、教程和示例多 | 如果团队已有成熟 C# 工具与库，可能不能充分利用 | **目前 D-02 已选，可再次评审** |
| C# | 更通用的静态语言、IDE/重构支持、成熟 .NET 生态 | 需要 Godot .NET 版与匹配环境，部署和构建依赖更多 | 技术上可行，团队 C# 强时值得比较 |
| C++ / GDExtension | 原生性能与外部 SDK 接入能力 | 编译、ABI、平台兼容与维护工作更多 | 有性能或联网 SDK 需求再考虑，不必为了 12 人轮盘自研核心 |
| Python | 用户可用来写外部分析/验证工具 | 并非 Godot 原生的首选游戏脚本 | 不建议当 Godot 主业务脚本语言 |

**结论**：仅从这款 2～12 人、低频回合制轮盘游戏来看，没有证据表明必须用 C++ 才能满足性能；是否需要插件更多由 **P2P 公网连接与平台 SDK** 决定，和规则计算复杂度无关。

## 5. 这不自动决定 P2P

GDScript 不是“联机语言”。同一套 GDScript 规则在房主型 P2P、全员 Mesh 或其他选定网络方式中都可以复用；真正影响连通性的是 `MultiplayerPeer` 类型、NAT 穿透与平台服务，以及如何组织身份/随机/计时/动作保密。

## 6. 官方一手资料

- Godot 4.7 脚本语言选型：https://docs.godotengine.org/en/4.7/getting_started/step_by_step/scripting_languages.html
- Godot 4.7 GDScript 参考：https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_basics.html
- Godot 4.7 高层多人联网：https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html

> 当前只是文档，未新增 `.gd` 或 `.tscn`，没有安装 .NET、GDExtension 或联网插件。
