# 001 产品范围 Spec

## 要解决的问题

本阶段要把 EasyTier 从“节点可组网”推进到“Web 控制台可管理任意节点之间的全量出口转发”。

Web 控制台必须能在同一 EasyTier 网络内选择任意一个 source 节点和任意一个 exit 节点，创建、启用、停用、切换 full tunnel 出口策略。策略启用后，source 节点的默认出口流量经 EasyTier 网络转发到 exit 节点，由 exit 节点通过系统 forwarding/NAT 出口。

## 不解决的问题

本阶段不解决以下问题：

- 不实现公网级安全鉴权体系。
- 不实现 device token、enrollment token、scope RBAC。
- 不实现 OpenClash 集成。
- 不实现任意远程命令执行。
- 不实现任意流量分类规则引擎。
- 不修改 EasyTier 数据面核心。
- 不实现多租户计费、套餐、配额。

鉴权第一阶段沿用 EasyTier 默认 Web 用户/session/token 能力，仅用于内网、containerlab、UTM 和受控测试环境。

## 目标用户和使用场景

目标用户是需要集中管理多台 EasyTier 节点出口路径的管理员。

典型场景：

- 管理员在 Web 控制台选择 `node-a -> node-b`，让 `node-a` 的所有出口流量走 `node-b`。
- 管理员实时切换为 `node-a -> node-c`。
- 管理员停用 `node-a` 的出口转发策略。
- 多个 source 节点同时使用同一个 exit 节点。
- 节点切换出口时，Agent 仍能保持与 Web 控制台、config-server、relay 的控制面连接。

## 当前系统边界

仓库职责：

- `easytier-net`：总控仓库，保存 spec、plan、target、lab、runbook。
- `vendor/EasyTier`：EasyTier fork 工作区，实现 Web 控制台 policy/report API 和 Agent。
- `vendor/luci-app-easytier`：LuCI fork 工作区，实现 OpenWrt/iStoreOS 本地配置和状态入口。

修改边界：

- 可以改 EasyTier Web 控制台、Web API、proto/control-plane。
- 可以新增 `easytier-agent`。
- 可以改 LuCI 插件和 OpenWrt package。
- 不改 EasyTier tunnel、peer、NAT traversal、packet forwarding 数据面核心。

## 核心能力

本阶段必须实现：

- Web 创建 logical policy：`full_tunnel_exit`。
- Web 将 logical policy 拆成两个 device policy：
  - source 节点：`client_exit_via_peer`
  - exit 节点：`provide_exit_for_peer`
- Agent 执行 source 节点默认路由切换。
- Agent 执行 exit 节点 forwarding/NAT。
- Agent 在修改默认路由前保护 control-plane underlay route。
- Agent 上报 runtime report 和 policy apply result。
- Web 展示 desired state 和 observed state。
- containerlab 验证策略启用、切换、停用和失败回滚。

## 稳定性原则

控制面流量永远不能被 full tunnel 策略劫持。

Agent 修改 default route、policy route、firewall/NAT 前，必须先建立 control-plane protected routes。若无法确认 Web/control-plane 可达，禁止应用 full tunnel 策略。

切换策略后必须再次验证 Web/control-plane 可达。验证失败时必须回滚到 last known good 状态。

## 转发实现边界

基础出口转发使用系统路由和防火墙能力：

- OpenWrt/iStoreOS：`uci firewall -> fw4 reload -> nftables`
- 普通 Linux：`iproute2 -> nftables`

不得依赖 OpenClash 实现基础出口转发。

不得在通用 Agent 逻辑中写死 `iptables`。旧系统兼容只能放在 platform backend 中，并且必须在 runtime report 中上报实际 backend。

## 可观测性要求

Web 控制台必须展示：

- logical policy desired source/exit 节点。
- source 节点 observed exit 节点。
- exit 节点 observed provider 状态。
- policy version。
- source apply result。
- exit apply result。
- control-plane health。
- internet exit health。
- 最近失败原因。

## 验收标准

containerlab 至少验证：

- 创建 `node-a -> node-b` 策略后，`node-a` 默认出口走 `node-b`。
- 切换 `node-a -> node-c` 时，`node-a` 和 Web 控制台的连接不中断超过设定阈值。
- 停用策略后，`node-a` 删除 full tunnel 默认路由并恢复 last known good 状态。
- 下发不可达 exit 节点时，`node-a` 不失联，策略进入 `degraded` 或 `rollbacked`。
- 多个 source 使用同一个 exit 时，停用其中一个 source 不影响其它 source 的 NAT/forwarding。

