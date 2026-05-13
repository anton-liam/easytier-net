# easytier-net

Productization workspace for an EasyTier based managed mesh, exit-node policy, node telemetry, and OpenWrt/iStoreOS deployment workflow.

This repository is the orchestration repo. It keeps build targets, lab automation, product architecture, and scripts that coordinate the two upstream forks:

- `EasyTier/EasyTier` fork: Web console, control plane, policy API, runtime telemetry, and optional agent crate.
- `EasyTier/luci-app-easytier` fork: OpenWrt/iStoreOS package, LuCI entry points, and node service packaging.

## Quick Start

```sh
make bootstrap
make vendor
make lab-up
make lab-test
```

On macOS, run `make lab-*` inside a Linux VM with Docker and containerlab installed. The UTM three-VM environment should be kept for milestone acceptance, not daily development.

## Repository Layout

```text
docs/
  architecture/        Product and engineering design notes.
  runbooks/            Operator runbooks for lab, OpenWrt, and release checks.
scripts/
  bootstrap.sh         Host dependency checks.
  vendor-sync.sh       Clone or update forked upstream repositories.
  build-target.sh      Target-oriented build entry point.
targets/
  nanopi-r3s/          OpenWrt/iStoreOS target profile and package settings.
  x86_64-linux/        Linux server/agent build target.
tests/lab/
  clab.yml             One-command containerlab topology.
  images/              Lab container images.
  scripts/             E2E assertions for policy, route, NAT, telemetry.
vendor/
  EasyTier/            Fork checkout location.
  luci-app-easytier/   Fork checkout location.
```

## Build Targets

```sh
make build TARGET=x86_64-linux
make build TARGET=nanopi-r3s
```

`x86_64-linux` builds Linux server/agent artifacts for the Web console and Ubuntu relay node.

`nanopi-r3s` prepares OpenWrt package build inputs for iStoreOS/NanoPi R3S. The final firmware/package build should run in a Linux builder or CI runner.

## Lab Strategy

Daily tests use containerlab:

```text
web      EasyTier Web console + relay/config server
node-a   simulated source R3S gateway
client-a simulated managed client connected to node-a
node-b   simulated exit R3S gateway
internet-b simulated upstream network behind node-b
node-c   simulated alternate exit R3S gateway
```

Real OpenWrt/iStoreOS validation is a second layer using ImageBuilder/QEMU. UTM and physical NanoPi R3S are final acceptance environments.
