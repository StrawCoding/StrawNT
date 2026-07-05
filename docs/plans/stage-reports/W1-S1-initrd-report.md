# W1-S1 initrd 階段報告

| 任務 | W1-S1-initrd |
|------|--------------|
| 版本 | 0.4.1.4 |
| 日期 | 2026-07-05 |
| Worker | 階段 5/47（w1-s1-initrd） |
| 最後驗證 | 2026-07-05T02:11 UTC-4（companion worker 重跑） |
| Commit | `e0de8a0ff` feat(w1): initrd overlays |
| 結果 | **PASS**（Hermes mark 2026-07-05T02:11:43-0400，v0.4.1.4） |

## 交付物

| 類型 | 路徑 |
|------|------|
| initrd overlays | `os-image/initrd/overlays/scripts/casper-premount/`、`casper-bottom/` |
| iso-scan overlay | `os-image/initrd/overlays/scripts/casper-premount/20iso_scan` |
| live-shutdown overlay | `os-image/initrd/overlays/scripts/casper-bottom/25disable_cdrom.mount` |
| wait-live-media | `os-image/initrd/overlays/scripts/casper-premount/05strawwu-wait-live-media` |
| splice 整合 | `os-image/scripts/initrd-splice.py`（`DEFAULT_OVERLAYS_ROOT`、`inject_initrd_overlays`） |
| Preflight | `tests/preflight/test-initrd-overlays.sh` |
| ISO preflight 修正 | `tests/preflight/test-iso-before-boot.sh`（QEMU scan heredoc；release-iso xz squashfs 大小閾值） |
| Makefile | `preflight` 含 initrd test；`repack-iso` 修正為 `STRAWWU_ISO_MODE=dev-iso` |
| ISO 產物 | `os-image/output/StrawWU-0.4.1.4-amd64.iso`（release-iso，xz squashfs，含 overlay initrd） |
| VERSION | `0.4.1.4` |

## 技術摘要

| 項目 | 說明 |
|------|------|
| 策略 | 保留 upstream `main.zst` splice；僅 overlay 替換低風險 casper 腳本 |
| iso-scan | 覆寫 `20iso_scan`：StrawWU panic 訊息；無 `iso-scan/filename=` 時 early exit |
| live-shutdown | 覆寫 `25disable_cdrom.mount`：維持 cdrom.mount 於 casper shutdown 前不被卸載 |
| wait-live-media | 自 branding 遷移至 `initrd/overlays/`（單一來源） |
| splice | `refresh_preserved_main` 注入 overlays 後 recompress main.zst |

## 驗收命令輸出（2026-07-05T02:10–02:11 UTC-4，companion worker 重跑）

### `make preflight` — exit 0

含 `test-initrd-overlays.sh` 全部 PASS（含 staged initrd 內三個 overlay 腳本含 StrawWU marker）。

Log: `/tmp/w1-s1-preflight-20260705-021024.log`

### `make preflight-iso-before-boot`（release-iso 預設）— exit 0

- initrd verify、early3 strawwu 模組、overlay 腳本已注入 staging — 全部 PASS
- build mode `release-iso` 匹配
- ISO 5.35GB、initrd 68.9MB、minimal.squashfs xz ~1.3GB — 全部 PASS
- branded 內容 marker/plymouth/GDM 均 PASS

Log: `/tmp/w1-s1-iso-preflight-20260705-021044.log`

## 環境修復（本 session）

| 問題 | 處理 |
|------|------|
| 無 `/dev/loop*`、`/dev/loop-control` | `mknod` 建立 loop-control + loop0–31 |
| snapd 佔用 loop0–7 | losetup 使用 loop8+ |
| release-iso 重建 | 完整 `build-iso.sh` release-iso（~12 min，xz squashfs） |

## 變更檔案

- `os-image/initrd/overlays/scripts/casper-premount/05strawwu-wait-live-media`（新增，自 branding 遷移）
- `os-image/initrd/overlays/scripts/casper-premount/20iso_scan`（新增）
- `os-image/initrd/overlays/scripts/casper-bottom/25disable_cdrom.mount`（新增）
- `os-image/config/branding/initrd/scripts/casper-premount/05strawwu-wait-live-media`（刪除）
- `os-image/scripts/initrd-splice.py`
- `tests/preflight/test-initrd-overlays.sh`（新增）
- `tests/preflight/test-iso-before-boot.sh`
- `Makefile`
- `VERSION`（0.4.1.4）

## 已知限制 / Hermes 後續

1. **W8-S2/S3**：casper 核心 / bottom 全面 fork 留待後續 Wave。
2. **loop 裝置**：容器/host 若無 loop 模組，需手動 `mknod` 或卸載 snap loop 後才能 `mount -o loop` 建 ISO。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make preflight
make preflight-iso-before-boot
```

## 建議 commit message

```
feat(w1): initrd overlays — iso-scan, live-shutdown, splice integration

- Add os-image/initrd/overlays/ with casper-premount/bottom low-risk scripts
- Wire initrd-splice.py DEFAULT_OVERLAYS_ROOT + inject_initrd_overlays
- Migrate wait-live-media from branding; add test-initrd-overlays preflight
- Fix test-iso-before-boot: QEMU scan heredoc + release-iso xz squashfs size gate
Tests: make preflight PASS; make preflight-iso-before-boot PASS (release-iso)
```

## 下一步

Hermes mark PASS（2026-07-05T02:11:43-0400）→ 下一階段 **W2-B2-bug-reporter**。
