# UTM 4 节点 gateway_policy 验收计划

## 目标

在 UTM 中搭建 A/B/C/D 四节点环境，验证当前 `gateway_policy` 方案是否能稳定实现：

```text
D(client) -> A(source/OpenWrt) -> EasyTier tunnel -> B(exit/OpenWrt) -> Internet
```

本计划只验证当前干净实现：
- A/B 运行 OpenWrt
- C 运行 Ubuntu，部署 `easytier-core` config-server 和 `easytier-web`
- D 运行 Ubuntu，作为 A LAN 侧客户端
- 不使用旧 agent
- 策略通过 Web 的 `gateway_policy` pair API 下发

## 验收边界

必须验证：
- A/B 能通过 `easytier-core -w udp://C:22020/admin` 连接 C
- C 的 Web Device List 能看到 A/B 在线
- C 能通过 pair API 一次指定 Source/Exit 并下发策略
- D 的公网出口表现为 B
- D -> A 本机访问不被策略捕获
- A/B/C 控制面互联不因策略失联
- 删除策略后 A/B 网络规则清理干净
- EasyTier tunnel 异常时策略自动回滚

暂不验证：
- iStoreOS 镜像
- 独立 agent
- LuCI 页面交互细节
- HIL 真机测试台

## UTM 网络拓扑

UTM 当前用两个网络模拟“客户端 LAN”和“外部/骨干网络”：

| 网络 | 网段 | 用途 |
|------|------|------|
| Shared 网络 | `192.168.64.0/24` | A WAN、B WAN、C 控制面所在网络 |
| Host 网络 | `192.168.128.0/24` | A LAN 和 D 客户端网络 |
| EasyTier tunnel | `10.126.126.0/24` | A/B/C 组网后的虚拟网络 |

```text
            Shared / underlay: 192.168.64.0/24
      ┌────────────────────────────────────────────┐
      │ A WAN              B WAN              C    │
      │ OpenWrt            OpenWrt            Ubuntu
      │ eth0               eth0               eth0 │
      └──────┬──────────────┬──────────────────┬───┘
             │              │                  │
             │        EasyTier tunnel          │
             │        10.126.126.0/24          │
             │              │                  │
      ┌──────┴──────┐       │                  │
      │ A LAN       │       │                  │
      │ br-lan/eth1 │       │                  │
      │ 192.168.128.254     │                  │
      └──────┬──────┘       │                  │
             │ Host / LAN: 192.168.128.0/24    │
      ┌──────┴──────┐                          │
      │ D Ubuntu    │                          │
      │ default gw  │                          │
      │ -> A LAN    │                          │
      └─────────────┘                          │
```

## 节点角色

| 节点 | OS | 角色 | 必要服务 |
|------|----|------|----------|
| A | OpenWrt | Source 网关 | `easytier-core -w` + `gateway_policy` |
| B | OpenWrt | Exit 网关 | `easytier-core -w` + `gateway_policy` |
| C | Ubuntu | 控制面和搭线节点 | `easytier-core` config-server + `easytier-web` |
| D | Ubuntu | 客户端 | 无 EasyTier，仅作为流量源 |

## 初始网络配置

### A: Source/OpenWrt

WAN 口使用 Shared 网络：

```sh
uci set network.wan=interface
uci set network.wan.device='eth0'
uci set network.wan.proto='dhcp'
uci commit network
/etc/init.d/network restart
```

LAN 口使用 Host 网络，供 D 接入：

```sh
uci set network.lan.ipaddr='192.168.128.254'
uci set network.lan.netmask='255.255.255.0'
uci commit network
/etc/init.d/network restart
```

### B: Exit/OpenWrt

B 只需要 WAN 接入 Shared 网络：

```sh
uci set network.wan=interface
uci set network.wan.device='eth0'
uci set network.wan.proto='dhcp'
uci commit network
/etc/init.d/network restart
```

### C: Ubuntu

C 使用 Shared 网络，固定或 DHCP 获取可访问 IP，例如：

```text
192.168.64.4
```

需要能从宿主机访问：

```text
http://192.168.64.4:11211
```

### D: Ubuntu Client

D 使用 Host 网络，默认网关指向 A LAN：

```sh
sudo ip addr flush dev enp0s1
sudo ip addr add 192.168.128.100/24 dev enp0s1
sudo ip route replace default via 192.168.128.254
```

## 构建产物

当前构建命令：

```sh
make build-server
make build-openwrt
make build-docker-test
```

产物：

```text
dist/x86_64/easytier-core
dist/x86_64/easytier-web
dist/aarch64/easytier-core
dist/aarch64/easytier-web
```

`make build-openwrt` 和 `make build-docker-test` 默认使用 `EASYTIER_BUILD_BACKEND=auto`：

- 本机存在 `aarch64-linux-musl-gcc`、`aarch64-linux-musl-ar`、Rust target 时，优先走本机增量构建。
- 本机工具链缺失或 native 构建失败时，自动回退到 Docker builder。
- 可通过 `EASYTIER_BUILD_BACKEND=native` 强制本机构建。
- 可通过 `EASYTIER_BUILD_BACKEND=docker` 强制 Docker 构建。

