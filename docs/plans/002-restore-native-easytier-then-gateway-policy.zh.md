# 002 恢复原生 EasyTier 后扩展出口策略 Plan

## 基于 Spec

- `docs/specs/001-product-scope.zh.md`
- `docs/specs/002-gateway-full-tunnel-policy.zh.md`
- `docs/specs/003-native-control-plane-first.zh.md`

## 目标

先恢复 EasyTier Web 控制台和 Device List 的原始功能，再让 A/B/C 三个节点通过 `easytier-core -w` 正常连接 C 的 Web/config-server 并完成原生组网。只有在原生组网验收通过后，才继续实现出口策略下发、应用和 observed state 展示。

## 总体原则

- 先恢复原生功能，再做扩展。
- `Device List` 只展示 `/api/v1/machines`。
- 出口策略候选节点必须来自在线 machine。
- runtime report 只做 observed state，不做节点注册主数据源。
- 不二开 EasyTier 数据面核心。
- 不让 Agent 独立绕过 WebClient session。
- 每个阶段开始实现前，必须先确认该阶段需求已经写入 spec/plan。
- 未通过前置验收的阶段，不允许提前实现后续阶段。

## 实现前置门禁

后续实现必须遵守以下门禁：

```text
Gate 1: EasyTier Web 原生功能恢复
  通过条件：Device List 只依赖 /api/v1/machines，原生 Device Management 可用。

Gate 2: A/B/C 原生节点上线
  通过条件：/api/v1/machines 包含 A/B/C，summary.device_count = 3。

Gate 3: A/B/C 原生组网成功
  通过条件：A/B/C 运行同一个 network instance，EasyTier IPv4 互通。

Gate 4: 出口策略 UI 入口
  通过条件：入口只出现在 Device Management 的 running network instance 状态区域，未满足条件时置灰并显示原因。

Gate 5: 出口策略下发与执行
  通过条件：source/exit 均来自同一 running network instance 的在线 machine，策略执行后 observed state 可回传。
```

若任一 Gate 未通过，停止后续实现，只修复当前 Gate。

## 阶段 0：冻结当前偏移实现并建立恢复点

目标：避免继续在错误抽象上叠加功能。

涉及目录：

- `vendor/EasyTier/easytier-web/frontend/src/components`
- `vendor/EasyTier/easytier-web/frontend/src/modules/api.ts`
- `vendor/EasyTier/easytier-web/src`
- `scripts/utm-deploy-web.sh`

实施步骤：

1. 查看当前 EasyTier fork diff。
2. 将偏移实现分类：
   - 必须回退：把 `gateway-nodes` 合并进 Device List 的逻辑。
   - 暂停使用：独立 `gateway-nodes` 节点列表作为策略候选的逻辑。
   - 可保留但需重接线：policy store、runtime report、desired/observed API。
   - 工程修正可保留：UTM 部署脚本中 `cargo clean -p easytier-web` 和远端 PATH 修正。
3. 不删除可复用代码，先通过 UI/API 主路径禁用偏移入口。

验证命令：

```sh
cd /Users/anton/www/easytier-net/.worktrees/gateway-full-tunnel/vendor/EasyTier
git diff --stat
pnpm --dir easytier-web/frontend build
```

预期结果：

- 明确哪些文件需要恢复原始 EasyTier 行为。
- 前端构建通过。
- 没有继续新增依赖 `gateway-nodes` 的 Device List 逻辑。

提交建议：

```sh
git add docs/specs/003-native-control-plane-first.zh.md docs/plans/002-restore-native-easytier-then-gateway-policy.zh.md
git commit -m "docs: define native EasyTier control plane first plan"
```

## 阶段 1：恢复 EasyTier Web 原始功能

目标：让基础 `easytier-web` 回到原始可用状态。

涉及文件：

- `vendor/EasyTier/easytier-web/frontend/src/components/DeviceList.vue`
- `vendor/EasyTier/easytier-web/frontend/src/components/MainPage.vue`
- `vendor/EasyTier/easytier-web/frontend/src/main.ts`
- `vendor/EasyTier/easytier-web/frontend/src/modules/api.ts`
- `vendor/EasyTier/easytier-web/src/restful/mod.rs`
- `vendor/EasyTier/easytier-web/src/restful/network.rs`
- `vendor/EasyTier/easytier-web/src/client_manager/*`

