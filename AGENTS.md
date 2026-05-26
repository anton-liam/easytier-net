# EasyTier-Net Gateway

## 沟通与文档规范

- **沟通语言**：使用中文
- **文档语言**：所有 spec（`docs/specs/`）和 plan（`docs/plans/`）文档使用中文撰写
- **文件命名**：spec 和 plan 文件以 `.zh.md` 结尾
- **代码注释**：实现代码中需要补充方法级别的注释，描述功能用途

## 项目目标

在 EasyTier 组网基础上，实现 D → A → B → Internet 的出口网关策略编排。
C 作为控制面，通过 EasyTier 已有通道下发策略。Web pair API 同时下发 EasyTier 原生配置和 `gateway_policy`：
- `proxy_cidrs`：A 声明 D 子网，供 B 获得回程路径
- `exit_nodes`：A 指定 B 的 tunnel IP 作为 EasyTier 出口 peer
- `gateway_policy Source`：A 只选择 D 子网出口流量进入 EasyTier，并在异常时 fail-closed
- `gateway_policy Exit`：B 对来自 EasyTier 的受管流量做出口 NAT

## 网络前提

A、B、C 分别处于**三个不同的物理网络**（可能是不同地域、不同运营商）。
它们通过 EasyTier 组网后形成虚拟子网互通。

关键约束：
- A 能访问 C（通过 EasyTier 或直连 underlay）
- B 能访问 C（通过 EasyTier 或直连 underlay）
- D 是 A 的子网设备，只能通过 A 出网
- A 和 B 之间**不一定有直接物理连通**，靠 EasyTier tunnel 互达

在 Docker 集成测试中，用同一个 underlay 网络简化模拟三者互通。
但设计上不能假设 A/B 处于同一局域网。

## 硬件设备模型

### 双口设备（dualport）— NanoPi R3S

模拟真实 NanoPi R3S 运行 OpenWrt 的环境。双网口：

```
         WAN (eth0)                LAN (eth1 / br-lan)
           │                            │
    连接上游网络/underlay            连接下游子网设备 (D)
```

- WAN 口：接入上游网络（underlay），也是 EasyTier 组网通道
- LAN 口：作为网关为下游设备（D）提供出网服务
- OpenWrt 默认配置：eth0=WAN, eth1=LAN(br-lan)

**用作 Source 网关（A）时**：D 连 LAN 口，受管流量从 WAN 口经 EasyTier tunnel 发往 B。

### 单口设备（singleport）— Raspberry Pi 4/5

模拟 Raspberry Pi 4 或 5 运行 OpenWrt 的环境。仅一个网口：

```
         eth0 (唯一网口)
           │
    同时承担 WAN 接入 + EasyTier 组网
```

- 单口接入上游网络，作为旁路由
- 无独立 LAN 口，不直连下游客户端
- OpenWrt 默认配置：eth0=LAN(br-lan)，WAN 通过 DHCP client 或手动配置

**用作 Exit 网关（B）时**：只需接入 WAN（上游网络），接收 tunnel 流量并 masquerade 出网。无需 LAN 口。

### 网口差异对策略的影响

| 设备模板 | 网口 | 可承担角色 | nft mark 的 iif |
|----------|------|-----------|-----------------|
| dualport (R3S) | WAN + LAN | Source 或 Exit | `iif "br-lan"` (LAN 口) |
| singleport (RPi) | 仅 WAN | **仅 Exit** | 不需要 mark（只做 masquerade） |

Gateway 模块根据设备角色（source/exit）决定行为，不需要暴露网口细节给 Web 用户。

## 网络拓扑

