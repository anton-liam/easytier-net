# 002 Full Tunnel Exit Policy Spec

## 目标

定义 Web 控制台和 Agent 之间的 full tunnel 出口策略模型。该模型支持任意 source 节点选择任意 exit 节点，并支持实时启用、停用、切换和回滚。

## Logical Policy

Web 控制台保存 logical policy：

```json
{
  "policy_id": "full-exit-001",
  "type": "full_tunnel_exit",
  "enabled": true,
  "network_instance_id": "00000000-0000-0000-0000-000000000000",
  "source_machine_id": "node-a",
  "exit_machine_id": "node-b",
  "desired_version": 12,
  "protect_control_plane": true,
  "healthcheck": {
    "control_plane_timeout_seconds": 5,
    "exit_timeout_seconds": 10
  },
  "rollback": {
    "enabled": true,
    "max_fail_seconds": 30
  }
}
```

约束：

- 一个 source 节点同一时间只能有一个 enabled `full_tunnel_exit`。
- 一个 exit 节点可以服务多个 source 节点。
- `source_machine_id` 和 `exit_machine_id` 不能相同。
- `source_machine_id` 和 `exit_machine_id` 必须在同一 EasyTier network instance 中可达。

## Device Policy

Web 下发给 source 节点：

```json
{
  "policy_id": "full-exit-001",
  "device_policy_id": "full-exit-001/source",
  "version": 12,
  "role": "client_exit_via_peer",
  "network_instance_id": "00000000-0000-0000-0000-000000000000",
  "source_machine_id": "node-a",
  "exit_machine_id": "node-b",
  "exit_peer_ipv4": "10.126.126.3",
  "protect_control_plane": true,
  "rollback_enabled": true
}
```

Web 下发给 exit 节点：

```json
{
  "policy_id": "full-exit-001",
  "device_policy_id": "full-exit-001/exit",
  "version": 12,
  "role": "provide_exit_for_peer",
  "network_instance_id": "00000000-0000-0000-0000-000000000000",
  "source_machine_id": "node-a",
  "source_peer_ipv4": "10.126.126.2",
  "exit_machine_id": "node-b",
  "rollback_enabled": true
}
```

## Web 编排顺序

启用或切换策略时，Web 必须按顺序推进：

```text
prepare exit provider -> switch source client -> cleanup old provider
```

切换 `node-a -> node-b` 到 `node-a -> node-c`：

1. 下发 `provide_exit_for_peer` 给 `node-c`。
2. 等待 `node-c` 上报 `prepared`。
3. 下发 `client_exit_via_peer` 给 `node-a`。
4. 等待 `node-a` 上报 `active`。
5. 下发 cleanup 给 `node-b`，只清理 `node-a` 对应规则。

## Agent 状态机

Device policy 状态：

```text
pending
validating
planned
prepared
applying
verifying_control_plane
verifying_exit
active
degraded
rollbacking
rollbacked
disabled
```

source 节点进入 `active` 的条件：

- control-plane protected route 已建立。
- default route 已指向 exit peer。
- Web/control-plane healthcheck 成功。
- exit healthcheck 成功。
- runtime report 已包含 observed exit。

exit 节点进入 `prepared` 的条件：

- IPv4 forwarding 已启用。
- source peer 对应 NAT/forwarding 已存在。
- 不影响其它 source 的现有规则。
- runtime report 已包含 provider 状态。

## Control-plane Protected Routes

Agent 必须保护：

- Web API 地址。
- EasyTier config-server 地址。
- EasyTier relay/listener 地址。
- 当前策略需要访问的 DNS 服务器地址，若 Web/config-server 使用域名。

Agent 行为：

1. 解析 control-plane endpoint。
2. 记录当前 underlay route。
3. 添加 `/32` 或等价 host route。
4. 验证 control-plane 可达。
5. 才允许改 default route。

## Runtime Report

最小 report：

```json
{
  "machine_id": "node-a",
  "agent_version": "0.1.0",
  "policy": {
    "policy_id": "full-exit-001",
    "device_policy_id": "full-exit-001/source",
    "version": 12,
    "role": "client_exit_via_peer",
    "status": "active"
  },
  "network": {
    "easytier_interface": "easytier0",
    "easytier_ipv4": "10.126.126.2",
    "default_route": "via 10.126.126.3 dev easytier0",
    "protected_routes": ["192.168.64.4/32 via 192.168.64.1 dev eth0"]
  },
  "firewall": {
    "backend": "fw4-nftables",
    "forwarding_enabled": false,
    "nat_enabled": false
  },
  "health": {
    "control_plane": "ok",
    "exit": "ok"
  },
  "last_error": null
}
```

## 失败处理

如果 source 节点无法验证 control-plane：

- 禁止切换 default route。
- 上报 `degraded`。
- 保留 last known good。

如果 source 节点切换 default route 后 exit healthcheck 失败：

- 执行 rollback。
- 上报 `rollbacked`。
- Web 保留 desired policy，但 observed state 显示未生效。

如果 exit 节点 prepare 失败：

- Web 不下发 source 切换。
- logical policy 状态为 `degraded`。

