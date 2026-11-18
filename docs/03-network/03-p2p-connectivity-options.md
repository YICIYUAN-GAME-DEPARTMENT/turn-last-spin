# TURN：P2P 公网可达性、房间码、平台服务比较

> 2026-11-18 · RFC v0.1 · **尚未选择任何实际传输或部署技术**  
> 产品已确定采用 P2P；初始人数 2～12、默认 8；两台**不同网络**的设备完整联机仍是 P0，不能以本机或局域网多开代替。

## 1. 先把 P2P、NAT、打洞和“服务器”区分开

- P2P：最终游戏消息在玩家设备之间交换，**不要求每局必有独立运行的游戏计算服务器**。在 Host-Client 型 P2P 中，房主的游戏就是逻辑服务器。
- NAT（网络地址转换）：家庭网络、校园网和移动网络常让本机只有私有地址；其他玩家无法简单根据此地址从公网发起直连。运营商 CGNAT 下，房主通常也没有可自行映射的入站公网 IPv4。
- 端口映射/UPnP：允许外部请求进入某位房主电脑；是否能用取决于路由器权限、防火墙、网络类型，**不能保证校园网、手机热点可用**。
- Signaling（信令）：双方通过一个服务交换连接元信息；它不一定负责转发实际的游戏数据。
- STUN：帮助发现连接候选；不能保证所有 NAT 配对都能直连。
- TURN Relay：当无法打洞时，由中继服务转发游戏流量；**这是外部服务器资源**，尽管游戏结算仍然在玩家设备上进行。
- Lobby/发现：把短房间码关联到房主的网络身份或会话；**不是 P2P 网络 API 自带的通用服务**。

## 2. 哪些方案值得考虑？

| 方案 | 玩家公网体验 | 是否要自己维护外部服务 | 依赖/不足 | 初步定位 |
| --- | --- | --- | --- | --- |
| A. Godot ENet 房主直连 | 房主提供 IP/端口；在某些网络要手工映射 UDP | 可完全不自建服务 | 不能保证校园网/CGNAT/手机热点；普通短码入房需额外发现层 | **最小原型/可控网络环境** |
| B. ENet + UPnP | 有条件地自动映射端口 | 可不自建服务 | UPnP 依赖路由器开启与用户授权，遇到 CGNAT 仍可能不可用；有安全/隐私权衡 | 仅可选优化 |
| C. Godot WebRTC P2P | 尝试建立跨 NAT 直连；失败时可经 TURN 中继 | 通常需要信令服务；必要时 STUN/TURN 服务或第三方提供 | Windows 原生客户端需 **WebRTC GDExtension**，还要维护信令/ICE 逻辑 | 可跨多网络的候选 |
| D. Steam P2P/SDR | 通过 Steam 身份、Lobby、P2P API 和中继联机 | 未必需要自建信令/中继 | 依赖 Steamworks 接入资格、平台分发、账户与 SDK/插件；不能默认独立 EXE 可用 | 平台允许时重点评估 |
| E. 其他平台 P2P 服务 | 由对应平台提供会话/穿透/中继 | 视平台而定 | 必须逐项审核 Godot 4.7 插件、许可、免费额度和用户登录方式 | 备选，未验证 |
| F. WebSocket 服务器 | 可提供房间与联网 | 必须有 WebSocket 服务进程 | **纯 WebSocket 客户端↔中心服务是客户端服务器架构，不是 P2P** | 仅用于信令或非 P2P 备选 |

**结论**：若坚持“不用独立服务器且输入短房间码随处一键连接”，只能依赖平台已有服务，或者自己/第三方至少负责部分会话发现、穿透及中继。不能仅使用 Godot 的 `ENetMultiplayerPeer.create_server()` 就得到这三项能力。

## 3. Godot 原生可以复用的部分

- `ENetMultiplayerPeer.create_server/create_client`：可以在房主游戏里接待客户端；使用 UDP，Godot 高层 RPC 可直接使用。
- `ENetMultiplayerPeer.create_mesh/add_mesh_peer`：接口支持 Mesh；**不提供自动公网发现或 NAT 成功保证**。
- `WebRTCMultiplayerPeer.create_server/create_client/create_mesh`：同样适配 Godot `MultiplayerAPI`；其 mesh 需要逐个建立 `WebRTCPeerConnection`，类本身不创建 SDP offer/answer，不会自己完成信令。
- Godot 官方 WebRTC 教程写明：**原生（非 HTML5）客户端需要额外 GDExtension**；而浏览器版本内置 WebRTC 支持。这是当前 Windows 客户端的重要插件成本。
- Godot 场景/节点、RPC、Button/Control、CanvasItem、Tween、RandomNumberGenerator 与纯 GDScript 规则均可复用，均不需要从零开发网络包重传或自定义渲染管线。

## 4. “短房间码 + P2P”究竟依赖什么？

```text
建房：Host 创建本地对局
  ├── 直连方式：分享 IP:UDP 端口（不是正常意义的短房间码）
  ├── 平台方式：游戏平台创建 Lobby，生成可分享的 Lobby ID/邀请码
  └── 自有信令方式：Host 向发现服务登记 session_id → 短码映射
入房：其他人输入码/链接
  → 解析成要连接的房主身份或连接描述
  → 直接连或通过信令协商 / 平台中继
  → 连上才收到房间成员列表、准备、游戏消息
```

D-04 已确认**房主创建+房间码加入**，因此当前 P2P 方案必须能够说明“**码由谁生成、在哪里查找、怎样过期、如何处理重复与假码**”。不能把这部分留成一句“调用联网 API”。

如果坚持纯直连零服务，可考虑用包含网络信息的连接字符串取代短码，但这**不等价于已确认的房间码体验**，必须由用户正式变更 D-04。

