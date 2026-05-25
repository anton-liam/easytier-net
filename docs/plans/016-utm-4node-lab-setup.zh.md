# UTM 4 节点测试环境搭建计划

## Context

gateway_policy 模块代码和 Docker 集成测试已全部完成（21 tests pass）。现在需要在 UTM 虚拟机中搭建真实 4 节点环境，模拟 3 个异地网络，验证端到端 gateway policy。

**硬件环境**：Mac Apple Silicon (ARM64)，UTM 虚拟化
- A/B: OpenWrt 25.12.4 空白系统（aarch64）
- C/D: Ubuntu（同模板克隆，需改 MAC）

## 实际网络拓扑

UTM 自动分配的网段：
- **Shared 网络 (bridge100)**: 192.168.64.0/24，网关 192.168.64.1
- **Host 网络 (bridge101)**: 192.168.128.0/24，网关 192.168.128.1

```
  站点 1 (A 的 LAN 侧)                   UTM 共享网络 (模拟骨干/互联网)
  192.168.128.0/24 (Host)                 192.168.64.0/24 (Shared)
  ┌─────────────┐                         ┌───────────────────────────────┐
  │ D: .2       │                         │  宿主机: .1 (可访问 C Web)    │
  │ Ubuntu      │                         │  A eth0: DHCP→.x             │
  │ gw → A      │                         │  B eth0: DHCP→.x             │
  └──────┬──────┘                         │  C eth0: .4 (已有)            │
         │ (Host 网络)                    └───────────────────────────────┘
    A eth1/br-lan: .254                          │          │
                                            站点 2 (B)  站点 3 (C)
                                            只有 WAN    Web 控制面
```

| VM | 角色 | 网卡 | IP | 子网 | MAC |
|----|------|------|----|------|-----|
| A  | Source GW (双口) | eth0 (WAN) | DHCP 或静态 | Shared 192.168.64.0/24 | 3A:0C:8C:7D:72:47 |
|    |                  | eth1 (LAN) | 192.168.128.254 | Host 192.168.128.0/24 | 8E:4F:6E:AC:34:2F |
| B  | Exit GW (单口) | eth0 | DHCP 或静态 | Shared 192.168.64.0/24 | 36:2C:D8:10:0F:2F |
| C  | 控制面 Web | eth0 | 192.168.64.4 | Shared 192.168.64.0/24 | 6E:77:0D:65:D6:70 |
| D  | 客户端 | eth0 | 192.168.128.2 (DHCP) | Host 192.168.128.0/24 | E6:8E:03:51:D8:AE |

## 已完成

### 步骤 1: VM 配置（通过修改 .utm/config.plist）✅

- 4 台 VM MAC 全部唯一
- A: 双网卡 Shared + Host
- D: Host-Only 模式（只能通过 A 出网）
- B/C: Shared 模式

## 当前阻塞

### C/D (Ubuntu): SSH 未安装
- 网络可达（C=192.168.64.4, D=192.168.128.2）
- `Connection refused` — 需要在 UTM 控制台安装 openssh-server

### A/B (OpenWrt 25.12.4): 默认 IP 不可达
- OpenWrt 默认 LAN IP 为 192.168.1.1，不在 Shared/Host 子网内
- 从宿主机无法 SSH
- 需要先通过 UTM 控制台配置 WAN 接口 DHCP 或静态 IP

## 待执行步骤

### 步骤 2: 初始化 SSH 访问（需要 UTM 控制台手动操作）

**C (Ubuntu 控制台)**：
```sh
sudo apt update && sudo apt install -y openssh-server
```

**D (Ubuntu 控制台)**：
```sh
sudo apt update && sudo apt install -y openssh-server
```

**A (OpenWrt 控制台)** — 配置 WAN 口获取共享网络 IP：
```sh
# 查看接口
ip addr show
# 配置 WAN (eth0) 为 DHCP
uci set network.wan=interface
uci set network.wan.device='eth0'
uci set network.wan.proto='dhcp'
uci commit network
/etc/init.d/network restart
# 验证
ip addr show eth0
```

**B (OpenWrt 控制台)** — 同样配置：
```sh
uci set network.wan=interface
uci set network.wan.device='eth0'
uci set network.wan.proto='dhcp'
uci commit network
/etc/init.d/network restart
ip addr show eth0
```

### 步骤 3: 远程配置网络（SSH 可达后自动化）

**A**：
```sh
# WAN 保持 DHCP（已配）
# LAN 改为 192.168.128.254
uci set network.lan.ipaddr='192.168.128.254'
uci set network.lan.netmask='255.255.255.0'
uci commit network
/etc/init.d/network restart
```

**D**：
```sh
# 静态 IP + 网关指向 A
sudo ip addr flush dev enp0s1
sudo ip addr add 192.168.128.100/24 dev enp0s1
sudo ip route replace default via 192.168.128.254
```

### 步骤 4: 编译 aarch64 二进制

```sh
make build TARGET=aarch64-linux
# 产出: dist/aarch64-linux/{easytier-core, easytier-web-embed, easytier-agent}
```

### 步骤 5: 创建 inventory.env

```env
UTM_A_HOST=<A 的 Shared IP>
UTM_A_USER=root
UTM_A_MACHINE_ID=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
UTM_A_EASYTIER_IPV4=10.126.126.2
UTM_A_LAN_IP=192.168.128.254
UTM_A_MANAGED_CIDRS=192.168.128.0/24

UTM_B_HOST=<B 的 Shared IP>
UTM_B_USER=root
UTM_B_MACHINE_ID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
UTM_B_EASYTIER_IPV4=10.126.126.3

UTM_C_HOST=192.168.64.4
UTM_C_USER=anton
UTM_C_PASSWORD=anton
UTM_WEB_URL=http://192.168.64.4:11211
UTM_CONFIG_SERVER=udp://192.168.64.4:22020/admin

UTM_D_HOST=192.168.128.100
UTM_D_USER=anton
UTM_D_PASSWORD=anton
```

### 步骤 6: 部署 C + A/B 并组网

```sh
make utm-deploy-web                    # 部署 C 控制台
scp easytier-core/agent 到 A/B         # 部署二进制
make utm-configure-core-webclient      # A/B 组网注册
make utm-configure-agent-service       # A/B 策略代理
```

### 步骤 7: 验证

```sh
D → A (192.168.128.254)   ping
A → B (Shared IP)         ping
A → C (192.168.64.4)      ping
A tun0 ↔ B tun0           ping (10.126.126.x)
C Web 设备列表包含 A、B
make utm-stability-test
```

## 关键文件

| 文件 | 用途 |
|------|------|
| `targets/aarch64-linux/build-in-docker.sh` | 编译 aarch64 二进制 |
| `scripts/utm-deploy-web.sh` | 部署 C 控制台 |
| `scripts/utm-configure-core-webclient.sh` | A/B 组网注册 |
| `scripts/utm-configure-agent-service.sh` | A/B 策略代理 |
| `tests/utm/inventory.env.example` | 环境变量模板 |
