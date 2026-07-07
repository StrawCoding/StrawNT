# StrawWU HW4 筆電周邊策展計畫

| 版本 | 1.1 |
|------|-----|
| 對照維度 | E10 觸控板/Fn、E15 webcam/指紋 |
| Stage | `post-hw4-peripherals` |

## 目標

對標 Mint mint-meta / Pop system76-power 基礎策展：

1. `strawwu-laptop` meta：tlp、libinput 觸控板、Fn 鍵基線（brightnessctl/acpid）
2. `strawwu-laptop-peripherals` CLI + `device_profile.json` 策展（Q5 社群 PR 路線）
3. fprintd + 指紋登入 smoke（有硬體時）
4. webcam PipeWire/v4l smoke（有硬體時）
5. `hw-matrix-results.json` 新增 T2 peripheral 條目（非 SKIP）

## 套件策展（strawwu-laptop）

| 維度 | 套件 | 說明 |
|------|------|------|
| 電源 | tlp, tlp-rdw | 筆電電源管理 |
| 觸控板 | xserver-xorg-input-libinput, libinput-tools | E10 libinput 基線 |
| Fn 鍵 | brightnessctl, acpid | 亮度/ACPI 事件 |
| 指紋 | fprintd, libpam-fprintd | E15 fprintd 登入 |
| Webcam | v4l-utils | PipeWire 相容探測 |

## device_profile

- 路徑：`/usr/share/strawwu/laptop/device_profiles/generic-intel-laptop.json`
- schema：`strawwu-device-profile/v1`
- 社群 PR：Q5（見 `docs/decisions-2026-07-02.md`）

## 驗收

```bash
make test-hw4-peripherals
make preflight
```

Hermes 實機 workflow：

```bash
bash tests/hw/smoke-peripherals.sh --environment physical-installed --output /tmp/peripheral.json
bash tests/hw/merge-entry.sh --entry /tmp/peripheral.json
```

## 交付物

| 類型 | 路徑 |
|------|------|
| Meta 套件 | `os-image/debs/strawwu-laptop/` |
| Smoke 腳本 | `tests/hw/smoke-peripherals.sh` |
| Matrix runner | `tests/hw/run-hw-peripherals.sh` |
| Preflight | `tests/preflight/test-hw4-peripherals.sh` |
| Baseline | `docs/plans/baselines/hw4-peripherals-baseline.json` |
