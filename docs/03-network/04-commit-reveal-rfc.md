# TURN · 行动 Commit–Reveal 协议 RFC v0.2

> 日期：2026-11-18；**仅设计评审，未批准施工或安装网络插件**。  
> 来源：原始 `turn.md` v0.1 的公开手牌、秘密出牌、统一公开、每轮淘汰 1 人、保留未使用手牌、统计守恒；以及用户后续确认的房主型 P2P 候选、房主也不能提前知道他人行动、**15 秒只用于决策/锁定，之后允许揭晓验证**。  
> 本文中“2 秒冻结确认、5 秒揭晓”等都是**待批准的建议参数**，不是已确认需求。联网传输 ENet/WebRTC、是否使用轻量服务、Host 退出策略仍按 D-03 讨论。

## 0. 必须先理解的安全边界

**Commit–Reveal 能保证：** 在玩家行动明文发送之前，合法的高熵 salted hash 承诺不泄露所选牌及方向；已经承诺的玩家在公开他人动作之后不能再修改自己的有效行动；任何一端可以用相同的规则检查被公布的动作和结果。

**Commit–Reveal 不能单独保证：** 所有玩家一定揭晓、Host 一定广播所有人的承诺与揭晓、Host 不作弊地选择骰子结果、Host 不故意取消游戏、12 人收到揭晓的时刻完全同步。Host 的星形路由可以单独控制发送给各客户端的消息；只在 Host 上保存日志不能防止恶意 Host 伪造或选择性隐瞒事件。

> 最重要的规则冲突：既有 D-06 要求“已确认的合法行动掉线后保留”。但在只传 hash 的方案中，行动**直到 Reveal 才能验证其具体内容**；如果确认后断线且未 Reveal，其他端无法从 SHA-256 逆推出卡牌/符号。下文把该场景单独列为阻塞产品决定，不擅自将已承诺行动改成 PASS。

## 1. 状态机与时间轴（建议版）

~~~mermaid
stateDiagram-v2
  [*] --> ROUND_READY
  ROUND_READY --> COMMIT_OPEN: 明牌与初始指向公开，协调端开始倒计时
  COMMIT_OPEN --> FREEZE: 存活者全部锁定/自动PASS 或 15 秒到期
  FREEZE --> REVEAL_OPEN: 公共承诺名单一致性检查通过
  FREEZE --> ABNORMAL: 名单冲突、必要回执缺失
  REVEAL_OPEN --> VERIFY: 所有要求揭晓者提供数据 或 揭晓期限到达
  VERIFY --> ROUND_RESULT: 所有有效动作得到一致处理
  VERIFY --> ABNORMAL: 承诺者失联/不揭晓/校验失败且政策未确定
  ROUND_RESULT --> [*]
  ABNORMAL --> [*]: 暂停/弃局/恢复策略待决
~~~

| 阶段 | 暂定持续时间 | Host / 协调端 | 玩家端 |
| --- | --- | --- | --- |
| ROUND_READY | 无固定时长（待讨论） | 发布手牌、初始指向、alive_order、round_id；等待 UI/客户端准备就绪 | 展示明牌；校验版本和身份 |
| COMMIT_OPEN | **15 秒已确认** | 接收承诺并给本人回执；仅广播确认人数 | 草稿可改；按确认后生成哈希并锁定；仍不发送明文 |
| FREEZE | **建议最多 2 秒** | 按稳定 player_id 顺序固定承诺名单；未提交者标记 AUTO_PASS；发送共同名单摘要 | 必须检查自己的 commit 是否原样出现、Host 自己是否也在名单里；反馈摘要 |
| REVEAL_OPEN | **建议最多 5 秒** | 仅在冻结名单确认成功后请求揭晓 | 本地自动发送 action + nonce（不是再让玩家手动按一次） |
| VERIFY | 视网络与计算，待测 | 汇集全部揭晓并进行校验与行动合法性检查 | 同时自己重算所有已揭晓承诺/本轮结果 |
| ROUND_RESULT | 展示时长待定 | 广播最终动作集合、位移、弃牌、淘汰与统计 | 播放动画，等待下一轮 |

