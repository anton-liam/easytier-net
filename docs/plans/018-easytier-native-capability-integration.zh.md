# EasyTier 原生能力互补集成计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 在当前 `gateway_policy` 初步雏形上，借用 EasyTier 已有的子网代理、出口节点、系统转发和配置下发能力，补齐 D -> A -> B -> Internet 的回程、稳定性和防泄漏验证。

**Architecture:** Web 控制台继续通过 EasyTier WebClient/config-server 通道管理 A/B，不新增独立 agent。A/B 的基础组网能力尽量使用 EasyTier 既有 `ConfigRpc` 和网络配置字段；`gateway_policy` 只保留最小职责：A 选择 D 子网出口流量进入 EasyTier，B 对来自 EasyTier 的受管流量做转发和 NAT。回程由 EasyTier `proxy_cidrs` 路由传播能力承接，出口 peer 选择由 EasyTier `exit_nodes` 承接。

**Tech Stack:** Rust, protobuf/prost, EasyTier ConfigRpc/WebClient, nftables, iproute2, OpenWrt, Docker Compose, UTM。

---

## 里程点状态

当前 `gateway_policy` 雏形已具备：

- `GatewayPolicyRpc` 能随 `easytier-core -w` 的 WebClient session 注册。
- Web 侧 pair API 能按 Source/Exit 下发策略。
- A 端能按 `managed_cidrs + ingress_iface` 做 nft mark 和 policy route。
- B 端能启用 IPv4 forwarding，对受管 CIDR 从 WAN 出口做 masquerade。
- 策略删除、进程退出和隧道异常已有 cleanup 基础路径。

当前仍未证明或仍需补齐：

- UTM 中没有完成严格回程抓包验收。
- A 端仅依赖 `ip route default via B_tun_ip dev tun0 table 126` 不足以表达 EasyTier 内部出口 peer 选择。
- B 端回 D 子网应优先借用 EasyTier `proxy_cidrs` 路由传播，而不是手写静态回程路由。
- 策略异常时需要明确 fail-closed 行为，避免 D 流量回落到 A 本地 WAN 泄漏。

## 需要借用的 EasyTier 能力

| 能力 | 当前 EasyTier 含义 | 在本项目中的用途 | 结论 |
|------|--------------------|------------------|------|
| `proxy_cidrs` / 子网代理 | 节点声明自己可达的后端子网，并同步给其他 peer | A 声明 D 子网，B 自动知道 D 子网应经 A 回程 | 必须借用 |
| `exit_nodes` | 当目标 IP 不属于 EasyTier 虚拟网段时，选择指定出口 peer | A 将 D 的公网目标包交给 B 作为 EasyTier 出口 peer | 必须借用 |
| `proxy_forward_by_system` | 子网代理/出口转发交给系统内核，不走内置 IP proxy | OpenWrt 上保持 nft/ip route/kernel forwarding 的可观测性 | 默认启用 |
| `enable_exit_node` | 允许节点作为 EasyTier 内置出口节点 | B 可作为语义标记或内置代理 fallback；主路径不依赖它 | 可选补充 |
| `manual_routes` | 手动覆盖路由 CIDR，会禁用子网代理传播路由 | 会和 `proxy_cidrs` 冲突 | 不用于主路径 |
| `mtu` | 配置 EasyTier tun MTU | 弱网和隧道封装下避免分片问题 | 验收参数 |
| `latency_first` / KCP / QUIC | 路由偏好和弱网优化 | 可作为后续性能调优，不影响主逻辑 | 后续增强 |

## 最终目标流量模型

```text
D 192.168.128.100
  -> A br-lan 192.168.128.254
  -> A nft mark 0x7e
  -> A ip rule table 126
  -> A tun0
  -> EasyTier exit_nodes 选择 B
  -> B tun0
  -> B kernel forward + nft masquerade
  -> B WAN
  -> Internet

Internet reply
  -> B WAN
  -> B conntrack 还原 D 连接
  -> B 根据 EasyTier proxy_cidrs 路由 D 子网
  -> B tun0
  -> A tun0
  -> A br-lan
  -> D
```

