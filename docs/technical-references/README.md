# StrawWU 技術文件庫

本目錄收錄 **Ubuntu resolute (26.04 LTS) 上游權威文件**，供 StrawWU v3.0-cleanroom 各 Phase **規劃對照**與**驗收稽核**使用。

> 上游原始碼體積大（~370MB），`upstream/` 已列入 `.gitignore`。索引與更新腳本會進版控；首次使用或升級 resolute 套件後請執行 `scripts/refresh-technical-references.sh`。

## 快速開始

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
./docs/technical-references/scripts/refresh-technical-references.sh   # 下載/更新
less docs/technical-references/indexes/phase-validation-map.md       # Phase→文件→驗證對照
```

## 目錄結構

| 路徑 | 內容 |
|------|------|
| `indexes/phase-validation-map.md` | 8 階段 × 上游文件 × StrawWU 測試命令 |
| `indexes/catalog.json` | 機器可讀清單（套件版本、路徑、URL） |
| `upstream/` | apt source、git shallow、manpage、kernel doc（本地快取） |
| `scripts/refresh-technical-references.sh` | 一鍵更新腳本（自 `ubuntu-base-target.json` 推導 suite） |

## 已收錄上游（resolute）

| 領域 | 套件/來源 | StrawWU 用途 |
|------|-----------|--------------|
| Live 開機 | `casper` 26.04.x | `/casper` squashfs、overlay、boot=casper |
| initramfs | `initramfs-tools` 0.151ubuntu* | early3/main 結構、hook 順序 |
| 開機動畫 | `plymouth` 24.004.60+git | initrd main 段 plymouthd、主題 |
| ISO 封裝 | `libisoburn`/xorriso 1.5.6 | El Torito、增量 repack |
| 開機載入 | `grub2` 2.14 | BIOS/UEFI、live 參數 |
| 安裝器 | `calamares` 3.3.14 + `calamares-settings-ubuntu-common` 26.04.x | Phase 3 上游對齊 |
| Kernel | `linux-stable` v6.14.x Documentation | kbuild、overlayfs、iso9660 |
| 社群指南 | Ubuntu LiveCDCustomization wiki | 規劃參考（非驗收依據） |

## 使用原則

1. **驗收以 StrawWU 測試為準**（`make preflight`、`boot-test-*`、`test-install-e2e`），上游文件僅作「為何這樣做」的依據。
2. **禁止偏離上游 Calamares 行為**（見 `~/.hermes/skills/.../calamares-sop.md`）；對照 `calamares-settings-ubuntu-common` resolute 包內 `etc/calamares/`。
3. **initrd/casper 變更**前先讀 `casper/hooks/`、`initramfs-tools/hooks/` 與 skill `initrd-casper-pitfalls.md`。
4. 規劃新 Phase 時在 `indexes/phase-validation-map.md` 增列對照列，勿只改程式不留文件鏈。

## 相關專案文件

- `docs/iso-modes.md` — dev-vm / dev-iso / release-iso
- `docs/phase-roadmap.md` — 8 階段驗收表
- `~/.hermes/skills/software-development/strawwu-worker/references/` — 踩坑與 SOP
