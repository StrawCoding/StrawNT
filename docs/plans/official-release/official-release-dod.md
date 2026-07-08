# StrawWU Official Release Definition of Done (Q9)

| 欄位 | 值 |
|------|-----|
| 產品目標 | 1.0.0-target（Q9 正式版授權發布） |
| 建置版本 | 見 VERSION（`1.0.0.0`） |
| 前置階段 | phase0 → phase6 + Post-MVP 全段 PASS |
| 授權標記 | `.official-release-authorized` |

## 1. 硬性閘門

| # | 項目 | 驗收 |
|---|------|------|
| 1 | 全 7 前置 Phase PASS | Hermes state |
| 2 | Post-MVP 21 段 PASS | post-mvp-status.json |
| 3 | 使用者授權正式版 | `.official-release-authorized` |
| 4 | preflight PASS | `STRAWWU_OFFICIAL_RELEASE=1 make preflight` |
| 5 | release-iso 建置 | `make build-iso` → `os-image/output/StrawWU-1.0.0.0-amd64.iso` |
| 6 | SHA256SUMS 驗證 | `sha256sum -c SHA256SUMS` |
| 7 | Calamares install E2E | `make test-install-e2e` |
| 8 | HTML hermes-deliver | `docs/plans/official-release/html/official-release-report.html` |

## 2. 驗證命令（Hermes trigger-verify）

```bash
test -f .official-release-authorized
make build-iso
make test-install-e2e
sha256sum -c SHA256SUMS
```

## 3. 證據路徑

| 證據 | 路徑 |
|------|------|
| 授權標記 | `.official-release-authorized` |
| 目標版本 | `.official-release-target` |
| ISO | `os-image/output/*.iso` |
| 校驗和 | `SHA256SUMS`（repo 根目錄 + os-image/output/） |
| boot/install | `tests/install-e2e/output/` |
| CI | `.github/workflows/release.yml` |

## 4. 版本政策

- 預發布：MAJOR=0（`0.a.b.d`）
- 正式版：MAJOR=1 僅在 `.official-release-authorized` 存在後
- ISO 檔名：`StrawWU-1.0.0.0-amd64.iso`
- Git tag：`v1.0.0.0`

## 5. 產品範圍備註

| Q | 項目 | 1.0.0 狀態 |
|---|------|------------|
| Q7 | 反作弊=可正常運行 | PARTIAL（誠實報告） |
| Q8 | Office/Steam/Epic/三角洲 launcher | stub + golden-apps gate |
| Q1 | 預發布範圍 | 待使用者另行提出 |