```
                        underlay (192.168.64.0/24)
                  ┌───────────┬───────────┬───────────┐
                  │           │           │           │
          ┌───────┴───────┐ ┌─┴─────────┐ ┌─┴───────┐
          │  A (source)   │ │ B (exit)  │ │    C    │
          │  NanoPi R3S   │ │ RPi4/5 或 │ │  Ubuntu │
          │  OpenWrt     │ │ R3S       │ │         │
          │               │ │ OpenWrt  │ │         │
          │  WAN: .8 ─────│─│── .3 ─────│─│── .4    │
          │  LAN: 192.168.│ │           │ │         │
          │       1.1     │ │  eth0     │ │easytier │
          │               │ │  (单口)   │ │ -web    │
          │  easytier-core│ │           │ │         │
          │  + gateway mod│ │ easytier  │ │         │
          └───────┬───────┘ │ + gateway │ └─────────┘
                  │         └─────┬─────┘
    ┌─────────────┤               │
    │  EasyTier tunnel (tun0)     │
    │  10.126.126.0/24            │
    │             │               │
    │    LAN 口   │          WAN  │
    │ 192.168.1.0/24     (NAT → Internet)
    │             │
          ┌───────┴───────┐
          │       D       │
          │    Ubuntu     │
          │   .2 (client) │
          │               │
          │ 默认网关→A LAN │
          └───────────────┘
```

### 节点职责

| 节点 | 硬件模型 | OS | 角色 | 网口 | 运行的服务 |
|------|----------|------|------|------|------|
| A | NanoPi R3S (dualport) | OpenWrt | Source 网关 | WAN(eth0) + LAN(eth1/br-lan) | easytier-core + gateway 模块 |
| B | RPi4/5 或 R3S (singleport/dualport) | OpenWrt | Exit 网关（旁路由） | eth0（接入 WAN） | easytier-core + gateway 模块 |
| C | 通用 x86/arm | Ubuntu | 控制面 | eth0 | easytier-web + config-server + relay |
| D | 任意 | Ubuntu | 客户端 | eth0（连 A LAN） | 无，仅作为流量源 |

### 网络划分

| 网络 | 网段 | 用途 | 连接节点 |
|------|------|------|------|
| underlay | 192.168.64.0/24 | A/B/C 物理互联（WAN 侧） | A(WAN), B(eth0), C(eth0) |
| lan_a | 192.168.1.0/24 | D 连接 A 的 LAN 口 | A(LAN), D |
| tunnel | 10.126.126.0/24 | EasyTier 虚拟网络 | A(tun0), B(tun0), C(tun0) |
| wan_b | NAT / 公网 | B 出口到 Internet | B(eth0 出向) |

## 流量路径

### 受管流量（D 的出口）

```
D (192.168.1.2)
  → A br-lan (nft: iif=br-lan, saddr=192.168.1.0/24 → mark 0x7e)
  → A policy route (fwmark 0x7e → table 126 → dev tun0)
  → EasyTier tunnel (exit_nodes 选择 B)
  → B tun0 (receive)
  → B nft masquerade (oif=wan → SNAT)
  → Internet
```

### 回程流量

```
Internet reply
  → B WAN
  → B conntrack 还原 D 连接
  → B 根据 EasyTier proxy_cidrs 获得 D 子网回程
  → B tun0
  → A tun0
  → A br-lan
  → D
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
  "ingress_iface": "br-lan",
  "easytier_iface": "tun0",
  "exit_peer_tun_ip": "10.126.126.3",
  "exit_wan_iface": "eth0"
}
```

pair apply 的顺序必须是：
1. 对 A 下发 EasyTier 原生配置：`proxy_cidrs += managed_cidrs`，`exit_nodes += exit_peer_tun_ip`
2. 对 B 下发 `GatewayRole::Exit`
3. 对 A 下发 `GatewayRole::Source`

失败时按已执行步骤反向回滚，避免只完成半边策略。

### A 收到策略后执行

