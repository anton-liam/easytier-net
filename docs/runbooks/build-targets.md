# Build Targets Runbook

## x86_64-linux

Purpose:

- Ubuntu Web console node.
- Linux relay node.
- Local development binaries.

Command:

```sh
make vendor
make build TARGET=x86_64-linux
```

Artifacts:

```text
dist/x86_64-linux/
```

## nanopi-r3s

Purpose:

- OpenWrt/iStoreOS package or firmware build inputs for NanoPi R3S.

Command:

```sh
make build TARGET=nanopi-r3s
```

The first implementation writes a target manifest. The next engineering step is wiring this target to a selected OpenWrt or iStoreOS ImageBuilder release.

Expected profile:

```text
target=rockchip
subtarget=armv8
profile=friendlyarm_nanopi-r3s
```

