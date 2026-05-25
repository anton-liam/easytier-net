# gateway_policy 最小下发实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 基于 EasyTier 现有 WebClient/config-server 下发能力，实现可控的 D → A → B → Internet 出口转发策略。

**Architecture:** Web 控制台只暴露 `gateway_policy` 策略接口；A/B 的 `easytier-core -w` 通过现有控制通道接收策略；节点侧 gateway_policy 模块负责校验、执行 nft/route/NAT、健康检查和回滚。实现上允许 easytier-core 参与策略接收，但内部代码按协议、RPC、状态、执行、监控分层，避免污染 tunnel/peer/NAT 穿透核心逻辑。

**Tech Stack:** Rust, prost/protobuf, EasyTier RPC/config-server, tokio, nftables, iproute2, LuCI Lua1, Docker/UTM 验证。

---

## 当前决定

本计划确认采用 `gateway_policy` 路线，不再切回独立 agent 主动通信模型。

核心口径：
- 控制面：`easytier-web` 新增 gateway policy REST API，通过已在线的 WebClient session 下发到目标 machine。
- 节点面：`easytier-core` 注册 `GatewayPolicyRpc`，收到策略后调用内部 `gateway_policy` 模块执行。
- 执行面：Source 节点只标记从 LAN 进入的受管流量；Exit 节点只做 tunnel 入站流量的转发和 masquerade。
- 安全面：策略必须可重复下发、可撤销、进程退出可清理、隧道异常可回滚。
- 不做：不新增公网 HTTP agent、不改 EasyTier 加密认证、不改 tunnel/peer/NAT 穿透核心。

## 文件责任

| 文件 | 责任 |
|------|------|
| `vendor/EasyTier/easytier/src/proto/gateway_policy.proto` | 定义策略字段、角色、状态和 RPC 服务 |
| `vendor/EasyTier/easytier/src/gateway_policy/mod.rs` | GatewayPolicyManager 状态入口、apply/remove/status、run loop、退出清理 |
| `vendor/EasyTier/easytier/src/gateway_policy/executor.rs` | 参数校验、命令规划、nft/ip/sysctl 执行、cleanup |
| `vendor/EasyTier/easytier/src/gateway_policy/monitor.rs` | tun 接口和 peer 可达性检查 |
| `vendor/EasyTier/easytier/src/rpc_service/gateway_policy.rs` | RPC 到 GatewayPolicyManager 的桥接 |
| `vendor/EasyTier/easytier/src/web_client/controller.rs` | WebClient session 注册 GatewayPolicyRpc |
| `vendor/EasyTier/easytier/src/web_client/mod.rs` | WebClient 构造时注入 GatewayPolicyManager |
| `vendor/EasyTier/easytier/src/core.rs` | core 启动 run loop，退出时 cleanup |
| `vendor/EasyTier/easytier-web/src/restful/gateway_policy.rs` | Web 侧 REST API，下发/查询/删除策略 |
| `vendor/luci-app-easytier/...` | 后续补齐 core webclient 进程开关与状态展示 |

## Task 1: 固化协议字段

- [ ] `GatewayPolicy` 保留现有字段并新增 `easytier_iface`。
- [ ] `easytier_iface` 为空时节点端默认使用 `tun0`。
- [ ] 策略字段最小集合：

```json
{
  "policy_id": "gw-001",
  "enabled": true,
  "role": "SOURCE",
  "source_machine_id": "node-a",
  "exit_machine_id": "node-b",
  "managed_cidrs": ["192.168.128.0/24"],
  "ingress_iface": "br-lan",
  "easytier_iface": "tun0",
  "exit_peer_tun_ip": "10.126.126.3",
  "exit_wan_iface": "eth0"
}
```

## Task 2: core 启动链路接入

