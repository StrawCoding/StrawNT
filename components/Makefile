.PHONY: help build test package clean check fmt \
	test-wincompat test-execution-backends test-graphics-vulkan test-graphics-opengl \
	test-anticheat-matrix test-device-proxy generate-compat-matrix

VERSION ?= 0.3.0
COMPONENTS_DIR := $(abspath .)

help:
	@echo "StrawWU components $(VERSION)"
	@echo ""
	@echo "Targets:"
	@echo "  build                    Build all workspace crates (release)"
	@echo "  test                     Run all unit tests"
	@echo "  package                  Build .deb package"
	@echo "  check                    Cargo check (fast compile check)"
	@echo "  fmt                      Format code"
	@echo "  clean                    Remove build artifacts"
	@echo ""
	@echo "Phase 6 — Windows compat tests:"
	@echo "  test-wincompat           Full Phase 6 acceptance (all sub-stages)"
	@echo "  test-execution-backends  Execution backend + runtime cooperation tests"
	@echo "  test-graphics-vulkan     Vulkan/DXGI graphics stack tests"
	@echo "  test-graphics-opengl     OpenGL/WGL graphics stack tests"
	@echo "  test-anticheat-matrix    Anti-cheat probe matrix tests"
	@echo "  test-device-proxy        Device proxy + IOCTL tests"
	@echo "  generate-compat-matrix   Generate compat-matrix.json"

build:
	cargo build --release --workspace --manifest-path $(COMPONENTS_DIR)/Cargo.toml

test:
	@echo "=== strawwu-components test suite ==="
	cargo test --workspace --manifest-path $(COMPONENTS_DIR)/Cargo.toml -- --nocapture
	@echo ""
	@echo "=== Spec files integrity check ==="
	@test -f $(COMPONENTS_DIR)/specs/bridge-abi.md || (echo "FAIL: specs/bridge-abi.md missing" && exit 1)
	@test -f $(COMPONENTS_DIR)/specs/runtime-cooperation.md || (echo "FAIL: specs/runtime-cooperation.md missing" && exit 1)
	@test -f $(COMPONENTS_DIR)/specs/execution-backends.md || (echo "FAIL: specs/execution-backends.md missing" && exit 1)
	@test -f $(COMPONENTS_DIR)/specs/device-driver-proxy.md || (echo "FAIL: specs/device-driver-proxy.md missing" && exit 1)
	@test -f $(COMPONENTS_DIR)/specs/graphics-stack.md || (echo "FAIL: specs/graphics-stack.md missing" && exit 1)
	@test -f $(COMPONENTS_DIR)/specs/anticheat-compat.md || (echo "FAIL: specs/anticheat-compat.md missing" && exit 1)
	@test -f $(COMPONENTS_DIR)/specs/vfio-passthrough-poc.md || (echo "FAIL: specs/vfio-passthrough-poc.md missing" && exit 1)
	@echo "Spec integrity: OK"
	@echo ""
	@echo "=== Component structure check ==="
	@test -d $(COMPONENTS_DIR)/strawwu-bridge/src || (echo "FAIL: strawwu-bridge missing" && exit 1)
	@test -d $(COMPONENTS_DIR)/strawwu-runtime/src || (echo "FAIL: strawwu-runtime missing" && exit 1)
	@test -d $(COMPONENTS_DIR)/strawwu-launcher/src || (echo "FAIL: strawwu-launcher missing" && exit 1)
	@test -d $(COMPONENTS_DIR)/strawwu-nt/src || (echo "FAIL: strawwu-nt missing" && exit 1)
	@test -d $(COMPONENTS_DIR)/strawwu-graphics/src || (echo "FAIL: strawwu-graphics missing" && exit 1)
	@test -d $(COMPONENTS_DIR)/strawwu-audio/src || (echo "FAIL: strawwu-audio missing" && exit 1)
	@test -d $(COMPONENTS_DIR)/strawwu-anticheat/src || (echo "FAIL: strawwu-anticheat missing" && exit 1)
	@test -d $(COMPONENTS_DIR)/strawwu-device-proxy/src || (echo "FAIL: strawwu-device-proxy missing" && exit 1)
	@test -d $(COMPONENTS_DIR)/packaging || (echo "FAIL: packaging missing" && exit 1)
	@echo "Structure: OK"
	@echo ""
	@echo "=== ALL TESTS PASSED ==="

# Phase 6 — Windows compatibility test targets

