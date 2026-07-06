# StrawWU 安裝器進階（LUKS + 雙系統）

| 版本 | 1.0 |
|------|-----|
| 對照維度 | C7 LUKS、C8 雙系統偵測 |
| Stage | `post-i2-calamares-luks` |

## 目標

1. Calamares LUKS 全碟/分割加密路徑獨立 E2E（QEMU 或實機）
2. 雙啟動（Windows/macOS 共存）偵測與使用者文案（strawwu-calamares-settings）
3. `tests/install-e2e/` 新增 luks / dualboot scenario marker

## 驗收

`make test-calamares-luks-dualboot` + stage report