实施步骤：

1. 对照 EasyTier upstream 或 fork 基线，确认 Device List、Device Management、Dashboard 仍使用原生 `/api/v1/machines`、`/api/v1/summary`、machine scoped RPC。
2. 移除 Device List 工具栏中的“出口策略”按钮和 Drawer，Device List 只保留原生排序、详情、管理入口。
3. 移除或隐藏主路由中的全局 `gatewayPolicies` 页面入口，避免用户在原生组网前进入独立策略编排页。
4. 暂时隐藏或禁用会让用户误以为 Agent report 就是在线 machine 的策略候选逻辑。
5. `api.ts` 中 `list_gateway_nodes()` 若暂时保留，只允许供诊断或后续 observed state 使用，不得被 Device List 或策略候选选择调用。
6. 确认 `/api/v1/machines`、`/api/v1/summary`、`/api/v1/machines/:machine-id/networks` 行为与原始 EasyTier 一致。

验证命令：

```sh
cd /Users/anton/www/easytier-net/.worktrees/gateway-full-tunnel/vendor/EasyTier
rg -n "GatewayPolicyConsole|gatewayPolicyVisible|list_gateway_nodes|gatewayNodes|出口策略" easytier-web/frontend/src/components/DeviceList.vue easytier-web/frontend/src/main.ts easytier-web/frontend/src/components/GatewayPolicyConsole.vue
pnpm --dir easytier-web/frontend build
cargo test -p easytier-web
```

预期结果：

- `Device List` 无额外 Agent 卡片。
- `Device List` 无独立“出口策略”按钮和策略 Drawer。
- Web 主路由不暴露原生组网前可直接进入的全局出口策略编排入口。
- Dashboard `device_count` 只反映原生 machine 数量。
- 原生 Device Management 可以正常打开。
- 未连接任何 `easytier-core -w` 节点时，Device List 为空是正确结果。

提交建议：

```sh
git add easytier-web
git commit -m "fix(web): restore native device list semantics"
```

## 阶段 2：搭建 C 节点原生服务

目标：C Ubuntu 同时运行 Web 控制台和 EasyTier 中转节点。

涉及环境：

- C Ubuntu：`192.168.64.4`
- Web API：`http://192.168.64.4:11211`
- Config server：`udp://192.168.64.4:22020/<user_token>`

实施步骤：

1. 部署 `easytier-web` 到 C。
2. 使用同一个 user token 启动 C 自身 `easytier-core -w`。
3. 为 C 设置稳定 `machine_id`。
4. 确认 C 出现在 `/api/v1/machines`。

建议命令：

```sh
make utm-deploy-web
ssh anton@192.168.64.4
easytier-core -w udp://192.168.64.4:22020/admin --machine-id cccccccc-cccc-cccc-cccc-cccccccccccc
```

验证命令：

```sh
curl --noproxy '*' -fsS -c /tmp/et.cookie \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"21232f297a57a5a743894a0e4a801fc3"}' \
  http://192.168.64.4:11211/api/v1/auth/login

curl --noproxy '*' -fsS -b /tmp/et.cookie \
  http://192.168.64.4:11211/api/v1/machines
```

预期结果：

- `/api/v1/machines` 至少包含 C。
- `summary.device_count >= 1`。
- Device List 显示 C。

提交建议：

```sh
git add docs/runbooks/lab.md scripts/utm-deploy-web.sh
git commit -m "docs: document UTM native EasyTier web client startup"
```

## 阶段 3：让 A/B 作为原生节点上线

目标：A/B iStoreOS 通过 EasyTier 原生 WebClient 连接 C。

涉及环境：

- A iStoreOS：`istoreos1`
- B iStoreOS：`istoreos2`
- C Ubuntu：`192.168.64.4`

实施步骤：

1. 在 A 安装或复制 `easytier-core`。
2. 在 B 安装或复制 `easytier-core`。
3. A 使用稳定 `machine_id` 启动：

```sh
easytier-core -w udp://192.168.64.4:22020/admin --machine-id aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
```

4. B 使用稳定 `machine_id` 启动：

