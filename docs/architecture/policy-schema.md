# Device Policy Schema Draft

## exit_via_peer

```json
{
  "policy_id": "a-exit-via-b",
  "version": 1,
  "machine_id": "node-a",
  "type": "exit_via_peer",
  "enabled": true,
  "network_instance_id": "00000000-0000-0000-0000-000000000000",
  "exit_peer_ipv4": "10.126.126.3",
  "protect_underlay_routes": ["172.30.40.10/32"],
  "dns_mode": "keep_local",
  "healthcheck": {
    "targets": ["1.1.1.1", "223.5.5.5"],
    "timeout_seconds": 10
  },
  "rollback": {
    "enabled": true,
    "max_fail_seconds": 30
  }
}
```

## Runtime Report

```json
{
  "machine_id": "node-a",
  "agent_version": "0.1.0",
  "easytier_version": "2.6.x",
  "policy_version": 1,
  "policy_status": "applied",
  "interfaces": [
    {
      "name": "easytier0",
      "ipv4": "10.126.126.2",
      "up": true
    }
  ],
  "routes": {
    "default": "10.126.126.3 dev easytier0",
    "protected_underlay": ["172.30.40.10/32 dev eth0"]
  },
  "firewall": {
    "backend": "nftables",
    "forwarding_enabled": true,
    "nat_enabled": false
  },
  "health": {
    "control_plane": "ok",
    "exit_reachable": "ok",
    "internet_via_exit": "ok"
  },
  "last_error": null
}
```

