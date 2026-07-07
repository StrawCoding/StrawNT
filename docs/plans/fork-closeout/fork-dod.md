# StrawWU Fork 基底遷移 Definition of Done

| 欄位 | 值 |
|------|-----|
| 產品目標 | v0.6.2.0-target（fork 基底預設） |
| 建置版本 | 見 VERSION |
| 遷移段數 | 7（fork-f1 → fork-f7-closeout） |
| 基線 | Ubuntu 26.04 LTS Resolute + StrawWU fork snapshot |

## 1. 遷移目標（fork-migration-plan §1）

| # | 項目 | 狀態 | 證據 |
|---|------|------|------|
| 1 | fork baseline snapshot（F1） | ✅ | fork-base/manifest.json、snapshots/*.tar.zst |
| 2 | manifest repo（include/remove/replace/pin） | ✅ | fork-base/packages/、test-fork-f2 |
| 3 | build pipeline 支援 fork-sync-base | ✅ | sync-base.sh、test-fork-f3 |
| 4 | fork package overlays | ✅ | os-image/fork/packages/、test-fork-f4 |
| 5 | strawwu-fork APT suite | ✅ | publish-fork-debs.sh、test-fork-f5 |
| 6 | fork base boot + install-firstboot E2E | ✅ | boot-result、firstboot-e2e、test-fork-f6 |
| 7 | base_mode=fork 預設 + closeout 報告 | ✅ | ubuntu-base-target.json、HTML、fork-status.json |

## 2. 各段摘要

| 段 | ID | 重點 |
|----|-----|------|
| F1 | fork-f1-baseline-snapshot | u26 驗證 rootfs → fork snapshot |
| F2 | fork-f2-manifest-repo | packages manifest 進 repo |
| F3 | fork-f3-build-pipeline | sync-base 路由、fork marker |
| F4 | fork-f4-package-overlays | fork/packages debian/ 原始碼 |
| F5 | fork-f5-apt-fork-suite | strawwu-fork APT suite 發佈 |
| F6 | fork-f6-regression-e2e | release-iso BIOS+UEFI、FIRSTBOOT_OK |
| F7 | fork-f7-closeout | base_mode=fork 預設、全段 PASS 彙整、HTML |

## 3. 基底模式切換（fork-migration-plan §3）

| 模式 | 環境變數 | marker | 狀態 |
|------|----------|--------|------|
| clone | `STRAWWU_BASE_MODE=clone` | `.clone-ubuntu-base-ok` | 覆寫用（舊路徑） |
| fork | 預設 | `.fork-sync-base-ok` | **F7 後預設** |

配置：`docs/plans/ubuntu-base-target.json` → `base_mode: fork`

## 4. 風險緩解驗收

| 風險 | 緩解驗收 |
|------|----------|
| snapshot 還原失敗 | fork-sync-base marker + manifest sha256 |
| fork 與 clone 管線分歧 | sync-base 分派、base-marker.sh 共用 |
| APT suite 隔離 | strawwu-fork 獨立 dists、GPG 簽章 |
| 回歸退化 | F6 boot+install E2E on fork base PASS |

## 5. 驗收閘門

```bash
make test-fork-all-pass   # 7/7 fork stages PASS
make test-fork-f7-closeout
make preflight            # 全 Wave + 基礎設施
```

## 6. 產物索引

| 類型 | 路徑 |
|------|------|
| Fork 狀態 | `docs/plans/baselines/fork-status.json` |
| 基底配置 | `docs/plans/ubuntu-base-target.json` |
| Stage reports | `docs/plans/stage-reports/FORK-F*.md`（7 份） |
| HTML 報告 | `docs/plans/fork-closeout/html/fork-closeout-report.html` |
| Fork 計畫 | `docs/plans/strawwu-fork-migration-plan.md` |
| release ISO | `os-image/output/StrawWU-<VERSION>-amd64.iso` |

## 7. 後續

`fork-f7-closeout` PASS → 自動啟動 **post-d1-strawwu-drivers**（Post-MVP 12+2 track）。
