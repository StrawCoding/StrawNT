# StrawWU

StrawWU 是以 **Ubuntu 官方 live 映像為基底**的桌面作業系統，透過 **clone → 替換自訂 kernel → 疊加 StrawWU 元件** 的方式建置，目標是在單一 OS 內提供 Windows 與 Linux 應用程式同級的 runtime 調度能力。

> **最後正式發布 v0.4.0.0（2026-07-04）** — Phase 0–7 全部完成，完全 clean-room 實作，禁用封存 legacy 程式碼；ISO 通過 BIOS + UEFI boot test。
> **目前開發 v0.7.0.21** — rebase 至 Ubuntu 26.04 (resolute) + kernel 7.0.0-strawwu，並加入 Secure Boot（MOK 簽核 + Canonical fallback）等強化。

## 版本規格

採用 `a.b.c.d` 四位版本號（詳見 [docs/versioning.md](docs/versioning.md)）：
- `a.b.c` = Major.Minor.Patch
- `d` = Preview 版本號（`0` = 正式版，`≥1` = 預覽版）

## 版本狀態

| 項目 | 值 |
|------|-----|
| 開發版本 | `v0.7.0.21`（Ubuntu 26.04 resolute rebase 開發中；最後正式發布為 v0.4.0.0） |
| ISO | `StrawWU-<version>-amd64.iso` |
| Kernel | `7.0.0-strawwu`（Ubuntu resolute ABI 7.0.0-14，上游 Linux 6.14+） |
| Tests | Rust + Hub 全綠（見 `make test-wincompat` / `hub` npm test） |
| Windows 相容 | 13/13 sub-stages PASS |
| i18n | 206 語言（Ubuntu 完整清單） |
| Boot test | BIOS PASS / UEFI PASS |
| CI | GitHub Actions release workflow |

## 核心原則

1. **Ubuntu clone 優先** — 不自造 rootfs/Calamares 行為；直接參照 Ubuntu resolute (26.04) 官方套件與 `calamares-settings-ubuntu-common`。
2. **僅替換 kernel** — 換 `linux-image-*` 為 StrawWU 自訂 kernel（7.0.0-strawwu，上游 Linux 6.14+），其餘 userland 保持 Ubuntu 相容。
3. **Clean-room NT 子系統** — Windows 相容層為全新實作（見 `components/`），禁止 Wine/Proton 依賴。
4. **先自查再 E2E** — preflight 靜態檢查 PASS 才跑 QEMU/安裝測試。

## 架構

```
官方 Ubuntu resolute (26.04) live ISO
        │
        ▼ clone (unsquashfs + chroot)
   Ubuntu rootfs（保留官方 calamares/desktop）
        │
        ▼ swap-kernel.sh
   StrawWU custom kernel (7.0.0-strawwu, 上游 Linux 6.14+)
        │
        ▼ 疊加 components（11 Rust crates + Electron Hub）
   strawwu-nt / bridge / runtime / graphics / audio
   anticheat / device-proxy / launcher / app-registry / cli + Hub GUI
        │
        ▼ repack ISO (xorriso, xz 壓縮)
   StrawWU-<version>-amd64.iso
```

## 元件總覽

| Crate | 功能 |
|-------|------|
| `strawwu-nt` | NT 核心 — PE loader, VMM, VFS, Registry, COM, NtSection, IPC |
| `strawwu-runtime` | 協作 runtime — Orchestrator, ProcessGraph, SessionRegistry, Executor |
| `strawwu-bridge` | 橋接層 — policy, transport, Linux↔Win32 映射 |
| `strawwu-graphics` | 圖形棧 — Vulkan ICD, WGL/OpenGL, D3D11, DXGI, Present (vsync) |
| `strawwu-audio` | 音訊 — WASAPI bridge (PipeWire/PulseAudio), XInput 控制器 |
| `strawwu-anticheat` | 反作弊 — ProbeEngine, EAC/BE/Vanguard 矩陣, compat grade |
| `strawwu-device-proxy` | 裝置代理 — udev 列舉, COM port, hotplug, IOCTL, VFIO passthrough |
| `strawwu-launcher` | Launcher — AppDatabase, installer, WoW64, CLI |
| `strawwu-app-registry` | 使用者 app 註冊表 — list/register/remove + schema 驗證 |
| `strawwu-cli` | 共用 CLI 參數解析與命令分派 |

