# W5-GRT GDM/Greeter/Session 階段報告

| 任務 | w5-grt-session |
|------|----------------|
| 版本 | 0.4.1.32 |
| 日期 | 2026-07-05 |
| Worker | 階段 29/47（w5-grt-session） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

strawwu greeter 主題 — GRT0 GDM 登入畫面 StrawWU 品牌、GRT1 預設 session 銜接 strawwu-session、GRT2 live autologin 策略（build-iso 保留 casper ubuntu 使用者）。

## 交付物

| 類型 | 路徑 |
|------|------|
| greeter deb 套件 | `os-image/debs/strawwu-greeter/` |
| CLI + core | `usr/bin/strawwu-greeter`、`usr/lib/strawwu-greeter/core.py` |
| GDM dconf 預設 | `etc/gdm3/greeter.dconf-defaults` |
| Greeter CSS | `usr/share/gnome-shell/theme/strawwu-greeter.css` |
| Manifest | `usr/share/strawwu/greeter/greeter-manifest.yaml` |
| Live autologin 參考 | `usr/share/strawwu/greeter/live-autologin.conf.example` |
| target/install-init 整合 | `target-manifest.yaml`、`install-init-manifest.yaml` |
| chroot 建置 | `os-image/scripts/chroot-install-target-setup.sh` |
| Preflight | `tests/preflight/test-greeter-session.sh` |
| baseline JSON | `docs/plans/baselines/greeter-session-baseline.json` |
| Makefile | `test-greeter-session`；`preflight` 含本階段 |
| Observability | `docs/plans/strawwu-observability-debug-plan.md` — `greeter.log` |

## 功能摘要

| 項目 | 實作 |
|------|------|
| GRT0 主題 | `greeter.dconf-defaults`：`gtk-theme=StrawWU-Dark`、teal CSS overlay、distributor-logo.svg |
| GRT0 無 Ubuntu 文案 | greeter 檔案無 upstream 商標；manifest 僅保留 casper live 使用者技術參考 |
| GRT1 session | `strawwu-greeter apply` 設定 `DefaultSession=strawwu-session`；`strawwu-session` 已 GDM 註冊 + `GNOME_SHELL_SESSION_MODE=strawwu` |
| GRT2 live | `live-autologin.conf.example` + manifest 指向 `build-iso.sh`（`AutomaticLogin=ubuntu` 不變） |
| 單使用者 | `disable-user-list=true`（對齊 deferred-scope §1，不做 fast user switching UI） |
| lifecycle | `lifecycle.greeter` via strawwu-initd；log `/var/log/strawwu/greeter.log`；錯誤碼 `SWU-GR-001` |

## 驗收命令輸出（2026-07-05 UTC-4，worker 複驗）

### `make test-greeter-session` — exit 0（~0.7s，squashfs 同步後無 WARN）

Log: `/tmp/w5-grt-test-greeter-session.log`

```
=== W5-GRT greeter-session done: PASS ===
```

關鍵檢查（全 PASS，無 WARN）：

- 8 單元測試 PASS（manifest、dconf、CSS、dry-run/apply、CLI version）
- `strawwu-greeter_0.4.1.32_all.deb` 建置成功（9.7K）
- target-manifest / install-init-manifest 含 strawwu-greeter
- strawwu-session GDM 註冊 + strawwu shell mode
- CLI `--dry-run apply` + `version`
- **rootfs + squashfs** 均含 `StrawWU-Dark` greeter.dconf-defaults 與 `/usr/bin/strawwu-greeter`

### `make preflight` — exit 0（~168s）

Log: `/tmp/w5-grt-preflight.log`

含 W0–W5 全部階段 + **W5-GRT greeter-session** PASS；最終 W5-B4 disable-upstream-init 亦 PASS。

WARN（預期/環境）：W5-B4 `ubuntu-desktop` 仍留 rootfs/squashfs（過渡期 WARN，不阻斷 PASS）；greeter squashfs WARN 已於 chroot sync 修復後消除。

### 治本修復（本 worker）

**根因**：`chroot-install-target-setup.sh` 的 `sync_squashfs()` 同步 dpkg status 但未 rsync greeter 檔案，導致 squashfs 仍為 upstream greeter.dconf-defaults。

**修復**：於 `sync_squashfs()` 新增 `strawwu-greeter` CLI、`usr/lib/strawwu-greeter/`、`usr/share/strawwu/greeter/`、`etc/gdm3/greeter.dconf-defaults`、`strawwu-greeter.css` 同步；並手動 rsync rootfs→squashfs 驗證。

## 技術備註（治本）

1. **不複製 legacy greeter 二進位**：沿用 GDM + gnome-shell CSS/dconf overlay（計畫非目標 v0.5）。
2. **開發路徑 fallback**：`core.py` 在未安裝 deb 時從 package `usr/share/` 讀取模板，使 preflight dry-run 無需 chroot。
3. **session 雙層**：target-setup 仍保留 `configure_gdm_session`；greeter 套件 postinst/`apply` 再次確保 DefaultSession，安裝後 idempotent。
4. **squashfs 同步**：`sync_squashfs()` 現含 greeter 全套檔案，避免 dpkg status 已標安裝但 live ISO 仍顯示 upstream greeter。
5. **延後範圍**：未實作 fast user switching / 家庭帳號 UI；live ISO autologin 維持 build-iso 既有行為。

## 變更檔案清單

```
os-image/debs/strawwu-greeter/          (新套件)
tests/preflight/test-greeter-session.sh (新)
docs/plans/baselines/greeter-session-baseline.json (新)
docs/plans/stage-reports/W5-grt-session-report.md (本報告)
os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml
os-image/debs/strawwu-install-init/usr/share/strawwu/install-init/install-init-manifest.yaml
os-image/scripts/chroot-install-target-setup.sh
docs/plans/strawwu-observability-debug-plan.md
Makefile
VERSION (0.4.1.31 → 0.4.1.32)
```

## 建議 commit message

```
feat(w5): add strawwu-greeter GDM theme and session defaults

- GRT0 StrawWU-Dark greeter dconf + teal CSS overlay
- GRT1 DefaultSession=strawwu-session via strawwu-greeter apply
- GRT2 live autologin documented; build-iso unchanged
- Integrate into target/install-init manifests + preflight

Tests: make test-greeter-session PASS; make preflight PASS
Issue: w5-grt-session v0.4.1.32
```

## 待 Hermes / 後續

| 項目 | 狀態 |
|------|------|
| Hub wincompat 分頁即時 session | 可於 w6 階段評估 |
| GDM 視覺 E2E 截圖 | 待 release-iso boot-test（非本 stage 硬性閘門） |

**w6-n5-install-e2e**（Hermes mark PASS 後自動啟動，勿問使用者）。
