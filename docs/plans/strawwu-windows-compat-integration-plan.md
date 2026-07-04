# StrawWU Windows Compat 整合計畫

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-04 |
| 對齊 | `docs/phase-roadmap.md` Phase 6、`components/specs/*` |

## 1. 定位

Windows compat 是 StrawWU 核心賣點；主計畫須有獨立工作流 **W**，與 App Registry、Hub、firstboot 合流。

## 2. 現況（2026-07-04）

- Phase 6.1–6.12：367 cargo tests PASS（FUNCTIONAL/PASS）
- **缺口**：桌面圖示、Registry 整合、Hub UI、install E2E、launcher 與 session 未進 OS 映像

## 3. 工作流 W0–W6

| Phase | 工作 | DoD |
|-------|------|-----|
| W0 | runtime baseline in rootfs | `strawwu status` 在 Live 可跑 |
| W1 | launcher + Registry integration | `strawwu run` 註冊 AppRecord |
| W2 | filesystem mapping（prefix/VFS） | 安裝 exe 到 `~/.strawwu/win/` |
| W3 | process lifecycle + session | 多 app 同 session smoke |
| W4 | GUI app smoke（notepad 等） | 視窗出現在 Mutter |
| W5 | uninstall / sandbox / permissions | Registry remove + prefix 清理 |
| W6 | E2E：install → 桌面 icon → 啟動 → 移除 | Playwright/CLI 證據 |

## 4. 與其他工作流合流

| 合流點 | 說明 |
|--------|------|
| R1/R4 | Windows app 寫入 App Registry |
| D3 Hub | 「Windows 相容」分頁：session 狀態、compat grade |
| N3 firstboot | 步驟 5 導覽 Windows compat |
| SEC4 | session 隔離審計 |
| HW T3 | 實機遊戲 smoke（誠實 PARTIAL） |

## 5. 禁止事項

- 不宣稱完整 Windows 相容
- 不載入 Windows .sys
- Vanguard grade=F 為設計邊界

## 6. 測試

- `make test-wincompat` CI 必跑
- ISO E2E：`tests/e2e/wincompat-smoke.sh`
- compat-matrix.json 隨 release 發布
