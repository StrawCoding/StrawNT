# Wave 1 — S1 initrd 低風險替換

| 任務 ID | W1-S1-initrd |
|---------|--------------|
| 版本 | 1.0 |
| 日期 | 2026-07-04 |
| 狀態 | 待啟動 |

## 目標

initrd overlay 低風險替換（live-shutdown、iso-scan 等）；保留 upstream `main.zst` splice 策略。

## 範圍

### 必須交付

1. `os-image/initrd/overlays/` 低風險腳本/設定
2. 整合現有 `initrd-splice.py` 流程（若已有）
3. `make preflight-iso-before-boot` PASS
4. `docs/plans/stage-reports/W1-S1-initrd-report.md`
5. VERSION bump

### 必讀

- `docs/iso-modes.md`
- repo `docs/plans/` initrd 相關計畫摘要

## PASS 條件

```bash
make preflight
make preflight-iso-before-boot
# exit 0
```

## 禁止

- 整包重寫 casper / main.zst 無 fallback
- `SKIP_SQUASHFS=1` + boot-test 同一 ISO
- 改 kernel/ 源碼（除非 overlay 僅腳本）
- worker 自宣稱 PASS

## 完成後

Hermes mark PASS → 自動啟動 W2-B2-bug-reporter（Wave 2 鎖序已配置）。
