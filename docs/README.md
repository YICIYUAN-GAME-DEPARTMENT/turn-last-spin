# TURN: Last Spin · 设计文档导航

> **2026-11-19 当前实现：独立专服 C/S。** 已加入游客重连和大厅成员管理，公网采用 WSS。跑游戏看[项目 README](../README.md)，接手云服和查看公网验收结果看[联机专服交接](05-engineering/07-dedicated-server-handoff.md)。

## 2026-11-18 原型与方案记录

以下内容记录此前的玩家房主模式与 P2P 评审。当前版本的运行和验证以项目 README 为准。

> **项目状态：最小 Host-Client Demo 已实现并通过本机多实例验证；正式公网 P0 仍未完成。** 最近修订 2026-11-18。  
> 工程路径：`H:/Godot/turn--last-spin`；Godot **4.7.1** / GL Compatibility，已建立 `scenes/main.tscn`、GDScript 规则、ENet/RPC 和原生占位 UI。原始上传文件所称旧本地人机原型并不存在，本版代码是新实现。
>
> 用户最新明确要求：**P2P 在线多人游戏**。原始上传 `turn.md` v0.1 §7.1 的“固定公网权威专用服务器”是旧版技术建议，已被 P2P 决策覆盖。原始玩法、2～12 人、公网跨网络真实可玩、秘密揭晓和一致结算的目标仍需满足。回合建议 20 秒已由用户确认值 **15 秒**覆盖。

## 先读这五份：避免未经评审就确定架构

1. [P2P 整体架构候选](02-architecture/03-p2p-architecture-options.md)：P2P 到底是什么、Host-Client 和 Mesh、谁判定结果、各部分如何实现、关键风险及所有待拍板事项。
2. [P2P 公网连接方案](03-network/03-p2p-connectivity-options.md)：ENet 直连、WebRTC 信令/STUN/TURN、Steam 平台方案、房间码如何寻找房主、是否真的不用服务器。
3. [决策登记簿](00-product/02-open-decisions.md)：**D-03 P2P 方向已确认，但 D-03a～h 细节全部待决**；其他 D-02 和 D-04～08 已确定业务行为。
4. [Commit–Reveal 协议 RFC v0.2](03-network/04-commit-reveal-rfc.md)：**15 秒选择承诺**、承诺名单冻结、独立揭晓、异常处理、Host 公平性与新增待决规则。
5. [P2P 施工路线](05-engineering/03-roadmap.md)：哪一步先验证公网、什么时候处理 15 秒与揭晓、何时制作 UI、每步验收什么。**路线仍是建议，不是施工授权。**

## 分类索引

| 类别 | 文档 | 内容 |
| --- | --- | --- |
| 00 产品 | [01-brief-scope.md](00-product/01-brief-scope.md) | 产品 P0/P1、原始规则、原文与当前决定的冲突说明 |
| 00 产品 | [02-open-decisions.md](00-product/02-open-decisions.md) | 已确认与未决事项、P2P 八项关键架构决策 |
| 00 产品 | [03-requirements-map.md](00-product/03-requirements-map.md) | NET-01～13 / UI-01～07 / A01～A11 追踪 |
| 01 玩法 | [01-rules.md](01-gameplay/01-rules.md) | 明牌、行动、淘汰与统计不变量 |
| 01 玩法 | [02-playtest-balance.md](01-gameplay/02-playtest-balance.md) | 5～8 人参与感、主动 PASS 与 15 秒超时区分 |
| 01 玩法 | [03-initial-lives.md](01-gameplay/03-initial-lives.md) | **可调初始生命：1～5、默认 1，命中扣血、归零淘汰、回合上界** |
| 02 架构 | [01-system.md](02-architecture/01-system.md) | 现行 P2P 架构概览及模块边界 |
| 02 架构 | [02-domain-state.md](02-architecture/02-domain-state.md) | 领域实体、回合阶段与一致性约束 |
| 02 架构 | [03-p2p-architecture-options.md](02-architecture/03-p2p-architecture-options.md) | P2P 架构详细 RFC、完整流程与备选 |
| 02 架构 | [04-gdscript-guide.md](02-architecture/04-gdscript-guide.md) | GDScript 语法、Godot Scene/Node 与 C# 备选比较 |
| 03 联网 | [01-protocol.md](03-network/01-protocol.md) | 传输无关业务消息、明文 vs Commit-Reveal、Host 退出 |
| 03 联网 | [02-deployment.md](03-network/02-deployment.md) | P2P 交付与测试：是否需要平台/信令/中继 |
| 03 联网 | [03-p2p-connectivity-options.md](03-network/03-p2p-connectivity-options.md) | 公网 NAT、WebRTC、房间码和可选中继 |
| 03 联网 | [04-commit-reveal-rfc.md](03-network/04-commit-reveal-rfc.md) | **15 秒承诺 + 独立揭晓验证阶段**、Host 保密、异常与待决规则 |
| 04 UI | [01-ui-ux.md](04-ui/01-ui-ux.md) | 轮盘、牌框、倒计时、准备、出局观察与极端尺寸 |
| 05 工程 | [01-reuse-research.md](05-engineering/01-reuse-research.md) | Godot 原生能力/第三方复用评估 |
| 05 工程 | [02-testing.md](05-engineering/02-testing.md) | 规则、P2P 公网、Host 与非 Host 掉线及验收 |
| 05 工程 | [03-roadmap.md](05-engineering/03-roadmap.md) | 分阶段与先调研后施工门槛 |
| 05 工程 | [04-feasibility-audit.md](05-engineering/04-feasibility-audit.md) | 原 P0 技术能力审计；原集中式假定应以本次 P2P 补充说明覆盖 |
| 05 工程 | [05-minimal-demo-plan.md](05-engineering/05-minimal-demo-plan.md) | 最小 Demo 的精简技术选型与功能范围 |
| 05 工程 | [06-demo-validation.md](05-engineering/06-demo-validation.md) | **实际施工 Summary + 规则/联网/GUI/超时测试证据** |

