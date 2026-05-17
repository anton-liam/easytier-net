# 003 原生 EasyTier 控制链路优先 Spec

## 要解决的问题

当前出口策略实现出现了边界偏移：A/B 节点没有先作为 EasyTier 原生 WebClient 节点出现在 Web 控制台 `Device List` 中，而是通过独立 `gateway-nodes` 上报路径被用于策略编排。

本 spec 重新明确产品基础链路：所有可编排节点必须先通过 EasyTier 原生 `easytier-core -w/--config-server` 连接到 C 的 Web 控制台，成为 Web 控制台原生 machine。出口策略只能作为原生 machine 的扩展能力，不能替代或绕过 EasyTier 原有节点注册、heartbeat、网络实例下发和远程 RPC 能力。

## 不解决的问题

本阶段不解决以下问题：

- 不新增独立于 EasyTier WebClient session 的节点注册中心。
- 不使用 `gateway-nodes` 作为 Device List 的替代来源。
- 不让 Agent 独立决定组网关系。
- 不修改 EasyTier tunnel、peer、NAT traversal、packet forwarding 数据面核心。
- 不重做 Web 鉴权、RBAC、设备 enrollment token。
- 不实现 OpenClash 作为基础出口转发依赖。

## 目标用户和使用场景

目标用户是通过 Web 控制台集中管理多台 R3S/iStoreOS EasyTier 节点的管理员。

## 当前需求整理

当前明确需求如下：

1. 先恢复并验证 EasyTier 原始 Web 控制台能力。
2. A/B/C 三个节点必须通过 `easytier-core -w/--config-server` 连接 C 的 Web/config-server。
3. Web 控制台 `Device List` 必须能看到 A/B/C 三个原生 EasyTier machine。
4. Web 控制台必须先能对 A/B/C 下发原生 EasyTier network instance 组网配置。
5. 只有确认 A/B/C 已运行同一个 network instance 且 EasyTier IPv4 互通后，才允许进入出口策略功能。
6. 出口策略入口放在 Device Management 的已运行 network instance 状态区域，而不是污染 Device List。
7. 出口策略按钮在未满足条件时置灰，并显示明确原因。
8. 出口策略配置默认以当前 Device Management 节点作为 source，以当前 running network instance 作为策略上下文。
9. exit 候选只能来自同一个 running network instance 中的其它在线 machine。
10. 拓扑图是后续体验增强方向，第一阶段只预留，不实现。

基础场景：

- A：iStoreOS/R3S，运行 `easytier-core -w udp://C:22020/<user_token>`，等待 Web 控制台下发组网配置。
- B：iStoreOS/R3S，运行 `easytier-core -w udp://C:22020/<user_token>`，等待 Web 控制台下发组网配置。
- C：Ubuntu，运行 `easytier-web`、config-server/listener、relay/中转节点自身的 `easytier-core`。
- Web 控制台 `Device List` 能看到 A、B、C 三个原生 EasyTier machine。
- 管理员先通过 Web 控制台完成 A/B/C 的 EasyTier 组网。
- 组网成功后，管理员再在 Web 控制台为任意 source/exit 节点创建出口策略，例如 `A -> B`。

## 系统边界

### 原生 EasyTier 基础能力

节点必须先满足 EasyTier 原生 WebClient session 条件：

```text
easytier-core -w udp://<web-host>:22020/<user_token> --machine-id <stable-machine-id>
```

节点连接后：

- `easytier-core` 连接 C 的 config-server。
- 节点周期性发送 `HeartbeatRequest`。
- Web 后端通过 `ClientManager` 维护 session。
- `/api/v1/machines` 返回该节点。
- `Device List` 显示该节点。
- Web 控制台可以通过 `/api/v1/machines/:machine-id/...` 下发网络实例配置。

### 出口策略扩展能力

出口策略只能建立在原生 machine 基础上：

- source/exit 候选节点来自 `/api/v1/machines`。
- 策略启用前必须确认 source/exit 都在线。
- 策略必须关联已有 EasyTier network instance。
- Agent/runtime report 只补充 observed state，不作为节点是否存在的主来源。
- 若 Agent report 存在但 machine 不在线，Web 必须显示该节点不可编排。

出口策略必须复用 EasyTier 原生 network config 能力：

