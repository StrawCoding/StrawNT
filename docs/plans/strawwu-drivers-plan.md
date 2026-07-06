# StrawWU Linux 驅動管理計畫（strawwu-drivers）

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-06 |
| 對標 | Linux Mint Driver Manager · Ubuntu Additional Drivers |
| 長任務 stage | `post-d1-strawwu-drivers` |

## 1. 問題

StrawWU 繼承 Ubuntu noble 的 `linux-firmware` 與 `ubuntu-drivers`，但缺少發行版級驅動管理 UX。使用者需手動 `apt install` 專有 GPU 驅動，體驗落後 Mint / Pop!_OS。

## 2. 目標產物

| 產物 | 說明 |
|------|------|
| `os-image/debs/strawwu-drivers/` | CLI + polkit + 後端腳本 |
| Hub「驅動」分頁 | 列出可用/已裝驅動；一鍵安裝 NVIDIA/AMD |
| firstboot 提示（可選） | 偵測專有 GPU → 建議安裝 |
| `tests/preflight/test-drivers.sh` | 靜態 + mock 閘門 |

## 3. 功能範圍（v0.6）

### 必做
- 包裝 `ubuntu-drivers` / `ubuntu-drivers-common` 為 StrawWU 品牌 CLI：`strawwu-drivers list|install|status`
- Hub 分頁：顯示 GPU 型號、推薦驅動、安裝狀態
- NVIDIA 專有驅動一鍵安裝（3 種 GPU 各 1 台 Live PASS 證據）
- 誠實標示：Secure Boot 未簽模組警告（連結 SEC 計畫）

### 不做（v0.6）
- 自簽 kernel module
- ROCm 策展
- Win device-proxy（屬 DDP stage）

## 4. PASS 條件

```bash
make test-drivers    # exit 0
make preflight       # exit 0
```

證據：
- `docs/plans/stage-reports/POST-D1-strawwu-drivers-report.md`
- ≥1 NVIDIA + ≥1 AMD + ≥1 Intel iGPU 各 1 台 Live 驅動偵測 PASS（可 QEMU proxy 輔助，但 NVIDIA 需實機或誠實 SKIP）

## 5. 技術參考

- Mint：`mintdrivers`（Python + apt）
- Ubuntu：`ubuntu-drivers` + `software-properties-gtk`
- Pop：System76 自動 NVIDIA（參考 UX，不複製程式碼）

## 6. 禁止

- 複製 legacy 封存程式碼
- 宣稱完整 Secure Boot 簽章支援
- worker 自宣稱 PASS
