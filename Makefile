.PHONY: help preflight preflight-iso-before-boot preflight-dev-vm clone-ubuntu-base swap-kernel \
	build-iso dev-iso release-iso repack-iso validate-rootfs boot-test-iso boot-test-dev-iso \
	boot-test-release-iso dev-vm-start dev-vm-sync dev-vm-test dev-vm-cycle dev-vm-rollback \
	test-phase0 test-phase2 kernel-build validate-calamares-preflight validate-partition-probe \
	test-install-e2e test-install-firstboot-e2e test-installed-boot test-target-flathub test-wincompat test-wincompat-os test-wincompat-registry test-wincompat-gui test-wincompat-e2e test-hw-live-usb test-hw-matrix test-user-docs test-handbook test-mvp-closeout test-release-manifest test-apt-repo test-ci-baseline test-ci-nightly test-perf-baseline test-perf-legal-gate test-strawwu-shell test-hub test-hub-settings test-apps-page test-flathub-hub test-l10n-ime test-firstboot test-finished-meta test-context-menu test-registry-hooks test-deep-uninstall test-initramfs-hooks test-target-identity test-greeter-session test-wave0-baseline test-wave-all-pass test-purge-baseline test-flatpak test-nosnap test-initrd-overlays test-initrd-core test-initrd-bottom test-init-tools test-bug-reporter test-calamares-settings test-app-registry test-security-baseline test-observability test-legal-trademark test-desktop-stack test-live-install-ux test-update-notifier test-target-setup test-meta-audit purge-ubuntu-telemetry \
	install-flatpak-setup install-bug-reporter install-calamares-settings install-update-notifier install-target-setup install-firstboot install-wincompat nosnap-harden build-debs bump-version check-version-bump generate-release-manifest release-sign publish-debs

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
	@echo "  test-install-firstboot-e2e    Install + installed boot + serial FIRSTBOOT_OK"
	@echo "  test-installed-boot           Install + BIOS+UEFI installed disk STRAWWU_BOOT_OK"
	@echo "  test-target-flathub           Install + target flathub system remote E2E"
	@echo "  test-meta-audit               W6-B5 ubuntu-* allowlist + strawwu-minimal meta"
	@echo "  test-wave0-baseline           Wave 0 preflight baselines (12 scripts + JSON)"
	@echo "  test-wave-all-pass            Verify all 47 wave stages PASS (MVP closeout gate)"
	@echo "  test-post-mvp-roadmap         Post-MVP + Ubuntu 26.04 long-task infrastructure gate"
	@echo "  test-post-mvp-all-pass        Verify all 14 post-MVP stages PASS"
	@echo "  test-post-mvp-v06-closeout    v0.6 drivers/HW closeout gate"
	@echo "  test-ubuntu-2604-roadmap      Ubuntu 26.04 migration infrastructure gate"
	@echo "  test-ubuntu-2604-all-pass     Verify all 7 Ubuntu 26.04 migration stages PASS"
	@echo "  test-drivers                  POST-D1 strawwu-drivers"
	@echo "  test-hw-t1-live-usb           POST-HW-T1 real Live USB matrix"
	@echo "  test-hw-t2-installed          POST-HW-T2 installed smoke"
	@echo "  test-ddp-rootfs               POST-DDP device-proxy rootfs"
	@echo "  test-mfp-smoke                POST-Q3 MFP print/scan"
	@echo "  test-upgrade-rollback         POST-UPG rollback"
	@echo "  test-secureboot-route         POST-SEC Secure Boot route"
	@echo "  test-ci-kernel-selfhosted     POST-CI self-hosted kernel"
	@echo "  test-hw-t3-wincompat          POST-HW-T3 Win compat HW smoke"
	@echo "  test-golden-apps              POST-Q8 golden apps launch"
	@echo "  test-purge-baseline           W1-B1 telemetry/pro/snap purge verification"
	@echo "  test-flatpak                  W1-F1 flatpak + flathub remote verification"
	@echo "  test-nosnap                   W1-F2 snapd absent + meta mask verification"
	@echo "  test-initrd-core              W8-S2 strawwu-live-init casper core fork"
	@echo "  test-initrd-bottom            W8-S3 strawwu-live-bottom casper-bottom fork"
	@echo "  test-initramfs-hooks          W8-S4 strawwu-initramfs-hooks disk-boot deb"
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
	@echo "  test-wincompat-registry       W4-W1 launcher ↔ app-registry integration"
	@echo "  test-wincompat-gui            W5-W4 Windows GUI app launch smoke"
	@echo "  test-wincompat-e2e            W6-W6 install→icon→launch→remove E2E"
	@echo "  test-hw-live-usb              W6-HW1 Live USB matrix (≥3 machine profiles)"
	@echo "  test-hw-matrix                W8-HW-MATRIX GPU/Wi-Fi/suspend/HiDPI matrix"
	@echo "  test-user-docs                W6-DOC1 install/rescue user guides + HTML"
	@echo "  test-handbook                 W8-DOC user+admin handbook + DOC2/DOC3 HTML"
	@echo "  test-mvp-closeout             W8-MVP closeout DoD + HTML + wave evidence"
	@echo "  test-release-manifest         W7-RE1+RE2 release-manifest + GPG signing"
	@echo "  test-apt-repo                 W7-RE3+RE4 APT repo + strawwu-keyring"
	@echo "  test-ci-baseline              W7-CI0 CI pipeline inventory + ci-baseline.json"
	@echo "  test-ci-nightly               W7-CI2+CI3+CI4 nightly + PR gate + self-hosted"
	@echo "  test-perf-baseline            W7-PERF0+PERF1 ISO size baseline + budget gate"
	@echo "  test-perf-legal-gate          W7 PERF1+LEG4 CI workflow wiring gate"
	@echo "  generate-release-manifest     Build os-image/output/release-manifest.json"
	@echo "  release-sign                  SHA256SUMS + detached GPG for release ISO"
	@echo "  publish-debs                  Build signed APT repo from strawwu .debs"
	@echo "  test-strawwu-shell            W4-D2 strawwu-shell fork profile + built-in dock"
	@echo "  test-hub-settings             W4-D3 Hub settings center preflight"
	@echo "  test-apps-page                W4-R2 Hub Apps page (App Registry UI)"
	@echo "  test-flathub-hub              W4-F3 Hub Flathub browse/install MVP"
	@echo "  test-l10n-ime                 W4-L10N fcitx5 + zh_TW localization"
	@echo "  test-firstboot                W5-N3 strawwu-firstboot GTK4 six-step wizard"
	@echo "  test-finished-meta            W5-N4 install-init meta + Calamares finished zh_TW"
	@echo "  test-context-menu             W5-D4 desktop remove context menu + favorites sync"
	@echo "  test-registry-hooks           W5-R4 Linux/Flatpak install scan → app registry"
	@echo "  test-deep-uninstall           W6-R5 registry deep remove + scan uninstall sync"
	@echo "  test-target-identity          W5-I3 GRUB/Plymouth post-install target branding"
	@echo "  test-greeter-session          W5-GRT strawwu-greeter GDM theme + session defaults"
	@echo "  purge-ubuntu-telemetry        chroot purge apport/whoopsie/ubuntu-pro/snapd (needs root)"
	@echo "  install-flatpak-setup         chroot install flatpak + strawwu-flatpak-setup (needs root)"
	@echo "  install-bug-reporter          chroot install strawwu-bug-reporter (needs root)"
	@echo "  install-calamares-settings    chroot install strawwu-calamares-settings (needs root)"
	@echo "  install-update-notifier       chroot install strawwu-update-notifier (needs root)"
	@echo "  install-target-setup          chroot install strawwu-target-setup + desktop stack (needs root)"
	@echo "  install-firstboot             chroot install/verify strawwu-firstboot (needs root)"
	@echo "  install-wincompat             chroot install strawwu-wincompat /usr/bin/strawwu (needs root)"
	@echo "  nosnap-harden                 chroot mask snapd Recommends + /snap stub (needs root)"

