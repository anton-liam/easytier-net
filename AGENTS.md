# AGENTS.md

本仓库是 `easytier-net` 的工程总控仓库，用于产品化 EasyTier 的集中组网、出口策略、节点遥测、OpenWrt/iStoreOS 部署和一键测试能力。

## 项目能力边界

本项目构建以下能力：

- Web 控制台统一管理 EasyTier 节点、网络实例、出口策略、运行状态和审计记录。
- 节点 Agent 接收 Web 下发的声明式策略，并在本机稳定执行路由、防火墙、NAT、健康检查和回滚。
- OpenWrt/iStoreOS LuCI 插件提供设备本地安装、基础配置、服务状态和日志查看能力。
- containerlab 提供日常一键三节点拓扑测试。
- OpenWrt/ImageBuilder 或 iStoreOS SDK 提供目标设备包和固件构建能力。
- UTM 虚拟机和真实 NanoPi R3S 仅作为验收环境，不作为日常开发依赖。

本项目不构建以下能力：

- 不把 Web 控制台做成任意远程命令执行平台。
- 不重写 EasyTier 的 tunnel、peer、NAT traversal、packet forwarding 数据面核心。
- 不把 OpenWrt 专属的 `uci`、`procd`、`fw4`、`nftables` 编排逻辑塞进 EasyTier 数据面。
- 不让 LuCI 承担中心化策略编排职责。

## 仓库职责

本仓库是 orchestration repo，负责组织工程、构建、测试和文档。

```text
vendor/EasyTier/             EasyTier fork 工作区
vendor/luci-app-easytier/    LuCI fork 工作区
scripts/                     通用工程脚本
targets/                     目标机器构建入口
tests/lab/                   containerlab 一键测试拓扑
docs/                        架构、策略、运行手册
dist/                        本地构建产物，禁止提交
build/                       临时构建目录，禁止提交
```

所有目标设备构建必须通过统一入口：

```sh
make build TARGET=x86_64-linux
make build TARGET=nanopi-r3s
```

所有日常实验环境必须优先通过：

```sh
make lab-up
make lab-test
make lab-down
```

## 中文 Spec 和 Plan 规范

所有新增产品能力、架构调整、跨仓库改动、目标设备适配、测试环境能力，都必须先写中文 spec，再写中文 plan。

推荐目录：

```text
docs/specs/               中文需求和架构规格
docs/plans/               中文实施计划
```

文件命名必须稳定、可排序、可检索：

```text
docs/specs/001-product-scope.zh.md
docs/specs/002-agent-architecture.zh.md
docs/specs/003-web-policy-api.zh.md
docs/plans/001-bootstrap-workspace.zh.md
docs/plans/002-easytier-agent-mvp.zh.md
docs/plans/003-containerlab-e2e.zh.md
```

Spec 必须回答：

- 要解决的问题。
- 不解决的问题。
- 目标用户和使用场景。
- 当前系统边界。
- 需要修改的仓库和模块。
- 数据模型和 API 边界。
- 状态机或关键流程。
- 安全边界。
- 可观测性要求。
- 测试和验收标准。

Spec 禁止出现：

- 未解释的“后续完善”。
- 无验收标准的能力描述。
- 只描述 UI、不描述数据和状态来源。
- 只描述命令、不描述声明式 policy。
- 把 EasyTier 数据面修改作为默认方案。

Plan 必须回答：

- 基于哪个 spec。
- 分几个阶段实施。
- 每阶段修改哪些文件或模块。
- 每阶段产出什么可运行能力。
- 每阶段如何测试。
- 每阶段如何回滚。
- 哪些任务可以并行。
- 哪些任务依赖上一步结果。

Plan 必须拆成可执行任务，每个任务至少包含：

- 目标。
- 涉及目录或文件。
- 实施步骤。
- 验证命令。
- 预期结果。
- 提交建议。

Spec 和 Plan 的语言必须使用中文，代码、命令、API 字段、文件路径保留英文原文。

Spec 和 Plan 必须避免空泛表达。以下表达不合格：

- “优化体验”
- “增强稳定性”
- “完善错误处理”
- “增加相关测试”
- “支持更多平台”

必须改写成可验收描述，例如：

- “Agent 在 healthcheck 连续失败 30 秒后执行 rollback，并上报 `policy_status=rollbacked`。”
- “Web 节点详情页同时展示 desired policy version 和 observed policy version。”
- “containerlab 测试必须断开当前 exit 节点后验证 source 节点进入 degraded 或 rollback 状态。”

任何实现代码提交前，必须能在 `docs/specs/` 或 `docs/plans/` 中找到对应设计依据；纯修复拼写、格式化、CI 配置的小改动除外。

## EasyTier Fork 开发规范

允许修改：

- Web 控制台后端 API。
- Web 控制台前端页面。
- Web/client control-plane proto。
- 节点注册、策略下发、运行状态上报、审计日志。
- 可选的 `easytier-agent` crate 或 agent 相关 SDK。