## 5. 公网 NAT 的验收前置

1. 房主处在普通家庭宽带，另一客户端通过手机热点加入，尝试完成 15 秒回合。
2. 房主处于校园网/CGNAT 等无法映射入站端口的网络，检查连接是否仍可建立。
3. 房主与加入者交换网络环境；测试直连失败后的提示或中继切换，不假装已入房。
4. 被淘汰的玩家保持连接只读观看；确认前/后掉线遵守 D-06，但 **Host 掉线单独处理**，尚待 D-03f。
5. 同时存在两局/不同房间，身份、房间号、动作不能串局。
6. 2、8、12 人下测试连接增长、房间同步、轮盘 UI 和多轮保留卡牌。
7. 构建需在其他设备运行，不强制用户自行安装开发环境，除非平台/插件条款本身另有要求且经批准。

测试记录包含：网络类型、是否获得公网地址、是否可端口映射、使用哪种 relay/平台、是否出现掉线、客户端 Godot 版本和是否成功完成整局。

## 6. P2P 信任与安全边界

- 直接 Host-Client：Host 可以接收到其他人的提交；如果是**明文动作**，其拥有“揭晓前偷看”的技术可能性，与原文秘密选择的预期存在冲突。
- 要求 Host 也无法提前读取行动时，可采用 Hash Commit → Reveal，但**15 秒如何划分、揭晓缺席如何处理、随机数如何抗操纵**都必须一并确认。
- Steam SDR 官方说明对其受支持的流量提供认证、加密和中继，但**并非所有独立发行游戏默认可用**。尤其不应把 GodotSteam 某个插件的存在等同于平台资格、真实可用性和长期维护保障。
- “房主掉线不立即淘汰”与“继续一局比赛”不是同一个保证；没有迁移方案时 Host 离开可能令所有人中断。此风险必须在设计评审中明确接受或解决。

## 7. 当前应优先回答的现实问题

1. 目标发行环境是什么：比赛提供独立 EXE、Steam 分发、Web 还是其他？
2. 玩家是否允许使用 Steam / 第三方登录？
3. 是否**必须**让校园网和手机热点的普通玩家无需端口映射即可建房？
4. 是否接受一个轻量的外部发现/信令服务（但不运行游戏规则）？
5. 是否可以使用 TURN 等中继并承担平台额度/带宽成本？
6. 是否要求房主也不能提前得知别人的动作？
7. Host 离开是提示整场结束还是要无缝迁移？

在这些答案明确之前，不适合声称某条路线是唯一合理方案，更不应安装插件或实现协议。

## 官方/一手资料

- Godot 4.7 高层多人游戏与端口映射：https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html
- Godot 4.7 ENet 与 Mesh：https://docs.godotengine.org/en/4.7/classes/class_enetmultiplayerpeer.html
- Godot 4.7 WebRTC（原生 GDExtension 与信令）：https://docs.godotengine.org/en/4.7/tutorials/networking/webrtc.html
- WebRTCMultiplayerPeer：https://docs.godotengine.org/en/4.7/classes/class_webrtcmultiplayerpeer.html
- WebRTC 官方 STUN/TURN/ICE：https://webrtc.org/getting-started/peer-connections
- Valve Steam Datagram Relay（条件/限制）：https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay
- GodotSteam MultiplayerPeer GitHub 仓库已归档并迁至 Codeberg，不能直接拿旧仓库作为在维护的兼容依据：https://github.com/GodotSteam/MultiplayerPeer

## 8. 2026-11-18 独立 EXE、可用轻量服务的分阶段选型策略

**用户排除 Steam，优先 Host-Client，允许必要的网络服务，但不希望提前内定。** 推荐先验证原生 ENet Host-Client 的局域网协议与 15 秒协调机制，然后尽早在家庭宽带、校园网、手机热点之间实测 NAT 连接；公网不通时，不要把“生成房间码”当成解决方案。

### 短房间码是索引而不是连接本身

```text
Host 建房 → 向轻量发现服务/平台请求 short_code
发现服务记录 short_code → 会话标识 / Host 地址或信令数据（带有效期）
Joiner 输入 short_code → 查找会话 → 按所选 P2P 传输建立连接
```

如果没有发现服务，IP:端口直接分享是可以测试的替代，但**不是已确认的短房间码体验**；短随机字符在没有共享索引的情况下不能神奇地找到公网 Host。

### 两种基础设施职责要区分

- **发现/信令**：帮双方发现会话，或交换 WebRTC offer/answer/ICE 候选。只负责建立连接，不一定中继游戏数据。
- **TURN 中继**：无法 P2P 直连时转发网络流量。需要带宽与运维资源，但并不必然参与发牌/结算。TURN 中继与 TURN 游戏名称无关系。

### 2026-11-18 调研重点

- 官方 Godot ENet：通过 UDP 监听，公网入站常需要端口映射，NAT/CGNAT/校园网可能造成阻塞。
- 官方 Godot WebRTC：Windows 原生 EXE 需要 GDExtension；需要信令，STUN 协助寻址，必要时用 TURN 中继。WebRTCMultiplayerPeer 也支持 `create_server()/create_client()`，可以用 Host 星形拓扑，**并非只有 12 人 Mesh**。
- 原生 `MultiplayerAPI.multiplayer_peer` 支持替换底层 peer，但业务层独立程度、发现/连接/peer ID/超时/安全语义要分别测试。
- Steam 已排除，不进入当前候选实施路线。
- 网友、校园网与手机热点的公网成功率不能仅凭 API 文档确认；必须以真正异网设备测试。

参考：
- https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html
- https://docs.godotengine.org/en/4.7/classes/class_webrtcmultiplayerpeer.html
- https://docs.godotengine.org/en/4.7/tutorials/networking/webrtc.html
- https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Connectivity
