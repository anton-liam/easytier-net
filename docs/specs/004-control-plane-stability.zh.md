# 004 控制面稳定性和重入兜底 Spec

## 要解决的问题

出口策略会修改 source/exit 节点的路由、防火墙和 NAT。若策略错误、exit 失效、EasyTier interface 抖动或 Web 短暂不可达，A/B 节点不能因此永久失去 C Web 控制台控制面连接。

本 spec 定义 A/B/C 三节点环境下的稳定性边界：策略切换和故障注入期间，A/B 到 C 的 Web/config-server/control-plane 流量必须始终优先走 underlay；若短暂失败，Agent 必须持续重入并重新上报状态。

## 不解决的问题

- 不保证公网宽带本身不断线。
- 不保证 C 整机宕机期间 A/B 仍能上报。
- 不实现复杂多路径 HA 控制面。
- 不把 Web 做成远程 shell 平台。
- 不通过修改 EasyTier 数据面核心实现兜底。
- 不在第一阶段引入 OpenClash、订阅规则或 DNS 分流。

## 目标用户和使用场景

目标用户是在 R3S/iStoreOS 上部署 A/B 节点，并通过 C Ubuntu Web 控制台集中编排出口策略的管理员。

核心场景：

- A 作为 source，经 B 作为 exit 异地出口。
- Web 控制台实时把 A 的出口切换到 B，后续也可切换到其它 exit。
- A/B 在策略切换、Agent 重启、Web 重启、exit 断开后，仍能恢复与 C 的控制面通信。

## 系统边界

控制面包括：

- Web API：`http://C:11211`
- config-server/WebClient：`udp://C:22020`
- relay/中转节点地址
- SSH/本地管理地址
- Agent report API

受管数据面包括：

- source 节点 `managed_cidrs`
- source 节点 `ingress_ifaces`
- 可选 source 节点自身普通出站流量
- exit 节点 forwarding/NAT

控制面流量不得被受管数据面策略捕获。

## 稳定性要求

### 控制面保护路由

Agent 在应用 source 策略前必须先生成控制面保护路由。

验收标准：

- apply plan 中 `protect_control_plane` 必须出现在 `route_managed_traffic` 前。
- source 节点策略路由表中必须存在 C Web host 的 `/32` underlay route。
- route table 中 C Web host 的 `/32` route 不得经 EasyTier exit peer。

### Apply Verify Rollback

Agent 应用策略时必须执行：

```text
preflight control-plane verify
protect control-plane route
apply route/firewall/NAT
post-apply control-plane verify
success -> report active/prepared
failure -> rollback -> report rollbacked/degraded
```

验收标准：

- preflight 失败时不得应用策略。
- post-apply 失败时必须生成 cleanup/rollback plan。
- rollback 后必须上报 `policy_status=rollbacked` 或 `degraded`。

### Run Loop 重入

`easytier-agent run` 是长期进程，不能因为单次 Web 拉取失败、report 失败或网络抖动直接退出。

验收标准：

- 单次 reconcile iteration 返回错误时，进程继续运行。
- 下一轮 interval 到达后继续拉取 desired policy。
- Web 恢复后 Agent 能重新应用或上报 observed state。

### Web 重启恢复

Web 重启后必须能从 DB 恢复 desired policy 和 observed reports。

验收标准：

- `gateway_runtime_reports` 不得按 `machine_id` 覆盖不同 policy/role 的 observed state。
- Web 重启后策略快照仍能按 source/exit role 显示 observed version/status。

## UTM 稳定性验收

第一阶段 UTM 验收环境：

```text
C Web: 192.168.64.4:11211
A iStoreOS: 192.168.64.2
B iStoreOS: 192.168.64.3
```

验收命令：

```sh
make utm-stability-test
```

最小覆盖：

- A 能访问 C Web。
- B 能访问 C Web。
- C 本机 Web API 可登录并读取 gateway policies。
- A/B 上 `easytier-core` 进程存在。
- A/B 上 `easytier-agent` 进程存在。
- A/B 到 C 的主路由不经过 EasyTier interface。
- 当前 enabled gateway policy 的 observed source/exit version 与 desired version 对齐。

可选故障注入：

```sh
UTM_STABILITY_CHAOS=1 make utm-stability-test
```

故障注入必须覆盖：

- 短暂停止 A/B Agent 后由 procd 自动重启。
- 重启 C Web 后 A/B 仍能重新访问 C Web。
- Agent 重启后 A/B 仍能访问 C Web。
- Agent 重启后 observed state 能恢复。
- A/B 到 C Web 的路由仍走 underlay，不经 EasyTier tunnel。

后续增强故障注入覆盖：

- 删除 EasyTier interface 后 Agent 进入 degraded 或 rollback。
- 断开 exit 节点后 source 进入 degraded 或 rollback。
- 在策略路由表中注入错误 default route 时，C Web `/32` protected route 仍可达。

## 失败处理

任一稳定性测试失败时，测试脚本必须：

- 输出失败节点。
- 输出失败检查项。
- 输出下一步排查命令。
- 返回非零退出码。

不得静默跳过 A/B/C 中任一节点。