禁止修改，除非有明确设计评审：

- tunnel 数据面。
- peer 连接核心。
- NAT traversal 核心。
- packet forwarding 核心。
- 与 EasyTier 兼容性强相关的协议行为。

如必须扩展 EasyTier 本体，优先扩展 WebClient、heartbeat、RPC 或 proto 控制面，不改数据面。

## LuCI Fork 开发规范

LuCI 插件只负责设备本地体验：

- 配置 Web 控制台地址、token、machine id。
- 启停 `easytier-core` 和 `easytier-agent` 服务。
- 展示 Agent 状态、EasyTier 状态、当前策略版本、最近错误。
- 展示本地日志。

LuCI 插件不负责中心化策略决策，不直接生成复杂出口策略。

OpenWrt/iStoreOS 服务必须使用 `procd` 管理，配置必须落到 UCI 或明确的 `/etc/easytier-agent/agent.toml`。

## Agent 开发规范

Agent 是节点侧稳定执行器。它必须具备以下能力：

- 注册节点。
- 拉取或接收声明式 policy。
- 校验 policy。
- 生成执行计划。
- 应用系统变更。
- 验证生效结果。
- 失败回滚。
- 上报 runtime report。
- 上报 policy apply result。

Agent 必须支持以下执行阶段：

```text
validate -> plan -> apply -> verify -> commit
                         \-> rollback
```

Agent 不允许执行 Web 下发的任意 shell 字符串。Web 只能下发结构化 policy。

Agent 对系统的每次改动都必须满足：

- 可 dry-run。
- 可审计。
- 可幂等重复执行。
- 可检测当前状态。
- 可失败回滚。
- 可在重启后恢复目标状态。

平台差异必须通过 backend 隔离：

```text
platform/openwrt     uci, procd, fw4, nftables, iproute2
platform/linux       systemd, nftables, iproute2
```

通用 policy、planner、healthcheck、report 逻辑不得直接依赖 OpenWrt 专属命令。

## 流量转发实现规范

第一阶段流量转发必须基于系统路由、EasyTier 网络能力、OpenWrt `fw4`/`nftables` 和 Linux `iproute2` 实现。

OpenWrt/iStoreOS 上不得将基础出口转发能力绑定到 OpenClash。OpenClash 只能作为后续高级规则分流、透明代理、订阅规则、DNS 策略增强的可选集成，不能作为 `gateway_full_tunnel` 的基础依赖。

基础出口转发模型：

```text
source 节点:
  保护 Web/control-plane underlay route
  对 source LAN CIDR 建立到 exit 节点 EasyTier IPv4 的策略路由
  上报 route、source LAN CIDR 和 healthcheck 状态

exit 节点:
  开启 IPv4 forwarding
  允许 easytier interface 到 WAN forwarding
  对来自 source LAN CIDR 的出口流量做 masquerade/NAT
  上报 firewall、NAT 和出口 healthcheck 状态
```

OpenWrt/iStoreOS 后端优先使用：

```text
uci firewall -> fw4 reload -> nftables
```

普通 Linux 后端优先使用：

```text
iproute2 -> nftables
```

不得在通用 Agent 逻辑中写死 `iptables` 命令。若需要兼容旧系统，只能在 platform backend 内部做能力探测和降级处理，并必须把实际 backend 写入 runtime report。

## Policy 规范

Policy 是 Web 到 Agent 的唯一控制输入。

Policy 必须包含：

- `policy_id`
- `version`
- `machine_id`
- `type`
- `enabled`
- 目标 EasyTier network instance
- rollback 配置
- healthcheck 配置

第一阶段必须支持 logical policy：

```text
gateway_full_tunnel
```

该策略用于让任意 source R3S 网关下游 LAN/Wi-Fi 设备的出口流量经任意 exit R3S 节点异地转发。

Web 必须将 `gateway_full_tunnel` 拆成两个 device policy：

```text
client_gateway_via_peer
provide_exit_for_gateway
```

`gateway_full_tunnel` 必须支持：

- 指定 exit peer 的 EasyTier IPv4。
- 指定 source LAN CIDR。
- 保护 Web/control-plane underlay route。
- 检查 EasyTier interface。
- 检查 peer 可达性。
- 在 source 节点上对 source LAN CIDR 应用策略路由。
- 在 exit 节点上对 source LAN CIDR 应用 forwarding/NAT。
- 一个 source 同一时间只能启用一个 gateway full tunnel exit。
- 一个 exit 可以服务多个 source。
- 验证出口可用。
- 失败时回滚。

## Runtime Report 规范

Agent 必须周期性上报节点状态。最小状态包括：

- machine id
- hostname
- OS 类型和版本
- Agent 版本
- EasyTier 版本
- 当前 policy id/version/status
- EasyTier interface 状态
- 默认路由
- source LAN CIDR 策略路由
- control-plane 保护路由
- firewall backend
- forwarding/NAT 状态
- healthcheck 结果
- 最近一次 apply 错误

