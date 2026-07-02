.PHONY: help preflight clone-ubuntu-base swap-kernel build-iso validate-rootfs boot-test-iso test-phase0

REPO_ROOT := $(abspath .)
SCRIPTS   := os-image/scripts
VERSION   ?= 0.3.0-cleanroom
export STRAWWU_VERSION := $(VERSION)

help:
	@echo "StrawWU $(VERSION) — Ubuntu clone cleanroom"
	@echo ""
	@echo "Targets:"
	@echo "  preflight           Static checks (run before anything else)"
	@echo "  clone-ubuntu-base   Extract Ubuntu noble live rootfs (needs root)"
	@echo "  swap-kernel         Replace kernel in cloned rootfs (needs root)"
	@echo "  build-iso           Clone + kernel swap + xorriso repack (needs root)"
	@echo "  validate-rootfs     Verify cloned rootfs has ubuntu calamares"
	@echo "  boot-test-iso       QEMU BIOS+UEFI boot test (needs built ISO)"
	@echo "  test-phase0         Phase 0 acceptance"

preflight:
	bash tests/preflight/test-ubuntu-clone.sh

clone-ubuntu-base: preflight
	sudo bash $(SCRIPTS)/clone-ubuntu-base.sh

swap-kernel:
	sudo bash $(SCRIPTS)/swap-kernel.sh

build-iso: preflight
	sudo STRAWWU_VERSION=$(VERSION) bash $(SCRIPTS)/build-iso.sh

validate-rootfs:
	@test -d os-image/work/rootfs/etc || (echo "run make clone-ubuntu-base first" && exit 1)
	@test -f os-image/work/rootfs/usr/bin/calamares
	@test -f os-image/work/rootfs/etc/calamares/modules/mount.conf
	@test -d os-image/work/rootfs/usr/share/doc/calamares-settings-ubuntu-common || (echo "missing calamares-settings-ubuntu-common" && exit 1)
	@echo "validate-rootfs: OK"

boot-test-iso:
	bash tests/boot/run.sh

test-phase0: preflight
	@test -f docs/architecture.md
	@test -f docs/phase-roadmap.md
	@test -f docs/versioning.md
	@test -f VERSION
	@test -f README.md
	@echo "test-phase0: PASS"
