# StrawWU 深色主題策展（post-ux-theme-curation）

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-06 |
| 對標 | Zorin dark · Pop dark mode |
| 差距 ID | B14（對比書 v4/v5） |
| Stage | `post-ux-theme-curation` |

## 1. 現況

- 繼承 GNOME 預設 light/dark 切換
- 無 StrawWU 品牌配色深色主題包
- HiDPI 縮放仍待 HW T2 實機驗證

## 2. 目標

- `strawwu-gtk-theme` + `strawwu-icon-theme` 深色變體
- firstboot 或 Hub 設定：預設深色（可切淺色）
- 與 `strawwu-colors.md` Teal 進度條色一致
- gsettings override 於 `strawwu-session`

## 3. PASS 條件

```bash
make test-ux-theme-curation
make preflight
```

## 4. 交付物

- `os-image/config/branding/themes/`
- `strawwu-desktop-meta` 依賴更新
- `docs/plans/stage-reports/POST-UX-theme-curation-report.md`