```sh
# 1. mark
nft add table inet easytier_gw
nft add chain inet easytier_gw prerouting { type filter hook prerouting priority -150 \; }
nft add rule inet easytier_gw prerouting iif "br-lan" ip saddr 192.168.1.0/24 ip daddr != 192.168.1.0/24 meta mark set 0x7e

# 2. policy route
ip rule add fwmark 0x7e table 126
ip route replace default dev tun0 table 126
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
nft delete table inet easytier_gw_guard 2>/dev/null
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
applied ──(收到 disabled)──→ idle
applied ──(Exit 组网异常)──→ degraded ──→ idle
applied ──(Source 组网异常)──→ degraded_guarded
degraded_guarded ──(隧道恢复)──→ applied
degraded_guarded ──(收到 disabled)──→ idle
```

状态保持最小集合，但 Source 异常必须保留 `degraded_guarded`，用于阻断 D 子网泄漏并等待隧道恢复。

### Run Loop（每 5 秒）

```
loop {
    tunnel_ok = check tun0 exists && peer reachable
    policy = get desired policy from config-server channel

    match (current_state, tunnel_ok, policy) {
        (idle, true, Some(enabled))            → apply rules → applied
        (applied, _, Some(disabled))           → cleanup rules → idle
        (applied(source), false, Some(enabled))→ cleanup rules + guard → degraded_guarded
        (degraded_guarded, true, Some(enabled))→ cleanup guard + apply rules → applied
        (applied(exit), false, _)              → cleanup rules → degraded → idle
        (applied, true, _)                     → noop
        (idle, _, None)                        → noop
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
| Source 组网断开（tun0 down / peer 不通） | 清理 policy route，安装 guard drop | D 子网 fail-closed |
| Exit 组网断开 | 自动回滚 | 干净 |
| C 下发 disable | cleanup | 干净 |
| easytier-core 进程退出 | trap cleanup | 干净 |
| C 不可达但组网正常 | 保持当前策略不变 | 保持 |

**原则：用户删除策略才恢复普通网络；Source 策略仍 desired 但隧道异常时必须 fail-closed，不能让 D 流量回落到 A 本地 WAN。控制面不可达但组网正常时保持现状。**

## EasyTier Fork 改动边界

### 允许改动

- 新增 `gateway/` 模块
- 扩展 proto 消息（添加 GatewayPolicy）
- web_client 收到 policy 后分发给 gateway 模块
- easytier-web 策略 CRUD
- easytier-web pair API 通过 `ConfigRpc/PatchConfig` 下发 `proxy_cidrs` 和 `exit_nodes`

### 禁止改动

- tunnel/peer 发现/NAT 穿越核心代码
- 加密/认证机制
- config-server 协议本身
- CLI 工具核心逻辑
- 使用 `manual_routes` 作为主路径

## 构建方案

### 开发环境

- 宿主机：Mac (Apple Silicon / arm64)
- 交叉编译通过 Docker 或 cross 完成

### 构建目标

| 产物 | 目标架构 | Rust target | 部署位置 |
|------|----------|-------------|----------|
| easytier-core | x86_64 linux | `x86_64-unknown-linux-musl` | C 云服务器 |
| easytier-web (含前端) | x86_64 linux | `x86_64-unknown-linux-musl` | C 云服务器 |
| easytier-core | aarch64 linux | `aarch64-unknown-linux-musl` | R3S/RPi (A/B) |
| OpenWrt 镜像 (R3S) | aarch64 | OpenWrt ImageBuilder | NanoPi R3S |
| OpenWrt 镜像 (RPi4) | aarch64 | OpenWrt ImageBuilder | Raspberry Pi 4 |
| OpenWrt 镜像 (RPi5) | aarch64 | OpenWrt ImageBuilder | Raspberry Pi 5 |

### EasyTier 编译 (C 云服务器包)

通过 Docker 交叉编译，产出静态链接的 musl 二进制：

```sh
make build-server
# 产出:
#   dist/x86_64/easytier-core
#   dist/x86_64/easytier-web
```

构建流程：
1. Docker 容器内使用 `rust:latest` + `musl-tools`
2. `cargo build --release -p easytier` → easytier-core
3. `cd easytier-web/frontend && pnpm build` → 前端静态文件
4. `cargo build --release -p easytier-web` → easytier-web（内嵌前端）
5. 产出复制到 `dist/x86_64/`

### EasyTier 编译 (OpenWrt 设备包)

```sh
make build-openwrt
# 产出:
#   dist/aarch64/easytier-core
```

### OpenWrt 镜像打包

使用 OpenWrt ImageBuilder 将 easytier 二进制 + luci 插件注入官方镜像：

```sh
make image-r3s      # dist/images/openwrt-r3s.img.gz
make image-rpi4     # dist/images/openwrt-rpi4.img.gz
make image-rpi5     # dist/images/openwrt-rpi5.img.gz
```

构建流程：
1. 下载对应设备的 OpenWrt ImageBuilder
2. 编译 easytier-core (aarch64-unknown-linux-musl)
3. 打包为 ipk 或直接注入 rootfs overlay
4. 注入 luci-app-easytier 配置界面
5. 注入 UCI defaults（首次启动自动配置 easytier 服务）
6. ImageBuilder 生成最终 .img.gz

OpenWrt 镜像默认服务参数：

```sh
easytier-core -w "$config_server" --proxy-forward-by-system
```

`proxy_forward_by_system` 是设备基础默认能力，写入 UCI 配置，不作为 gateway policy 每次动态 patch 的字段。`manual_routes` 不写入镜像默认配置。

### 一键构建

```sh
make build-all
# 等价于:
#   make build-server    (C 的 x86_64 包)
#   make build-openwrt   (A/B 的 aarch64 包)
#   make image-r3s       (R3S 镜像)
#   make image-rpi4      (RPi4 镜像)
#   make image-rpi5      (RPi5 镜像)
```

### 产出目录

```
dist/
├── x86_64/
│   ├── easytier-core          # C 云服务器
│   └── easytier-web           # C 云服务器 (含内嵌前端)
├── aarch64/
│   └── easytier-core          # A/B 设备
└── images/
    ├── openwrt-r3s.img.gz     # NanoPi R3S 刷机镜像
    ├── openwrt-rpi4.img.gz    # Raspberry Pi 4 刷机镜像
    └── openwrt-rpi5.img.gz    # Raspberry Pi 5 刷机镜像