preflight:
	bash tests/preflight/test-ubuntu-clone.sh
	bash tests/preflight/test-branding.sh
	bash tests/preflight/test-purge-baseline.sh
	bash tests/preflight/test-flatpak.sh
	bash tests/preflight/test-nosnap.sh
	bash tests/preflight/test-initrd-overlays.sh
	bash tests/preflight/test-initrd-core.sh
	bash tests/preflight/test-initrd-bottom.sh
	bash tests/preflight/test-initramfs-hooks.sh
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
	bash tests/preflight/test-flathub-hub.sh
	bash tests/preflight/test-wincompat-registry.sh
	bash tests/preflight/test-wincompat-gui.sh
	bash tests/preflight/test-l10n-ime.sh
	bash tests/preflight/test-firstboot.sh
	bash tests/preflight/test-finished-meta.sh
	bash tests/preflight/test-context-menu.sh
	bash tests/preflight/test-registry-hooks.sh
	bash tests/preflight/test-target-identity.sh
	bash tests/preflight/test-greeter-session.sh
	bash tests/preflight/test-upstream-init-disabled.sh
	bash tests/preflight/test-install-firstboot-e2e.sh
	bash tests/preflight/test-installed-boot.sh
	bash tests/preflight/test-target-flathub.sh
	bash tests/preflight/test-meta-audit.sh
	bash tests/preflight/test-deep-uninstall.sh
	bash tests/preflight/test-wincompat-e2e.sh
	bash tests/preflight/test-hw-live-usb.sh
	bash tests/preflight/test-user-docs.sh
	bash tests/preflight/test-handbook.sh
	bash tests/preflight/test-mvp-closeout.sh
	bash tests/preflight/test-release-manifest.sh
	bash tests/preflight/test-apt-repo.sh
	bash tests/preflight/test-ci-nightly.sh
	bash tests/preflight/test-perf-baseline.sh
	bash tests/preflight/test-perf-legal-gate.sh
	bash tests/preflight/test-hw-matrix.sh
	bash tests/preflight/test-post-mvp-roadmap.sh

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

