# StrawWU Hardware Compatibility 實機相容性計畫

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-04 |

## 1. 問題

現有 DoD 偏重 QEMU BIOS/UEFI；桌面 OS 須實機矩陣避免「只在虛擬機自嗨」。

## 2. 測試分級

| Tier | 環境 | 必要性 |
|------|------|--------|
| T0 | QEMU virtio | CI 必跑 |
| T1 | 實機 USB Live 開機 | beta 必跑 |
| T2 | 實機安裝 + 日常使用 24h | stable 必跑 |
| T3 | 遊戲 / Windows compat 實機 | v0.6+ |

## 3. 硬體矩陣維度

| 類別 | 測試項 | 最低覆蓋 |
|------|--------|----------|
| CPU | Intel 12th+ / AMD Zen3+ | 各 1 台 |
| GPU | Intel iGPU / AMD / NVIDIA | 各 1 台 |
| Wi-Fi / BT | Intel AX / Realtek / Broadcom | 2 晶片 |
| 音效 | 內建 + USB 耳機 | PASS mic+spk |
| 輸入 | 觸控板 / Fn / 外接鍵鼠 | 1 筆電 |
| 顯示 | 多螢幕 / HiDPI 150–200% | 1 組 |
| 電源 | suspend / resume | 3 次循環 |
| 儲存 | NVMe / SATA / USB 安裝碟 | 各 1 |
| 韌體 | Legacy BIOS / UEFI / SB off | 各 1 |
| 輸入法 | 繁中 fcitx5 / ibus | 打字測試 |
| 列印 | CUPS 網路印表機 | 1 台 |

## 4. 記錄格式

`docs/plans/hw-matrix-results.json`：

```json
{"machine_id":"...", "gpu":"...", "tests":{"wifi":"PASS","suspend":"FAIL","notes":"..."}}
```

## 5. Phase HW0–HW5

| Phase | 工作 |
|-------|------|
| HW0 | 矩陣模板 + 測試腳本 `tests/hw/smoke-live.sh` |
| HW1 | 實機 Live USB 清單（≥3 台） |
| HW2 | 安裝後 smoke（網路/音效/顯示） |
| HW3 | suspend/resume + HiDPI |
| HW4 | 列印 + 輸入法 |
| HW5 | beta release gate：≥80% 矩陣 PASS |

## 6. USB 安裝碟相容

- 測試：Rufus / dd / Ventoy 各 1
- 驗證：UEFI + Legacy 可開機