- source machine 的目标 network instance 必须公告 `managed_cidrs` 到 EasyTier 原生 `proxy_cidrs`。
- source machine 的目标 network instance 必须设置 `exit_nodes=[exit_peer_ipv4]`。
- exit machine 的目标 network instance 必须设置 `enable_exit_node=true`。
- exit machine 使用系统转发时必须设置 `proxy_forward_by_system=true`。
- 上述字段由 Web 控制台基于策略 desired state 更新原生 network config 并通过 WebClient 下发，不通过 EasyTier 数据面改造实现。

## 数据来源边界

### `Device List`

`Device List` 必须保持 EasyTier 原生语义：

```text
数据源：/api/v1/machines
用途：展示 EasyTier WebClient session 节点，并进入原生设备管理能力
```

禁止：

- 将 `gateway-nodes` 合并进 `Device List`。
- 用 Agent 上报伪造 EasyTier machine。
- 在原 Device card 中塞入出口策略角色按钮，导致原生设备管理语义混乱。
- 在 MVP 阶段新增独立于 Device Management 上下文的 Device List 出口策略主入口。

允许：

- 在节点详情或出口策略页展示与该 machine 相关的 Agent observed state。
- 在 Device Management 的已运行 network instance 状态区域增加“设置出口策略”上下文入口。
- 后续在拓扑图或策略页中提供更强的全局编排体验，但必须以原生 online machine 和 running network instance 为候选来源。

### `gateway runtime report`

runtime report 是原生 machine 的扩展状态：

```text
主键：user_id + machine_id
前置条件：machine_id 必须能对应 /api/v1/machines 中的原生 machine
用途：展示出口策略 observed state、Agent 状态、路由/防火墙/健康检查状态
```

若 report 中的 `machine_id` 不存在于当前在线 `/machines`：

- Web 不得把它显示为可编排节点。
- 出口策略状态显示为 `invalid_offline_machine` 或等价不可用状态。

## 关键流程

### 阶段 1：原生三节点上线

```text
C 启动 easytier-web
C 启动自身 easytier-core -w udp://C:22020/<user_token>
A 启动 easytier-core -w udp://C:22020/<user_token>
B 启动 easytier-core -w udp://C:22020/<user_token>
Web /api/v1/machines 返回 A/B/C
Device List 显示 A/B/C
```

验收标准：

- `/api/v1/summary.device_count = 3`。
- `/api/v1/machines` 包含 A/B/C 三个 `machine_id`。
- A/B/C 均能进入原生 Device Management。

### 阶段 2：原生组网下发

```text
Web 选择 A/B/C
Web 下发同一个 EasyTier network instance 配置
A/B/C 运行该 network instance
Web 通过原生 RPC 查询 running_network_instances
```

验收标准：

- A/B/C 的 `running_network_instances` 包含同一个 network instance id。
- Web 能查询该 network instance 的 network info。
- A/B/C EasyTier IPv4 互通。

### 阶段 3：出口策略扩展

```text
Web 只从在线 machines 中选择 source/exit
Web 创建 gateway_full_tunnel desired policy
Web 拆成 source/exit device policy
Agent 或扩展控制面在对应 machine 上应用策略
Agent 上报 observed state
Web 展示 desired/observed 差异
```

验收标准：

- source/exit 不在线时不能启用策略。
- source/exit 不在同一 EasyTier network instance 时不能启用策略。
- 策略生效后 source 受管流量经 exit 出口。
- Web/control-plane protected route 生效，切换时不失联。

## 安全边界

- Web 不下发任意 shell 字符串。
- Web 只下发结构化 policy。
- Agent 只处理已定义 policy 字段。
- 所有路由、防火墙、NAT 变更必须可 dry-run、可审计、可幂等、可回滚。
- control-plane underlay route 必须优先保护。
- exit Agent 必须为每个非默认 `managed_cidr` 建立回 source peer 的系统路由，例如 `ip route replace 192.168.10.0/24 via <source_peer_ipv4> dev <easytier_iface>`，否则 NAT 回包无法经 EasyTier 返回 source。

## 可观测性要求

Web 必须区分：

- `machine online`：来自 `/api/v1/machines`。
- `network instance running`：来自 EasyTier 原生 WebClient RPC。
- `agent/report online`：来自 runtime report。
- `policy desired`：来自 Web policy store。
- `policy observed`：来自 runtime report。

出口策略 UI 至少展示：