```sh
easytier-core -w udp://192.168.64.4:22020/admin --machine-id bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
```

5. C 自身使用稳定 `machine_id` 启动。

验证命令：

```sh
curl --noproxy '*' -fsS -b /tmp/et.cookie \
  http://192.168.64.4:11211/api/v1/machines

curl --noproxy '*' -fsS -b /tmp/et.cookie \
  http://192.168.64.4:11211/api/v1/summary
```

预期结果：

- `/api/v1/machines` 包含 A/B/C 三个 machine。
- `summary.device_count = 3`。
- Web Device List 显示 A/B/C。
- 每个节点均可打开原生 Device Management。

提交建议：

```sh
git add docs/runbooks/lab.md
git commit -m "docs: add native A B C node enrollment steps"
```

## 阶段 4：通过 Web 控制台完成原生组网

目标：不依赖出口策略，先确认 EasyTier 原生组网成功。

涉及功能：

- Device Management
- Network instance config
- WebClientService RPC

实施步骤：

1. 在 Web 控制台创建或下发同一个 network instance 到 A/B/C。
2. 确认三个节点都启动同一个 network instance。
3. 查询各节点 running network instance。
4. 查询 network info，记录 A/B/C 的 EasyTier IPv4。
5. 在节点内验证 EasyTier IPv4 互通。

验证命令：

```sh
curl --noproxy '*' -fsS -b /tmp/et.cookie \
  http://192.168.64.4:11211/api/v1/machines
```

在 A/B/C 上验证：

```sh
ip addr
ip route
ping <peer-easytier-ipv4>
```

预期结果：

- A/B/C 均有同一个 running network instance。
- A 能 ping B/C 的 EasyTier IPv4。
- B 能 ping A/C 的 EasyTier IPv4。
- C 可作为中转/搭线节点被 EasyTier 网络使用。

提交建议：

```sh
git add docs/runbooks/lab.md
git commit -m "docs: add native EasyTier networking acceptance checks"
```

## 阶段 5：重接出口策略数据模型

目标：让出口策略建立在原生 machine 和 network instance 之上。

涉及文件：

- `vendor/EasyTier/easytier-web/src/gateway_policy.rs`
- `vendor/EasyTier/easytier-web/src/restful/gateway_policy.rs`
- `vendor/EasyTier/easytier-web/src/db/mod.rs`
- `vendor/EasyTier/easytier-web/frontend/src/components/GatewayPolicyConsole.vue`
- `vendor/EasyTier/easytier-web/frontend/src/components/GatewayPolicyEditor.vue`
- `vendor/EasyTier/easytier-web/frontend/src/components/GatewayPolicyTopology.vue`
- `vendor/EasyTier/easytier-web/frontend/src/components/DeviceManagement.vue`
- `vendor/EasyTier/easytier-web/frontend/src/modules/api.ts`

实施步骤：

1. 策略候选 source/exit 只来自 `/api/v1/machines`。
2. 在 Device Management 的 running network instance 状态区域增加“设置出口策略”按钮。
3. 按钮启用条件：
   - 当前节点在线。
   - 当前 network instance 正在运行。
   - 当前节点运行该 network instance。
   - 同一 network instance 中存在至少一个其它在线 machine。
4. 按钮置灰时显示明确原因：
   - `节点未连接 Web 控制台`。
   - `请选择一个 EasyTier network instance`。
   - `当前网络尚未运行成功`。
   - `当前节点未运行该网络实例`。
   - `当前网络未发现可作为出口的对端节点`。
5. 打开策略编辑器时预填：
   - `source_machine_id = 当前节点 machine_id`。
   - `network_instance_id = 当前 running network instance id`。
   - exit 候选来自同一 network instance 的其它在线 machine。
6. 创建策略前校验：
   - source machine 在线。
   - exit machine 在线。
   - source 和 exit 不相同。
   - source/exit 都有目标 network instance。
   - source/exit 在同一个 network instance 内。
