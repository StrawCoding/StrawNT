# StrawWU components — greenfield

v3.0-cleanroom 全新實作，禁止複製封存 legacy crate。

## 規劃結構（Phase 4+）

```
components/
├── specs/               # API/ABI 規格文件
├── strawwu-bridge/      # kernel↔userspace IPC
├── strawwu-runtime/     # 行程調度、subsys 註冊
├── strawwu-launcher/    # PE/ELF 啟動骨架
└── packaging/           # .deb 建置
```

Phase 1–3 專注 Ubuntu clone 管線；元件實作自 Phase 4 起依鎖序推進。
