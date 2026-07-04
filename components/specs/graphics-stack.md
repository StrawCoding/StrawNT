# 圖形棧規格：Vulkan + OpenGL

| 版本 | 0.4.0.0 |
|------|----------------------|
| 對齊 | 原始系統計畫 Phase 5 圖形與輸入 |

## 目標

在 **app workload**（container 或 microvm 後端內）支援 Windows 遊戲與日常 app 的圖形需求：**Vulkan** 與 **OpenGL** 雙路徑，乾淨實作，禁止 Wine/Proton 嵌入。

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

## 驗收

```bash
# 於 container workload 內（strawwu run --backend container …）
vulkaninfo --summary
glxinfo | head
# 自製 triangle + 輕量 D3D11 demo
```

證據：截圖 + `tests/graphics/output/vulkan-opengl-result.json`

## 遊戲相關

- 優先 D3D11→Vulkan 路徑（覆蓋率最高之獨立/2D 遊戲）
- D3D12 長期 PARTIAL（非 v3.0 目標）
- 可選 VFIO GPU 直通供高負載 3A（microvm 後端進階選項）
