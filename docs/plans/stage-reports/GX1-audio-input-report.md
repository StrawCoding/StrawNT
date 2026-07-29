# GX1 — Audio / Input 階段報告

| 任務 | gx1-audio-input |
|------|-----------------|
| Track | Game Compat |
| 版本 | 0.7.1.27 |
| 日期 | 2026-07-29 |
| Worker | 階段 16/20 |
| 結果 | **待 Hermes mark**（worker 不自宣稱最終 PASS） |

## 目標

在 Portable **native** 路徑落地 WASAPI→PipeWire（或 ALSA／Pulse／File 等價）與基本 XInput 輸入路徑，產出可觀測 PCM／輸入證據。

## 交付物

| 類型 | 路徑 |
|------|------|
| Host 探測 | `components/strawwu-audio/src/host.rs` |
| WASAPI 橋 | `components/strawwu-audio/src/wasapi.rs` |
| 輸入路徑 | `components/strawwu-audio/src/input_path.rs` |
| 管線 | `components/strawwu-audio/src/pipeline.rs` |
| 驗證 bin | `gx-audio-verify` |
| Runtime 掛接 | `components/strawwu-runtime/src/audio_smoke.rs` |
| 煙測 | `tests/portable/smoke-gx-audio-input.sh` |
| 證據 | `tests/portable/output/gx-audio-input.json` |
| 副作用 | `tests/portable/output/gx1-side-effects/gx-tone.wav`、`gx-input-obs.json` |

## 驗收（Hermes verify）

```bash
test -f tests/portable/output/gx-audio-input.json
jq -e '.status == "PASS" or .status == "PARTIAL"' tests/portable/output/gx-audio-input.json
```

本地煙測：`make test-portable-gx-audio-input` / `bash tests/portable/smoke-gx-audio-input.sh`

## 誠實邊界（known_limitations／gaps）

- 尚未連結 native libpipewire SPA client（host 為 socket／ALSA 探測 + PCM 檔案等價 sink）
- 尚未在 strawwu-nt CPU loop 掛真實 PE WASAPI／XAudio2 import trampoline
- 即時麥克風 capture／exclusive mode 未在 gx1 行使
- DirectInput 完整 HID 列舉仍屬 stub 級

## 排除項（已遵守）

- 未改 ISO／os-image／Plymouth／Calamares／kernel／桌面 session
- 未用 Wine／Proton 底層；`execution_backend=native`
- 未用 WinBox 命名；未宣稱完整 Windows／反作弊通過