- 所有玩家提前完成**承诺**即可提前结束 COMMIT_OPEN。**“承诺已提交”不等于“动作已验证并被成功执行”**，界面和日志要分别记录。
- Host 发送给客户端的任何截止时间只是当前权威协调计时的声明。不同设备的网络延迟不同，客户端实际接收时间会有差异，**不能宣称所有人有完全相等的有效网络操作时间**。正式版需依据网络测试制定同步与容错方案。
- 2 秒 FREEZE 和 5 秒 REVEAL 暂定为配置参数，保留调整空间；如果 FREEZE 出错，不能先继续揭晓以“赌一下结果一致”。
- 进入 REVEAL_OPEN 后不允许新 commit 或更换已经锁定的动作；全体揭晓完可以提前进入 VERIFY。

## 2. 提交承诺需要绑定的字段（规范化编码 v1）

~~~text
ActionCommitV1 {
  domain_tag    = "TURN/ACTION_COMMIT/V1"
  protocol_ver  = 1
  match_id      = 一局稳定 ID
  round_id      = 当前回合 ID
  player_id     = 一局稳定身份
  action_type   = PASS 或 PLAY
  card_id       = PLAY 时的具体卡牌唯一 ID；PASS 使用规范空值
  sign          = +1/-1；PASS 使用规范空值
  nonce         = Crypto.generate_random_bytes(32) 产生的一次性随机盐
}
commit_hash = SHA256(规范化字节编码后的 ActionCommitV1)
~~~

- PASS 和 PLAY 都按相同流程生成 **独立高熵 nonce**，否则 PASS、+1、-1 可能因选项有限被 Host 枚举猜出。
- action 字段不是玩家牌面的数字，而是 **card_id + sign**；避免同数字的两张牌被混为一张。
- 必须定义一份固定序列化规则：UTF-8 文本编码、整数宽度/字节序、字符串长度前缀、字段顺序、空值格式都保持一致；**不可以简单依赖 Dictionary/JSON 的不确定键顺序**。
- 同一个 commit_hash 的重发视为幂等请求；同一回合不同 hash 的二次确认必须拒绝。
- 接收方检查网络身份与 player_id 绑定、match_id/round_id、存活、阶段、格式长度与重复提交。由于不知道明文，此时**无法验证卡牌归属/动作合法性**，这些验证必须等 Reveal。
- Host 本人必须按照同一机制生成 commit。每一端保存自己的 action + nonce 到本轮结束；不可在收到 COMMIT_ACK 后清除。

## 3. 冻结承诺名单（关键的防偷看关口）

~~~text
COMMIT_FREEZE {
  match_id, round_id, roster_hash,
  entries: [
    { player_id, status: COMMITTED, hash: "<SHA256>" },
    { player_id, status: AUTO_PASS }, ...
  ],
  manifest_hash
}
~~~

- Host 排序并广播同一份完整 roster + commit 清单（**包括 Host 自己的承诺**）。尚未提交者在 15 秒截止时以 AUTO_PASS 定义，不需要 Reveal，也不能消耗牌。断线者按已确认的非 Host 规则自动 PASS。
- 客户端比较本地预期的 roster、自己的 hash、Host 的 commit、round_id 和 manifest_hash。不一致必须拒绝揭晓并报告不同步。
- 建议客户端对**唯一** manifest_hash 做 ACK；同一玩家在同一回合不能 ACK 两份不同名单；Host 收齐在线者的相同 ACK 后才广播 REVEAL_OPEN。
- **安全限度**：如果所有 ACK 只发往恶意 Host，Host 仍可隐瞒/伪造确认报告，甚至向不同客户端发送不同名单。仅有本地 ACK 并不构成完整的拜占庭一致性证明。
- 强化方案：各参与者用经过验证的身份签署所确认 manifest_hash，Host 收集签名并广播完整回执集合，客户端在任何 reveal 之前校验全部有效签名与一致名单。需要公开密钥与身份生命周期，成本更高。另一可选方案是轻量可信服务只为 manifest_hash 提供共同见证/登记。**两者均未定案**。