Web 控制台必须以 runtime report 为准展示节点真实运行状态，不得只根据数据库中的期望配置判断节点健康。

## Web 控制台开发规范

Web 控制台必须区分 desired state 和 observed state。

- desired state：用户期望的网络、策略、出口、节点角色。
- observed state：Agent 和 EasyTier 实际上报的运行状态。

任何策略下发都必须产生审计记录：

- 操作者。
- 策略 id。
- 策略版本。
- 目标节点。
- 下发时间。
- Agent 应用结果。
- 失败原因。

Web UI 必须至少能表达：

- 节点在线/离线。
- Agent 连接状态。
- EasyTier 实例状态。
- 策略是否已应用。
- 节点是否 degraded。
- 最近一次失败原因。

## 测试规范

开发优先级：

1. 单元测试：policy parser、validator、planner、dry-run applier。
2. containerlab E2E：三节点 Web/A/B 一键拓扑。
3. QEMU OpenWrt：包安装、procd、uci、firewall 行为。
4. UTM iStoreOS/Ubuntu：里程碑验收。
5. NanoPi R3S 真机：发布验收。

任何涉及路由、防火墙、NAT、回滚的改动，必须至少提供：

- dry-run 输出测试。
- 幂等执行测试。
- 回滚测试。
- runtime report 测试。

containerlab 测试必须覆盖：

- Web、node-a、node-b、node-c 节点启动。
- Web 下发任意 source 经任意 exit 的 gateway full tunnel 策略。
- source LAN CIDR 策略路由切换到 exit。
- source 从一个 exit 实时切换到另一个 exit。
- Web/control-plane underlay route 未被默认路由捕获。
- 当前 exit 断开后 source 状态进入 degraded 或 rollback。
- Agent 上报最终状态。

## 构建和发布规范

构建产物必须输出到 `dist/`。

临时构建缓存必须输出到 `build/`。

禁止提交：

- `dist/`
- `build/`
- `vendor/EasyTier/`
- `vendor/luci-app-easytier/`
- containerlab runtime 目录

目标设备构建必须明确 target profile，不允许在脚本中隐式猜测设备。

NanoPi R3S 默认目标：

```text
OPENWRT_TARGET=rockchip
OPENWRT_SUBTARGET=armv8
OPENWRT_PROFILE=friendlyarm_nanopi-r3s
```

## 代码质量规范

实现必须克制，避免过度设计。

所有功能必须服务于当前中文 spec 和 plan 中明确列出的验收目标。不得为了“未来可能需要”提前引入复杂抽象、插件系统、通用编排引擎、规则 DSL、跨平台框架或额外服务。

开发 EasyTier fork 时，必须优先参考 EasyTier 现有代码范式：

- Rust 模块组织跟随现有 crate 风格。
- RPC/proto 命名跟随现有 `api.*`、`web.*` 语义。
- 错误处理跟随现有 `anyhow`、`thiserror`、`rpc_types::error` 使用方式。
- 异步任务、session、manager、storage 的边界跟随现有实现。
- Web 前端 UI 组件和状态管理跟随现有 easytier-web frontend 风格。

开发 LuCI fork 时，必须优先参考 `luci-app-easytier` 现有结构和 OpenWrt 常规包范式，不引入与 LuCI 体系不一致的前端框架或服务管理方式。

开发 Agent 时，第一阶段只实现 `gateway_full_tunnel` 所需的最小能力：

- policy 解析。
- policy 校验。
- dry-run plan。
- source 网关策略路由切换。
- exit 节点 forwarding/NAT。
- control-plane protected route。
- verify。
- rollback。
- runtime report。

第一阶段不得实现：

- 通用远程命令执行。
- 任意流量分类规则引擎。
- OpenClash 集成。
- 多租户计费。
- 复杂 RBAC。
- 通用工作流引擎。
- 与 `gateway_full_tunnel` 无关的代理能力。

任何新增模块都必须能用一句话说明职责。如果一个模块同时处理 policy、平台命令、状态持久化和 Web 通信，必须拆分。

任何新增配置项都必须有直接使用场景。没有被 MVP 使用的配置项不得提前加入。

所有脚本必须：

- 使用 `set -eu`。
- 失败时返回非零退出码。
- 输出明确的下一步提示。
- 不依赖开发者本机的绝对路径。

所有新增工程入口必须能从仓库根目录通过 `make` 调用。

所有配置示例必须能被复制到目标环境后直接理解，避免隐藏前置条件。

所有网络策略相关代码必须优先保证安全、可回滚和可观测，再考虑自动化便利性。

## 当前阶段目标

当前阶段只做工程骨架和第一阶段产品能力：

- 建立 fork 工作区。
- 建立 target build 入口。
- 建立 containerlab 测试入口。
- 定义 policy schema。
- 实现 Agent MVP。
- 实现 Web policy/report API MVP。
- 实现 LuCI Agent 配置和状态页 MVP。
