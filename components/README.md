# StrawWU components — greenfield

v3.0-cleanroom 全新實作，禁止複製封存 legacy crate。

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
make -C components test                  # 單元測試 + 規格完整性 + 結構檢查
make -C components test-wincompat        # Phase 6 Windows 相容層全驗收
make -C components test-execution-backends  # 6.2 執行後端測試
make -C components test-graphics-vulkan  # 6.4 Vulkan 圖形棧測試
make -C components test-graphics-opengl  # 6.4b OpenGL 圖形棧測試
make -C components test-anticheat-matrix # 6.7 反作弊矩陣測試
make -C components test-device-proxy     # 6.11 裝置代理測試
make -C components generate-compat-matrix  # 產出 compat-matrix.json
make -C components package               # 建置 release binary + .deb 打包
make -C components build                  # 僅 cargo build --release
make -C components check                  # 快速 cargo check
```

## 設計原則

- **預設不使用 sandbox** — app 在共享 SubsystemSession 內互通
- **native 後端為預設** — container/microvm 僅作覆寫
- **禁止 WinBox / strawwu-box** — 統一使用 `strawwu` CLI
- **禁止 Wine/Proton** — 全部自行實作翻譯層
- **誠實標 PASS/PARTIAL/FAIL** — 不宣稱完整 Windows 相容
