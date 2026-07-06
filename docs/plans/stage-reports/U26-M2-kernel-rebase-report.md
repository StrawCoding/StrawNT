# U26-M2 Kernel Rebase 階段報告

| 任務 | u26-m2-kernel-rebase |
|------|----------------------|
| 版本 | 0.6.1.1 |
| 日期 | 2026-07-06 |
| Worker | 階段 2/8（Ubuntu 26.04 遷移） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 摘要

將 StrawWU 自訂 kernel 從 **noble 6.8.0-124** rebase 至 **Ubuntu 26.04 Resolute linux 7.0.0-14**（上游 Linux 6.14+），保留 `LOCALVERSION=-strawwu` 與 `strawwu_ipc` 模組，產出合併模組的 `linux-image-strawwu` .deb 並 swap 至 resolute rootfs。

## 交付物

| 類型 | 路徑 |
|------|------|
| Kernel 建置腳本 | `kernel/build.sh`（resolute apt source、rootfs config fallback、ABI 自動偵測） |
| Kernel Makefile | `kernel/Makefile`（`KERNEL_ABI=7.0.0-14`） |
| 產出 deb | `kernel/output/linux-image-strawwu_7.0.0-2_amd64.deb`（~119 MB） |
| Build marker | `kernel/output/.build-ok`、`.kernel-abi`（7.0.0-14） |
| Rootfs swap | `os-image/work/.swap-kernel-ok` → `strawwu-kernel:7.0.0-strawwu` |
| swap 修復 | `os-image/scripts/swap-kernel.sh`（apt 失敗時 `dpkg -i` fallback） |
| 階段測試 | `tests/preflight/lib/u26-stage-stub.sh`（u26-kernel-rebase 完整驗證） |
| VERSION | `0.6.1.1` |

## 技術變更（治本）

1. **ABI 切換**：預設 `KERNEL_ABI=7.0.0-14`，對齊 resolute rootfs 已安裝的 `linux-image-7.0.0-14-generic`；Ubuntu 套件版號 7.0.0 對應上游 Linux 6.14+。
2. **Source 取得**：`enable_deb_src_for_codename` 動態加入 resolute deb-src；`apt-get source linux=7.0.0-14.14`。
3. **Config 來源**：優先 `/boot/config-*`，fallback 至 `os-image/work/rootfs/boot/config-7.0.0-14-generic`（支援 noble host 編譯 resolute kernel）。
4. **建置依賴**：新增 `libdw-dev`（7.0 bindeb-pkg Build-Depends）。
5. **strawwu_ipc**：沿用 cleanroom 模組整合；deb 內含 `7.0.0-strawwu/kernel/drivers/misc/strawwu_ipc/strawwu_ipc.ko`。
6. **swap-kernel**：chroot 內 apt 因 u26-m1 殘留 broken deps 失敗時，改 `dpkg -i` 安裝合併 deb（無外部 modules 依賴）。

## 驗收命令輸出（2026-07-06）

### `make test-u26-kernel-rebase` — exit 0

Log: `/tmp/u26-m2-test-kernel-rebase.log`

```
PASS: plan strawwu-ubuntu-2604-migration-plan.md
PASS: kernel build marker
PASS: kernel ABI stamp 7.0.0-14
PASS: linux-image-strawwu deb linux-image-strawwu_7.0.0-2_amd64.deb
PASS: upstream target 6.14+ (deb 7.0.0-2)
PASS: LOCALVERSION -strawwu + strawwu_ipc.ko in deb
PASS: rootfs vmlinuz vmlinuz-7.0.0-strawwu
PASS: u26-kernel-rebase preflight stub
```

### `make preflight` — exit 0

Log: `/tmp/u26-m2-preflight.log`（~356s）

末行：`POST-MVP INFRASTRUCTURE OK`；FAIL 計數 0。

## 環境備註

- 本機為 noble 24.04 host；`/dev/null` 曾為一般檔案導致 apt 失敗，已 `mknod` 修復（同 u26-m1）。
- Kernel `bindeb-pkg` 全量編譯約 90 分鐘（12 jobs）；dbg 包 1.5 GB 為附帶產物，最終合併 deb 119 MB。
- rootfs 仍保留 `7.0.0-14-generic` 模組目錄（purge 未完全清除）；`vmlinuz` symlink 與 initrd 已指向 `7.0.0-strawwu`。
- chroot broken deps（fcitx5、strawwu-desktop 等）屬 u26-m3-debs-rebuild 範圍；不影響本階段 kernel deb 產出與 swap。

## 已知限制 / 後續階段

| 項目 | 狀態 |
|------|------|
| strawwu-* deb 對 resolute 重編 | 待 **u26-m3-debs-rebuild** |
| APT suite `resolute` publish | 待 **u26-m4-suite-migrate** |
| initrd splice 全量回歸 | 待 **u26-m6-regression-e2e** |
| technical-references 6.14 | 待 **u26-m5-techrefs-refresh** |

## 變更檔案清單

- `kernel/build.sh`、`kernel/Makefile`、`kernel/README.md`
- `os-image/scripts/swap-kernel.sh`
- `tests/preflight/lib/u26-stage-stub.sh`
- `VERSION`、`hub/package.json`、`components/Cargo.toml`
- `docs/plans/stage-reports/U26-M2-kernel-rebase-report.md`

## 建議 commit message

```
feat(u26-m2): rebase kernel to resolute 7.0.0-14 (linux 6.14+)

- kernel/build.sh: resolute apt source, rootfs config fallback, libdw-dev
- produce linux-image-strawwu_7.0.0-2_amd64.deb with strawwu_ipc.ko
- swap-kernel: dpkg -i fallback when chroot apt broken
- expand test-u26-kernel-rebase validation
Tests: make test-u26-kernel-rebase PASS; make preflight PASS
Version: 0.6.1.1
```

## Hermes 驗收建議

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-u26-kernel-rebase
make preflight
```

證據路徑見上表；請 Hermes mark PASS 後自動啟動 `u26-m3-debs-rebuild`。