## Task 1: 策略编排接入 EasyTier ConfigRpc

**Files:**

- Modify: `vendor/EasyTier/easytier-web/src/restful/gateway_policy.rs`
- Modify: `vendor/EasyTier/easytier/src/proto/gateway_policy.proto`
- Test: `vendor/EasyTier/easytier-web/src/restful/gateway_policy.rs`

- [ ] **Step 1: 在 pair API 中下发 EasyTier 原生配置补丁**

  pair apply 时按顺序执行：

  1. 对 A 调用 `api.config.ConfigRpcService/PatchConfig`，`proxy_networks ADD managed_cidrs`。
  2. 对 A 调用 `api.config.ConfigRpcService/PatchConfig`，`exit_nodes ADD exit_peer_tun_ip`。
  3. 对 B 下发 `GatewayRole::Exit` 策略。
  4. 对 A 下发 `GatewayRole::Source` 策略。

  预期 payload 语义：

  ```json
  {
    "patch": {
      "proxy_networks": [
        {
          "action": "ADD",
          "cidr": "192.168.128.0/24"
        }
      ],
      "exit_nodes": [
        {
          "action": "ADD",
          "node": "10.126.126.3"
        }
      ]
    }
  }
  ```

- [ ] **Step 2: pair apply 失败时按已执行步骤反向回滚**

  失败回滚顺序：

  1. 如果 A Source 已应用，调用 A `RemovePolicy`。
  2. 如果 B Exit 已应用，调用 B `RemovePolicy`。
  3. 如果 A `exit_nodes` 已添加，调用 `ConfigRpc/PatchConfig` remove。
  4. 如果 A `proxy_networks` 已添加，调用 `ConfigRpc/PatchConfig` remove。

- [ ] **Step 3: pair remove 同时清理 gateway policy 和 EasyTier 原生配置**

  remove 顺序：

  1. A `RemovePolicy`
  2. B `RemovePolicy`
  3. A `exit_nodes REMOVE exit_peer_tun_ip`
  4. A `proxy_networks REMOVE managed_cidrs`

- [ ] **Step 4: 增加单元测试覆盖下发顺序和回滚顺序**

  测试至少覆盖：

  - Exit 下发失败时，A 的 `proxy_networks` 和 `exit_nodes` 被 remove。
  - Source 下发失败时，B Exit 被 remove，A 的原生配置也被 remove。
  - pair remove 对离线节点返回明确错误，不吞掉失败。

## Task 2: 调整 Source 路由语义，避免把 B_tun_ip 当作唯一出口选择依据

**Files:**

- Modify: `vendor/EasyTier/easytier/src/gateway_policy/executor.rs`
- Test: `vendor/EasyTier/easytier/src/gateway_policy/executor.rs`

- [ ] **Step 1: 保留 `exit_peer_tun_ip` 作为健康检查和 Web 编排字段**

  `exit_peer_tun_ip` 继续用于：

  - A pair API 给 EasyTier `exit_nodes` 添加 B tunnel IP。
  - A monitor ping B tunnel IP。
  - Web UI 显示出口节点。

- [ ] **Step 2: Source table 126 默认路由改为指向 EasyTier tun 接口**

  推荐命令：

  ```sh
  ip route replace default dev tun0 table 126
  ```

  不再把 `via B_tun_ip` 作为唯一出口选择语义。真正选择 B 作为出口 peer 的逻辑交给 EasyTier `exit_nodes`。

- [ ] **Step 3: 单元测试确认命令规划**

  断言 Source plan 包含：

  ```text
  ip rule add fwmark 0x7e table 126
  ip route replace default dev tun0 table 126
  ```

  同时断言不再出现：

  ```text
  ip route replace default via B_TUN_IP dev tun0 table 126
  ```

