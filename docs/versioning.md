# StrawWU 版本政策

| 欄位 | 值 |
|------|-----|
| 生效日期 | 2026-07-02 |
| 決策來源 | 使用者明確指示 |

## Semver 規則

格式：`MAJOR.MINOR.PATCH`（可選 `-qualifier`，例如 `-cleanroom`、`-phase1`）。

### 正式版之前（預設狀態）

- **MAJOR 必須為 `0`**（`MAJOR >= 1` 禁止）
- 範例：`0.3.0-cleanroom`、`0.3.1`、`0.4.0-phase6`
- ISO 檔名：`StrawWU-<version>-amd64.iso`（例：`StrawWU-0.3.0-cleanroom-amd64.iso`）
- Git tag：`v0.3.0-cleanroom`、`v0.3.0-cleanroom-components` 等

### 正式版

- **僅在使用者明確通知後**才可將 `MAJOR` 設為 `>= 1`
- Hermes / worker **不得**自行宣稱正式版或 bump major
- 正式版發布須同時滿足：
  1. 使用者書面/對話確認「可發正式版」及目標版本號
  2. ISO + SHA256SUMS + `sha256sum -c`
  3. boot/install 證據 JSON
  4. HTML 報告 hermes-deliver
  5. CI 綠燈（若已配置）

### 計畫代號 vs 版本號

| 概念 | 值 | 說明 |
|------|-----|------|
| 計畫代號 | `v3.0-cleanroom` | 架構路線名稱，**不是** semver |
| 當前 semver | `0.3.0-cleanroom` | 實際產物版本號 |
| 正式版 semver | **1.0.0**（目標，見 `.official-release-target`） | Q9 鎖定；授權前 MAJOR 仍須為 0 |

## 環境變數

- `STRAWWU_VERSION` — 覆寫建置版本（須符合 MAJOR=0 政策，除非已獲正式版授權）
- `Makefile`：`VERSION ?= 0.3.0-cleanroom`

## Preflight 檢查

`make preflight` 會驗證 `VERSION` / `STRAWWU_VERSION` 的 MAJOR 為 `0`（除非設 `STRAWWU_OFFICIAL_RELEASE=1` 且存在 `.official-release-authorized` 標記檔）。

## Worker 階段版本

各 phase 的 `version` 欄位使用當前 semver（`0.3.0-cleanroom`）。最終 `official-release` 階段在通過前保持 **BLOCKED**，等待使用者授權。
