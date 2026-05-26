# EasyTier-Net Gateway

基于 [EasyTier](https://github.com/EasyTier/EasyTier) 组网，实现 D → A → B → Internet 出口网关策略编排。

## 网络拓扑

```
D (client)                A (source)              B (exit)               C (control)
Ubuntu                    NanoPi R3S / OpenWrt     RPi4/5 / OpenWrt       Ubuntu x86_64
192.168.1.2               WAN + LAN (双口)          eth0 (单口旁路由)       云服务器
    │                         │                        │                     │
    └── LAN 192.168.1.0/24 ───┘                        │                     │
                              │                        │                     │
                              └──── EasyTier tunnel ───┘─────────────────────┘
                                    (10.126.126.0/24)
```

- A/B/C 处于三个不同物理网络，通过 EasyTier 组网互达
- D 是 A 的子网设备，只能通过 A 出网
- C 通过 EasyTier 通道下发出口策略，同时补齐 EasyTier 原生 `proxy_cidrs` 和 `exit_nodes`
- `proxy_cidrs` 负责 B 回 D 子网的回程路由传播，`exit_nodes` 负责 A 选择 B 作为 EasyTier 出口 peer
- `gateway_policy` 只承担最小职责：A 选择 D 子网流量并 fail-closed，B 做出口 NAT

## 前置依赖

- Docker Desktop (Mac Apple Silicon)
- Git
- Make

## 快速开始

```sh
# 克隆项目
git clone --recurse-submodules <repo-url>
cd easytier-net

# 一键编译所有产物
make build-all
```

## 构建命令

### 编译 EasyTier

| 命令 | 产出 | 用途 |
|------|------|------|
| `make build-server` | `dist/x86_64/easytier-core` `dist/x86_64/easytier-web` | C 云服务器部署 |
| `make build-openwrt` | `dist/aarch64/easytier-core` | A/B OpenWrt 设备 |
| `make build-all` | 以上全部 + OpenWrt 镜像 | 一键全量构建 |

### 打包 OpenWrt 固件镜像

预置 easytier-core + LuCI 管理界面，刷入即用：

| 命令 | 产出 | 目标设备 |
|------|------|----------|
| `make image-r3s` | `dist/images/openwrt-r3s.img.gz` | NanoPi R3S |
| `make image-rpi4` | `dist/images/openwrt-rpi4.img.gz` | Raspberry Pi 4 |
| `make image-rpi5` | `dist/images/openwrt-rpi5.img.gz` | Raspberry Pi 5 |

> 镜像构建依赖 `dist/aarch64/easytier-core`，需先执行 `make build-openwrt`，
> 或直接 `make build-all` 自动处理依赖顺序。

## 部署

### C 云服务器 (Ubuntu x86_64)

```sh
# 复制二进制到服务器
scp dist/x86_64/easytier-core dist/x86_64/easytier-web user@server:/opt/easytier/

# 在服务器上启动
ssh user@server
cd /opt/easytier
./easytier-web --listen 0.0.0.0:11211 &
```

### A/B OpenWrt 设备

```sh
# 刷入镜像 (以 R3S 为例，SD 卡设备名按实际情况替换)
gunzip -c dist/images/openwrt-r3s.img.gz | dd of=/dev/sdX bs=4M status=progress

# 首次启动后通过 LuCI 配置 EasyTier:
#   浏览器访问 http://192.168.1.1
#   服务 → EasyTier → 填入 C 的 config-server 地址
```

镜像中的 EasyTier 服务默认以 `easytier-core -w <config-server> --proxy-forward-by-system` 启动。该能力属于设备基础能力，出口策略只负责动态编排 Source/Exit，不再每次下发时重复调整系统转发模式。

## 集成测试

使用 Docker Compose 模拟完整 4 节点拓扑：

```sh
# 启动测试环境
make test-integration

# 或手动操作
cd tests/integration
make up          # 启动 A/B/C/D 四个容器
make test        # 运行测试
make down        # 清理

# 调试: 进入单个节点
make shell-a     # A (source, OpenWrt)
make shell-b     # B (exit, OpenWrt)
make shell-c     # C (control, Ubuntu)
make shell-d     # D (client, Ubuntu)
```

集成测试当前覆盖：

| 脚本 | 验证内容 |
|------|----------|
| `test-gateway-forward.sh` | Web pair API 下发后 D → A → B → endpoint |
| `test-gateway-native-easytier.sh` | A 的 `proxy_cidrs` / `exit_nodes` 原生配置下发和清理 |
| `test-gateway-return-path.sh` | TCP/UDP 回程和 B 侧 nft 计数 |
| `test-gateway-fail-closed.sh` | Source 隧道异常时阻断 D 外联，避免回落 A WAN |
| `test-policy-restore.sh` | pair remove 后清理 gateway policy 和 guard |
| `test-process-exit-cleanup.sh` | easytier-core 退出时清理规则 |

## 产出目录

```
dist/
├── x86_64/
│   ├── easytier-core            # C 云服务器
│   └── easytier-web             # C 云服务器 (含 Web 管理界面)
├── aarch64/
│   └── easytier-core            # A/B 设备
└── images/
    ├── openwrt-r3s.img.gz       # NanoPi R3S 刷机镜像
    ├── openwrt-rpi4.img.gz      # Raspberry Pi 4 刷机镜像
    └── openwrt-rpi5.img.gz      # Raspberry Pi 5 刷机镜像
```

## 项目结构

```
├── AGENTS.md                    # 架构设计、拓扑约束、模块设计
├── Makefile                     # 顶层构建入口
├── vendor/EasyTier/             # EasyTier fork (submodule)
├── scripts/
│   ├── build-server.sh          # x86_64 交叉编译
│   ├── build-openwrt.sh         # aarch64 交叉编译
│   └── build-image.sh           # OpenWrt ImageBuilder 打包
├── targets/
│   ├── r3s/                     # R3S 设备特定文件
│   ├── rpi4/                    # RPi4 设备特定文件
│   └── rpi5/                    # RPi5 设备特定文件
└── tests/integration/
    ├── docker-compose.yml       # 4 节点测试拓扑
    └── scripts/                 # 测试脚本
```

## 详细文档

- [AGENTS.md](AGENTS.md) — 架构设计、网络拓扑、Gateway 模块设计、一致性保证
