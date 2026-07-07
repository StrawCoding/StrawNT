#!/usr/bin/env bash
# build-package.sh — Template only. Copy _template/ to a real package before building.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

die "This is the fork package scaffold template. Copy os-image/fork/packages/_template/ to <pkgname>/, customize, register in packages.json, then build."
