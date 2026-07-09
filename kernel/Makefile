.PHONY: help build clean test

# ABI is resolved by build.sh from docs/plans/ubuntu-base-target.json
# (active.kernel_abi) — the single source of truth. Only override here by passing
# KERNEL_ABI=<x.y.z-n> on the command line.
KERNEL_ABI ?=
JOBS       ?= $(shell nproc)

help:
	@echo "StrawWU kernel — Phase 2"
	@echo "  make build   Build linux-image-strawwu .deb (long-running)"
	@echo "  make clean   Remove build artifacts"
	@echo "  make test    Verify .deb exists"

build:
	$(if $(KERNEL_ABI),STRAWWU_KERNEL_ABI=$(KERNEL_ABI) ,)STRAWWU_KERNEL_JOBS=$(JOBS) bash build.sh

clean:
	rm -rf build output

test:
	@test -f output/.build-ok || (echo "run make build first" && exit 1)
	@test -f output/linux-image-strawwu_*.deb || (echo "missing linux-image-strawwu deb" && exit 1)
	@echo "kernel test: PASS"