## 决策标记与优先级

- **已确认**：Godot 4.7 + GDScript（具体补丁需统一）、2～12 人/默认 8、15 秒决策、房主创建房间及全部准备后开始、非协调者掉线 PASS、结束回房重新准备、人机 P1；**P2P 作为联机方向**。
- **待确认**：Host-Client 的具体技术实现、ENet/WebRTC 等底层选择、短房间码发现；**Host 不能在选择期提前看到其他人行动已确认**，但承诺冻结、揭晓期限、未揭晓异常（N1/N2/N3）、随机公平级别仍待决；Steam 已排除，发行独立 Windows EXE；Host 断线处置和服务成本继续讨论。
- 旧文档中因集中式架构产生的词语如“服务端”、“固定公网 UDP 服务器”，在未明确改成 P2P 时**不得当作已批准实现**。请以本页、现行 [01-system.md](02-architecture/01-system.md) 与 P2P RFC 优先。
- 每次讨论如果改变规则/功能，需要更新决策簿和测试；不能让原始 v0.1 的技术建议压倒最新用户明确要求。

## 工程现状、Demo 验证与下一阶段门槛

- **已按用户批准完成最小 Demo**：新增 `scenes/main.tscn`、规则 GDScript、Host-Client ENet/RPC、简化 Commit–Reveal、原生占位轮盘/手牌 UI 和规则/多实例测试。没有下载美术、安装第三方插件或部署服务器。
- **已运行通过**：Godot 4.7.1 规则单测、2 人联机、4 人多轮联机、15 秒超时自动 PASS、真正的 Godot GUI 截图。证据参见 [06-demo-validation.md](05-engineering/06-demo-validation.md)。
- **未实现且不能冒充通过**：公网短码发现、NAT/中继、两台异网真实整局、正式 12 人 UI、揭晓前已承诺玩家掉线继续执行已锁定行动、Windows EXE 正式导出。
- **先调研后动手**仍有效：查已有实现 → Godot 对应版本原生能力 → 第三方方案（兼容性、许可、维护、部署）→ 最小必要自研。
- 后续 P0 的联网/平台/美术实施仍需要用户继续明确目标与验收，不因为最小 Demo 通过就默认全部批准。交付反馈始终是 **Summary + Validation**。

## 2026-11-18 初始生命功能落地

新增 **LIFE-01**：房主在大厅使用原生 SpinBox 设置相同的初始生命（1～5，默认1），所有客户端同步；每轮轮盘命中者扣1，生命归零才真正淘汰。已通过规则测试、两进程三生命联网和 GUI 截图检查。

- [生命规则与边界](01-gameplay/03-initial-lives.md)
- [实际施工测试记录](05-engineering/06-demo-validation.md)

注意：本文件较早的“每轮必淘汰”或“12人最多11轮”历史判断只对**初始生命=1**有效，多生命会增加回合与牌量；正式 12 人多生命 UI 尚未全部验收。
