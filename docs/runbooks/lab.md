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

