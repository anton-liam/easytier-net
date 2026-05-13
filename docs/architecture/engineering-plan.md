# EasyTier Net Engineering Plan

## Goal

Build a productized EasyTier management layer that can centrally configure mesh networking, assign exit-node policies, observe node runtime state, and deploy repeatably to OpenWrt/iStoreOS devices such as NanoPi R3S.

## Repository Strategy

This repository is the orchestration layer. It stores scripts, target profiles, lab topology, runbooks, and CI entry points.

Forks:

- `EasyTier/EasyTier`: Web console, policy API, runtime reports, and optional `easytier-agent` crate.
- `EasyTier/luci-app-easytier`: OpenWrt package integration and LuCI UX.

## Product Boundary

Do not modify EasyTier data-plane internals for the first production milestone.

Modify or extend:

- EasyTier Web console backend/frontend.
- Web/client control-plane protocol if needed.
- Node Agent for OS route/firewall/NAT execution.
- LuCI package for installation, local configuration, and service status.

## Node Agent Responsibilities

- Register with the Web console.
- Pull declarative device policy.
- Validate current node state.
- Apply route/firewall/NAT changes.
- Manage health checks and rollback.
- Report runtime telemetry.

The Agent must not execute arbitrary commands received from the Web console. It consumes typed policies only.

## First Supported Policy

`exit_via_peer`: send node A's default egress traffic through node B.

Required behavior:

- Protect Web/control-plane underlay routes.
- Verify EasyTier interface and peer reachability.
- Apply default route on A through B's EasyTier IP.
- Enable forwarding/NAT on B.
- Report success/failure with policy version.
- Roll back on health-check failure.

## Test Layers

1. Unit tests: policy validation, planning, dry-run applier.
2. containerlab: three-node topology for daily E2E tests.
3. QEMU OpenWrt: package/procd/uci/firewall compatibility.
4. UTM/iStoreOS: milestone acceptance.
5. Physical NanoPi R3S: release acceptance.