OpenWrt 镜像构建可通过 `.env` 指定默认 C 端地址：

```env
EASYTIER_CONFIG_SERVER=udp://192.168.64.4:22020/admin
```

`.env` 不进入 git；示例见 `.env.example`。

## 部署步骤

### 1. 部署 C

上传并运行：

```sh
dist/x86_64/easytier-core
dist/x86_64/easytier-web
```

C 需要提供：
- EasyTier config-server：`udp://192.168.64.4:22020/admin`
- Web 控制台：`http://192.168.64.4:11211`

### 2. 部署 A/B

上传：

```sh
dist/aarch64/easytier-core -> /usr/bin/easytier-core
```

启动：

```sh
/usr/bin/easytier-core -w udp://192.168.64.4:22020/admin
```

正式镜像验收时，应通过 OpenWrt procd 服务启动。

### 3. Web 组网验证

在 C 的 Web 控制台验证：
- A 在线
- B 在线
- A/B 有各自 machine id
- A/B 已进入同一 EasyTier network instance
- A tunnel IP 和 B tunnel IP 可确认

## 策略下发

通过 pair API 一次编排 A/B：

```http
POST /api/v1/gateway-policy/pair
```

示例 payload：

```json
{
  "policy_id": "utm-gw-001",
  "source_machine_id": "<A_MACHINE_ID>",
  "exit_machine_id": "<B_MACHINE_ID>",
  "managed_cidrs": ["192.168.128.0/24"],
  "ingress_iface": "br-lan",
  "easytier_iface": "tun0",
  "exit_peer_tun_ip": "<B_TUN_IP>",
  "exit_wan_iface": "eth0"
}
```

下发顺序要求：
1. C 先下发 Exit 策略到 B
2. C 再下发 Source 策略到 A
3. 如果 A 下发失败，C 必须回滚 B

## 验收命令

### 基础连通

```sh
# D -> A LAN
ping -c 3 192.168.128.254

# A -> C underlay
ping -c 3 192.168.64.4

# A -> B tunnel
ping -c 3 <B_TUN_IP>

# B -> A tunnel
ping -c 3 <A_TUN_IP>
```

### 出口流量

在 D 上：

```sh
curl -4 https://ifconfig.me
curl -4 https://api.ipify.org
```

预期：
- 返回 IP 应表现为 B 的出口
- 不能表现为 A 的出口

### 本机访问不被捕获

在 D 上：

```sh
ping -c 3 192.168.128.254
ssh root@192.168.128.254
```

预期：
- D 访问 A 本机正常
- 该流量不走 B

### 控制面不失联

策略启用后验证：

```sh
# A 上
ping -c 3 192.168.64.4

# B 上
ping -c 3 192.168.64.4
```

预期：
- A/B 仍可访问 C
- Web Device List 仍显示 A/B 在线

### 策略规则检查

A 上应能看到：

```sh
nft list table inet easytier_gw
ip rule show | grep 0x7e
ip route show table 126
```

B 上应能看到：

```sh
nft list table inet easytier_gw
```

B 至少应包含：
- postrouting masquerade
- tunnel -> WAN forward accept
- WAN -> tunnel established/related forward accept
- OpenWrt fw4 forward 链中带 `easytier_gw` comment 的兼容规则（如果 fw4 存在）

## 策略删除验收

通过 pair remove API：

```http
POST /api/v1/gateway-policy/pair/remove
```

payload 与 pair 下发一致，至少需要：

```json
{
  "policy_id": "utm-gw-001",
  "source_machine_id": "<A_MACHINE_ID>",
  "exit_machine_id": "<B_MACHINE_ID>",
  "managed_cidrs": ["192.168.128.0/24"],
  "ingress_iface": "br-lan",
  "exit_peer_tun_ip": "<B_TUN_IP>",
  "exit_wan_iface": "eth0"
}
```

删除后验证：

```sh
# A
ip rule show | grep 0x7e
ip route show table 126
nft list table inet easytier_gw

# B
nft list table inet easytier_gw
```

预期：
- A 无 fwmark 0x7e rule
- A table 126 为空
- A/B 无 `inet easytier_gw` table
- OpenWrt fw4 中无 `easytier_gw` comment 规则

## 异常回滚验收

模拟 tunnel 异常：

```sh
# A 上临时停止 easytier-core 或删除 tun0
/etc/init.d/easytier stop
```

预期：
- `gateway_policy` run loop 检测 tunnel 异常
- A 自动 cleanup
- D 不应继续错误地被导向不可达 B
- A/B/C 控制面恢复后可重新下发策略

## 当前注意事项

- `016` 是 UTM 端到端验收计划，不是代码实现计划。
- 代码实现以 `017-gateway-policy-minimal-downlink.zh.md` 为准。
- Docker 集成测试后续应改为产品路径：Web REST -> RPC -> gateway_policy executor，而不是手写 nft/ip 命令。
