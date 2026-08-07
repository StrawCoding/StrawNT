# 圖形棧規格：Vulkan + OpenGL

| 版本 | 0.4.0.0 |
|------|----------------------|
| 對齊 | 原始系統計畫 Phase 5 圖形與輸入 |

## 目標

在 **app workload**（container 或 microvm 後端內）支援 Windows 遊戲與日常 app 的圖形需求：**Vulkan** 與 **OpenGL** 雙路徑，乾淨實作，（歷史 GX0 規格；NTW0 起產品預設改 wine／proton-ge，本檔保留為 legacy 圖形軌道說明。）

## 架構

```
Win PE（D3D11/D3D12/GDI32/wgl）
        │
        ▼
strawwu-graphics（userspace，由 runtime 掛接）
├── strawwu-dxgi-vk   DXGI/D3D11 → Vulkan
├── strawwu-wgl       wgl* → GLX/EGL
└── strawwu-present   與 Wayland/X11 合成
        │
        ▼
Linux Mesa（RADV/ANV + GL）
```

圖形能力由 app profile `permissions.gpu` 與 `resource_policy.gpu_mode` 控制；runtime 在啟動 workload 時注入對應 ICD/呈現橋接。

## 子模組

| 模組 | 職責 | v3.0 狀態 |
|------|------|-----------|
| strawwu-vk-icd | Win32 可載入的 Vulkan ICD 入口 | PASS — instance/surface/device/swapchain/command pool/acquire+present 迴圈 |
| strawwu-dxgi-vk | D3D11 常見呼叫翻譯 | PASS — resource tracking、shader/RTV creation、draw call、triangle stats |
| strawwu-wgl | OpenGL 1.x/2.x 子集 | PASS — 多 context、GL state machine、50+ proc addresses |
| present-bridge | 全螢幕、vsync、多螢幕 | PASS — Wayland/X11 + vsync + fps 計算 + resize |

## 可攜路徑（Portable gx0）

`strawwu-graphics` 在 Portable native 路徑提供 `GraphicsPipeline`：
DXGI/D3D11→Vulkan ICD 合約 + wgl→GL/present + 可觀測 triangle PPM。
證據：`tests/portable/output/gx-graphics.json`（`execution_backend=native`）。

誠實邊界：host Mesa ICD 綁定與 PE import trampoline 列於 evidence `gaps`；禁止宣稱完整 Windows／反作弊通過。

## 驗收

```bash
# Portable gx0
bash tests/portable/smoke-gx-graphics.sh
jq -e '.status == "PASS" or .status == "PARTIAL"' tests/portable/output/gx-graphics.json

# （可選）於有 GPU 的環境
# vulkaninfo --summary
# glxinfo | head
```

證據：`tests/portable/output/gx-graphics.json` + `gx0-side-effects/gx-triangle.ppm`

## 遊戲相關

- 優先 D3D11→Vulkan 路徑（覆蓋率最高之獨立/2D 遊戲）
- D3D12 長期 PARTIAL（非 v3.0 目標）
- 可選 VFIO GPU 直通供高負載 3A（microvm 後端進階選項）