## 4. 揭晓与合法性验证

~~~text
ACTION_REVEAL {
  match_id, round_id, player_id,
  action: { type: PASS | PLAY, card_id, sign },
  nonce
}
~~~

1. 每名已承诺玩家在收到自己验证过的 REVEAL_OPEN 后自动发送 action + nonce；Host 亦按相同规则揭晓。
2. 用本轮规范编码重算 SHA-256，与被冻结的 commit_hash 比对。不匹配、格式非法、身份不符，一律**不视为合法出牌**。
3. 验证 PLAY 的 card_id 确实属于当前玩家、没有用过、sign 是 +1/-1，PASS 不带牌 ID。
4. 统一生成 VERIFIED_REVEALS：按稳定 player_id 排序，包含所有已验证动作与没有承诺的 AUTO_PASS；汇总总位移。
5. 所有客户端独立重算 target=((s+delta)%n+n)%n、PLAYED、ELIMINATED 与 issued=played+eliminated+held。卡牌仅在**整轮结算有效并确认**后转为 PLAYED。
6. 若结果/commit/manifest 不一致，客户端不能私自按某一个 Host 结果推进下一回合；应报告分歧并进入异常流程。所有人出局后是否维持连接、终局返回原房间按 D-07。

## 5. 异常矩阵（设计建议，不是已批准惩罚）

| 场景 | 可以直接采用的原则 | 仍待明确的处理 |
| --- | --- | --- |
| 15 秒内未提交承诺 | **AUTO_PASS**，不花牌，正常参与轮盘 | 无 |
| 本轮 PASS 已提交承诺但尚未揭晓 | **不能从 hash 判断它是 PASS** | 同所有 committed-but-unrevealed 情况 |
| COMMIT_ACK 丢失/重复 | 同 hash 幂等回执；在 COMMIT_OPEN 内可重发 | 超出 15 秒后的迟到 ACK 仅用于确认已接收状态，不可新增 commit |
| 玩家提交两个不同 hash | 首次合法锁定为准，第二个拒绝 | 首次有效 commit 被 Host 故意隐瞒是对抗性问题 |
| 已承诺、揭晓前掉线 | hash 无法反推 card_id/sign | **D-06 冲突：选择暂停/弃局、改判 PASS 或可信托管** |
| Reveal 明文与 hash 不一致 | 不得把伪造动作计入结算 | 是判 AUTO_PASS、异常停止还是其他后果，待决 |
| 玩家故意不 Reveal | hash 无法强迫揭晓；可能影响淘汰结果 | 不能承诺零作弊。选择性不揭晓是已知攻击 |
| Host 未提交自己的承诺 | 不准让 Host 在 reveal 后补交 | 冻结/揭晓不能继续；走异常 |
| Host 给不同玩家不同 manifest | 发现摘要分歧拒绝继续 | 签名全体 ACK / 独立见证可加强检测 |
| Host 掉线 | 房主型拓扑下无法继续统一协调 | 用户已倾向房间终止，是否正式确认待决 |
| Reveal 到达顺序不同 | 不影响最终结果：锁定动作不可修改 | Host 仍可能率先看到明文、延迟转发或选择性 abort |
| Host 私自修改发牌/起点 | SHA action commit 不涉及随机发牌 | 骰娘随机公平机制需另外决策 |
| 旧 match/round 的提交 | 版本校验拒绝、不能跨回合影响牌 | 无 |

### 5.1 未揭晓者：存在三个互相竞争的处理路线

**N1：未揭晓动作按 PASS 继续**（最简单，但公平性较差）
- 正常一轮仍淘汰一个人；没有 Reveal 的承诺不消耗牌。
- 风险：当玩家在揭晓阶段看到他人行动后，可根据当前结果选择“Reveal 自己的动作”或“故意不 Reveal 变 PASS”，从而影响谁出局。
- 也与 D-06 的“已确认行动掉线后保留”不兼容。**不建议在要求房主与普通玩家公平的版本中悄悄采用。**

