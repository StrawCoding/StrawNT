# StrawWU

StrawWU 是以 **Ubuntu 官方 live 映像為基底**的桌面作業系統，透過 **clone → 替換自訂 kernel → 疊加 StrawWU 元件** 的方式建置，目標是在單一 OS 內提供 Windows 與 Linux 應用程式同級的 runtime 調度能力。

> **2026-07-02 重啟：** 舊版（mmdebstrap 自造 ISO 管線）已封存於 `../封存/StrawWU-legacy-2026-07-02`，Git tag `legacy/archive-2026-07-02`。

## 核心原則

1. **Ubuntu clone 優先** — 不自造 rootfs/Calamares 行為；直接參照 Ubuntu noble 官方套件與 `calamares-settings-ubuntu-common`。
2. **僅替換 kernel** — 第一階段只換 `linux-image-*` 為 StrawWU 自訂 kernel，其餘 userland 保持 Ubuntu 相容。
3. **Clean-room NT 子系統** — Windows 相容層為自建（見 `components/`），禁止 Wine/Proton 依賴。
4. **先自查再 E2E** — preflight 靜態檢查 PASS 才跑 QEMU/安裝測試。

## 架構

```
官方 Ubuntu noble live ISO
        │
        ▼ clone (unsquashfs + chroot)
   Ubuntu rootfs（保留官方 calamares/desktop）
        │
        ▼ swap-kernel.sh
   StrawWU custom kernel（linux-image-strawwu）
        │
        ▼ 疊加 components
   strawwu-nt / runtime / control-center
        │
        ▼ repack ISO
   StrawWU-<version>-amd64.iso
```

## Repository 結構

```
StrawWU/
├── README.md
├── Makefile
├── docs/
│   ├── architecture.md
│   └── phase-roadmap.md
├── os-image/
│   ├── scripts/
│   │   ├── clone-ubuntu-base.sh   # 從官方 ISO 提取 rootfs
│   │   ├── swap-kernel.sh         # 替換 kernel 套件
│   │   └── build-iso.sh           # 重打包 live ISO
│   ├── config/                    # 僅 branding overlay（不改 upstream calamares 行為）
│   └── output/
├── kernel/                        # 自訂 kernel 建置（待實作）
├── components/                    # NT/runtime/control-center（自 legacy 遷移）
└── tests/preflight/
```

## 快速開始

```bash
make help
make preflight                  # 檢查工具與設定
make clone-ubuntu-base          # 下載並提取 Ubuntu noble live rootfs
make build-iso                  # clone + kernel swap + repack
```

## 授權

StrawCoding 專有軟體，見 [LICENSE](LICENSE)。Ubuntu 元件受其各自授權約束。

## 相關

- 封存舊版：`../封存/StrawWU-legacy-2026-07-02`
- 關聯專案：[StrawWinBox](../StrawWinBox)
