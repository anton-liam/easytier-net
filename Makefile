.PHONY: build-all build-server build-openwrt build-docker-test image-r3s image-rpi4 image-rpi5 \
       test-integration clean

DIST := dist
VENDOR := vendor/EasyTier

# ── Build all ──
build-all: build-server build-openwrt image-r3s image-rpi4 image-rpi5

# ── C server binaries (x86_64 linux musl) ──
build-server:
	@bash scripts/build-server.sh

# ── A/B device binaries (aarch64 linux musl) ──
build-openwrt:
	@bash scripts/build-openwrt.sh

# ── Docker integration binaries (arm64 core + web) ──
build-docker-test:
	@bash scripts/build-docker-test.sh

# ── OpenWrt images ──
image-r3s:
	@bash scripts/build-image.sh r3s

image-rpi4:
	@bash scripts/build-image.sh rpi4

image-rpi5:
	@bash scripts/build-image.sh rpi5

# ── Integration tests ──
test-integration:
	@$(MAKE) build-docker-test
	@cd tests/integration && $(MAKE) up && $(MAKE) test; rc=$$?; $(MAKE) down; exit $$rc

# ── Clean ──
clean:
	rm -rf $(DIST)
