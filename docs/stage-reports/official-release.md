# Stage Report — official-release (Phase 8/8)

**版本目標**: 1.0.0  
**當前 semver**: 0.3.0.0  
**階段**: 8/8 (official-release)  
**日期**: 2026-07-04  
**最後檢查**: 2026-07-04T03:35 UTC-4 (worker-TICK)  
**狀態**: BLOCKED — 待使用者授權

---

## 阻塞原因

本階段為最終正式版發布，設計上 BLOCKED 直到以下條件全部滿足：

| # | 條件 | 狀態 | 說明 |
|---|------|------|------|
| 1 | Phase 0（skeleton）PASS | ✅ | 已通過 |
| 2 | Phase 1（ubuntu-clone）PASS | ✅ | 已通過 |
| 3 | Phase 2（custom-kernel）PASS | ✅ | 已通過 |
| 4 | Phase 3（calamares-e2e）PASS | ✅ | 已通過 |
| 5 | Phase 4（greenfield）PASS | ✅ | 已通過 |
| 6 | Phase 5（hub）PASS | ✅ | 已通過 |
| 7 | Phase 6（wincompat）PASS | ✅ | 已通過（122 unit tests，所有子階段 PARTIAL） |
| 8 | **使用者明確授權正式版** | ❌ | `.official-release-authorized` 不存在 |

---

## 驗證命令狀態

| 驗證命令 | 結果 | 說明 |
|---------|------|------|
| `test -f .official-release-authorized` | ❌ BLOCKED | 使用者尚未授權 |
| `make build-iso` | ⏸ 未執行 | 等待授權後以 VERSION=1.0.0 建置 |
| `make test-install-e2e` | ⏸ 未執行 | 等待 ISO 建置完成 |
| `sha256sum -c SHA256SUMS` | ⏸ 未執行 | 等待 ISO 產出 |

---

## 解除阻塞所需動作

使用者須明確表達「可發正式版」，worker 將執行以下流程：

1. 建立 `.official-release-authorized` 標記檔
2. 設定 `VERSION=1.0.0` 並更新所有版本引用
3. `make build-iso`（release-iso 模式，xz 壓縮）
4. 產出 `SHA256SUMS` 並驗證
5. `make test-install-e2e`（BIOS + UEFI 雙韌體）
6. 產出 boot/install 證據 JSON
7. HTML 報告 hermes-deliver
8. 建議 Hermes trigger-verify

---

## 版本政策參照

- `.official-release-target` 內容：`1.0.0`
- `docs/versioning.md`：MAJOR >= 1 僅在使用者明確通知後
- Makefile `VERSION ?= 0.3.0.0`
- Preflight 閘門：檢查 MAJOR=0 除非 `STRAWWU_OFFICIAL_RELEASE=1` 且 `.official-release-authorized` 存在

---

## 技術就緒度（供使用者參考）

所有 7 個前置階段已通過，元件基礎已建立：

- **OS 基礎**: Ubuntu Noble clone + 自訂 kernel + Calamares 安裝器
- **元件**: 8 crates（runtime/bridge/nt/graphics/audio/anticheat/device-proxy/launcher），122 unit tests
- **Windows 相容層**: 所有 13 個子階段 PARTIAL（stub/mock 層，尚未接入真實 Windows 二進位）
- **裝置代理**: 10 類裝置映射 + IOCTL handler
- **圖形棧**: Vulkan ICD + DXGI + OpenGL WGL + D3D11→VK
- **反作弊**: EAC/BE C 級、Vanguard F 級

---

## Q 系列路線圖注意事項

Phase 6 的所有子階段均為 PARTIAL 狀態（誠實報告），以下 Q 項目在正式版前可能需要進一步迭代：

| Q | 項目 | 當前狀態 |
|---|------|----------|
| Q7 | 反作弊驗收=可正常運行 | EAC/BE C 級、Vanguard F 級 |
| Q8 | Office/Steam/Epic/三角洲啟動器 | stub 基礎完成 |
| Q1 | 預發布範圍 | 待使用者另行提出 |

---

## 產品決策阻塞

**是，本階段存在產品決策阻塞：需要使用者明確授權才能進行正式版發布。**

在使用者授權前，worker 不會：
- 將 MAJOR 版本號設為 >= 1
- 建置正式版 ISO
- 推送任何 release tag

**等待使用者指示。**
