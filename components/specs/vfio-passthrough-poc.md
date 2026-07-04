# VFIO 直通 PoC — 實驗文件

| 版本 | 0.3.0.0 |
|------|-----------------|
| 狀態 | **實驗性 — 不進 v3.0 MVP** |
| 對齊 | `device-driver-proxy.md` Tier 4、`execution-backends.md` microvm 後端 |

## 摘要

VFIO (Virtual Function I/O) 直通允許將 PCI 裝置（通常是 GPU）直接指派給 microvm 後端內的 guest，繞過 host 驅動。此為 **Tier 4 最後手段**，用於：

- 僅有 Windows 驅動的專業硬體
- 需要原生 GPU 效能的 3A 遊戲（microvm + GPU passthrough）
- 企業工作站場景

## 架構

```
Host (Ubuntu Linux)
├── IOMMU 群組 → VFIO 綁定
├── strawwu-runtime (microvm 後端)
│   └── QEMU/KVM or crosvm
│       ├── VFIO PCI passthrough (GPU / USB controller)
│       ├── 極小 Windows guest (或 strawwu-nt in VM)
│       └── virtio-gpu fallback
├── strawwu-bridge (vsock 傳輸)
└── Hub 顯示 VFIO 狀態
```

## 前置條件

1. **IOMMU 支援** — BIOS 啟用 VT-d (Intel) 或 AMD-Vi
2. **核心參數** — `intel_iommu=on iommu=pt` 或 `amd_iommu=on`
3. **VFIO 模組** — `vfio-pci` 載入並綁定目標裝置
4. **雙 GPU 或無頭** — host 需保留至少一個顯示輸出

## 實作範圍（PoC 等級）

| 項目 | v3.0 PoC | 說明 |
|------|----------|------|
| GPU passthrough | 文件 | 未實作 runtime 整合 |
| USB passthrough | 文件 | libvirt/QEMU 標準流程 |
| 自動 IOMMU 群組偵測 | 未實作 | 需 sysfs 掃描 |
| Looking Glass 整合 | 未評估 | 可選低延遲顯示回傳 |
| Hub 顯示 VFIO 狀態 | 未實作 | 僅 compat-db 標 C/F |

## 風險

- **安全性** — DMA 直硬體存取繞過 host 記憶體保護，需 IOMMU 嚴格隔離
- **穩定性** — VM reset 時 GPU 可能不完全重置（ACS reset bug）
- **相容性** — 部分 GPU 拒絕在 VM 內初始化（Code 43）
- **複雜度** — 使用者需手動配置 IOMMU、VFIO 綁定、雙 GPU

## 結論

VFIO 直通作為 StrawWU 的**可選進階功能**，不在 v3.0 MVP 範圍內。建議：

1. 先完成 Tier 1-3 裝置代理（覆蓋大部分日常需求）
2. 社群回饋確認需求後再投入 VFIO 整合
3. 企業版可考慮預設支援 VFIO 配置精靈

## 參考

- [VFIO 官方文件](https://docs.kernel.org/driver-api/vfio.html)
- [Arch Wiki: PCI passthrough via OVMF](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
- [Looking Glass](https://looking-glass.io/)
