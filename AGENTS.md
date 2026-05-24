# EasyTier-Net Gateway

## 项目目标

在 EasyTier 组网基础上，实现 D → A → B → Internet 的出口网关策略编排。
C 作为控制面，通过 EasyTier 已有通道下发策略，A/B 接收并执行 nft/route 规则。

## 网络拓扑

```
                      underlay (192.168.64.0/24)
                ┌───────────┬───────────┬───────────┐
                │           │           │           │
          ┌─────┴─────┐ ┌──┴──────┐ ┌──┴──────┐   │
          │  A (src)  │ │ B (exit)│ │    C    │   │
          │ iStoreOS  │ │ iStoreOS│ │  Ubuntu │   │
          │ .8        │ │ .3      │ │  .4     │   │
          │           │ │         │ │         │   │
          │ easytier  │ │ easytier│ │ easytier│   │
          │  + gateway│ │  + gate │ │  -web   │   │
          │   module  │ │  module │ │         │   │
          └─────┬─────┘ └────┬────┘ └─────────┘   │
                │            │                      │
    ┌───────────┤            │                      │
    │  EasyTier tunnel       │                      │
    │  (tun0: 10.126.126.x)  │                      │
    │           │            │                      │
    │      lan  │       wan  │                      │
    │ 192.168.1.0/24    (NAT to Internet)           │
    │           │                                    │
          ┌─────┴─────┐                              │
          │     D     │                              │
          │  Ubuntu   │                              │
          │  .2       │                              │
          │ (client)  │                              │
          └───────────┘
```

### 节点职责

| 节点 | OS | 角色 | 运行的服务 |
|------|------|------|------|
| A | iStoreOS (OpenWrt) | Source 网关 | easytier-core（含 gateway 模块） |
| B | iStoreOS (OpenWrt) | Exit 网关 | easytier-core（含 gateway 模块） |
| C | Ubuntu | 控制面 | easytier-web + config-server + relay |
| D | Ubuntu | 客户端 | 无，仅作为流量源 |

### 网络划分

| 网络 | 网段 | 用途 |
|------|------|------|
| underlay | 192.168.64.0/24 | A/B/C 物理互联 |
| lan_a | 192.168.1.0/24 | D 连接 A 的 LAN 口 |
| tunnel | 10.126.126.0/24 | EasyTier 虚拟网络 |
| wan_b | Docker NAT | B 出口到 Internet |

## 流量路径

### 受管流量（D 的出口）

```
D (192.168.1.2)
  → A br-lan (nft: iif=br-lan, saddr=192.168.1.0/24 → mark 0x7e)
  → A policy route (fwmark 0x7e → table 126 → via B_tun0_ip dev tun0)
  → EasyTier tunnel
  → B tun0 (receive)
  → B nft masquerade (oif=wan → SNAT)
  → Internet
```

### 不受管流量（天然安全，无需保护规则）

以下流量**不匹配** nft mark 规则（因为 `iif != br-lan` 或目标是本机），不会被策略捕获：

- A 自身到 C 的控制面流量（A 自身发出，不经 br-lan）
- SSH 到 A 的管理流量（目标是 A 本机，不转发）
- D 到 A 本机地址的直连（目标是 A 本机 192.168.1.1，不转发）
- A/B/C underlay 互联流量

## 策略下发

### 通道

复用 EasyTier 已有的 config-server 加密通道。C 的 easytier-web 通过 config-server 下发策略到 A/B 的 easytier-core gateway 模块。不需要额外的 HTTP API 或认证机制。

### 策略模型

C 下发到 A/B 的策略是一个简单结构：

```json
{
  "policy_id": "gw-001",
  "enabled": true,
  "source_machine_id": "node-a",
  "exit_machine_id": "node-b",
  "managed_cidrs": ["192.168.1.0/24"],
  "ingress_iface": "br-lan"
}
```

### A 收到策略后执行

```sh
# 1. mark
nft add table inet easytier_gw
nft add chain inet easytier_gw prerouting { type filter hook prerouting priority -150 \; }
nft add rule inet easytier_gw prerouting iif "br-lan" ip saddr 192.168.1.0/24 meta mark set 0x7e

# 2. policy route
ip rule add fwmark 0x7e table 126
ip route add default via <B_tun0_ip> dev tun0 table 126
```

### B 收到策略后执行