test-wincompat: test-execution-backends test-graphics-vulkan test-graphics-opengl test-anticheat-matrix test-device-proxy generate-compat-matrix
	@echo ""
	@echo "=== Phase 6 — Windows compatibility test suite ==="
	@echo ""
	@echo "--- 6.1 strawwu-nt (TEB/PEB/PE loader) ---"
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-nt -- --nocapture
	@echo "6.1 strawwu-nt: PASS (PARTIAL — stubs only)"
	@echo ""
	@echo "--- 6.3 Daily app stubs (USER32/GDI32/COM) ---"
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-nt win32_stubs -- --nocapture
	@echo "6.3 Daily app stubs: PASS (PARTIAL — stub registry)"
	@echo ""
	@echo "--- 6.5 Audio/Input (WASAPI/XInput) ---"
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-audio -- --nocapture
	@echo "6.5 Audio/Input: PASS (PARTIAL — bridge stubs)"
	@echo ""
	@echo "--- 6.6 Game path (D3D11→VK) ---"
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-graphics d3d11 -- --nocapture
	@echo "6.6 Game path D3D11→VK: PASS (PARTIAL — translation stubs)"
	@echo ""
	@echo "--- 6.8 Installer (strawwu install + repair) ---"
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-nt installer -- --nocapture
	@echo "6.8 Installer: PASS (PARTIAL — app database + snapshot)"
	@echo ""
	@echo "--- 6.9 WoW64 (32-bit PE path) ---"
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-nt wow64 -- --nocapture
	@echo "6.9 WoW64: PASS (PARTIAL — path redirect stubs)"
	@echo ""
	@echo "--- 6.10 compat-db + Hub integration ---"
	@test -f $(COMPONENTS_DIR)/tests/wincompat/output/compat-matrix.json || (echo "FAIL: compat-matrix.json not generated" && exit 1)
	@echo "6.10 compat-db: PASS (PARTIAL — compat-matrix.json produced)"
	@echo ""
	@echo "--- 6.12 VFIO passthrough PoC ---"
	@test -f $(COMPONENTS_DIR)/specs/vfio-passthrough-poc.md || (echo "FAIL: VFIO doc missing" && exit 1)
	@echo "6.12 VFIO PoC: PASS (PARTIAL — experimental documentation only)"
	@echo ""
	@echo "============================================"
	@echo "Phase 6 sub-stage results:"
	@echo "  6.1  strawwu-nt (TEB/PEB/PE):     PARTIAL"
	@echo "  6.2  Execution backends:           PARTIAL"
	@echo "  6.3  Daily apps (USER32/GDI32):    PARTIAL"
	@echo "  6.4  Graphics Vulkan (DXGI→VK):    PARTIAL"
	@echo "  6.4b Graphics OpenGL (wgl→GLX):    PARTIAL"
	@echo "  6.5  Audio/Input (WASAPI/XInput):  PARTIAL"
	@echo "  6.6  Game path (D3D11→VK):         PARTIAL"
	@echo "  6.7  Anti-cheat matrix:            PARTIAL"
	@echo "  6.8  Installer:                    PARTIAL"
	@echo "  6.9  WoW64 (32-bit PE):            PARTIAL"
	@echo "  6.10 compat-db + Hub:              PARTIAL"
	@echo "  6.11 device-proxy:                 PARTIAL"
	@echo "  6.12 VFIO PoC:                     PARTIAL"
	@echo "============================================"
	@echo ""
	@echo "=== test-wincompat: PASS ==="

test-execution-backends:
	@echo "=== 6.2 Execution backends + runtime cooperation ==="
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-runtime -- --nocapture
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-bridge -- --nocapture
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-nt ipc -- --nocapture
	@echo "6.2 Execution backends: PASS (PARTIAL)"
	@echo ""
	@echo "=== test-execution-backends: PASS ==="

test-graphics-vulkan:
	@echo "=== 6.4 Graphics: Vulkan (DXGI→VK) ==="
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-graphics vulkan -- --nocapture
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-graphics dxgi -- --nocapture
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-graphics present -- --nocapture
	@echo "6.4 Graphics Vulkan: PASS (PARTIAL — stub/mock)"
	@echo ""
	@echo "=== test-graphics-vulkan: PASS ==="

test-graphics-opengl:
	@echo "=== 6.4b Graphics: OpenGL (wgl→GLX/EGL) ==="
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-graphics opengl -- --nocapture
	@echo "6.4b Graphics OpenGL: PASS (PARTIAL — stub/mock)"
	@echo ""
	@echo "=== test-graphics-opengl: PASS ==="

test-anticheat-matrix:
	@echo "=== 6.7 Anti-cheat matrix ==="
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-anticheat -- --nocapture
	@echo "6.7 Anti-cheat matrix: PASS (PARTIAL — probe does not crash)"
	@echo ""
	@echo "=== test-anticheat-matrix: PASS ==="

test-device-proxy:
	@echo "=== 6.11 Device proxy ==="
	cargo test --manifest-path $(COMPONENTS_DIR)/Cargo.toml -p strawwu-device-proxy -- --nocapture
	@echo "6.11 Device proxy: PASS (PARTIAL)"
	@echo ""
	@echo "=== test-device-proxy: PASS ==="

generate-compat-matrix:
	@echo "=== Generating compat-matrix.json ==="
	@bash $(COMPONENTS_DIR)/tests/wincompat/generate-compat-matrix.sh
	@echo ""

package: build
	@echo "=== Building .deb package ==="
	STRAWWU_VERSION=$(VERSION) bash $(COMPONENTS_DIR)/packaging/build-deb.sh
	@echo ""
	@echo "=== Package verification ==="
	@test -f $(COMPONENTS_DIR)/packaging/output/strawwu-launcher_$(VERSION)-1_amd64.deb || \
		(echo "FAIL: .deb not found" && exit 1)
	dpkg-deb --info $(COMPONENTS_DIR)/packaging/output/strawwu-launcher_$(VERSION)-1_amd64.deb
	@echo ""
	@echo "=== PACKAGE BUILD COMPLETE ==="

check:
	cargo check --workspace --manifest-path $(COMPONENTS_DIR)/Cargo.toml

fmt:
	cargo fmt --all --manifest-path $(COMPONENTS_DIR)/Cargo.toml

clean:
	cargo clean --manifest-path $(COMPONENTS_DIR)/Cargo.toml
	rm -rf $(COMPONENTS_DIR)/packaging/output
	rm -rf $(COMPONENTS_DIR)/tests/wincompat/output
