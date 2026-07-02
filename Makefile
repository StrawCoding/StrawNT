.PHONY: help preflight clone-ubuntu-base swap-kernel build-iso validate-rootfs test-phase0

REPO_ROOT := $(abspath .)
SCRIPTS   := os-image/scripts
VERSION   ?= 2.0.0-reboot

help:
	@echo "StrawWU $(VERSION) — Ubuntu clone reboot"
	@echo ""
	@echo "Targets:"
	@echo "  preflight           Static checks (run before anything else)"
	@echo "  clone-ubuntu-base   Extract Ubuntu noble live rootfs (needs root)"
	@echo "  swap-kernel         Replace kernel in cloned rootfs (needs root)"
	@echo "  build-iso           Clone + kernel swap + pack (needs root)"
	@echo "  validate-rootfs     Verify cloned rootfs has ubuntu calamares"
	@echo "  test-phase0         Phase 0 acceptance"

preflight:
	bash tests/preflight/test-ubuntu-clone.sh

clone-ubuntu-base: preflight
	sudo bash $(SCRIPTS)/clone-ubuntu-base.sh

swap-kernel:
	sudo bash $(SCRIPTS)/swap-kernel.sh

build-iso: preflight
	sudo bash $(SCRIPTS)/build-iso.sh

validate-rootfs:
	@test -d os-image/work/rootfs/etc || (echo "run make clone-ubuntu-base first" && exit 1)
	@test -f os-image/work/rootfs/usr/bin/calamares
	@test -f os-image/work/rootfs/usr/share/calamares/settings-ubuntu.conf
	@echo "validate-rootfs: OK"

test-phase0: preflight
	@test -f docs/architecture.md
	@test -f docs/phase-roadmap.md
	@test -f README.md
	@echo "test-phase0: PASS"