```

## 测试方案

### Docker 集成测试

开发宿主机为 Mac (Apple Silicon / arm64)。所有容器镜像使用 arm64 原生：
- A/B：`ghcr.io/openwrt/rootfs:armsr-armv8`（arm64 原生，有 UCI/procd/fw4/nftables）
- C/D：`ubuntu:24.04`（multi-arch，自动使用 arm64）
- EasyTier 二进制：编译为 `aarch64-unknown-linux-musl` 目标

```
tests/integration/
├── docker-compose.yml
├── images/
│   ├── Dockerfile.openwrt    # A/B 基础镜像 (OpenWrt)
│   └── Dockerfile.ubuntu     # C/D 基础镜像
├── scripts/
│   ├── test-gateway-forward.sh         # D→A→B→Internet
│   ├── test-gateway-native-easytier.sh # proxy_cidrs/exit_nodes 下发和清理
│   ├── test-gateway-return-path.sh     # TCP/UDP 回程和计数器
│   ├── test-gateway-fail-closed.sh     # Source 异常防泄漏
│   ├── test-policy-restore.sh          # 还原策略后网络干净
│   ├── test-tunnel-down-rollback.sh    # 兼容旧入口，验证 fail-closed
│   └── test-process-exit-cleanup.sh    # 进程退出清理
```

### 测试分层

| 层级 | 工具 | 验证什么 | 频率 |
|------|------|------|------|
| 集成 | Docker Compose | 路由/nft/策略/回滚 | 每次提交 |
| 验收 | UTM (4 VM) | OpenWrt 真机行为、tun0、回程抓包、弱网/MTU | 发版前 |