7. runtime report 只按 `machine_id` 附加 observed state。
8. 若 report 存在但 machine 不在线，策略显示无效，不允许启用。
9. `gateway-nodes` API 若保留，只作为 observed report 诊断接口，不作为主列表。
10. 在“设置出口策略”按钮旁增加“拓扑图”按钮，入口仍限定在 Device Management 的 running network instance 状态区域。
11. 引入 `@vue-flow/core`、`@vue-flow/background`、`@vue-flow/controls`，拓扑弹窗使用 Vue Flow 画布，不使用静态卡片模拟拓扑。
12. 新增 `topologyBuilder.ts`，把 native machine、当前 `NetworkInstance`、gateway policy snapshot 转换成 Vue Flow nodes/edges。
13. 拓扑只展示当前 network instance 内的在线 machine，不写死 A/B/C 数量。
14. 控制面搭线层用蓝色虚线表达 machine 到当前 Web/config-server 节点的 `control / config-server` 关系。
15. 数据面 peer 层用中性色实线表达当前 EasyTier peer route 上报的 `p2p`、`relay(n)`、`tcp`、`udp` 等关系。
16. 出口策略层用绿色动画线表达 `gateway_full_tunnel` 流向：source -> exit -> 出口网络。
17. 拓扑弹窗展示 desired/observed 状态、EasyTier IPv4、policy version、受管网段、入口接口、设备自身流量和 exit egress。
18. 拓扑弹窗在入口节点区域提供“测试出口”按钮。按钮只执行结构化诊断，不执行 Web 下发的任意 shell 命令。诊断项包括策略启用、source/exit 在线、observed status、version 对齐、EasyTier IPv4、受管流量范围。
19. `GatewayPolicyConsole.vue` 在 MVP 中不得作为独立策略创建主入口；如保留文件，只能作为后续 observed/diagnostics 页面待接线组件。

实现前确认：

- Gate 1、Gate 2、Gate 3 已通过。
- `/api/v1/machines` 中的 source/exit 均包含当前 network instance。
- 当前入口实现不修改 Device List 数据来源。
- 当前入口实现不使用 `gateway-nodes` 作为候选节点来源。

验证命令：

```sh
cd /Users/anton/www/easytier-net/.worktrees/gateway-full-tunnel/vendor/EasyTier
cargo test -p easytier-web gateway_policy
pnpm --dir easytier-web/frontend build
```

预期结果：

- 未在线 machine 不能创建/启用出口策略。
- 未共同组网的 machine 不能创建/启用出口策略。
- runtime report 不会让离线节点进入可编排候选列表。
- Device Management 的网络状态区域能看到出口策略入口。
- Device Management 的网络状态区域能看到拓扑图入口。
- 未满足条件时按钮置灰并显示原因。
- 创建入口默认带入当前 machine 和当前 running network instance。
- 拓扑图使用 Vue Flow 动态画布，能清晰显示当前 network instance 内 machine 拓扑。
- 拓扑图能用不同连线样式区分控制面搭线、EasyTier peer 数据面和出口策略流量。
- 拓扑图能清晰显示 source 到 exit 再到出口网络的流量方向。
- “测试出口”能基于 desired/observed state 给出通过、警告或失败结果，且不依赖任意远程命令执行。

提交建议：

```sh
git add easytier-web
git commit -m "feat(web): bind gateway policy to native machines"
```

## 阶段 6：实现策略下发路径

目标：在原生 EasyTier WebClient session 基础上，下发出口策略扩展能力。

候选方案：

### 方案 A：Agent 作为本机辅助执行器

`easytier-core` 继续负责：

- WebClient session。
- machine heartbeat。
- network instance 下发。
- EasyTier 组网数据面。

`easytier-agent` 负责：

- 从 Web 拉取当前 machine 的 device policy。
- 应用 route/firewall/NAT。
- 上报 runtime report。

要求：

- Agent 必须使用与 `easytier-core` 相同的 stable machine_id。
- Agent 不注册独立节点。
- Agent report 不能替代 machine heartbeat。

### 方案 B：扩展 EasyTier WebClient control-plane

在 EasyTier 原生 WebClient/RPC 中增加出口策略扩展 RPC 或 heartbeat 附加字段。

要求：

- 不改 tunnel/peer/packet forwarding 数据面。
- 只扩展 control-plane proto/RPC。
- 路由、防火墙、NAT 执行逻辑仍可放在独立 agent/backend 模块。

第一阶段推荐：方案 A。

理由：

