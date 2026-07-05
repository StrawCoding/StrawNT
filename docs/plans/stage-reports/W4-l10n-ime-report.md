# W4-L10N 繁中輸入法階段報告

| 任務 | w4-l10n-ime |
|------|-------------|
| 版本 | 0.4.1.21 |
| 日期 | 2026-07-05 |
| Worker | 階段 21/47（w4-l10n-ime） |
| 結果 | **待 Hermes mark** |

## 目標

fcitx5 + 繁中本地化（L10N1）：注音/倉頡輸入法、Noto Sans CJK 字型、zh_TW 預設 locale、Live/target 可切換輸入。

## 交付物

| 類型 | 路徑 |
|------|------|
| IME deb 套件 | `os-image/debs/strawwu-l10n-ime/` |
| IME manifest | `usr/share/strawwu/l10n-ime/ime-manifest.yaml` |
| Locale 政策 | `usr/share/strawwu/l10n-ime/locale-policy.yaml` |
| fcitx5 預設 profile | `usr/share/fcitx5/default/conf/profile`、`etc/xdg/fcitx5/conf/profile` |
| 系統 IME 環境 | `etc/environment.d/95-strawwu-ime.conf` |
| Session IME export | `os-image/debs/strawwu-session/usr/bin/strawwu-session` |
| Calamares locale | `locale.conf` → 預設 `zh_TW.UTF-8`，支援 `en_US.UTF-8` |
| Desktop 整合 | `strawwu-desktop` Depends `strawwu-l10n-ime`；移除 `ibus` |
| Target manifest | `target-manifest.yaml` 新增 `strawwu-l10n-ime` |
| Chroot staging | `chroot-install-target-setup.sh` 建置/暫存新 deb |
| 單元測試 | `os-image/debs/strawwu-l10n-ime/tests/test-l10n-ime.py`（6 tests） |
| Preflight | `tests/preflight/test-l10n-ime.sh` |
| baseline | `docs/plans/baselines/l10n-ime-baseline.json` |
| Makefile | `test-l10n-ime`；`preflight` 含本階段 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| 輸入法框架 | fcitx5（im-config 預設 fcitx5） |
| 注音 | fcitx5-chewing，profile 預設 IM |
| 倉頡 | fcitx5-table-cangjie5 |
| 字型 | fonts-noto-cjk（Noto Sans TC 等 CJK） |
| GTK/Qt/Wayland | fcitx5-frontend-gtk3/4、qt5/6、module-wayland |
| 環境變數 | `GTK_IM_MODULE`/`QT_IM_MODULE`/`XMODIFIERS`/`SDL_IM_MODULE` = fcitx |
| 預設 locale | Calamares `zh_TW.UTF-8`（保留 en_US） |
| 語言包 | Recommends `language-pack-zh-hant`、`language-pack-gnome-zh-hant` |
| ibus 移除 | strawwu-desktop 不再 Recommends ibus |

## 變更檔案清單

```
os-image/debs/strawwu-l10n-ime/          (新增)
tests/preflight/test-l10n-ime.sh         (新增)
docs/plans/baselines/l10n-ime-baseline.json (新增)
os-image/debs/strawwu-desktop/debian/control
os-image/debs/strawwu-desktop/tests/test-meta.py
os-image/debs/strawwu-session/usr/bin/strawwu-session
os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml
os-image/debs/strawwu-calamares-settings/etc/calamares/modules/locale.conf
os-image/config/calamares-installer/etc/calamares/modules/locale.conf
os-image/scripts/chroot-install-target-setup.sh
Makefile
VERSION (0.4.1.20 → 0.4.1.21)
```

## 驗收命令輸出（2026-07-05T07:16–07:17 UTC-4）

### `make test-l10n-ime` — exit 0

Log: `/tmp/w4-l10n-test-l10n-ime.log`

```
=== W4-L10N l10n-ime preflight ===
…（38 項 PASS）…
=== W4-L10N l10n-ime done: PASS ===
```

關鍵檢查：fcitx5-chewing/cangjie5/noto-cjk Depends、profile DefaultIM=chewing、desktop Depends strawwu-l10n-ime、無 ibus、calamares zh_TW 預設、6 單元測試 PASS、`strawwu-l10n-ime_0.4.1.21_all.deb`（1.9K）建置成功。

### `make preflight` — exit 0（~45s）

Log: `/tmp/w4-l10n-preflight.log`

含 W0 baseline + W1–W3 全部階段 + W4-D2/D3/R2/F3/W1 + **W4-L10N l10n-ime** exit 0（最終行 `=== W4-L10N l10n-ime done: PASS ===`）。

## 技術備註（治本）

1. **獨立 deb 而非 inline 依賴**：`strawwu-l10n-ime` 封裝 fcitx5 依賴鏈、profile、environment.d 與 manifest，桌面 meta 僅 Depends 此套件，避免 control 檔膨脹且利於 L10N3 安裝後驗收追蹤。
2. **三層 IME 環境**：`environment.d`（全系統）、`strawwu-session` export（登入 session）、fcitx5 profile（引擎清單），確保 GTK/Qt/Wayland 應用一致走 fcitx5。
3. **Calamares locale 預設 zh_TW**：對齊 PRD 繁中目標使用者；en_US 仍列於 locales 供切換。
4. **移除 ibus**：避免與 fcitx5 雙框架衝突；im-config 改由 strawwu-l10n-ime Depends 提供。

## 未完成 / 後續 Wave

| 項目 | 負責 Wave |
|------|-----------|
| Calamares/firstboot gettext .qm 覆寫 | W5-N4 finished-meta |
| 安裝後 target IME boot 驗收 | L10N3 / W6-I4 |
| chroot 實際安裝 fcitx5 至 squashfs | 需 `sudo make install-target-setup`（非本階段硬性閘門） |

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-l10n-ime
make preflight
```

## Commit message（建議）

```
feat(w4): add strawwu-l10n-ime fcitx5 + zh_TW locale stack

- fcitx5 chewing/cangjie5, Noto CJK, environment.d + session exports
- Calamares default locale zh_TW.UTF-8; desktop Depends strawwu-l10n-ime
- Remove ibus from strawwu-desktop; stage deb in target-setup chroot
Tests: make test-l10n-ime PASS, make preflight PASS
Version: 0.4.1.21
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T07:12 UTC-4 | `[worker-START]` companion supervisor started |
| 2026-07-05T07:13 UTC-4 | `[worker-TICK]` tick168: w4-l10n-ime IN_PROGRESS |
| 2026-07-05T07:16 UTC-4 | `make test-l10n-ime` exit 0（38 項 PASS） |
| 2026-07-05T07:17 UTC-4 | `make preflight` exit 0（~107s，含 W4-L10N 最終 PASS） |
| 2026-07-05T07:17 UTC-4 | `[worker-DONE]` 階段 21/47 終驗完成 — **待 Hermes mark PASS** |

## 下一階段

**w5-n3-firstboot**（Hermes mark PASS 後自動啟動，勿問使用者）。