- source machine 在线/离线。
- exit machine 在线/离线。
- source/exit 是否在同一 network instance。
- Agent report 是否新鲜。
- desired version。
- observed source version/status。
- observed exit version/status。
- 最近失败原因。

## 出口策略入口体验

第一阶段出口策略创建入口放在 Device Management 的 network instance 状态区域。

显示规则：

- 当前节点出现在 `/api/v1/machines` 时显示入口区域。
- 当前节点有已选择的 running network instance 时启用“设置出口策略”按钮。
- 同一 network instance 中存在至少一个其它在线 machine 时启用按钮。
- 条件不满足时按钮置灰，并显示明确原因。

置灰原因必须至少覆盖：

- `节点未连接 Web 控制台`。
- `请选择一个 EasyTier network instance`。
- `当前网络尚未运行成功`。
- `当前节点未运行该网络实例`。
- `当前网络未发现可作为出口的对端节点`。

打开策略编辑器时：

- 默认 source 为当前 Device Management 节点。
- 默认 network instance 为当前已选中的 running network instance。
- exit 候选只显示同一 network instance 中的其它在线 machine。

当前阶段实现一个基于 Vue Flow 的上下文动态拓扑弹窗。拓扑入口放在“设置出口策略”按钮旁边，只服务于当前 Device Management 节点和当前 running network instance，不新增全局拓扑编辑器。

拓扑弹窗必须展示当前 network instance 的 EasyTier 组网拓扑，并用不同图层表达不同语义：

- 节点层：展示当前 network instance 内所有在线 EasyTier machine，不写死 A/B/C，后续必须支持多入口节点和多普通节点。
- 控制面搭线层：展示各节点到当前 Web/config-server 节点的连接关系，用蓝色虚线或等价样式表达 `control / config-server`，避免误解为出口流量。
- 数据面 peer 层：展示当前 EasyTier peer route 上报的互通关系，用中性色实线表达 `p2p`、`relay(n)`、`tcp`、`udp` 等数据面信息。
- 出口策略层：当存在 `gateway_full_tunnel` 时，用绿色动画流动线表达 source 到 exit 的受管出口方向。
- 出口网络节点：当存在出口策略时展示逻辑节点 `出口网络`，并用动画线表达 exit 到 underlay egress 的方向。

拓扑节点必须展示：

- machine hostname。
- machine id 短 id。
- EasyTier IPv4，若可从 peer info 或 observed report 得到。
- 节点角色：当前查看节点、出口节点、控制面节点、普通节点。

出口策略图层必须展示：

- source machine。
- exit machine。
- `managed_cidrs`、`ingress_ifaces`、`include_device_traffic`、`exit_egress`。
- desired policy version 与 observed source/exit version。
- observed source/exit status、EasyTier IPv4 和最近错误。

拓扑弹窗必须在入口节点区域提供“测试出口”按钮。第一阶段该按钮只执行有边界的结构化诊断，不执行任意 shell 命令：

- 策略已启用。
- source/exit machine 均在线且属于当前 network instance。
- source observed status 为 `active`。
- exit observed status 为 `prepared` 或 `active`。
- source/exit observed version 与 desired version 一致。
- source/exit EasyTier IPv4 存在。
- `managed_cidrs` 非空或 `include_device_traffic=true`。

诊断结果必须清晰显示通过、警告或失败项。真正的数据面出口验证仍以 Agent healthcheck、containerlab/UTM 测试和 runtime report 为准，不通过 Web 执行任意远程命令。

拓扑布局必须是数据驱动的，不允许写死 3 个节点的位置和数量。当前 UTM 三节点环境应显示 A/B/C；后续多入口节点指向同一出口节点时，应显示多条 source 到 exit 的出口策略动画线。

## 测试和验收标准

必须按顺序验收：

1. 原始 EasyTier Web 功能恢复。
2. A/B/C 三节点出现在 Device List。
3. Web 可对 A/B/C 下发原生组网配置。
4. A/B/C EasyTier 网络互通。
5. 出口策略页面只能选择在线且已组网的 machine。
6. 启用 `A -> B` 出口策略后受管流量从 B 出口。
7. 切换出口策略时 A 与 C Web/control-plane 不失联。
8. Device Management 的网络状态区域能打开当前策略拓扑弹窗，且“测试出口”能基于 desired/observed state 给出明确诊断结果。

任何实现如果不能对应以上顺序中的某一项验收标准，必须先暂停并回到 spec/plan 调整，不得继续叠加代码。
