# Stage Report — OFFICIAL-RELEASE 1.0.0.0

| 欄位 | 值 |
|------|-----|
| 階段 | official-release (8/8) |
| 版本 | 1.0.0.0 |
| 日期 | 2026-07-08 |
| worker | stage 8/8 official-release |

## 摘要

Q9 正式版授權發布管線：VERSION bump 至 `1.0.0.0`、release-iso 建置、SHA256SUMS 驗證、install E2E 執行中。新增 official-release DoD、HTML hermes-deliver、preflight 閘門與共用版本政策庫。

## 變更

- `.official-release-authorized` 填入授權日期與目標版本
- `VERSION` → `1.0.0.0`（hub/package.json、components/Cargo.toml 同步）
- `tests/lib/version_policy.py` — closeout 驗證器支援 MAJOR=1 授權路徑
- `docs/plans/official-release/` — DoD + HTML
- `tests/official-release/` — validate + render
- `tests/preflight/test-official-release.sh` + Makefile target

## 驗證記錄

| 命令 | exit | 備註 |
|------|------|------|
| `test -f .official-release-authorized` | 0 | |
| `make preflight` | 0 | STRAWWU_OFFICIAL_RELEASE=1 |
| `make build-iso` | 0 | release-iso xz |
| `sha256sum -c SHA256SUMS` | 0 | |
| `make test-install-e2e` | 待完成 | log: /tmp/test-install-e2e-1.0.0.0.log |

## 建議

Hermes mark PASS 條件：E2E exit 0 + `make test-official-release` PASS。