## Task 3: 明确 OpenWrt 系统转发默认配置

**Files:**

- Modify: `scripts/build-image.sh`
- Modify: `targets/r3s/files/etc/uci-defaults/*` 或实际镜像 overlay 文件
- Modify: `targets/rpi4/files/etc/uci-defaults/*` 或实际镜像 overlay 文件
- Modify: `targets/rpi5/files/etc/uci-defaults/*` 或实际镜像 overlay 文件
- Test: `scripts/build-image.sh`

- [ ] **Step 1: 镜像默认 EasyTier 配置启用系统转发**

  A/B OpenWrt 镜像默认写入：

  ```toml
  proxy_forward_by_system = true
  ```

  该配置作为设备基础能力，不通过 gateway policy 每次动态下发，避免扩大动态 patch 面。

- [ ] **Step 2: B 出口角色允许可选启用 EasyTier 原生 exit-node**

  对作为 Exit 的配置模板，允许写入：

  ```toml
  enable_exit_node = true
  proxy_forward_by_system = true
  ```

  主路径仍以 `gateway_policy` 的 nft NAT 为准；`enable_exit_node` 只作为 EasyTier 语义兼容。

- [ ] **Step 3: 不启用 manual_routes**

  镜像默认配置不得写入：

  ```toml
  routes = [...]
  ```

  原因：manual routes 会覆盖从 `proxy_cidrs` 同步来的路由，破坏 B 回 D 的自动回程。

## Task 4: 设计 Source fail-closed 防泄漏状态

**Files:**

- Modify: `vendor/EasyTier/easytier/src/gateway_policy/mod.rs`
- Modify: `vendor/EasyTier/easytier/src/gateway_policy/executor.rs`
- Modify: `vendor/EasyTier/easytier/src/gateway_policy/state.rs`
- Test: `vendor/EasyTier/easytier/src/gateway_policy/*`

- [ ] **Step 1: 区分“用户删除策略”和“隧道异常”**

  - 用户删除策略：执行完整 cleanup，A 恢复普通网络状态。
  - 策略仍 desired 但 tunnel 异常：进入 `degraded_guarded` 行为，不能让 D 流量回落到 A WAN。

- [ ] **Step 2: Source tunnel 异常时安装 guard**

  推荐 guard 策略：

  ```sh
  nft add table inet easytier_gw_guard
  nft add chain inet easytier_gw_guard forward { type filter hook forward priority -140 ; }
  nft add rule inet easytier_gw_guard forward \
    iifname br-lan \
    ip saddr 192.168.128.0/24 \
    ip daddr != 192.168.128.0/24 \
    counter drop
  ```

  作用：策略 desired 仍存在但 EasyTier 隧道异常时，D 不能借 A 本地 WAN 泄漏出网。

- [ ] **Step 3: tunnel 恢复后自动移除 guard 并重新 apply Source 策略**

  run loop 在 `degraded_guarded` 状态下继续检查：

  - `tun0` 存在
  - B tunnel IP 可达

  恢复后：

  ```sh
  nft delete table inet easytier_gw_guard
  ```

  然后重新 apply Source 策略。

- [ ] **Step 4: 用户 remove 时清理正常策略和 guard**

  `RemovePolicy` 必须同时清理：

  ```sh
  nft delete table inet easytier_gw
  nft delete table inet easytier_gw_guard
  ip rule del fwmark 0x7e table 126
  ip route flush table 126
  ```

## Task 5: Docker 集成测试补齐回程和原生能力验证

**Files:**

- Modify: `tests/integration/scripts/lib-gateway.sh`
- Modify: `tests/integration/scripts/test-gateway-forward.sh`
- Create: `tests/integration/scripts/test-gateway-native-easytier.sh`
- Create: `tests/integration/scripts/test-gateway-return-path.sh`
- Create: `tests/integration/scripts/test-gateway-fail-closed.sh`