validate-partition-probe: validate-calamares-preflight
	bash tests/install-e2e/partition-probe.sh

test-install-e2e: validate-calamares-preflight validate-partition-probe
	bash tests/install-e2e/run.sh

test-install-firstboot-e2e: validate-calamares-preflight validate-partition-probe
	bash tests/install-e2e/run-firstboot-e2e.sh

test-installed-boot: validate-calamares-preflight validate-partition-probe
	bash tests/install-e2e/run-installed-boot.sh

test-target-flathub: validate-calamares-preflight validate-partition-probe
	bash tests/install-e2e/run-target-flathub.sh

test-wincompat:
	@echo "=== Phase 6: Windows Compatibility Layer ==="
	cd components && cargo test --workspace
	bash components/tests/wincompat/generate-compat-matrix.sh

test-wave0-baseline:
	bash tests/preflight/test-wave0-baseline.sh

test-wave-all-pass:
	bash tests/preflight/test-wave-all-pass.sh

test-post-mvp-roadmap:
	bash tests/preflight/test-post-mvp-roadmap.sh

test-post-mvp-all-pass:
	bash tests/preflight/test-post-mvp-all-pass.sh

test-post-mvp-v06-closeout:
	bash tests/preflight/test-post-mvp-v06-closeout.sh

test-ubuntu-2604-roadmap:
	bash tests/preflight/test-ubuntu-2604-roadmap.sh

test-ubuntu-2604-all-pass:
	bash tests/preflight/test-ubuntu-2604-all-pass.sh

test-u26-base-clone test-u26-kernel-rebase test-u26-debs-rebuild test-u26-suite-migrate \
test-u26-techrefs-refresh test-u26-regression-e2e:
	bash tests/preflight/test-$(subst test-,,$@).sh

test-software-sources test-ux-theme-curation:
	bash tests/preflight/test-$(subst test-,,$@).sh

test-drivers:
	bash tests/preflight/test-drivers.sh

test-hw-t1-live-usb:
	bash tests/preflight/test-hw-t1-live-usb.sh

test-hw-t2-installed:
	bash tests/preflight/test-hw-t2-installed.sh

test-ddp-rootfs:
	bash tests/preflight/test-ddp-rootfs.sh

test-mfp-smoke:
	bash tests/preflight/test-mfp-smoke.sh

test-upgrade-rollback:
	bash tests/preflight/test-upgrade-rollback.sh

test-secureboot-route:
	bash tests/preflight/test-secureboot-route.sh

test-ci-kernel-selfhosted:
	bash tests/preflight/test-ci-kernel-selfhosted.sh

