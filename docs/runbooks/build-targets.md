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

SDK preparation:

```sh
make fetch-nanopi-r3s-sdk
. dist/nanopi-r3s/sdk-env.sh
```

Build command:

```sh
make build TARGET=nanopi-r3s
```

The SDK build must run on Linux `x86_64`. The official OpenWrt SDK archive for this target is `Linux-x86_64`, so it is not suitable for direct execution on macOS or the UTM Ubuntu `aarch64` VM.

Expected profile:

```text
target=rockchip
subtarget=armv8
profile=friendlyarm_nanopi-r3s
```

Expected package artifact:

```text
dist/nanopi-r3s/easytier-agent_*.ipk
```

On macOS, the simplest one-command path is Docker Desktop with `linux/amd64` emulation:

```sh
make build-nanopi-r3s-docker
```

This runs the SDK workflow inside a Debian `linux/amd64` container and writes the same `dist/nanopi-r3s/easytier-agent_*.ipk` artifact.
