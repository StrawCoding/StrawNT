# POST-SEC-secureboot-route — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-sec-secureboot-route` |
| 版本 | `0.7.0.1`（`0.7.0.0` → `0.7.0.1`） |
| 版本目標 | `0.7.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T10:55+08:00 |
| Worker 回合 | 階段 1/8（post-sec-secureboot-route） |

## 摘要

實作 Post-MVP SEC **Secure Boot 路線文件與骨架**（shim + signed kernel/initrd），**預設不強制啟用**：

- 擴充 `strawwu-security-trust-model.md` §2 / SEC5：boot chain、金鑰規劃、v0.7 骨架對照
- 新增 `strawwu-secureboot` Debian 套件：`status` / `route` / `preflight` + fixture 模式
- 新增 `os-image/scripts/secureboot-route/`：`sign-boot-artifacts.sh`（預設 dry-run）、`verify-boot-chain.sh`、`MANIFEST.yaml`
- 強化 `test-secureboot-route.sh` 靜態閘門 + baseline JSON

## 交付物

| 類型 | 路徑 |
|------|------|
| 信任模型 | `docs/plans/strawwu-security-trust-model.md` |
| Debian 套件 | `os-image/debs/strawwu-secureboot/` |
| 簽章/驗證骨架 | `os-image/scripts/secureboot-route/` |
| Preflight gate | `tests/preflight/test-secureboot-route.sh` |
| Baseline | `docs/plans/baselines/secureboot-route-baseline.json` |
| Python 單元測試 | `os-image/debs/strawwu-secureboot/tests/test-secureboot.py` |

## 架構

```
UEFI firmware (DB)
    → shim.efi
    → grubx64.efi
    → signed vmlinuz
    → signed initrd.img
    → rootfs

v0.7 預設：STRAWWU_SECURE_BOOT_ENFORCE=0
簽章腳本：STRAWWU_SB_SIGN=0 → dry-run only
Hub/strawwu-drivers：SB 啟用時誠實警告 → post-sec-secureboot-route
```

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.7.0.0` → `0.7.0.1` |
| `hub/package.json`, `components/Cargo.toml` | 版本同步 |
| `docs/plans/strawwu-security-trust-model.md` | §2.1–2.3 boot chain + SEC5 交付對照 |
| `os-image/debs/strawwu-secureboot/` | **新增** CLI、core、manifest、fixture、tests |
| `os-image/scripts/secureboot-route/` | **新增** sign/verify 骨架腳本 |
| `os-image/scripts/build-os-debs.sh` | 納入 strawwu-secureboot |
| `tests/preflight/test-secureboot-route.sh` | **強化** 套件/腳本/單元測試閘門 |

## 功能範圍

### 已完成（v0.7 SEC5 骨架）

- `strawwu-secureboot status|route|preflight`（fixture 可離線測）
- `sign-boot-artifacts.sh` 預設 `--dry-run`；`STRAWWU_SB_SIGN=1` 才嘗試實簽
- `verify-boot-chain.sh` mokutil 狀態 + 工具/產物 JSON 報告
- 信任模型文件化 shim + **signed kernel** + **signed initrd** 路線
- 與 `strawwu-drivers` Secure Boot 警告計畫 ID 對齊

### 未做（留待後續）

- 實際 StrawWU UEFI DB 金鑰簽發與 CI secret 佈署
- ISO/安裝預設強制 SB（`STRAWWU_SECURE_BOOT_ENFORCE` 維持 0）
- `CONFIG_MODULE_SIG_FORCE` 啟用與 DKMS MOK 自動化
- release-iso UEFI SB 開機實機驗收

## 測試證據

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-secureboot-route   # exit 0 — POST-SEC secureboot route done: PASS
make preflight               # exit 0 — 全 preflight 通過（~245s，2026-07-08T10:55+08:00）
```

`make test-secureboot-route` 摘要：37 項 PASS（含 7 個 Python 單元測試、fixture CLI、sign/verify smoke）。

`make preflight`：exit 0；含 version policy OK（0.7.0.1, major=0）、POST-SEC kickoff 存在、全 wave/post-mvp closeout 閘門通過。

`strawwu-secureboot` deb 建置：`os-image/debs/strawwu-secureboot/output/strawwu-secureboot_0.7.0.1_all.deb`（8.7K）。

證據路徑：

- `docs/plans/baselines/secureboot-route-baseline.json`
- `os-image/debs/strawwu-secureboot/tests/test-secureboot.py`

## 產品決策

無阻塞。本階段依 kickoff 明確要求「文件與骨架、不強制啟用」，未將 `strawwu-secureboot` 加入 `target-manifest.yaml` 強制安裝清單。

## 後續

Hermes mark PASS → 自動啟動 **post-sec-cve-policy**（依 POST-MVP-AUTO-SEQUENCE）。

## 建議驗收

```bash
make test-secureboot-route
make preflight
```
