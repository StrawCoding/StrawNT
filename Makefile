.PHONY: help preflight preflight-iso-before-boot preflight-dev-vm clone-ubuntu-base swap-kernel \
	build-iso dev-iso release-iso repack-iso validate-rootfs boot-test-iso boot-test-dev-iso \
	boot-test-release-iso dev-vm-start dev-vm-sync dev-vm-test dev-vm-cycle dev-vm-rollback \
	test-phase0 test-phase2 kernel-build validate-calamares-preflight validate-partition-probe \
	test-install-e2e test-wincompat test-wincompat-os test-strawwu-shell test-hub test-hub-settings test-apps-page test-wave0-baseline test-wave-all-pass test-purge-baseline test-flatpak test-nosnap test-init-tools test-bug-reporter test-calamares-settings test-app-registry test-security-baseline test-observability test-legal-trademark test-desktop-stack test-live-install-ux test-update-notifier test-target-setup purge-ubuntu-telemetry \
	install-flatpak-setup install-bug-reporter install-calamares-settings install-update-notifier install-target-setup install-wincompat nosnap-harden build-debs bump-version check-version-bump

REPO_ROOT := $(abspath .)
SCRIPTS   := os-image/scripts
VERSION   ?= $(shell cat VERSION 2>/dev/null || echo 0.4.0.0)
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
	@echo "  test-wave0-baseline           Wave 0 preflight baselines (12 scripts + JSON)"
	@echo "  test-wave-all-pass            Verify all 47 wave stages PASS (MVP closeout gate)"
	@echo "  test-purge-baseline           W1-B1 telemetry/pro/snap purge verification"
	@echo "  test-flatpak                  W1-F1 flatpak + flathub remote verification"
	@echo "  test-nosnap                   W1-F2 snapd absent + meta mask verification"
	@echo "  test-init-tools               W2-N1 strawwu-initd shared setup state.json CLI"
	@echo "  test-bug-reporter             W2-B2 strawwu-bug-reporter CLI/GTK/consent verification"
	@echo "  test-calamares-settings       W2-I1 strawwu-calamares-settings deb (replaces ubuntu-common)"
	@echo "  test-app-registry             W2-R1 strawwu-app-registry crate + CLI + schema"
	@echo "  test-security-baseline        W2-trust SEC2 bug-reporter privacy/consent + telemetry purge"
	@echo "  test-observability            W2-trust OBS1 bug bundle schema + CLI"
	@echo "  test-legal-trademark          W2-trust LEG2 privacy/EULA draft + trademark scan"
	@echo "  test-desktop-stack            W3-D1 strawwu-session + strawwu-desktop meta"
	@echo "  test-live-install-ux          W3-I2 strawwu-install.desktop + finished copy"
	@echo "  test-update-notifier          W3-B3 strawwu-update-notifier (replaces update-notifier)"
	@echo "  test-target-setup             W3-N2 strawwu-target-setup Calamares chroot hook"
	@echo "  test-wincompat-os             W3-W0 strawwu-wincompat CLI in rootfs (strawwu status)"
	@echo "  test-strawwu-shell            W4-D2 strawwu-shell fork profile + built-in dock"
	@echo "  test-hub-settings             W4-D3 Hub settings center preflight"
	@echo "  test-apps-page                W4-R2 Hub Apps page (App Registry UI)"
	@echo "  purge-ubuntu-telemetry        chroot purge apport/whoopsie/ubuntu-pro/snapd (needs root)"
	@echo "  install-flatpak-setup         chroot install flatpak + strawwu-flatpak-setup (needs root)"
	@echo "  install-bug-reporter          chroot install strawwu-bug-reporter (needs root)"
	@echo "  install-calamares-settings    chroot install strawwu-calamares-settings (needs root)"
	@echo "  install-update-notifier       chroot install strawwu-update-notifier (needs root)"
	@echo "  install-target-setup          chroot install strawwu-target-setup + desktop stack (needs root)"
	@echo "  install-wincompat             chroot install strawwu-wincompat /usr/bin/strawwu (needs root)"
	@echo "  nosnap-harden                 chroot mask snapd Recommends + /snap stub (needs root)"

preflight:
	bash tests/preflight/test-ubuntu-clone.sh
	bash tests/preflight/test-branding.sh
	bash tests/preflight/test-purge-baseline.sh
	bash tests/preflight/test-flatpak.sh
	bash tests/preflight/test-nosnap.sh
	bash tests/preflight/test-initrd-overlays.sh
	bash tests/preflight/test-init-tools.sh
	bash tests/preflight/test-bug-reporter.sh
	bash tests/preflight/test-calamares-settings.sh
	bash tests/preflight/test-app-registry.sh
	bash tests/preflight/test-security-baseline.sh
	bash tests/preflight/test-observability.sh
	bash tests/preflight/test-legal-trademark.sh
	bash tests/preflight/test-desktop-stack.sh
	bash tests/preflight/test-live-install-ux.sh
	bash tests/preflight/test-update-notifier.sh
	bash tests/preflight/test-target-setup.sh
	bash tests/preflight/test-wincompat-os.sh
	bash tests/preflight/test-strawwu-shell.sh
	bash tests/preflight/test-hub-settings.sh
	bash tests/preflight/test-apps-page.sh

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

