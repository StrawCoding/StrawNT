# StrawWU Windows 相容分級指南

本指南（**DOC2**）說明 StrawWU 如何標示 Windows 應用與遊戲的相容等級，以及使用者應如何解讀 Hub 與 CLI 輸出。對齊 `compat-db` 與 `components/specs/anticheat-compat.md`。

## 1. 誠實原則

「相容」在 StrawWU v0.5 **不等於**「與 Windows 完全相同」或「可排位對戰」。定義為：

- 應用可啟動或在探測階段不立即崩潰
- Hub／compat-db 標示**明確等級**（A/B/C/F）
- 反作弊驗收標準（Q7）：**可正常運行**（非通過官方簽章驗證）

## 2. 相容等級

| 等級 | 含義 | 使用者預期 |
|------|------|------------|
| **A** | 可玩／可日常使用 | 功能大致完整，可作為主力環境 |
| **B** | 可啟動 | 可進入主畫面或啟動器；部分功能受限 |
| **C** | 探測通過 | 反作弊或驅動探測未立即失敗；遊戲體驗不保證 |
| **F** | 崩潰或拒絕 | 無法可靠啟動；Hub 會標示風險 |

等級由 CI 矩陣（`tests/anticheat-matrix/`、golden-apps）與執行時探測更新；Hub「Windows 相容」頁面顯示摘要。

## 3. 查看狀態

### 3.1 終端

```bash
strawwu status
```

顯示 SubsystemSession 狀態、已載入 profile、compat 摘要。

```bash
strawwu apps list
```

列出已登記 Windows 應用與等級（若 compat-db 有對應項目）。

### 3.2 Hub

開啟 Hub → **Windows 相容**：

- Session 狀態（native 預設）
- 相容等級列表（A/B/C/F）
- 無資料時顯示「尚無等級資料」（誠實空狀態）

## 4. 執行後端（Phase 6）

| 後端 | 用途 | v0.5 預設 |
|------|------|-----------|
| **native** | 共享 SubsystemSession；app 互通／協作 | **是** |
| container | 覆寫隔離（syscall profile 等） | 僅必要時 |
| microvm | VFIO／高隔離（Tier4 PoC） | Phase 6.12 |

日常應用、單機遊戲、啟動器＋本體協作使用 **native**。EAC／BattlEye 等優先 native；必要時 container + `syscall_profile: anticheat`。

> **禁止：** WinBox／strawwu-box（v3.0 cleanroom 政策）。

## 5. 反作弊與常見案例

| 反作弊 | v0.5 策略 | 典型等級 |
|--------|-----------|----------|
| 無／輕量 | native | A–B |
| EasyAntiCheat | 驅動 stub + 完整性回應 | B–C |
| BattlEye | syscall 攔截 + 假驅動介面 | B–C |
| Vanguard 等核心模式 | microvm 或 policy 拒絕 | F（受限） |

**Q7 驗收：** 反作弊案例可正常運行（程序不立即崩潰），非宣稱通過官方驗證。

## 6. 安裝 Windows 應用

1. 使用 `strawwu` CLI 或 Hub 引導選擇安裝程式。
2. 安裝完成後登記至 User App Registry（與 compat-db 分離）。
3. 查閱等級；**F 級**仍允許嘗試，但 Hub 會警告。

移除：Hub Apps 頁 deep uninstall，或 registry CLI。

## 7. Q8 黃金應用（啟動器驗收）

v0.5 路線包含下列**啟動器**層級驗收（不保證完整功能）：

- Microsoft Office
- Steam
- Epic Games
- 三角洲行動啟動器

完整遊戲內容與線上功能依 compat 等級而定。

## 8. 誠實邊界摘要

| 項目 | v0.5 |
|------|------|
| 所有 Windows 軟體 | **不保證** |
| 官方反作弊簽章 | **不通過** |
| 排位／線上對戰 | **不保證** |
| 裝置驅動代理 | Q4 預設開放；個別裝置見 compat C/F |
| 社群 device_profile PR | Q5 路線 |

## 9. 相關文件

- [user-handbook.md](user-handbook.md) §3.3、§2.4
- [admin-handbook.md](admin-handbook.md) §9
- `components/specs/anticheat-compat.md`
- `components/specs/execution-backends.md`
