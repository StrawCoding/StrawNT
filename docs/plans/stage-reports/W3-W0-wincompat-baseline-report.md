# W3-W0 Windows Compat OS Baseline 階段報告

| 任務 | w3-w0-wincompat-baseline |
|------|---------------------------|
| 版本 | 0.4.1.15 |
| 日期 | 2026-07-05 |
| Worker | 階段 15/47（w3-w0-wincompat-baseline） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |
| Companion | `[worker-TICK]` 2026-07-05T05:34:12-0400 Hermes 續跑 → 2026-07-05T05:36-0400 終驗完成 |

## 目標

rootfs 納入 strawwu CLI + status — Live ISO 上可執行 `strawwu status`（Wave W0 DoD）。

## 交付物

| 類型 | 路徑 |
|------|------|
| deb 套件 | `os-image/debs/strawwu-wincompat/` |
| CLI | `/usr/bin/strawwu`（由 `strawwu-launcher` cargo release 建置） |
| baseline 元資料 | `os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat/baseline.yaml` |
| 單元測試 | `os-image/debs/strawwu-wincompat/tests/test-wincompat-cli.sh` |
| chroot 安裝 | `os-image/scripts/chroot-install-wincompat.sh` |
| target 整合 | `target-manifest.yaml` 加入 `strawwu-wincompat`；`chroot-install-target-setup.sh` stage + 驗證 |
| Preflight | `tests/preflight/test-wincompat-os.sh` |
| baseline | `docs/plans/baselines/wincompat-os-baseline.json` |
| Makefile | `test-wincompat-os`、`install-wincompat`；`preflight` 含本階段 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| rootfs 整合 | `strawwu-wincompat` deb → `/usr/bin/strawwu` |
| W0 DoD | `strawwu status` 在 rootfs + squashfs 可跑 |
| CLI 子命令 | status · version · run · install · apps · profile · repair · config（stub） |
| 執行後端預設 | native（SubsystemSession；container/microvm 僅覆寫） |
| 日誌路徑 | `/var/log/strawwu/wincompat.log`（postinst 建目錄；寫入待 W5+） |
| 建置 | `cargo build --release --bin strawwu` → amd64 deb（~176K） |

## 驗收命令輸出（2026-07-05T05:36 UTC-4，Hermes 續跑終驗）

### `make test-wincompat-os` — exit 0（~0.7s）

Log: `/tmp/w3-w0-test-wincompat-os.log`

```
=== W3-W0 wincompat-os done: PASS ===
```

關鍵檢查項：deb 建置 PASS、`strawwu-wincompat_0.4.1.15_amd64.deb`（176K）、CLI unit tests PASS、rootfs+squashfs `/usr/bin/strawwu` 存在且 `strawwu status` 可執行、chroot marker 存在。

`strawwu status` 實際輸出：`strawwu: status — runtime idle, 0 sessions active`

### `make preflight` — exit 0（~108s）

Log: `/tmp/w3-w0-preflight.log`

含 W0 baseline + W1-B1~F2 + W2-N1/B2/I1/R1/trust + W3-D1/I2/B3/N2 + **W3-W0 wincompat-os** 全部 exit 0。

### chroot 安裝

Log: `/tmp/w3-w0-chroot-install.log`

| 項目 | 結果 |
|------|------|
| marker | `os-image/work/.wincompat-ok` 存在 |
| deb | `strawwu-wincompat_0.4.1.15_amd64.deb`（~176K） |
| rootfs CLI | `/usr/bin/strawwu` 可執行 |
| status 輸出 | `strawwu: status — runtime idle, 0 sessions active` |
| squashfs | `/usr/bin/strawwu` 已 rsync 同步 |

## 技術備註（治本）

1. **乾淨室建置**：deb 由 `components/strawwu-launcher` Rust 源碼編譯，未複製 legacy/封存程式碼；沿用 Phase 6 cargo workspace。
2. **獨立 deb 而非 components/packaging**：對齊 `os-image/debs/*` 慣例，與 chroot-install 流程一致。
3. **amd64 架構**：Rust 二進位為 amd64；與 Live ISO 目標一致。
4. **Phase 6 預設 native**：baseline.yaml 明確 SubsystemSession native 預設；禁止 WinBox/strawwu-box。
5. **squashfs 同步**：chroot 安裝後 rsync binary + dpkg status，preflight 無需重打 ISO 即可驗證。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| `strawwu --version` 顯示 0.4.0 | launcher crate 版本待 sync workspace（W4 整合時修正） |
| Registry / Hub 整合 | 待 W4-W1 / W4-F3 |
| target-manifest staged debs | 已加入 `strawwu-wincompat`（Calamares 安裝到磁碟時一併安裝） |
| wincompat.log 結構化寫入 | CLI status 尚未寫 log（待 W5-W4 GUI / W6 E2E） |
| release-iso 重打包 | chroot 變更需 `make dev-iso`/`release-iso` 才進 ISO |
| `make test-wincompat` cargo 367 tests | 獨立於本階段 OS 整合；CI 仍必跑 |

## 變更檔案清單

```
VERSION (0.4.1.13 → 0.4.1.15)
Makefile
components/Cargo.toml                                       (version sync)
os-image/debs/strawwu-wincompat/                            (新增)
os-image/scripts/chroot-install-wincompat.sh                (新增)
os-image/scripts/chroot-install-target-setup.sh             (wincompat stage + verify)
os-image/debs/strawwu-target-setup/.../target-manifest.yaml (加入 strawwu-wincompat)
tests/preflight/test-wincompat-os.sh                        (擴充 W3-W0)
docs/plans/baselines/wincompat-os-baseline.json             (新增)
docs/plans/stage-reports/W3-W0-wincompat-baseline-report.md (本檔)
```

## VERSION

`0.4.1.13` → `0.4.1.15`（iterate ×2：worker bump + preflight rebuild）

## Commit message（建議）

```
feat(w3): add strawwu-wincompat deb — strawwu CLI in rootfs

- Build /usr/bin/strawwu from strawwu-launcher via cargo release
- chroot-install-wincompat.sh + test-wincompat-os preflight
- W0 DoD: strawwu status runnable on Live rootfs/squashfs
Tests: make test-wincompat-os PASS, make preflight PASS
Version: 0.4.1.15
```

## 下一階段

**w4-d2-strawwu-shell**（Hermes mark PASS 後自動啟動，勿問使用者）。
