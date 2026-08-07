# StrawNT components

> **NTW0（2026-08-07）：** 產品預設 `execution_backend=wine`／`engine=proton-ge`（**powered by Wine**）。舊「native 預設／禁 Wine」已廢止。見 `docs/decisions/2026-08-07-wine-pivot.md`。

v3.0-cleanroom 元件樹；旗艦執行路徑為 Wine／Proton-GE；native PE crate 保留為 legacy／research。

## 結構

```
components/
├── Cargo.toml              # Workspace root
├── Makefile                # make test / make package / make test-wincompat
├── specs/                  # API/ABI 規格文件
│   ├── bridge-abi.md
│   ├── runtime-cooperation.md
│   ├── execution-backends.md
│   ├── device-driver-proxy.md
│   ├── graphics-stack.md
│   ├── anticheat-compat.md
│   └── vfio-passthrough-poc.md
├── strawwu-bridge/         # kernel↔userspace IPC + seccomp policy
├── strawwu-runtime/        # SubsystemSession + orchestrator + process graph
├── strawwu-launcher/       # PE/ELF 偵測 + CLI (strawwu 指令)
├── strawwu-nt/             # Phase 6: Win32/NT 相容層
│   ├── pe.rs               #   PE parser + stub PE builder
│   ├── teb.rs              #   TEB/PEB structures
│   ├── ntdll.rs            #   NT syscall dispatch
│   ├── win32_stubs.rs      #   kernel32/user32/gdi32/ole32 stub registry
│   ├── ipc.rs              #   Named Pipe IPC
│   ├── registry.rs         #   Virtual Windows Registry
│   ├── wow64.rs            #   WoW64 (32-bit PE path redirect)
│   └── installer.rs        #   App database + profile snapshot/restore
├── strawwu-graphics/       # Phase 6: 圖形棧
│   ├── vulkan.rs           #   Vulkan ICD passthrough
│   ├── dxgi.rs             #   DXGI→Vulkan factory/adapter
│   ├── d3d11.rs            #   D3D11→Vulkan translation stubs
│   ├── opengl.rs           #   wgl→GLX/EGL bridge
│   └── present.rs          #   Wayland/X11 present bridge
├── strawwu-audio/          # Phase 6: 音訊/輸入
│   ├── wasapi.rs           #   WASAPI→PipeWire bridge
│   └── xinput.rs           #   XInput controller mapping
├── strawwu-anticheat/      # Phase 6: 反作弊矩陣
│   ├── probes.rs           #   EAC/BE/Vanguard probe simulation
│   └── matrix.rs           #   Compatibility matrix generation
├── strawwu-device-proxy/   # Phase 6: 裝置代理
│   ├── devices.rs          #   10-class device map (udev/COM/CUPS/HID)
│   ├── ioctl.rs            #   IOCTL handler (allow/deny/stub/audit)
│   └── matrix.rs           #   Device matrix generation
├── packaging/              # .deb 建置腳本
│   ├── debian/
│   └── build-deb.sh
└── tests/                  # 整合測試資料
    └── wincompat/
        ├── golden-apps.json
        ├── generate-compat-matrix.sh
        └── output/
            └── compat-matrix.json
```

## 建置與測試

```bash
make -C components test                     # 單元測試 + 規格完整性 + 結構檢查
make -C components package                  # 建置 release binary + .deb 打包
make -C components build                    # 僅 cargo build --release
make -C components check                    # 快速 cargo check
```

### Legacy／archive（NTW0 soft-reset — 非產品 Wine 預設驗收）

下列 Phase 6 native-era 套件**不是**現行產品／完整 Windows 相容驗收；產品預設為 wine／proton-ge（**powered by Wine**）。見 `tests/archive/native/README.md`。

```bash
make -C components test-legacy-wincompat    # LEGACY Phase 6 套件（別名 test-wincompat）
make -C components test-execution-backends  # 6.2 執行後端（含 wine enum）
make -C components test-graphics-vulkan     # 6.4 Vulkan 圖形棧
make -C components test-graphics-opengl     # 6.4b OpenGL 圖形棧
make -C components test-anticheat-matrix    # 6.7 反作弊矩陣（禁排位宣稱）
make -C components test-device-proxy        # 6.11 裝置代理
make -C components generate-compat-matrix   # 產出 compat-matrix.json
```

Golden apps 契約：`tests/wincompat/golden-apps.json` → `backend_default=wine`。

## 設計原則

> **2026-08-07 Wine pivot（NTW0）：** 產品預設已改 `execution_backend=wine`／`engine=proton-ge`（**powered by Wine**）。舊「禁 Wine／Proton」與「native 為預設」硬契約已**廢止**；native PE 僅 legacy／research（`STRAWNT_LEGACY_NATIVE=1`、unsupported）。見 `docs/decisions/2026-08-07-wine-pivot.md`。

- **預設不使用 sandbox** — prefix／session 內 app 可互通（同／跨 prefix IPC 見 NTW4）
- **wine／proton-ge 為預設執行後端** — container/microvm 僅作覆寫；native 為 legacy
- **禁止 WinBox / strawwu-box** — 統一使用 `strawnt` CLI（舊 `strawwu` 僅相容別名）
- **誠實標示 powered by Wine** — 不得靜默改名為自研 PE／完整 Windows
- **誠實標 PASS/PARTIAL/FAIL/UNKNOWN** — 不宣稱完整 Windows／排位／官方 AC 通過
