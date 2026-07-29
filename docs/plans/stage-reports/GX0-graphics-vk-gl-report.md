# GX0 — Graphics Vulkan / OpenGL 階段報告

| 任務 | gx0-graphics-vk-gl |
|------|---------------------|
| Track | Game Compat |
| 版本 | 見 `VERSION`（本 stage bump） |
| 日期 | 2026-07-29 |
| Worker | 階段 15/20 |
| 結果 | **待 Hermes mark**（worker 不自宣稱最終 PASS） |

## 目標

在 Portable **native** 路徑落地 DXGI/D3D11→Vulkan 與 wgl→GL／present 橋接，產出可觀測 triangle／present 證據。

## 交付物

| 類型 | 路徑 |
|------|------|
| 管線 | `components/strawwu-graphics/src/pipeline.rs` |
| 三角 raster | `components/strawwu-graphics/src/triangle.rs` |
| 驗證 bin | `gx-graphics-verify` |
| Runtime 掛接 | `components/strawwu-runtime/src/graphics_smoke.rs` |
| 煙測 | `tests/portable/smoke-gx-graphics.sh` |
| 證據 | `tests/portable/output/gx-graphics.json` |
| 副作用 | `tests/portable/output/gx0-side-effects/gx-triangle.ppm`、`gx-present.json` |

## 驗收（Hermes verify）

```bash
test -f tests/portable/output/gx-graphics.json
jq -e '.status == "PASS" or .status == "PARTIAL"' tests/portable/output/gx-graphics.json
jq -e '.backend == "native" or .execution_backend == "native" or .backend == null' tests/portable/output/gx-graphics.json
```

本地煙測：`make test-portable-gx-graphics` / `bash tests/portable/smoke-gx-graphics.sh`

## 誠實邊界（known_limitations／gaps）

- 尚未綁定 host Mesa Vulkan ICD（RADV/ANV/lavapipe）為 Win32 可載入 ICD
- 尚未在 strawwu-nt CPU loop 掛真實 PE DXGI/D3D11/wgl import trampoline
- D3D12 翻譯不在 gx0 範圍

## 排除項（已遵守）

- 未改 ISO／os-image／Plymouth／Calamares／kernel／桌面 session
- 未用 Wine／Proton 底層；`execution_backend=native`
- 未用 WinBox 命名；未宣稱完整 Windows／反作弊通過