- [ ] **Step 1: 验证 A 原生配置下发结果**

  测试 pair apply 后，A 的 config 应包含：

  ```text
  proxy_cidrs: managed_cidrs
  exit_nodes: B_tun_ip
  ```

  可通过 `ConfigRpc/GetConfig` 或 `easytier-cli` 查询。

- [ ] **Step 2: 验证 B 获得 D 子网回程路由**

  在 B 上验证：

  ```sh
  ip route show | grep '192.168.128.0/24'
  ```

  预期路由指向 EasyTier tun 接口。

- [ ] **Step 3: 验证 TCP 回程**

  D 请求测试 endpoint：

  ```sh
  curl --noproxy '*' -fsS --max-time 5 "$LAB_ENDPOINT_URL"
  ```

  同时验证 B nft forward/postrouting counters 增加。

- [ ] **Step 4: 验证 UDP 回程**

  使用 UDP echo 或 iperf3：

  ```sh
  iperf3 -s -u
  iperf3 -c "$LAB_ENDPOINT_HOST" -u -b 1M -t 5
  ```

  预期 D 能收到 UDP 测试响应，B tunnel/WAN 计数增加。

- [ ] **Step 5: 验证 D -> A 本机不被捕获**

  D 执行：

  ```sh
  ping -c2 "$A_LAN_IP"
  curl --max-time 3 "http://$A_LAN_IP:$A_TEST_PORT"
  ```

  预期 A table 126 和 B NAT counters 不增长。

- [ ] **Step 6: 验证 A/B/C 控制面不被捕获**

  A/B 执行：

  ```sh
  ping -c2 "$C_UNDERLAY_IP"
  ```

  预期 C 可达，Device List 保持在线。

- [ ] **Step 7: 验证 fail-closed**

  策略启用后临时断开 A 到 B tunnel：

  ```sh
  ip link set tun0 down
  ```

  D 再访问外部 endpoint：

  ```sh
  curl --noproxy '*' --max-time 5 "$LAB_ENDPOINT_URL"
  ```

  预期失败，并且 A WAN 没有 D 子网流量 NAT 出去。

## Task 6: UTM 回程抓包验收补齐

**Files:**

- Modify: `docs/plans/016-utm-4node-lab-setup.zh.md`
- Create: `tests/utm/check-return-path.sh`
- Create: `tests/utm/check-native-easytier-config.sh`
- Create: `tests/utm/check-fail-closed.sh`

- [ ] **Step 1: UTM pair apply 前置检查**

  检查：

  ```sh
  A: ip addr show tun0
  B: ip addr show tun0
  A: ping -c3 "$B_TUN_IP"
  B: ping -c3 "$A_TUN_IP"
  C: curl -fsS http://127.0.0.1:11211/
  ```

- [ ] **Step 2: 验证 EasyTier 原生配置**

  A 上应能看到 `proxy_cidrs` 包含 D 子网：

  ```sh
  easytier-cli route
  ```

  B 上应能看到到 D 子网的路由：

  ```sh
  ip route show | grep "$D_CIDR"
  ```

- [ ] **Step 3: 抓去程**

  D 发起请求：

  ```sh
  curl -4 --max-time 10 https://api.ipify.org
  ```

  A 抓包：

  ```sh
  tcpdump -ni br-lan host "$D_IP"
  tcpdump -ni tun0 "host $D_IP or net $D_CIDR"
  ```

  B 抓包：

  ```sh
  tcpdump -ni tun0 net "$D_CIDR"
  tcpdump -ni "$B_WAN_IFACE" host "$TEST_PUBLIC_IP"
  ```

