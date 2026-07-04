# StrawWU components — greenfield

v3.0-cleanroom 全新實作，禁止複製封存 legacy crate。

## 結構

```
components/
├── Cargo.toml              # Workspace root
├── Makefile                # make test / make package
├── specs/                  # API/ABI 規格文件
│   ├── bridge-abi.md
│   ├── runtime-cooperation.md
│   ├── execution-backends.md
│   ├── device-driver-proxy.md
│   ├── graphics-stack.md
│   └── anticheat-compat.md
├── strawwu-bridge/         # kernel↔userspace IPC + seccomp policy
├── strawwu-runtime/        # SubsystemSession + orchestrator + process graph
├── strawwu-launcher/       # PE/ELF 偵測 + CLI (strawwu 指令)
├── packaging/              # .deb 建置腳本
│   ├── debian/
│   └── build-deb.sh
└── tests/                  # 整合測試資料
    └── wincompat/
```

## 建置與測試

```bash
make -C components test      # 單元測試 + 規格完整性 + 結構檢查
make -C components package   # 建置 release binary + .deb 打包
make -C components build     # 僅 cargo build --release
make -C components check     # 快速 cargo check
```

## 設計原則

- **預設不使用 sandbox** — app 在共享 SubsystemSession 內互通
- **native 後端為預設** — container/microvm 僅作覆寫
- **禁止 WinBox / strawwu-box** — 統一使用 `strawwu` CLI
- **禁止 Wine/Proton** — 全部自行實作翻譯層
