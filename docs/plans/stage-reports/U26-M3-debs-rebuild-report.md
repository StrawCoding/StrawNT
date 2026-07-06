# U26-M3 Debs Rebuild 階段報告

| 任務 | u26-m3-debs-rebuild |
|------|---------------------|
| 版本 | 0.6.1.2 |
| 日期 | 2026-07-06 |
| Worker | 階段 1/8（u26-m3-debs-rebuild） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 摘要

將 **22 個** `os-image/debs/strawwu-*` 套件對 **Ubuntu 26.04 Resolute** rootfs 全量重編（v0.6.1.2）、寫入 resolute chroot 並同步 squashfs；更新 meta-audit allowlist（`ubuntu-wallpapers-resolute`）；修復 chroot 安裝管線中 flatpak / initramfs-hooks / GRUB 探測等 resolute 相容問題。

## 交付物

| 類型 | 路徑 |
|------|------|
| 統一建置腳本 | `os-image/scripts/build-os-debs.sh`（22 套件 + cargo PATH） |
| Makefile 目標 | `make build-os-debs` |
| Rebuild marker | `os-image/work/.debs-rebuild-ok` → `0.6.1.2` |
| Deb 產物 | `os-image/debs/*/output/*_0.6.1.2_*.deb` |
| meta-audit | `ubuntu-wallpapers-resolute`（移除 noble） |
| 階段測試 | `tests/preflight/lib/u26-stage-stub.sh`（u26-debs-rebuild 完整驗證） |
| VERSION | `0.6.1.2` |

## 技術變更（治本）

1. **統一 deb 建置**：`build-os-debs.sh` 涵蓋 initd→keyring 共 22 包；`chroot-install-target-setup.sh` 改為呼叫此腳本；`latest_deb()` 補上 `strawwu-wincompat` amd64 架構。
2. **meta-audit resolute**：`meta-audit-manifest.yaml` allowlist `ubuntu-wallpapers-noble` → `ubuntu-wallpapers-resolute`；單元測試 `test_manifest_resolute_wallpapers`。
3. **flatpak postinst**：chroot 無 `boot_id` 時延後 flathub 註冊；完整 proc mount 下可正常 configure。
4. **initramfs-hooks postinst**：修正 CLI 參數順序 `--skip-initramfs apply`（原 `apply --skip-initramfs` 靜默失敗）；inner script 顯式呼叫 `strawwu-initramfs-hooks --skip-initramfs apply`。
5. **target-identity**：`grub-probe` 無 root device 時跳過 update-grub（live rootfs / chroot 預期行為）。
6. **sudo + cargo**：`build-os-debs.sh` 補 `/root/.cargo/bin` 至 PATH（wincompat / desktop-actions Rust 建置）。
7. **驗證閘門**：`.debs-rebuild-ok` 版本鎖、22 deb 產物、rootfs 21 個已安裝 strawwu-* @ VERSION、`dpkg --audit` clean。

## 驗收命令輸出（2026-07-06，worker 最終複驗）

### `make test-u26-debs-rebuild` — exit 0

Log: `/tmp/u26-m3-test-debs-rebuild-verify.log`（複驗 ~0.2s）

```
PASS: plan strawwu-ubuntu-2604-migration-plan.md
PASS: build-os-debs.sh
PASS: ubuntu-base-target
PASS: debs-rebuild marker
PASS: active Ubuntu 26.04.0 resolute
PASS: .debs-rebuild-ok v0.6.1.2
PASS: meta-audit allowlist resolute (no noble wallpapers)
PASS: 22 strawwu-* debs rebuilt at v0.6.1.2
PASS: rootfs 21 strawwu-* packages at v0.6.1.2
PASS: rootfs dpkg --audit clean
PASS: u26-debs-rebuild preflight stub
```

### `make preflight` — exit 0

Log: `/tmp/u26-m3-preflight-verify.log`（複驗 ~191s）

末行：`POST-MVP INFRASTRUCTURE OK`；FAIL 計數 0。

### `pytest os-image/debs/strawwu-minimal/tests/test-meta.py` — 6 passed

### 建置 / chroot 日誌

| 步驟 | Log |
|------|-----|
| `make build-os-debs` | `/tmp/u26-m3-build-os-debs.log` |
| `install-target-setup`（完成） | `/tmp/u26-m3-install-r6.log`（~244s） |

## 環境備註

- rootfs 為 resolute live ISO 提取；`install-target-setup` 內層 Calamares 模擬約 2–4 分鐘。
- `strawwu-keyring` 已建置但非 target-manifest 強制安裝項；rootfs 計 21 個 strawwu-*（不含 kernel deb 與虛擬包 `strawwu-compositor`）。
- chroot 內 fcitx5 / ubuntu-desktop 殘留 broken deps 為 purge 後過渡狀態；`dpkg --audit` 已 clean，不阻斷本階段 deb 重編驗收。
- Plymouth `strawwu-boot` 主題仍待後續 branding wave；target-identity 以 warn 跳過。

## 已知限制 / 後續階段

| 項目 | 狀態 |
|------|------|
| APT suite `resolute` publish | 待 **u26-m4-suite-migrate** |
| technical-references 6.14 | 待 **u26-m5-techrefs-refresh** |
| release-iso boot-test + E2E | 待 **u26-m6-regression-e2e** |
| fcitx5 依賴鏈 apt 修復 | 可於 suite-migrate 或 regression 階段一併處理 |

## 變更檔案清單

- `os-image/scripts/build-os-debs.sh`（新增）
- `os-image/scripts/chroot-install-target-setup.sh`
- `os-image/debs/strawwu-minimal/usr/share/strawwu/meta-audit/meta-audit-manifest.yaml`
- `os-image/debs/strawwu-minimal/tests/test-meta.py`
- `os-image/debs/strawwu-flatpak-setup/debian/postinst`
- `os-image/debs/strawwu-initramfs-hooks/debian/postinst`
- `os-image/debs/strawwu-target-identity/usr/lib/strawwu-target-identity/core.py`
- `tests/preflight/lib/u26-stage-stub.sh`
- `Makefile`
- `VERSION`、`hub/package.json`、`components/Cargo.toml`
- `docs/plans/baselines/meta-audit-baseline.json`（preflight 自動更新）
- `docs/plans/stage-reports/U26-M3-debs-rebuild-report.md`

## 建議 commit message

```
feat(u26-m3): rebuild all strawwu-* debs for resolute 26.04

- add build-os-debs.sh (22 packages) + make build-os-debs
- meta-audit: ubuntu-wallpapers-resolute allowlist
- fix flatpak/initramfs-hooks postinst and target-identity grub chroot skip
- expand test-u26-debs-rebuild + .debs-rebuild-ok marker
Tests: make test-u26-debs-rebuild PASS; make preflight PASS
Version: 0.6.1.2
```

## Hermes 驗收建議

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-u26-debs-rebuild
make preflight
```

證據：`os-image/debs/*/output/`、`os-image/work/.debs-rebuild-ok`、`/tmp/u26-m3-*.log`
