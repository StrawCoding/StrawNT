.PHONY: help build test package clean check fmt

VERSION ?= 0.3.0
COMPONENTS_DIR := $(abspath .)

help:
	@echo "StrawWU components $(VERSION)"
	@echo ""
	@echo "Targets:"
	@echo "  build     Build all workspace crates (release)"
	@echo "  test      Run all unit tests"
	@echo "  package   Build .deb package"
	@echo "  check     Cargo check (fast compile check)"
	@echo "  fmt       Format code"
	@echo "  clean     Remove build artifacts"

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
	@echo "Spec integrity: OK"
	@echo ""
	@echo "=== Component structure check ==="
	@test -d $(COMPONENTS_DIR)/strawwu-bridge/src || (echo "FAIL: strawwu-bridge missing" && exit 1)
	@test -d $(COMPONENTS_DIR)/strawwu-runtime/src || (echo "FAIL: strawwu-runtime missing" && exit 1)
	@test -d $(COMPONENTS_DIR)/strawwu-launcher/src || (echo "FAIL: strawwu-launcher missing" && exit 1)
	@test -d $(COMPONENTS_DIR)/packaging || (echo "FAIL: packaging missing" && exit 1)
	@echo "Structure: OK"
	@echo ""
	@echo "=== ALL TESTS PASSED ==="

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