```sh
# 1. forward
sysctl -w net.ipv4.ip_forward=1

# 2. masquerade
nft add table inet easytier_gw
nft add chain inet easytier_gw postrouting { type nat hook postrouting priority 100 \; }
nft add rule inet easytier_gw postrouting ip saddr 192.168.1.0/24 oif "eth0" masquerade
```

### 还原策略

A 或 B 收到 `enabled: false` 时：

```sh
ip rule del fwmark 0x7e table 126 2>/dev/null
ip route flush table 126 2>/dev/null
nft delete table inet easytier_gw 2>/dev/null
```

## Gateway 模块设计

### 位置

在 EasyTier fork 中新增模块，不修改数据面核心：

```
vendor/EasyTier/
├── easytier/src/
│   ├── gateway/              # 新增
│   │   ├── mod.rs            # 状态机 + run loop
│   │   ├── monitor.rs        # 检查 tun0/peer/connector 状态
│   │   └── executor.rs       # 执行 nft/ip rule/route + cleanup
│   ├── proto/
│   │   └── ...               # 扩展: GatewayPolicy 消息
│   └── web_client/
│       └── mod.rs            # 扩展: 收到 policy 后调 gateway 模块
│
├── easytier-web/src/
│   └── restful/
│       └── gateway_policy.rs # 策略 CRUD + 通过 config-server 下发
```

### 状态机

```
idle ──(收到 enabled policy + 组网正常)──→ applied
applied ──(收到 disabled / 组网断开)──→ idle
applied ──(组网异常)──→ degraded ──→ idle (自动回滚)
```

三个状态，够用。

### Run Loop（每 5 秒）

```
loop {
    tunnel_ok = check tun0 exists && peer reachable
    policy = get desired policy from config-server channel

    match (current_state, tunnel_ok, policy) {
        (idle, true, Some(enabled))     → apply rules → applied
        (applied, _, Some(disabled))    → cleanup rules → idle
        (applied, false, _)             → cleanup rules → degraded → idle
        (applied, true, _)              → noop (保持)
        (idle, _, None)                 → noop
    }

    report state to C (best effort)
}
```

### 进程退出清理

```rust
// trap SIGTERM/SIGINT
tokio::signal::ctrl_c().await;
cleanup_all_rules();  // 删除 nft table + ip rule + ip route
```

进程退出 = 所有策略规则被清除 = A/B 网络回到干净状态。

## 一致性保证

| 场景 | 行为 | A/B 网络 |
|------|------|------|
| 组网正常，无策略 | idle | 干净 |
| 组网正常，下发 enable | apply nft/route | 策略生效 |
| 组网断开（tun0 down / peer 不通） | 自动回滚 | 干净 |
| C 下发 disable | cleanup | 干净 |
| easytier-core 进程退出 | trap cleanup | 干净 |
| C 不可达但组网正常 | 保持当前策略不变 | 保持 |

**原则：任何组网异常都回到干净状态。控制面不可达但组网正常时保持现状。**

## EasyTier Fork 改动边界

### 允许改动

- 新增 `gateway/` 模块
- 扩展 proto 消息（添加 GatewayPolicy）
- web_client 收到 policy 后分发给 gateway 模块
- easytier-web 策略 CRUD

### 禁止改动

- tunnel/peer 发现/NAT 穿越核心代码
- 加密/认证机制
- config-server 协议本身
- CLI 工具核心逻辑

## 测试方案

### Docker 集成测试

使用 Docker Compose 编排完整拓扑，A/B 使用 OpenWrt rootfs 镜像（有 UCI/procd/fw4/nftables），C/D 使用 Ubuntu。

```
tests/integration/
├── docker-compose.yml
├── images/
│   ├── Dockerfile.openwrt    # A/B 基础镜像
│   └── Dockerfile.ubuntu     # C/D 基础镜像
├── scripts/
│   ├── test-gateway-forward.sh       # D→A→B→Internet
│   ├── test-no-capture-local.sh      # D→A 直连不被捕获
│   ├── test-no-capture-control.sh    # A→C 不被捕获
│   ├── test-policy-restore.sh        # 还原策略后网络干净
│   ├── test-tunnel-down-rollback.sh  # 组网断开自动回滚
│   └── test-process-exit-cleanup.sh  # 进程退出清理
```

### 测试分层

| 层级 | 工具 | 验证什么 | 频率 |
|------|------|------|------|
| 集成 | Docker Compose | 路由/nft/策略/回滚 | 每次提交 |
| 验收 | UTM (3 VM) | iStoreOS 真机行为 | 发版前 |