- 不污染 EasyTier 数据面核心。
- 对 OpenWrt/iStoreOS 的系统命令隔离更清晰。
- Web 仍以 EasyTier 原生 machine 为准。
- 后续可再把 Agent 和 core 的 machine_id、状态、服务管理做成 LuCI/procd 集成。

本阶段必须同时更新 EasyTier 原生 network config：

1. Web 保存 enabled `gateway_full_tunnel` 时，读取 source/exit 的目标 network instance config。
2. Web 将 `managed_cidrs` 合并进 source config 的 `proxy_cidrs`。
3. Web 将 `exit_peer_ipv4` 写入 source config 的 `exit_nodes`。
4. Web 将 exit config 的 `enable_exit_node` 和 `proxy_forward_by_system` 设置为 `true`。
5. Web 通过原生 WebClient `run_network_instance(overwrite=true)` 重新下发 source/exit config。
6. Agent 在 exit 侧为每个非默认 `managed_cidr` 添加 `ip route replace <managed_cidr> via <source_peer_ipv4> dev <easytier_iface>`，保证 NAT 回包能回到 source peer。

验证命令：

```sh
curl --noproxy '*' -fsS \
  http://192.168.64.4:11211/api/internal/users/<user-id>/machines/<machine-id>/gateway-policies
```

预期结果：

- 只有已在线且已组网的 machine 能拿到 device policy。
- source `easytier-cli -o json node` 显示 `proxy_cidrs` 包含策略的 `managed_cidrs`。
- source `easytier-cli -o json node` 显示 `exit_nodes` 包含 exit peer IPv4。
- exit `easytier-cli -o json node` 显示 `enable_exit_node=true` 和 `proxy_forward_by_system=true`。
- exit `ip route get <managed_client_ip>` 返回 `via <source_peer_ipv4> dev <easytier_iface>`。
- Agent 上报 report 后，Web 策略页显示 observed state。
- Device List 仍只显示原生 machines。
- Ubuntu/Linux Agent 二进制只能用于 Linux/glibc 或容器环境，不得复制到 iStoreOS 当作 R3S Agent 验收。
- iStoreOS/R3S Agent 必须通过 OpenWrt/iStoreOS SDK 产出 musl/aarch64 包或二进制。

提交建议：

```sh
git add easytier-web easytier-agent
git commit -m "feat(agent): apply gateway policy for native machines"
```

## 阶段 6.1：补齐 R3S/iStoreOS Agent 构建

目标：让 `make build TARGET=nanopi-r3s` 产出可安装到 iStoreOS/R3S 的 `easytier-agent` 包或明确失败。

涉及目录：

- `targets/nanopi-r3s/build.sh`
- `targets/nanopi-r3s/openwrt-profile.env`
- `vendor/EasyTier/easytier-agent`
- `vendor/luci-app-easytier`

实施步骤：

1. `OPENWRT_SDK_DIR` 未设置时，构建必须失败并写入 manifest，禁止生成伪产物。
2. `OPENWRT_SDK_DIR` 已设置时，脚本必须检查 SDK 中是否存在 `staging_dir`、`scripts/feeds` 和目标 toolchain。
3. 将 `easytier-agent` 包定义接入 SDK package tree。
4. 使用 SDK toolchain 构建 aarch64/musl Agent。
5. 将 `.ipk` 和构建 manifest 输出到 `dist/nanopi-r3s/`。
6. 在 iStoreOS VM 上安装 `.ipk` 后，`/usr/bin/easytier-agent --help` 必须能运行。

验证命令：

```sh
OPENWRT_SDK_DIR=/path/to/openwrt-sdk make build TARGET=nanopi-r3s
scp dist/nanopi-r3s/*.ipk root@192.168.64.2:/tmp/
ssh root@192.168.64.2 'opkg install /tmp/easytier-agent_*.ipk && /usr/bin/easytier-agent --help'
```

预期结果：

- 未设置 SDK 时构建返回非零退出码。
- 设置 SDK 后输出 `.ipk`。
- R3S/iStoreOS 能运行 Agent。
- Agent 可以 `run-once --platform open-wrt` 拉取当前 machine 的 device policy 并上报 runtime report。

## 阶段 7：UTM 验收