**N2：揭晓失败先暂停/重试，仍不能恢复则本轮异常终止**（无需外部托管）
- 给有限重试窗口；仍无法恢复已承诺明文时，标记 ROUND_ABORT，不计算出牌消耗与淘汰，不进入下一轮；可按产品决定中止整个房间或允许恢复。
- 优点：不会让对局悄悄按错误的行动集合结算，也不需要复杂服务。
- 缺点：玩家可通过拒绝揭晓恶意使比赛中断，**无法保证 D-06“已锁定动作一定被执行”**；如果允许直接重开本轮还可能出现刷结果问题。
- 若 GameJam 的首版不要求抗恶意玩家，N2 比 N1 更适合维护游戏结果的可信度，但可用性较差。

**N3：额外使用中立的秘密行动托管服务（Escrow）**（更强的掉线连续性）
- 玩家确认时把明文动作通过受信任的加密连接交给托管服务；服务对任何玩家包括 Host 均在冻结前不披露，截止后按协议自动公开，即使玩家已经掉线也能揭晓。
- 此方案能较好兼容 D-06“已确认行动保留”，也减少揭晓阶段恶意拒绝问题。
- 代价：必须信任和运维这个托管服务；它已承担**部分关键游戏规则的在线权威职责**，尽管房间/视觉/大部分游戏逻辑仍可在 P2P Host 上运行。不能声称“完全无服务器且零信任”。

**三者不可能在完全无服务、单一 Host 星形拓扑下同时提供“严格保密、绝不阻塞、掉线已确认行动必执行、任何玩家无法恶意放弃 Reveal”。**

## 6. Host 公平性分成四层，不承诺“一种哈希解决全部”

| 目标 | Commit–Reveal 本身 | 是否需要额外方案 |
| --- | --- | --- |
| Host 在 COMMIT_OPEN 阶段读不到别人行动 | **可以**（高熵 nonce、客户端本地保存明文、冻结后才 reveal） | 需要严格执行时序 |
| Host 看了别人 Reveal 后不能换掉自己已被冻结的动作 | **可以降低改动空间**，前提所有人看到同一份有效、不可伪造的承诺清单 | 建议 manifest/ACK；防恶意 Host 要认证签名/共同见证 |
| Host 不能隐藏消息/掐断网络/不揭晓 | **不能** | 外部可信协调、处理 abort 及明确规则 |
| Host 不能操纵发牌/初始指向的随机结果 | **不能** | DiceService 采用多人联合随机或中立可信骰娘；单方 Host RNG 仅可透明展示，不等于可验证公平 |

**“所有玩家几乎同时知道揭晓内容”不等于网络上必须同时收到。** 在 Host 星形拓扑中，Host 会先收到成员的明文；只要自己的承诺已冻结，它无法据此**合法**更改行动。但若要防 Host 选择性终止整场，则必须有更强见证或可信服务。

## 7. 与骰娘的衔接（暂不决定随机算法）

- 发牌和初始指向都在选择开始前**向所有人公布**；DiceService 需要发布事件，而不是客户端各自随机。
- 最简方案：Host 用 Godot RandomNumberGenerator 发牌、公布随机事件、所有客户端复核牌值范围和数量；**无法证明 Host 没反复抽取**。
- 更强方案：各存活玩家对随机种子先 Commit，再 Reveal，所有人校验后组合成种子，生成公开且可重现的牌值与指向（需要预先规定种子丢失的处理，且仍存在最后揭晓者拒绝揭晓问题）。
- 若用户要求绝对无房主控制权，可把随机数也托管给中立可信 DiceService；这会增加服务职责，需 D-03e 另行评审。
- **不要将用于保密行动的 nonce 重用于骰娘随机种子，也不要把未公开 nonce 放进公开的房间快照。**

## 8. 传输中立接口（避免未来更换 ENet/WebRTC 大改规则）

