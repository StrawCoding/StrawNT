# 版本規格

StrawWU 採用四位版本號 `a.b.c.d`：

| 位置 | 名稱 | 說明 |
|------|------|------|
| a | Major | 重大架構變更或正式授權發布（0 = 預授權階段） |
| b | Minor | 功能里程碑（對應 Phase 或 Quarter） |
| c | Patch | 修正、改善、非破壞性更新 |
| d | Preview | 預覽版本號；`0` = 正式版，`≥1` = 預覽版 N |

## 範例

| 版本 | 意義 |
|------|------|
| `0.3.0.0` | v0.3.0 正式版（Phase 0–7 完成） |
| `0.3.1.1` | v0.3.1 第一個預覽版 |
| `0.3.1.2` | v0.3.1 第二個預覽版 |
| `0.3.1.0` | v0.3.1 正式版 |
| `1.0.0.0` | v1.0.0 正式授權發布（Q9 目標） |

## 檔案對照

| 檔案 | 格式 | 說明 |
|------|------|------|
| `VERSION` | `a.b.c.d` | 唯一真實來源（Single Source of Truth） |
| `components/Cargo.toml` | `a.b.c` 或 `a.b.c-preview.d` | Cargo semver 限制 |
| `hub/package.json` | `a.b.c.d` | npm 允許任意字串 |
| Git tag | `va.b.c.d` | 例如 `v0.3.0.0` |
| ISO 檔名 | `StrawWU-a.b.c.d-amd64.iso` | |

## 規則

1. `d=0` 為正式版，`d≥1` 為預覽版（功能不完整或未經完整驗證）
2. 版本遞增時由 `VERSION` 檔案統一修改，其餘檔案同步
3. 每次 release 必須有對應 git tag
4. Preview 版不產正式 release 報告，但須有 boot-test 通過