**Hub（Electron）**— 桌面控制中心 GUI，顯示 subsystem 狀態、app 管理、更新通道、206 語言即時切換。

## Repository 結構

```
StrawWU/
├── README.md
├── Makefile
├── docs/
│   ├── architecture.md
│   ├── phase-roadmap.md
│   └── iso-modes.md
├── os-image/
│   ├── scripts/
│   │   ├── clone-ubuntu-base.sh
│   │   ├── swap-kernel.sh
│   │   └── build-iso.sh
│   ├── config/                    # branding overlay（Plymouth, GRUB, icons）
│   └── output/                    # ISO + SHA256SUMS
├── kernel/                        # 自訂 kernel 7.0.0-strawwu（上游 Linux 6.14+）
├── hub/                           # Electron 控制中心
│   ├── src/
│   ├── locales/                   # 206 語言翻譯檔
│   └── dist/
├── .github/workflows/             # CI: release ISO on tag push
├── components/                    # 11 Rust crates（workspace）
│   ├── Cargo.toml
│   ├── strawwu-nt/
│   ├── strawwu-runtime/
│   ├── strawwu-bridge/
│   ├── strawwu-graphics/
│   ├── strawwu-audio/
│   ├── strawwu-anticheat/
│   ├── strawwu-device-proxy/
│   ├── strawwu-launcher/
│   ├── strawwu-app-registry/
│   ├── strawwu-cli/
│   └── strawwu-hub/
├── packaging/                     # .deb 打包
└── tests/
    ├── preflight/
    └── boot/
```

## Phase 路線圖

| Phase | 內容 | 狀態 |
|-------|------|------|
| 0 | 骨架與規範 | PASS |
| 1 | Ubuntu Clone 管線 | PASS |
| 2 | 自訂 Kernel (7.0.0-strawwu) | PASS |
| 3 | Calamares 安裝 E2E | PASS |
| 4 | 元件基礎 (Greenfield) | PASS |
| 5 | 桌面控制中心 (Electron Hub) | PASS |
| 6 | Windows 相容路徑 (13/13) | PASS |
| 7 | Official Release | PASS |

## 快速開始

```bash
make help                       # 顯示所有可用目標
make preflight                  # 靜態檢查（工具、設定、branding）
make clone-ubuntu-base          # 下載並提取 Ubuntu resolute (26.04) live rootfs
make swap-kernel                # 替換 kernel 為 strawwu
make release-iso                # 完整 ISO 建置（xz 壓縮，約 30 分鐘）
make preflight-iso-before-boot  # ISO 完整性閘門
make boot-test-iso              # QEMU BIOS + UEFI 開機驗證
make test-wincompat             # Windows 相容層測試（367 tests）
make test-hub                   # Hub 單元測試（35 tests）
```

開發模式（快速迭代）：

```bash
make dev-iso                    # 快速 ISO（zstd，僅 BIOS）
make dev-vm-start               # VM snapshot 工作流（無 ISO）
make dev-vm-sync                # rsync 變更至 VM
```

## 建置需求

- Ubuntu 24.04+（建置主機；目標基底為 Ubuntu 26.04 resolute）
- Rust toolchain (edition 2021)
- Node.js 18+ (Hub)
- xorriso, squashfs-tools, qemu-system-x86
- 約 20 GB 磁碟空間

## 國際化（i18n）

Hub 支援 **206 語言**（取自 Ubuntu `/usr/share/i18n/SUPPORTED` 完整清單）：
- 完整翻譯：English (`en`)、繁體中文 (`zh`)
- 其餘語言含 stub 翻譯（fallback 至 English），供社群貢獻
- 功能：系統語言自動偵測、即時切換、fallback chain、參數替換
- Language 面板：可搜尋語言網格，含原文名稱 + 英文名稱 + 語言代碼

## CI/CD

GitHub Actions workflow（`.github/workflows/release.yml`）：
- **觸發**：push tag `v*`
- **流程**：cargo test → npm test → preflight → build ISO → SHA256SUMS → GitHub Release
- **版本判斷**：`d=0` → 正式 Release；`d≥1` → Pre-release（Preview N）
- **Runner**：self-hosted（需 root + xorriso + squashfs-tools）

## 授權

StrawCoding 專有軟體，見 [LICENSE](LICENSE)。Ubuntu 元件受其各自授權約束。