- `ActionProtocol` 只暴露：start_round、commit_action、freeze_manifest、reveal_action、verify_reveals、finalize/abort。
- `GameRules` 不依赖 RPC/Transport，输入验证后的动作集合和公开牌状态，输出淘汰与状态迁移。
- `TransportAdapter` 实现：send_to_host、send_to_peer、broadcast、connected/disconnected、ack/error；底层 ENet/WebRTC 可替换。
- `LobbyDiscovery` 只处理房间码和会话发现；若以后引入 EscrowService，其发布与保密职责不能混入 UI 或 DiceService。
- 决策时的客户端本地 action/nonce 存在内存，揭晓后按需求删除；重试只重复同一份 commit，不生成新的 nonce 与新 hash 以避开锁定。

更换网络库仍需重测身份、重发、消息排序、NAT/信令与公网，但不应重写轮盘数学、卡牌生命周期和结果动画。

## 9. 对应测试与准入（全部未执行）

| 编号 | 测试 | 期望 |
| --- | --- | --- |
| CR-01 | 2/8/12 人同一回合所有人合法 commit | Host 和普通玩家都提交唯一 hash；提前结束 15 秒 |
| CR-02 | 模拟 Host 读取收到的承诺 | 不能看到 action/card_id/sign/nonce，且无法穷举有限动作 |
| CR-03 | 同一个行动和 nonce 修改 card_id/方向/match/round | 更换字段后校验失败，不能跨局重放 |
| CR-04 | Host 未提交自己的承诺就要求揭晓 | 所有正常客户端拒绝 reveal |
| CR-05 | 提交名单分歧/缺少自己的 hash | 客户端拒绝 reveal；显示协议异常 |
| CR-06 | 15 秒没有提交承诺 | AUTO_PASS，仍只正常淘汰一名目标 |
| CR-07 | 承诺后揭晓前断线/失联 | 按选定 N1/N2/N3 策略，**不得暗中变更 D-06** |
| CR-08 | Host 部分转发 reveals、改变顺序/内容 | 哈希校验/规则结果校验可检测；恶意中止是否可避免属于选定信任模型 |
| CR-09 | Reveal 错 hash、错卡、错身份、旧回合、重复包 | 拒绝非法动作，绝无重复 PLAY/淘汰 |
| CR-10 | 最后一人提交与 15 秒定时器竞态 | COMMIT_OPEN→FREEZE 仅发生一次，状态版本唯一 |
| CR-11 | DICE 单机多次抽取但只公布一次 | 基础方案无法检测，明确列为不提供可验证公平 |
| CR-12 | 普通成员掉线 vs Host 掉线 | 分开按 D-06 与 D-03f 验收 |
| CR-13 | 不同网络真实多人 P2P 完整局 | 最终动作集合、统计和胜负一致；非开发机可用 |

## 10. 需要批准的新增决策

| 决策 | 问题 | 推荐的讨论顺序 |
| --- | --- | --- |
| D-03i | FREEZE + REVEAL 时限 | 建议先用 2 秒冻结 + 5 秒揭晓做网络实验；正式数值必须实测 |
| D-03j | 有承诺但缺失 Reveal 的处理 | N1：按 PASS 继续 / N2：异常停止 / N3：可信托管服务保证揭晓 |
| D-03k | 需要什么强度的 Host 防作弊 | K1：防提前偷看 + 客户端核验 / K2：签名或见证防名单分叉/冒充 / K3：可信托管和更强公平 |
| D-03e | DiceService 公平级别 | 仅公开随机结果 / 多方可验证随机 / 中立可信骰娘服务 |

D-03i/j/k 都仍待决；任何非正常中断、重赛或默认 PASS 均不得在未获批准时替代原规则。

## 11. 实际引用与已核对能力

- Godot 4.7 HashingContext（支持 SHA-256）：https://docs.godotengine.org/en/4.7/classes/class_hashingcontext.html
- Godot 4.7 Crypto（安全随机字节）：https://docs.godotengine.org/en/4.7/classes/class_crypto.html
- Godot 4.7 Multiplayer RPC（可靠、有序、身份与节点约束）：https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html
- 关于 Commit–Reveal / Last Revealer 的安全研究：https://eprint.iacr.org/2023/728.pdf
- 实务性的 Selective Abort 说明：https://logperiodic.com/commit-reveal.html

> 文档是**技术草案，不是安全审计结论**。并未安装组件、接入服务器、编写协议实现或进行任何真实网络测试。