- [ ] **Step 4: 抓回程**

  B 验证 conntrack：

  ```sh
  conntrack -L | grep "$D_IP"
  ```

  A 验证回包从 tun0 回到 br-lan：

  ```sh
  tcpdump -ni tun0 net "$D_CIDR"
  tcpdump -ni br-lan host "$D_IP"
  ```

  预期同一连接能观察到：

  ```text
  B WAN reply -> B tun0 -> A tun0 -> A br-lan -> D
  ```

- [ ] **Step 5: 验证出口 IP**

  D 执行：

  ```sh
  curl -4 https://api.ipify.org
  curl -4 https://ifconfig.me
  ```

  预期返回 B 宽带出口 IP，不是 A 宽带出口 IP。

- [ ] **Step 6: 验证 UDP/WebSocket/MTU**

  UDP：

  ```sh
  iperf3 -c "$LAB_ENDPOINT_HOST" -u -b 1M -t 10
  ```

  WebSocket：

  ```sh
  websocat -t "ws://$LAB_ENDPOINT_HOST/echo"
  ```

  MTU：

  ```sh
  tracepath "$LAB_ENDPOINT_HOST"
  ping -M do -s 1200 -c 3 "$LAB_ENDPOINT_HOST"
  ping -M do -s 1360 -c 3 "$LAB_ENDPOINT_HOST"
  ```

  预期：

  - UDP 不出现持续单向丢包。
  - WebSocket 长连接能建立并持续收发。
  - MTU 异常时能确定建议值，优先记录 1280/1360/1380 三档结果。

## Task 7: 文档和验收口径更新

**Files:**

- Modify: `AGENTS.md`
- Modify: `README.md`
- Modify: `docs/plans/016-utm-4node-lab-setup.zh.md`
- Modify: `docs/plans/017-gateway-policy-minimal-downlink.zh.md`

- [ ] **Step 1: 更新 AGENTS 架构口径**

  明确最终组合：

  ```text
  proxy_cidrs: 回程路由传播
  exit_nodes: EasyTier 内部出口 peer 选择
  gateway_policy Source: D 子网流量选择和 fail-closed
  gateway_policy Exit: B 出口 NAT
  ```

- [ ] **Step 2: 更新 README 产品口径**

  README 中不再只描述“C 下发 nft/route”，应补充：

  ```text
  C 同时下发 EasyTier 原生网络配置和 gateway_policy。
  ```

- [ ] **Step 3: 更新 016 UTM 验收**

  016 需要新增：

  - 回程抓包章节
  - `proxy_cidrs` / `exit_nodes` 验证章节
  - fail-closed 防泄漏章节
  - UDP/WebSocket/MTU 验收章节

## 验证命令

实现完成后至少执行：

```sh
cargo test -p easytier gateway_policy --features gateway-policy --no-default-features
cargo check -p easytier --features gateway-policy
cargo check -p easytier-web
bash -n tests/utm/check-return-path.sh tests/utm/check-native-easytier-config.sh tests/utm/check-fail-closed.sh
make test-integration
```

UTM 验收执行：

```sh
tests/utm/check-native-easytier-config.sh
tests/utm/check-return-path.sh
tests/utm/check-fail-closed.sh
```

## 验收标准

- A pair apply 后，A 的 EasyTier 配置包含 D 子网 `proxy_cidrs` 和 B tunnel IP `exit_nodes`。
- B 能通过 EasyTier 同步路由知道 D 子网在 A 后面。
- D 的 TCP/UDP/WebSocket 流量经 A 进入 EasyTier，并从 B 出口发出。
- B 的回包能经 EasyTier 回 A，再回到 D。
- D -> A 本机、A/B -> C 控制面流量不被策略捕获。
- 策略 desired 状态下 tunnel 异常时，D 流量 fail-closed，不回落到 A WAN 泄漏。
- 用户主动删除策略后，gateway policy 规则、guard 规则、A 的 `proxy_cidrs` 和 `exit_nodes` 均被清理。
- 不使用 `manual_routes` 作为主路径。