test-hw-t3-wincompat:
	bash tests/preflight/test-hw-t3-wincompat.sh

test-golden-apps:
	bash tests/preflight/test-golden-apps.sh

test-purge-baseline:
	bash tests/preflight/test-purge-baseline.sh

test-flatpak:
	bash tests/preflight/test-flatpak.sh

test-nosnap:
	bash tests/preflight/test-nosnap.sh

test-initrd-overlays:
	bash tests/preflight/test-initrd-overlays.sh

test-initrd-core:
	bash tests/preflight/test-initrd-core.sh

test-initrd-bottom:
	bash tests/preflight/test-initrd-bottom.sh

test-initramfs-hooks:
	bash tests/preflight/test-initramfs-hooks.sh

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

test-meta-audit:
	bash tests/preflight/test-meta-audit.sh

test-deep-uninstall:
	bash tests/preflight/test-deep-uninstall.sh

test-wincompat-os:
	bash tests/preflight/test-wincompat-os.sh

test-wincompat-registry:
	bash tests/preflight/test-wincompat-registry.sh

test-wincompat-gui:
	bash tests/preflight/test-wincompat-gui.sh

test-wincompat-e2e:
	bash tests/preflight/test-wincompat-e2e.sh

test-hw-live-usb:
	bash tests/hw/run-live-usb-matrix.sh
	bash tests/preflight/test-hw-live-usb.sh

test-hw-matrix:
	bash tests/hw/run-hw-matrix.sh
	bash tests/preflight/test-hw-matrix.sh

test-user-docs:
	python3 tests/user-docs/validate-user-docs.py

test-handbook:
	python3 tests/handbook/validate-handbook.py

test-mvp-closeout:
	python3 tests/mvp-closeout/validate-mvp-closeout.py

test-strawwu-shell:
	bash tests/preflight/test-strawwu-shell.sh

test-hub:
	$(MAKE) -C components test-hub

test-hub-settings:
	bash tests/preflight/test-hub-settings.sh

test-apps-page:
	bash tests/preflight/test-apps-page.sh

test-flathub-hub:
	bash tests/preflight/test-flathub-hub.sh

test-l10n-ime:
	bash tests/preflight/test-l10n-ime.sh

test-firstboot:
	bash tests/preflight/test-firstboot.sh

test-finished-meta:
	bash tests/preflight/test-finished-meta.sh

test-context-menu:
	bash tests/preflight/test-context-menu.sh

test-registry-hooks:
	bash tests/preflight/test-registry-hooks.sh

test-target-identity:
	bash tests/preflight/test-target-identity.sh

test-greeter-session:
	bash tests/preflight/test-greeter-session.sh

test-upstream-init-disabled:
	bash tests/preflight/test-upstream-init-disabled.sh

test-install-firstboot-e2e-static:
	bash tests/preflight/test-install-firstboot-e2e.sh

test-installed-boot-static:
	bash tests/preflight/test-installed-boot.sh

test-target-flathub-static:
	bash tests/preflight/test-target-flathub.sh

test-release-manifest:
	bash tests/preflight/test-release-manifest.sh

test-apt-repo:
	bash tests/preflight/test-apt-repo.sh

test-ci-baseline:
	bash tests/preflight/test-ci-baseline.sh

test-ci-nightly:
	bash tests/preflight/test-ci-nightly.sh

test-perf-baseline:
	bash tests/preflight/test-perf-baseline.sh

test-perf-legal-gate:
	bash tests/preflight/test-perf-legal-gate.sh

generate-release-manifest:
	bash scripts/generate-release-manifest.sh

release-sign:
	bash scripts/release-sign.sh

publish-debs:
	bash scripts/publish-debs.sh

install-calamares-settings:
	sudo bash $(SCRIPTS)/chroot-install-calamares-settings.sh

install-bug-reporter:
	sudo bash $(SCRIPTS)/chroot-install-bug-reporter.sh

install-update-notifier:
	sudo bash $(SCRIPTS)/chroot-install-update-notifier.sh

install-target-setup:
	sudo bash $(SCRIPTS)/chroot-install-target-setup.sh

install-firstboot:
	sudo bash $(SCRIPTS)/chroot-install-firstboot.sh

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
