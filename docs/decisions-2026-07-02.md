# StrawWU v3.0-cleanroom — 使用者決策鎖定

| 欄位 | 值 |
|------|-----|
| 日期 | 2026-07-02 |
| 來源 | 使用者對完整計畫報告 Q1–Q9 回覆 |
| 狀態 | **LOCKED**（Q1 除外，見下） |

## Q1 — v3.0 預發布最小交付範圍

**決策：DEFERRED（使用者另行提出時定案）**

0.3.0-cleanroom 全階段完成後，預發布 ISO 的最小集合**不在本次鎖定**；待使用者主動提出時再定案 A/B/C/D。

## Q2 — Tier 4（VFIO + microvm Windows guest）

**決策：A — 納入企業/進階選項（Phase 6.12 實作 PoC）**

- 開放 Tier 4 產品路線；保留規格章節
- Phase 6.12 實作 VFIO 直通 PoC（實驗性，compat 等級 C/F）

## Q3 — 印表機 MVP 支援範圍

**決策：B — 列印 + 掃描一體（MFP）**

- device-proxy D3 須涵蓋 CUPS 列印與掃描（SANE/IPP）映射
- 工作量大；誠實標 PARTIAL 起步

## Q4 — 裝置代理預設權限模型

**決策：A — 預設開放（同 Windows 桌面體驗）**

- Win app 存取 COM/USB/印表機預設允許
- Hub 可提供進階限制覆寫（非預設）

## Q5 — USB 自訂 IOCTL device_profile

**決策：A — 開放社群 JSON profile PR + compat-db 登記**

- `components/strawwu-device-proxy/profiles/` 接受 PR
- CI 驗證 schema；compat-db 登記 Tier 2 裝置

## Q6 — CI self-hosted runner（kernel build）

**決策：A — 配置 self-hosted runner**

- Phase 2 起 kernel 完整編譯走 self-hosted
- `.github/workflows/kernel-build.yml` 須標 `runs-on: self-hosted`

## Q7 — 反作弊「相容」定義

**決策：升級標準 — 應用可正常運行**

| 層級 | 定義 |
|------|------|
| 最低 | 探測不立即退出 |
| **目標（已鎖定）** | **應用可正常運行**（UI/主流程可操作） |
| 不承諾 | 線上排位、反作弊完全繞過 |

Hub 顯示等級；矩陣 CI 以「可正常運行」為 Phase 6.7 驗收門檻（誠實 PARTIAL 仍適用）。

## Q8 — 黃金回歸清單（Phase 6 首批）

**決策：以下優先（啟動器類僅驗啟動，不驗遊玩）**

| 優先 | App | 驗收範圍 |
|------|-----|----------|
| P0 | Microsoft Office 類 | 可啟動、基本文件操作 |
| P0 | Steam 啟動器 | 可啟動、登入 UI（不玩遊戲） |
| P0 | Epic Games 啟動器 | 可啟動、登入 UI（不玩遊戲） |
| P0 | 三角洲行動啟動器 | **僅啟動器**（不驗遊戲本體） |

清單檔：`components/tests/wincompat/golden-apps.json`

## Q9 — 正式版目標版本號

**決策：1.0.0**

- 目標 semver：`1.0.0`（寫入 `.official-release-target`）
- **尚未授權發布**；Phase 7 仍 BLOCKED 直到全階段 PASS + 使用者明示「可發正式版」
- 授權時須建立 `.official-release-authorized`（含日期與 `1.0.0`）

## 影響摘要

| 區域 | 變更 |
|------|------|
| Phase 6.11 | MFP 掃描納入 D3；預設開放裝置權限 |
| Phase 6.12 | Tier 4 PoC **實作**（非僅文件） |
| Phase 6.7 | 反作弊驗收升級為「可正常運行」 |
| Phase 2 CI | self-hosted kernel build |
| compat-db | 社群 device_profile PR 流程 |
| official-release | 目標 `1.0.0` |
