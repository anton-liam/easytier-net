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
- A/B 能通过 `easytier-core -w udp://C:22020/admin` 注册到 C
- C 能通过 pair API 下发 `peer_urls=[udp://C:11010]` 的基础组网配置
- C 的 Web Device List 能看到 A/B 在线
- C 能通过 pair API 一次指定 Source/Exit 并下发策略
- D 的公网出口表现为 B
- D -> A 本机访问不被策略捕获
- A/B/C 控制面互联不因策略失联
- 删除策略后 A/B 网络规则清理干净
- Source EasyTier tunnel 异常时进入 fail-closed guard，阻断 D 外联防止回落 A WAN
- Exit EasyTier tunnel 异常时策略自动回滚
- A 的 EasyTier 原生配置包含 `proxy_cidrs` 和 `exit_nodes`
- B 能看到 D 子网的回程路由或 EasyTier route 视图
- TCP/UDP/WebSocket/MTU 场景有明确验收记录

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
| EasyTier tunnel | `10.126.126.0/24` | A/B 组网后的虚拟网络，C 可作为 no-tun relay |

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

`build-image.sh` 会把每个设备的 OpenWrt ImageBuilder 压缩包缓存在 `build/imagebuilder/<target>/`，并把 OpenWrt 包下载缓存保留在 `build/imagebuilder/<target>/dl/`。首次构建会下载 ImageBuilder 和 ipk 包，后续同一 target 会复用缓存；实际解压和构建仍在容器内 `/tmp/ib` 完成，避免 macOS 非大小写敏感文件系统触发 OpenWrt prereq 失败。脚本会在首次缺少 `easytier-openwrt-builder:debian12` 时自动构建专用 ImageBuilder 容器，避免每次镜像打包都重复安装宿主依赖。

## 部署步骤

### 1. 部署 C

上传并运行：

```sh
dist/x86_64/easytier-core
dist/x86_64/easytier-web
```

C 需要提供：
- EasyTier config-server：`udp://192.168.64.4:22020/admin`
- EasyTier relay listener：`udp://192.168.64.4:11010`
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
- pair API 下发后，A/B 已进入同一 EasyTier network instance
- A/B 的 `peer_urls` 指向 C relay
- A tunnel IP 和 B tunnel IP 可确认

## 策略下发

通过 pair API 一次编排 A/B。pair API 先下发基础组网配置，再下发出口策略：

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
  "source_peer_tun_ip": "<A_TUN_IP>",
  "exit_peer_tun_ip": "<B_TUN_IP>",
  "exit_wan_iface": "eth0",
  "network_name": "utm-gw",
  "network_secret": "utm-gw-secret",
  "network_length": 24,
  "peer_urls": ["udp://192.168.64.4:11010"],
  "disable_p2p": true,
  "save_network": true
}
```

下发顺序要求：
1. C 先通过 WebClient `RunNetworkInstance` 给 A/B 下发 `peer_urls=[C]` 的基础组网配置。
2. C 再通过 `ConfigRpc/PatchConfig` 给 A 添加 `proxy_cidrs = managed_cidrs`。
3. C 再通过 `ConfigRpc/PatchConfig` 给 A 添加 `exit_nodes = exit_peer_tun_ip`。
4. C 下发 Exit 策略到 B。
5. C 下发 Source 策略到 A。
6. 任一步失败，C 必须按已完成步骤反向回滚；基础组网配置作为设备管理配置保留，不随出口策略删除。

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

### EasyTier 原生配置

在 pair apply 后验证：

```sh
# 通过 Web proxy-rpc 查询 A 的 ConfigRpc/GetConfig
curl -b cookie.json http://C:11211/api/v1/machines/<A_MACHINE_ID>/proxy-rpc