目标：在 A/B/C 三台 UTM VM 上完成端到端验收。

验收步骤：

1. C 启动 Web 控制台。
2. C 启动 `easytier-core -w`，作为中转节点加入 Web。
3. A 启动 `easytier-core -w`，加入 Web。
4. B 启动 `easytier-core -w`，加入 Web。
5. Web Device List 显示 A/B/C。
6. Web 下发原生组网配置。
7. A/B/C EasyTier IPv4 互通。
8. Web 创建 `A -> B` 出口策略。
9. Agent 在 B prepare forwarding/NAT。
10. Agent 在 A switch managed traffic route。
11. A 下挂客户端流量从 B 出口。
12. A 与 C Web/control-plane 不失联。
13. B 抓包必须看到受管客户端流量在 egress 侧被 SNAT 成 B 的 underlay 地址。
14. A 下挂客户端必须收到回包，证明 source `proxy_cidrs` 公告和 exit 回程路由同时生效。

验收命令：

```sh
curl --noproxy '*' -fsS -b /tmp/et.cookie \
  http://192.168.64.4:11211/api/v1/summary

curl --noproxy '*' -fsS -b /tmp/et.cookie \
  http://192.168.64.4:11211/api/v1/machines
```

预期结果：

- `device_count = 3`。
- A/B/C 均在线。
- 出口策略只能在 A/B/C 中选择节点。
- 策略状态能显示 desired/observed。
- 断开 exit 或切换 exit 时不会导致 A 与 Web 控制台失联。

## 阶段 8：清理偏移代码

目标：移除或重命名容易误导的独立节点概念。

涉及文件：

- `GatewayPolicyConsole.vue`
- `GatewayPolicyEditor.vue`
- `api.ts`
- `gateway_policy.rs`
- `restful/gateway_policy.rs`

实施步骤：

1. 将 UI 中“Agent 节点列表”改成“策略 observed report”或隐藏。
2. 将策略创建候选源切到原生 machine。
3. `gateway-nodes` API 若保留，改名或限制为 diagnostics。
4. 文档中明确：report 不是 machine online source。
5. 若阶段 1 已隐藏 `GatewayPolicyConsole.vue`，本阶段只保留可被 Device Management 复用的 editor 和 API 类型，删除未接线的全局策略入口代码。

验证命令：

```sh
cd /Users/anton/www/easytier-net/.worktrees/gateway-full-tunnel/vendor/EasyTier
rg -n "gatewayNodes|list_gateway_nodes|Agent .*\\(" easytier-web/frontend/src
pnpm --dir easytier-web/frontend build
cargo test -p easytier-web
```

预期结果：

- 前端策略候选不依赖 `list_gateway_nodes()`。
- `Device List` 不依赖 `gateway-nodes`。
- report 相关 UI 只表达 observed state。

提交建议：

```sh
git add easytier-web docs
git commit -m "refactor(web): make gateway reports observed state only"
```

## 回滚策略

如果任一阶段失败：

- 阶段 1 失败：回退 EasyTier fork 中 Web 前端/后端到 upstream 基线，只保留文档和部署脚本。
- 阶段 2/3 失败：不继续实现出口策略，先修复 `easytier-core -w` 到 Web 的连接问题。
- 阶段 4 失败：不继续 Agent，先修复原生网络实例下发和 EasyTier IPv4 互通。
- 阶段 5/6 失败：保留原生组网能力，禁用出口策略入口。

## 当前立即下一步

下一步不要继续新增出口策略能力。

立即执行：

1. 恢复 EasyTier Web 原生功能到可验收状态。
2. 移除 Device List 的独立出口策略入口，保留原生 Device Management。
3. 在 C/A/B 上启动 `easytier-core -w`。
4. 直到 `/api/v1/machines` 能看到 A/B/C，才继续出口策略实现。

当前已经明确的需求调整：

- 出口策略主创建入口应放在 Device Management 的 running network instance 信息区域。
- Device List 必须保持原生功能和原生信息架构，不承担出口策略编排入口。
- 按钮可以先实现为上下文入口，不实现拓扑图。
- 拓扑图作为后续 UI 增强预留。
- 后续所有代码实现都必须先对照本 plan 的 Gate 顺序。
