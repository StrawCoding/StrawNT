.PHONY: help preflight preflight-iso-before-boot preflight-dev-vm clone-ubuntu-base swap-kernel \
	build-iso dev-iso release-iso repack-iso validate-rootfs boot-test-iso boot-test-dev-iso \
	boot-test-release-iso dev-vm-start dev-vm-sync dev-vm-test dev-vm-cycle dev-vm-rollback \
	test-phase0 test-phase2 kernel-build validate-calamares-preflight validate-partition-probe \
	test-install-e2e test-wincompat

REPO_ROOT := $(abspath .)
SCRIPTS   := os-image/scripts
VERSION   ?= 0.3.0-cleanroom
export STRAWWU_VERSION := $(VERSION)

help:
	@echo "StrawWU $(VERSION) — Ubuntu clone cleanroom"
	@echo ""
	@echo "ISO modes (see docs/iso-modes.md):"
	@echo "  dev-vm          No ISO — rsync into installed VM (fastest daily dev)"
	@echo "  dev-iso         Fast zstd squashfs — live/casper/desktop checks"
	@echo "  release-iso     Slow xz squashfs — tags, Release, full boot-test"
	@echo ""
	@echo "Targets:"
	@echo "  preflight                 Static checks (run before anything else)"
	@echo "  clone-ubuntu-base         Extract Ubuntu noble live rootfs (needs root)"
	@echo "  swap-kernel               Replace kernel in cloned rootfs (needs root)"
	@echo "  dev-iso                   Build ISO (dev-iso mode, zstd -l 3)"
	@echo "  release-iso               Build ISO (release-iso mode, xz)"
	@echo "  build-iso                 Alias for release-iso (pipeline default)"
	@echo "  repack-iso                Fast initrd/casper refresh only (no boot-test pipeline)"
	@echo "  preflight-iso-before-boot ISO integrity gate (before boot-test)"
	@echo "  preflight-dev-vm          dev-vm backend readiness"
	@echo "  boot-test-dev-iso         preflight + BIOS-only boot-test (dev-iso)"
	@echo "  boot-test-release-iso     preflight + BIOS+UEFI boot-test (release-iso)"
	@echo "  boot-test-iso             Alias for boot-test-release-iso"
	@echo "  dev-vm-start/sync/test    VM snapshot workflow (no ISO)"
	@echo "  kernel-build              Build linux-image-strawwu .deb (Phase 2, long)"
	@echo "  test-phase0 / test-phase2 Phase acceptance"
	@echo "  validate-calamares-preflight  Calamares static gate (before E2E)"
	@echo "  validate-partition-probe      QEMU partition backend probe"
	@echo "  test-install-e2e              Calamares install E2E (preflight→probe→install)"

preflight:
	bash tests/preflight/test-ubuntu-clone.sh
	bash tests/preflight/test-branding.sh

preflight-dev-vm:
	bash tests/preflight/test-dev-vm-ready.sh

preflight-iso-before-boot:
	STRAWWU_ISO_MODE=$${STRAWWU_ISO_MODE:-release-iso} bash tests/preflight/test-iso-before-boot.sh

clone-ubuntu-base: preflight
	sudo bash $(SCRIPTS)/clone-ubuntu-base.sh

kernel-build:
	$(MAKE) -C kernel build

KERNEL_DEB ?= $(shell ls kernel/output/linux-image-strawwu_*.deb 2>/dev/null | head -1)

swap-kernel:
	sudo STRAWWU_KERNEL_DEB="$${STRAWWU_KERNEL_DEB:-$(KERNEL_DEB)}" bash $(SCRIPTS)/swap-kernel.sh

# release-iso is the default for pipelines and formal verification.
build-iso: release-iso

dev-iso: preflight
	sudo STRAWWU_ISO_MODE=dev-iso STRAWWU_VERSION=$(VERSION) \
		STRAWWU_KERNEL_DEB="$${STRAWWU_KERNEL_DEB:-$(KERNEL_DEB)}" \
		STRAWWU_SKIP_SQUASHFS=0 bash $(SCRIPTS)/build-iso.sh

release-iso: preflight
	sudo STRAWWU_ISO_MODE=release-iso STRAWWU_VERSION=$(VERSION) \
		STRAWWU_KERNEL_DEB="$${STRAWWU_KERNEL_DEB:-$(KERNEL_DEB)}" \
		STRAWWU_SKIP_SQUASHFS=0 bash $(SCRIPTS)/build-iso.sh

repack-iso: preflight
	@test -f os-image/work/.clone-ubuntu-base-ok || (echo "run make clone-ubuntu-base first" && exit 1)
	sudo STRAWWU_VERSION=$(VERSION) STRAWWU_KERNEL_DEB="$${STRAWWU_KERNEL_DEB:-$(KERNEL_DEB)}" STRAWWU_SKIP_SQUASHFS=1 bash $(SCRIPTS)/build-iso.sh

validate-rootfs:
	@test -d os-image/work/rootfs/etc || (echo "run make clone-ubuntu-base first" && exit 1)
	@test -f os-image/work/rootfs/usr/bin/calamares
	@test -f os-image/work/rootfs/etc/calamares/modules/mount.conf
	@test -d os-image/work/rootfs/usr/share/doc/calamares-settings-ubuntu-common || (echo "missing calamares-settings-ubuntu-common" >&2; exit 1)
	@echo "validate-rootfs: OK"

boot-test-iso: boot-test-release-iso

boot-test-dev-iso: preflight-iso-before-boot
	STRAWWU_ISO_MODE=dev-iso STRAWWU_BOOT_TEST_MODES=bios bash tests/boot/run.sh

boot-test-release-iso: preflight-iso-before-boot
	STRAWWU_ISO_MODE=release-iso STRAWWU_BOOT_TEST_MODES=bios,uefi bash tests/boot/run.sh

dev-vm-start:
	bash tests/dev-vm/start.sh

dev-vm-sync: preflight-dev-vm
	bash tests/dev-vm/sync-to-vm.sh

dev-vm-test: preflight-dev-vm
	bash tests/dev-vm/run-test.sh

dev-vm-cycle: preflight-dev-vm
	bash tests/dev-vm/run-cycle.sh

dev-vm-rollback:
	bash tests/dev-vm/rollback-snapshot.sh

test-phase2:
	bash tests/kernel/test-phase2.sh

test-phase0: preflight
	@test -f docs/architecture.md
	@test -f docs/phase-roadmap.md
	@test -f docs/versioning.md
	@test -f VERSION
	@test -f README.md
	@echo "test-phase0: PASS"

validate-calamares-preflight:
	bash tests/install-e2e/validate-calamares-preflight.sh

validate-partition-probe: validate-calamares-preflight
	bash tests/install-e2e/partition-probe.sh

test-install-e2e: validate-calamares-preflight validate-partition-probe
	bash tests/install-e2e/run.sh

test-wincompat:
	@echo "=== Phase 6: Windows Compatibility Layer ==="
	cd components && cargo test --workspace
	bash components/tests/wincompat/generate-compat-matrix.sh