# A 配置中应包含
proxy_cidrs = ["192.168.128.0/24"]
exit_nodes = ["<B_TUN_IP>"]
```

B 上验证 D 子网回程：

```sh
ip route show | grep 192.168.128.0/24 || true
easytier-cli route list || true
```

预期：
- B 能通过 EasyTier route 视图或系统路由识别 D 子网在 A 后面
- 主路径不使用 `manual_routes`

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

A 的 table 126 应为：

```sh
default dev tun0
```

出口 peer 选择由 EasyTier `exit_nodes` 完成，不应再把 `via <B_TUN_IP>` 作为唯一语义。

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

pair remove 会先校验 payload；CIDR/IP/网口字段不合法时必须直接返回 400，不向 A/B 下发任何清理 RPC，避免半清理状态。删除出口策略只清理 gateway policy 规则和 A 的 `proxy_cidrs` / `exit_nodes`，基础 EasyTier network instance 保留为设备管理配置。

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

## 回程抓包验收

D 发起请求：

```sh
curl -4 --max-time 10 https://api.ipify.org
```

A 抓包：

```sh
tcpdump -ni br-lan host <D_IP>
tcpdump -ni tun0 "host <D_IP> or net 192.168.128.0/24"
```

B 抓包：

```sh
tcpdump -ni tun0 net 192.168.128.0/24
tcpdump -ni eth0 host <TEST_PUBLIC_IP>
conntrack -L | grep <D_IP>
```

预期同一连接能观察到：

```text
D -> A br-lan -> A tun0 -> B tun0 -> B WAN
B WAN reply -> B tun0 -> A tun0 -> A br-lan -> D
```

## UDP/WebSocket/MTU 验收

默认验收分为强验收和弱验收，避免可选工具缺失或公网测试点不稳定时被 `|| true` 静默吞掉。

强验收：

```sh
curl -4 --max-time 10 -fsS "$UTM_TEST_TCP_URL"
ping -M do -s 1200 -c 3 "$UTM_TEST_MTU_HOST"
```

弱验收默认只记录结果，不作为失败条件；需要升格时设置 `UTM_REQUIRE_TRACEPATH=1`、`UTM_REQUIRE_LARGE_MTU=1`、`UTM_REQUIRE_WEBSOCKET=1` 或 `UTM_REQUIRE_PUBLIC_UDP=1`。

UDP：

```sh
iperf3 -c <endpoint> -u -b 1M -t 10
```

WebSocket：

```sh
printf 'hello\n' | websocat -t wss://echo.websocket.events
```

MTU：

```sh
tracepath 1.1.1.1
ping -M do -s 1200 -c 3 1.1.1.1
ping -M do -s 1360 -c 3 1.1.1.1
```

预期：
- 强验收失败直接失败
- 弱验收输出 `WEAK-FAIL/SKIP`，作为诊断证据记录
- MTU 至少强制验证 1200，1360 作为大包弱验收，异常时回收为后续 `mtu` 参数建议

## 异常 fail-closed 验收

模拟 tunnel 异常：

```sh
# A 上临时 down tun0
ip link set tun0 down
```

预期：
- `gateway_policy` run loop 检测 tunnel 异常
- A 删除 fwmark/ip route table 126
- A 安装 `inet easytier_gw_guard`，阻断 `br-lan` 受管子网到外部的转发
- D 不能继续通过 A 本地 WAN 出口泄漏
- D -> A 本机、A -> C 控制面仍可达
- tun0 恢复后可自动重新 apply，用户删除策略时 guard 必须被清理

## 自动化脚本

仓库内提供 UTM 验收脚本：

```sh
tests/utm/check-native-easytier-config.sh
tests/utm/check-return-path.sh
tests/utm/check-fail-closed.sh
```

脚本读取 `tests/utm/inventory.env`，用于记录 A/B/C/D IP、machine id、tunnel IP 和接口名。

## 当前注意事项

- `016` 是 UTM 端到端验收计划，不是代码实现计划。
- 代码实现以 `017-gateway-policy-minimal-downlink.zh.md` 和 `018-easytier-native-capability-integration.zh.md` 为准。
- Docker 集成测试走产品路径：Web REST -> RPC -> gateway_policy executor；UTM 负责真实 `tun0`、回程抓包和弱网验收。
