# W5-N3 firstboot 階段報告

| 任務 | w5-n3-firstboot |
|------|-----------------|
| 版本 | 0.4.1.22 |
| 日期 | 2026-07-05 |
| Worker | 階段 22/47（w5-n3-firstboot） |
| 結果 | **待 Hermes mark** |

## 目標

GTK4 + libadwaita 六步精靈：安裝後首次登入引導使用者完成語言、隱私同意、Flathub 說明、Windows 相容導覽，並透過 `strawwu-initd` 寫入 `lifecycle.firstboot`。

## 交付物

| 類型 | 路徑 |
|------|------|
| firstboot deb | `os-image/debs/strawwu-firstboot/` |
| 核心邏輯 | `usr/lib/strawwu-firstboot/core.py` |
| GTK4 精靈 | `usr/lib/strawwu-firstboot/wizard_gtk4.py` |
| i18n | `usr/lib/strawwu-firstboot/i18n.py`、`usr/share/strawwu/locale/firstboot.{en,zh_TW}.yaml` |
| manifest | `usr/share/strawwu/firstboot/firstboot-manifest.yaml` |
| autostart | `etc/xdg/autostart/strawwu-firstboot.desktop` |
| desktop 入口 | `usr/share/applications/strawwu-firstboot.desktop` |
| 單元測試 | `tests/test-firstboot.py`（7 tests） |
| Preflight | `tests/preflight/test-firstboot.sh` |
| baseline | `docs/plans/baselines/firstboot-baseline.json` |
| Makefile | `test-firstboot`；`preflight` 含本階段 |
| Desktop 整合 | `strawwu-desktop` Depends `strawwu-firstboot` |
| Target staging | `target-manifest.yaml` + `chroot-install-target-setup.sh` |

## 六步精靈（對齊 UX wireframe）

| 步驟 | ID | 內容 |
|------|-----|------|
| 1 | welcome | StrawWU 歡迎與精靈說明 |
| 2 | language | zh_TW / en_US 介面語言選擇 |
| 3 | privacy | 隱私政策 + EULA 連結；bug 上傳 / 使用統計 **預設關閉** opt-in |
| 4 | flathub | Flathub 第三方應用說明 |
| 5 | desktop | Hub 與 Windows 相容模式導覽 |
| 6 | finish | 完成並寫入 `lifecycle.firstboot=done` |

## 功能摘要

| 項目 | 實作 |
|------|------|
| UI 框架 | GTK4 + libadwaita `AdwAssistant` |
| 生命週期 | `strawwu-initd set lifecycle.firstboot` running → done |
| 結構化 log | `/var/log/strawwu/firstboot.log` JSON lines |
| 錯誤碼 | SWU-FB-001（crash）、SWU-FB-003（state mismatch） |
| 偏好設定 | `/var/lib/strawwu/setup/firstboot-prefs.json` |
| 自動啟動 | session autostart `strawwu-firstboot run --autostart` |
| 本地化 | 繁中 + 英文 YAML 字串（禁止硬編 UI） |
| 延後範圍 | 僅 primary 使用者；無家庭帳號精靈（deferred-scope §1） |

## 變更檔案清單

```
os-image/debs/strawwu-firstboot/          (新增)
tests/preflight/test-firstboot.sh         (新增)
docs/plans/baselines/firstboot-baseline.json (新增)
os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml
os-image/debs/strawwu-desktop/debian/control
os-image/debs/strawwu-desktop/tests/test-meta.py
os-image/scripts/chroot-install-target-setup.sh
Makefile
VERSION (0.4.1.21 → 0.4.1.22)
```

## 驗收命令輸出（2026-07-05 UTC-4）

### `make test-firstboot` — exit 0（~0.9s）

Log: `/tmp/w5-n3-test-firstboot.log`

```
Ran 7 tests in 0.296s — OK
firstboot dry-run: OK (6 steps)
=== W5-N3 firstboot done: PASS ===
```

關鍵檢查：六步 manifest、GTK4/libadwaita Depends、initd 整合、deb 打包、CLI dry-run、baseline 寫入。

### `make preflight` — exit 0（~109s）

Log: `/tmp/w5-n3-preflight.log`

含 W0–W4 全部階段 + **W5-N3 firstboot**（最終行 `=== W5-N3 firstboot done: PASS ===`，整體 EXIT: 0）。

## 技術備註（治本）

1. **initd 為唯一 state 來源**：精靈不直接寫 state.json，一律呼叫 `strawwu-initd`，避免與 target-setup / boot-selfcheck 分叉。
2. **core / GTK 分層**：preflight 與單元測試走 `--dry-run`，無需 DISPLAY 或 gi；實機 GTK4 由 deb Depends 保證。
3. **隱私預設關**：對齊 deferred-scope §3 與 SEC 模型；bug 上傳 opt-in 與 W2-B2 consent 一致。
4. **target 合流**：firstboot deb 納入 target-manifest staged-debs，安裝後 autostart 觸發一次。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| Calamares/firstboot gettext .qm | 待 **w5-n4-finished-meta** |
| GTK4 實機 Playwright / ISO E2E | 待 **w6-n5-install-e2e** |
| rootfs 內 firstboot deb 安裝 | 需 `sudo bash os-image/scripts/chroot-install-target-setup.sh` |
| 家庭帳號精靈 | deferred v1.0+ |

## VERSION

`0.4.1.21` → `0.4.1.22`（iterate）

## 建議 commit message

```
feat(w5): add strawwu-firstboot GTK4 six-step wizard

- AdwAssistant wizard: welcome, language, privacy, Flathub, desktop, finish
- strawwu-initd lifecycle integration, structured firstboot.log, zh_TW/en i18n
- autostart desktop, target-manifest staging, test-firstboot preflight
Tests: make test-firstboot PASS, make preflight PASS
Version: 0.4.1.22
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T07:29:00-0400 | `[worker-START]` w5-n3-firstboot |
| 2026-07-05T07:31:00-0400 | `[worker-DONE]` test-firstboot + preflight exit 0 — 待 Hermes mark PASS |

## 下一階段

**w5-n4-finished-meta**（Hermes mark PASS 後自動啟動，勿問使用者）。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-firstboot
make preflight
```