dev-iso-e2e: preflight
	sudo STRAWWU_ISO_MODE=dev-iso STRAWWU_ENABLE_E2E=1 STRAWWU_FORCE_X11=1 \
		STRAWWU_VERSION=$(VERSION) \
		STRAWWU_KERNEL_DEB="$${STRAWWU_KERNEL_DEB:-$(KERNEL_DEB)}" \
		STRAWWU_SKIP_SQUASHFS=0 bash $(SCRIPTS)/build-iso.sh

release-iso: preflight
	sudo STRAWWU_ISO_MODE=release-iso STRAWWU_VERSION=$(VERSION) \
		STRAWWU_KERNEL_DEB="$${STRAWWU_KERNEL_DEB:-$(KERNEL_DEB)}" \
		STRAWWU_SKIP_SQUASHFS=0 bash $(SCRIPTS)/build-iso.sh

repack-iso: preflight
	@test -f os-image/work/.clone-ubuntu-base-ok || (echo "run make clone-ubuntu-base first" && exit 1)
	sudo STRAWWU_ISO_MODE=dev-iso STRAWWU_VERSION=$(VERSION) STRAWWU_KERNEL_DEB="$${STRAWWU_KERNEL_DEB:-$(KERNEL_DEB)}" STRAWWU_SKIP_SQUASHFS=1 bash $(SCRIPTS)/build-iso.sh

validate-rootfs:
	@test -d os-image/work/rootfs/etc || (echo "run make clone-ubuntu-base first" && exit 1)
	@test -f os-image/work/rootfs/usr/bin/calamares
	@test -f os-image/work/rootfs/etc/calamares/modules/mount.conf
	@test -d os-image/work/rootfs/usr/share/doc/strawwu-calamares-settings || (echo "missing strawwu-calamares-settings" >&2; exit 1)
	@echo "validate-rootfs: OK"

boot-test-iso: boot-test-release-iso

boot-test-dev-iso:
	STRAWWU_ISO_MODE=dev-iso bash tests/preflight/test-iso-before-boot.sh
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

bump-version:
	bash scripts/bump-version.sh $(BUMP_MODE)

check-version-bump:
	bash scripts/check-version-bump.sh

validate-calamares-preflight:
	bash tests/install-e2e/validate-calamares-preflight.sh

validate-partition-probe: validate-calamares-preflight dev-iso-e2e
	bash tests/install-e2e/partition-probe.sh

test-install-e2e: validate-calamares-preflight validate-partition-probe
	bash tests/install-e2e/run.sh

test-wincompat:
	@echo "=== Phase 6: Windows Compatibility Layer ==="
	cd components && cargo test --workspace
	bash components/tests/wincompat/generate-compat-matrix.sh

test-wave0-baseline:
	bash tests/preflight/test-wave0-baseline.sh

test-wave-all-pass:
	bash tests/preflight/test-wave-all-pass.sh

test-purge-baseline:
	bash tests/preflight/test-purge-baseline.sh

test-flatpak:
	bash tests/preflight/test-flatpak.sh

test-nosnap:
	bash tests/preflight/test-nosnap.sh

test-initrd-overlays:
	bash tests/preflight/test-initrd-overlays.sh

test-init-tools:
	bash tests/preflight/test-init-tools.sh

test-bug-reporter:
	bash tests/preflight/test-bug-reporter.sh

test-calamares-settings:
	bash tests/preflight/test-calamares-settings.sh

test-app-registry:
	bash tests/preflight/test-app-registry.sh

test-security-baseline:
	bash tests/preflight/test-security-baseline.sh

test-observability:
	bash tests/preflight/test-observability.sh

test-legal-trademark:
	bash tests/preflight/test-legal-trademark.sh

test-desktop-stack:
	bash tests/preflight/test-desktop-stack.sh

test-live-install-ux:
	bash tests/preflight/test-live-install-ux.sh

test-update-notifier:
	bash tests/preflight/test-update-notifier.sh

test-target-setup:
	bash tests/preflight/test-target-setup.sh

test-wincompat-os:
	bash tests/preflight/test-wincompat-os.sh

test-strawwu-shell:
	bash tests/preflight/test-strawwu-shell.sh

test-hub:
	$(MAKE) -C components test-hub

test-hub-settings:
	bash tests/preflight/test-hub-settings.sh

test-apps-page:
	bash tests/preflight/test-apps-page.sh

install-calamares-settings:
	sudo bash $(SCRIPTS)/chroot-install-calamares-settings.sh

install-bug-reporter:
	sudo bash $(SCRIPTS)/chroot-install-bug-reporter.sh

install-update-notifier:
	sudo bash $(SCRIPTS)/chroot-install-update-notifier.sh

install-target-setup:
	sudo bash $(SCRIPTS)/chroot-install-target-setup.sh

install-wincompat:
	sudo bash $(SCRIPTS)/chroot-install-wincompat.sh

nosnap-harden:
	sudo bash $(SCRIPTS)/chroot-nosnap-harden.sh

install-flatpak-setup:
	sudo bash $(SCRIPTS)/chroot-install-flatpak-setup.sh

purge-ubuntu-telemetry:
	sudo bash $(SCRIPTS)/chroot-purge-ubuntu-telemetry.sh

build-debs:
	bash packaging/build-debs.sh