- [ ] 在 `easytier-core` 启动时，如果启用 `--config-server/-w` 且编译了 `gateway-policy` feature，则创建一个 `GatewayPolicyManager`。
- [ ] 将同一个 manager 注入 WebClient controller，使 GatewayPolicyRpc 跟随 WebClient session 注册。
- [ ] 启动 manager 的 5 秒 run loop。
- [ ] core 收到 Ctrl-C/SIGTERM 或 manager 退出时，调用 `cleanup()` 删除 nft table、ip rule、route table。

## Task 3: 执行器稳定性

- [ ] 应用策略前先校验字段，不合法则不清理当前策略。
- [ ] Source 必填：`managed_cidrs`、`ingress_iface`、`exit_peer_tun_ip`。
- [ ] Exit 必填：`managed_cidrs`、`exit_wan_iface`。
- [ ] CIDR 与 IP 地址必须能解析。
- [ ] 策略执行前先清理旧规则，避免重复下发导致 `File exists`。
- [ ] Source route 使用 `ip route replace`，降低重复执行风险。
- [ ] 执行失败后立即 cleanup，并把状态退回 Idle。

## Task 4: 监控与回滚

- [ ] monitor 使用策略里的 `easytier_iface`，为空默认 `tun0`。
- [ ] Source 检查 exit peer tunnel IP 可达。
- [ ] Exit 至少检查 EasyTier tunnel 接口存在。
- [ ] Applied 状态下隧道异常，执行 cleanup 并回到 Idle。
- [ ] C 暂时不可达但 tunnel 正常时保持当前策略，不主动清理。

## Task 5: Web API 口径

- [ ] `POST /api/v1/gateway-policy/:machine-id` 下发完整策略。
- [ ] `GET /api/v1/gateway-policy/:machine-id` 查询节点本地执行状态。
- [ ] `DELETE /api/v1/gateway-policy/:machine-id` 删除节点策略。
- [ ] `POST /api/v1/gateway-policy/pair` 一次指定 Source/Exit，按 Exit → Source 顺序下发，Source 失败时回滚 Exit。
- [ ] `POST /api/v1/gateway-policy/pair/remove` 同时移除 Source/Exit 策略。
- [ ] Web API 只通过已认证登录用户和已连接 session 操作节点，不新增节点公网 API。

## Task 6: LuCI 进程显示

- [ ] 保留原生 luci-app-easytier 的 core 配置体验。
- [ ] 补齐 `easytier-core-webclient` 的启动/停止/状态展示。
- [ ] 如果最终不再需要独立 agent，则不在 UI 中展示 agent，避免误导。

## Task 7: 验证

- [ ] `cargo test -p easytier gateway_policy --features gateway-policy --no-default-features`
- [ ] `cargo check -p easytier --features gateway-policy`
- [ ] `cargo check -p easytier-web`
- [ ] `bash -n scripts/build-image.sh scripts/build-openwrt.sh scripts/build-server.sh`
- [ ] Docker 集成测试覆盖策略下发到执行路径。
- [ ] UTM 4 节点最终验收：D 通过 A 入口，出口公网表现为 B。

## OpenWrt 镜像默认直连

镜像构建脚本读取仓库根目录 `.env`，通过 `EASYTIER_CONFIG_SERVER` 注入首次启动配置：

```env
EASYTIER_CONFIG_SERVER=udp://137.220.194.19:22020/admin
```

`.env` 不进入 git。未配置该变量时，镜像保留 EasyTier 服务但默认不启动连接。

## 验收标准

- A/B 节点能在 Device List 中保持原生 EasyTier 在线管理能力。
- Web 控制台能对在线节点下发 Source/Exit 策略。
- D 到 A 本机的访问不被策略捕获。
- A/B/C 控制面互联不被策略捕获。
- D 的默认出网流量通过 A 的 LAN 进入，经 EasyTier tunnel 到 B，从 B 出口 NAT 出网。
- 删除策略或隧道异常后，A/B 网络规则回到干净状态。
