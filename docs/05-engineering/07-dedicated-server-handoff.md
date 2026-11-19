# TURN 联机专服交接

更新于 2026-11-19。Ubuntu 22.04 ECS 上运行 Godot 4.7.1 专服，客户端使用协议 2，通过 WSS 连接。

## 队友怎么进游戏

1. 打开同版 Windows 客户端，或用 Godot 4.7.1 打开同版工程后按 F5。
2. 客户端自动连接公网专服。连接完成后直接进入建房和输码界面，失败时点 **重试连接**。
3. 一个人点 **创建房间**，把六位房间码发给队友。其余人输码加入，然后都点 **准备**。
4. 房主点 **房主开始**。第一局保留默认 1 点生命，一轮就能对照双方结果。

**验收时看这三点**。一方确认后整个出牌区锁定，另一方在揭晓前只看到确认人数。结算时双方看到同一落点、淘汰者和胜者。短暂掉线时保持游戏进程运行，恢复网络后能回到原席位和当前对局状态。

## 这次做了哪些

| 功能 | 现在怎么工作 |
| --- | --- |
| 独立专服 | 玩家都连 ECS。玩家房主负责大厅操作，专服负责发牌、15 秒计时、行动校验和结算。客户端和专服共用一个 Godot 工程。 |
| 房间管理 | 专服生成房间码，管理成员与准备状态。玩家可以主动离房，房主可以在大厅转交权限或移出其他成员。开局与管理权限由专服校验。 |
| 掉线重连 | 游客身份与网络连接分开。专服检测到掉线后保留会话 60 秒，重新连上可恢复原席位、手牌、生命和本人锁定状态。掉线期间对局继续计时，已锁定行动保留，未提交到期按 PASS。 |
| 出牌和结算界面 | 确认后禁用选牌、加减、PASS 和再次确认。结算显示橙色最终落点、已出牌和「已淘汰」。 |
| 公网传输 | 本机用 WS，公网用 WSS。客户端使用公网 IP 证书验证专服。接入层有握手超时、连接上限和建房／输码限频。 |

## 代码从哪里看

| 文件 | 职责 |
| --- | --- |
| [启动入口](../../scripts/bootstrap.gd) · [专服场景](../../scenes/server.tscn) | 按运行参数选择启动客户端或专服。 |
| [网络收发](../../scripts/network/net_bridge.gd) · [专服入口](../../scripts/server/server_main.gd) | 监听、WSS、版本握手、接收并分发请求。 |
| [玩家会话](../../scripts/server/player_session_manager.gd) · [房间管理](../../scripts/server/room_manager.gd) | 玩家身份、连接绑定、恢复凭证、房主权限和房间生命周期。 |
| [对局管理](../../scripts/server/match_session.gd) · [原有牌局规则](../../scripts/core/game_rules.gd) | 对局管理负责计时、锁定、揭晓和重连快照，原规则负责发牌、位移、生命、淘汰和胜负。 |
| [客户端会话](../../scripts/session/game_session.gd) · [界面](../../scripts/ui/main.gd) · [轮盘](../../scripts/ui/wheel_view.gd) | 发玩家请求、自动重连、刷新按钮和结算画面。 |

## 云服怎么维护

本次部署使用 Ubuntu 22.04、`systemd`、固定公网 IPv4 和 Let’s Encrypt IP 证书。下面的路径按本次部署约定列出。

| 项目 | 配置 |
| --- | --- |
| 应用目录 / Godot | `/opt/turn/app` · `/usr/local/bin/turn-godot` |
| 系统服务 / 运行用户 | `turn.service` · `turn` |
| 客户端默认地址 | [project.godot](../../project.godot) 的 `turn/network/server_address`。换服后更新地址并重新导出客户端。 |
| 阿里云入站端口 | TCP `24680` 供玩家连接，TCP `80` 供证书签发与续期 |
| 证书续期 | Certbot 证书名 `turn-ip`。部署钩子 `/etc/letsencrypt/renewal-hooks/deploy/turn` 将新证书复制到 `/etc/turn/tls/`，并重启运行中的专服。 |

在 ECS 的 SSH 终端查看状态或日志：

```bash
sudo systemctl status turn.service --no-pager
sudo journalctl -u turn.service -n 50 --no-pager
sudo ss -lntp 'sport = :24680'
```

启动成功的日志是 `TURN_SERVER_READY port=24680 protocol=2 transport=WSS`。更新代码或手动重启前先提醒队友结束当前局，房间和游客会话保存在进程内存中，服务重启后需要重建房间。

检查续期定时器和验证链路：

```bash
systemctl list-timers --all | grep -i certbot
sudo /snap/bin/certbot renew --cert-name turn-ip --dry-run
```

## 验收记录

2026-11-19，从一台 Windows 电脑启动两个独立 Godot 4.7.1 客户端，经公网连接 Ubuntu ECS。使用系统信任链校验证书，正常连接后再运行牌局用例。

| 项目 | 结果 |
| --- | --- |
| 公网 WSS | 通过。TLS 1.3，Let’s Encrypt 证书的 IP SAN 与连接 IP 一致。 |
| 默认连接 | 通过。从正常启动场景打开两个客户端，未传地址参数或点击连接。两端自动进入大厅入口，打完一局且终局一致。开发参数也已实测能连接本机专服。 |
| 正常整局 | 通过。错房间码被拒，正确房间码可入房。三生命对局完成 3 轮，两个客户端的终局结果一致。 |
| 权限、掉线重连和离房 | 通过。普通成员的管理请求被拒。验证了房主转交、移出后重新入房、锁牌后换连接恢复原身份及锁定状态、原行动只结算一次、主动离房和回大厅。 |
| 15 秒超时 | 通过。一方不提交，客户端记录 `elapsed_ms=15000 action=pass`，双方终局一致。 |

此前本地还通过了双房间并行，以及 12 个客户端打完 11 轮且结果一致。**正式双设备异网验收仍待补验**，可以用家庭宽带和手机热点各进一台设备，完成一局并记录双方结果。**证书自动续期需在 ECS 上补跑一次 `--dry-run`**。

本机运行和脚本验收详见[项目 README](../../README.md)。
