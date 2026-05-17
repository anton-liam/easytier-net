# Lab Runbook

## Recommended Daily Environment

Use one Ubuntu Linux VM with:

- Docker
- containerlab
- Rust toolchain
- OpenWrt ImageBuilder dependencies, when building device packages

Run:

```sh
make bootstrap
make vendor
make lab-up
make lab-test
make lab-down
```

## Why Not Three UTM VMs For Daily Tests

The three-VM iStoreOS/Ubuntu lab is valuable for acceptance, but it is slow for iterative development. containerlab gives fast topology setup, route/firewall verification, and failure injection.

## Acceptance Environment

Keep the existing UTM machines:

- `istoreos1`: client node A.
- `istoreos2`: exit node B.
- `istore ubuntu`: Web console, relay, config server.

Use this only after containerlab and QEMU OpenWrt checks pass.

## Deploy Web Console To UTM Ubuntu

The Ubuntu VM is Linux `aarch64`, so do not copy a macOS-built binary to it. Build `easytier-web` on the Ubuntu VM and deploy that ELF binary:

```sh
make utm-deploy-web
```

Defaults:

```text
UTM_WEB_HOST=192.168.64.4
UTM_WEB_USER=anton
UTM_REMOTE_DIR=/tmp/EasyTier
UTM_API_HOST=http://192.168.64.4:11211
```

The deploy script streams the EasyTier source tree with `COPYFILE_DISABLE=1` and excludes `._*`, `.DS_Store`, `target`, `node_modules`, and `.git`. This prevents macOS AppleDouble metadata files from being copied into `easytier/locales`, which can break `rust_i18n` code generation during the Linux build.

## UTM Native Control Plane Acceptance

Use this sequence before testing gateway policies:

```sh
easytier-core -w udp://192.168.64.4:22020/admin \
  --machine-id aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa \
  --hostname A-webclient \
  --config-dir /tmp/easytier-webclient

easytier-core -w udp://192.168.64.4:22020/admin \
  --machine-id bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb \
  --hostname B-webclient \
  --config-dir /tmp/easytier-webclient

easytier-core -w udp://192.168.64.4:22020/admin \
  --machine-id cccccccc-cccc-cccc-cccc-cccccccccccc \
  --hostname C-webclient \
  --config-dir /tmp/easytier-webclient-c
```

Expected Web checks:

```sh
curl --noproxy '*' -fsS -b /tmp/et.cookie \
  http://192.168.64.4:11211/api/v1/summary

curl --noproxy '*' -fsS -b /tmp/et.cookie \
  http://192.168.64.4:11211/api/v1/machines
```

Acceptance:

- `device_count = 3`.
- `/api/v1/machines` contains A/B/C machine ids.
- A/B/C all report the same running network instance after Web config is applied.
- A/B/C EasyTier IPv4 ping succeeds in both directions.

If a Web-managed EasyTier instance uses a new TUN interface such as `easytierw0`, pass that interface to Agent with `--easytier-iface easytierw0`. The Agent default remains `easytier0` for compatibility with simple local instances.

For lab-only validation, temporary nft rules can prove the network path. Product implementation must use Agent backend rules and rollback, not manual shell changes.

## Agent Binary Compatibility

Do not copy a glibc `aarch64-unknown-linux-gnu` Agent binary from Ubuntu directly to iStoreOS. The R3S/iStoreOS VM uses musl and only provides `/lib/ld-musl-aarch64.so.1`.

Valid paths:

- Build a Linux server Agent for Ubuntu or containerlab with `make build TARGET=x86_64-linux`.
- Build an R3S/iStoreOS Agent with an OpenWrt/iStoreOS SDK by setting `OPENWRT_SDK_DIR` and running `make build TARGET=nanopi-r3s`.

`make build TARGET=nanopi-r3s` must fail with a clear message when `OPENWRT_SDK_DIR` is missing. This avoids producing a manifest that looks like a deployable device build.

`OPENWRT_SDK_DIR` must point to an extracted SDK that contains:

```text
include/package.mk
scripts/feeds
staging_dir/toolchain-*
```

Do not point `OPENWRT_SDK_DIR` at ImageBuilder, a firmware image directory, or a plain OpenWrt source checkout without SDK staging output.

## Build R3S Agent IPK

Use a Linux OpenWrt/iStoreOS SDK that matches:

```text
OPENWRT_TARGET=rockchip
OPENWRT_SUBTARGET=armv8
OPENWRT_PROFILE=friendlyarm_nanopi-r3s
```

On a Linux `x86_64` builder, fetch the default OpenWrt SDK:

```sh
make fetch-nanopi-r3s-sdk
. dist/nanopi-r3s/sdk-env.sh
```

On macOS with Docker Desktop running, use the Docker builder:

```sh
make build-nanopi-r3s-docker
```

The default fetch target uses OpenWrt `24.10.5`:

```text
https://downloads.openwrt.org/releases/24.10.5/targets/rockchip/armv8/
```

Run from this repository:

```sh
OPENWRT_SDK_DIR=/path/to/openwrt-sdk \
EASYTIER_DIR=/path/to/EasyTier \
make build TARGET=nanopi-r3s
```

The SDK build must run on Linux `x86_64`. Do not run the SDK build directly on macOS or the UTM Ubuntu `aarch64` VM; use a Linux `x86_64` VM, container, or CI runner.

The build stages an SDK package at:

```text
$OPENWRT_SDK_DIR/package/easytier-agent
```

Expected output:

```text
dist/nanopi-r3s/easytier-agent_*.ipk
dist/nanopi-r3s/build-manifest.txt
```

Install check on iStoreOS/R3S:

```sh
scp dist/nanopi-r3s/easytier-agent_*.ipk root@192.168.64.2:/tmp/
ssh root@192.168.64.2 'opkg install /tmp/easytier-agent_*.ipk && /usr/bin/easytier-agent --help'
```

## Run Agent On UTM iStoreOS

After the IPK is installed and the native EasyTier network instance is running, run a dry-run first:

```sh
/usr/bin/easytier-agent run-once \
  --platform open-wrt \
  --web-base-url http://192.168.64.4:11211 \
  --user-id 2 \
  --machine-id aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa \
  --internal-auth-token easytier-lab-internal-token \
  --easytier-ipv4 10.77.77.2 \
  --easytier-iface easytierw0
```

If the dry-run plan protects `192.168.64.4/32` before applying gateway routes and uses the actual EasyTier interface, run again with `--execute`.
