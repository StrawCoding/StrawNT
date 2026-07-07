# POST-HW4-peripherals — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-hw4-peripherals` |
| 版本 | `0.6.3.3`（`0.6.3.2` → `0.6.3.3`） |
| 版本目標 | `0.6.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T05:12+08:00 |
| Worker 回合 | 階段 1/8（複驗確認） |

## 摘要

實作 POST-HW4 筆電周邊策展：新增 `strawwu-laptop` meta 套件（TLP、libinput 觸控板、Fn 鍵基線、fprintd、webcam 工具）、`strawwu-laptop-peripherals` CLI、`device_profile` 策展（Q5 路線）、fixture smoke 基礎設施，並合併 T2 周邊矩陣條目至 `hw-matrix-results.json`。納入 `make preflight` 鏈。

## 交付物

| 類型 | 路徑 |
|------|------|
| Meta 套件 | `os-image/debs/strawwu-laptop/` |
| device_profile | `.../device_profiles/generic-intel-laptop.json` |
| Smoke 腳本 | `tests/hw/smoke-peripherals.sh` |
| Matrix runner | `tests/hw/run-hw-peripherals.sh` |
| Preflight gate | `tests/preflight/test-hw4-peripherals.sh` |
| Baseline | `docs/plans/baselines/hw4-peripherals-baseline.json` |
| 矩陣結果 | `docs/plans/hw-matrix-results.json`（8 台，peripheral=1） |
| 計畫 | `docs/plans/strawwu-hw4-peripherals-plan.md` |

## 策展範圍（E10/E15）

| 維度 | 套件/機制 | 狀態 |
|------|-----------|------|
| 觸控板 | xserver-xorg-input-libinput, libinput-tools | meta Depends |
| Fn 鍵 | brightnessctl, acpid (Recommends) | meta 基線 |
| 電源 | tlp, tlp-rdw (Recommends) | meta + postinst enable |
| 指紋 | fprintd, libpam-fprintd | meta Depends |
| Webcam | v4l-utils + PipeWire 相容 | meta Depends |
| device_profile | generic-intel-laptop.json | Q5 社群 PR 路線 |

## T2 周邊矩陣 profile（1/1 fixture PASS）

| machine_id | environment | touchpad | webcam | fingerprint | peripherals |
|------------|-------------|----------|--------|-------------|-------------|
| `t2-peripheral-intel-laptop` | fixture | PASS | PASS | PASS | PASS |

> Worker 環境無實體筆電周邊硬體，以 `STRAWWU_LAPTOP_FIXTURE=1` 驗證 CLI + meta 策展邏輯。Hermes 可於 Intel 筆電以 `--environment physical-installed` 覆寫。

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.3.2` → `0.6.3.3` |
| `os-image/debs/strawwu-laptop/` | **新增** meta + CLI + manifest + device_profile + fixture |
| `tests/hw/smoke-peripherals.sh` | **新增** 周邊 smoke 輸出 JSON entry |
| `tests/hw/run-hw-peripherals.sh` | **新增** fixture merge runner |
| `tests/preflight/test-hw4-peripherals.sh` | 擴充完整 gate |
| `docs/plans/hw-matrix-results.json` | 合併 `t2-peripheral-intel-laptop` |
| `os-image/scripts/build-os-debs.sh` | 納入 strawwu-laptop |
| `os-image/debs/strawwu-target-setup/.../target-manifest.yaml` | chroot 安裝順序 |
| `os-image/scripts/chroot-install-target-setup.sh` | staged-debs 同步 |
| `os-image/debs/strawwu-desktop/debian/control` | Recommends strawwu-laptop |
| `Makefile` | preflight 鏈納入 hw4 gate |
| `docs/plans/strawwu-hw4-peripherals-plan.md` | 擴充 v1.1 |

## 誠實邊界

1. **Fixture 模式**：worker 以 fixture catalog 模擬 touchpad/webcam/fingerprint PASS；非實機硬體證據。
2. **Fn 鍵**：僅策展 brightnessctl/acpid 基線；各 OEM 熱鍵需 device_profile 擴充。
3. **指紋登入 PAM**：libpam-fprintd 已納入 meta；GDM 指紋 enrollment 需 Hermes 實機驗證。
4. **矩陣相容**：周邊條目標記 `live_boot/wifi/gpu_driver/suspend/hidpi=SKIP`，不影響既有 T1/T2 live 計數。

## 驗證命令輸出

### `make test-hw4-peripherals` — exit 0

Log: `/tmp/post-hw4-test.log`

```
PASS: strawwu-laptop deb / CLI / manifest / device_profile / fixture
PASS: target-manifest + build-os-debs + desktop Recommends integration
PASS: strawwu-laptop deb artifact
PASS: strawwu-laptop python tests (8 tests OK)
PASS: peripheral matrix entries 1
PASS: profiles=t2-peripheral-intel-laptop
=== POST-HW4 peripherals done: PASS ===
```

### `make preflight` — exit 0（~255s，全鏈）

Log: `/tmp/post-hw4-preflight-final.log`

本回合 worker 複驗全鏈 PASS（含 POST-HW4 → … → FORK-F7 closeout）。

```
=== POST-HW4 peripherals done: PASS ===
...
=== FORK-F7 closeout done: PASS ===
exit 0
```

### `tests/hw/run-hw-peripherals.sh` — exit 0

```
PASS: merged machine_id=t2-peripheral-intel-laptop
==> POST-HW4 peripheral matrix complete
```

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-hw4-peripherals
make preflight
# 實機（可選）：
bash tests/hw/smoke-peripherals.sh --environment physical-installed --output /tmp/peripheral.json
bash tests/hw/merge-entry.sh --entry /tmp/peripheral.json --machine-id t2-peripheral-intel-laptop
```

## Commit message（建議）

```
feat(hw4): add strawwu-laptop peripherals meta and T2 matrix smoke

- strawwu-laptop meta: tlp, libinput, fprintd, v4l-utils, device_profile
- strawwu-laptop-peripherals CLI with fixture smoke mode
- tests/hw/smoke-peripherals.sh + run-hw-peripherals.sh
- hw-matrix t2-peripheral-intel-laptop entry; preflight gate
Tests: make test-hw4-peripherals PASS; make preflight PASS
Issue: post-hw4-peripherals v0.6.3.3
```
