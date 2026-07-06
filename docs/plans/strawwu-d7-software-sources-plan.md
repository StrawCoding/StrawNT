# StrawWU 軟體源管理（post-d7-software-sources）

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-06 |
| 對標 | Linux Mint `mintsources` · Ubuntu `software-properties-gtk` |
| 差距 ID | D7（對比書 v4/v5） |
| Stage | `post-d7-software-sources` |

## 1. 現況

- 自有 APT repo（`w7-re-apt-repo`）已 PASS
- 缺少 GUI 管理 PPA / 第三方源 / StrawWU repo 開關
- 使用者需手動編輯 `/etc/apt/sources.list.d/`

## 2. 目標

新建 `strawwu-software-sources`：
- Hub 分頁或獨立 GTK4 視窗
- 列出：StrawWU official repo、Flathub（唯讀）、Ubuntu security（唯讀）
- 啟用/停用第三方源（需 polkit）
- 與 `strawwu-update-notifier` 整合「檢查更新」

## 3. PASS 條件

```bash
make test-software-sources
make preflight
```

## 4. 交付物

- `os-image/debs/strawwu-software-sources/`
- Hub 導覽入口
- `docs/plans/stage-reports/POST-D7-software-sources-report.md`
